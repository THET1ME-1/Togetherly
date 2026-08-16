import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/locale_service.dart';
import '../../services/pocketbase_service.dart';
import '../../services/watch_channel_service.dart';
import '../../services/watch_history_service.dart';
import '../../services/watch_room_service.dart';
import '../../services/watch_voice_service.dart';
import '../../utils/share_origin.dart';
import '../../widgets/common/m3_loading.dart';
import '../../widgets/watch/watch_voice_bar.dart';

/// Комната совместного просмотра.
///
/// Внутри крутится тот же движок, что на сайте: один канал Centrifugo, один
/// набор сообщений. Поэтому приложение и браузер попадают в одну комнату, а
/// починки источников приезжают сюда сами, без отдельной работы.
class WatchRoomScreen extends StatefulWidget {
  /// Код комнаты пары (выдаёт сервер по связи, вводить его не нужно).
  final String room;

  /// Ссылка на видео, если просмотр начали с карточки воспоминания.
  final String? videoUrl;

  /// Пара, чью историю просмотров пополняем.
  final String pairId;

  const WatchRoomScreen({
    super.key,
    required this.room,
    required this.pairId,
    this.videoUrl,
  });

  @override
  State<WatchRoomScreen> createState() => _WatchRoomScreenState();
}

class _WatchRoomScreenState extends State<WatchRoomScreen> {
  bool _loading = true;

  /// Своё подключение к каналу комнаты — рядом с тем, что держит страница
  /// внутри WebView. Второе соединение нужно потому, что голос идёт мимо
  /// браузера: WebRTC поднимает приложение, а сигналинг живёт в том же канале.
  WatchChannel? _room;
  WatchVoiceService? _voice;

  @override
  void initState() {
    super.initState();
    unawaited(_openVoice());
  }

  /// Голос поднимается ЗАРАНЕЕ, а не по нажатию: канал должен слушать зов
  /// партнёра с первой секунды, иначе его «voice-hello» никто не поймает и
  /// звонок будет уходить в пустоту.
  Future<void> _openVoice() async {
    final me = PocketBaseService().userId ?? 'app';
    final room = WatchChannel(widget.room, me);
    try {
      await room.connect(_onRoomMessage);
    } catch (e) {
      debugPrint('WatchRoom: канал не поднялся: $e');
      return;
    }
    if (!mounted) {
      unawaited(room.dispose());
      return;
    }
    final voice = WatchVoiceService(channel: room, me: me);
    voice.addListener(_onVoiceChanged);
    setState(() {
      _room = room;
      _voice = voice;
    });
  }

  void _onRoomMessage(Map<String, dynamic> data) {
    // Команды плеера разбирает страница в WebView — приложение в них не лезет.
    // Себе забираем только сигналинг разговора.
    final voice = _voice;
    if (voice != null && (data['t'] ?? '').toString().startsWith('voice-')) {
      unawaited(voice.handleMessage(data));
    }
  }

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  /// Позвонить или положить трубку. Микрофон спрашивает сам WebRTC; отказ
  /// оставляет комнату как была.
  Future<void> _toggleVoice() async {
    final voice = _voice;
    if (voice == null) return;
    if (voice.active) {
      await voice.stop();
    } else {
      await voice.start();
      if (mounted && voice.state == VoiceCallState.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocaleService.current.voiceNoPermission)),
        );
      }
    }
  }

  @override
  void dispose() {
    _voice?.removeListener(_onVoiceChanged);
    _voice?.dispose();
    unawaited(_room?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  /// Адрес открытой комнаты: с роликом, если пришли из карточки или карусели,
  /// и со своим именем — иначе страница подписывает обоих «Гость».
  String get _url => WatchRoomService.siteUrl(
        widget.room,
        src: widget.videoUrl,
        name: PocketBaseService().userName,
      );

  /// Ссылка для партнёра — без ролика и без имени: он войдёт в ту же комнату,
  /// получит источник от нас по каналу и подпишется своим именем.
  String get _inviteUrl => WatchRoomService.siteUrl(widget.room);

  Future<void> _share() async {
    // Без якоря на iPad лист не открывается вовсе, и кнопка выглядит мёртвой —
    // ровно за это прилетал реджект 2.1(a) по «Scan to Connect».
    await Share.share(
      _inviteUrl,
      sharePositionOrigin: shareOriginFromContext(context),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _inviteUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LocaleService.current.linkCopied),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(widget.room, style: const TextStyle(letterSpacing: 1.4)),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _copy,
            icon: const Icon(Icons.copy_rounded),
            tooltip: s.copyLink,
          ),
          IconButton(
            onPressed: _share,
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: s.copyLink,
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_url)),
            initialSettings: InAppWebViewSettings(
              // Видео должно запускаться командой партнёра, а не только пальцем.
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              transparentBackground: true,
              supportZoom: false,
            ),
            onWebViewCreated: (c) {
              // Комната сама сообщает, что включили: иначе приложение не знает,
              // что происходит внутри встроенного браузера.
              c.addJavaScriptHandler(
                handlerName: 'watchSource',
                callback: (args) {
                  final info = (args.isNotEmpty && args.first is Map)
                      ? Map<String, dynamic>.from(args.first as Map)
                      : const <String, dynamic>{};
                  unawaited(WatchHistoryService.remember(
                    groupId: widget.pairId,
                    url: (info['url'] ?? '').toString(),
                    kind: (info['kind'] ?? '').toString(),
                    title: (info['title'] ?? '').toString(),
                    thumb: (info['thumb'] ?? '').toString(),
                  ));
                  return null;
                },
              );
            },
            onLoadStop: (c, _) {
              if (mounted) setState(() => _loading = false);
            },
          ),
          if (_loading)
            Center(child: M3Loading(color: Theme.of(context).colorScheme.primary)),
        ],
      ),
      // Полоса голоса стоит ПОД комнатой и не зависит от того, включили ли
      // ролик: поговорить можно в пустой комнате. Пока канал не поднялся,
      // кнопки нет — нажимать было бы не на что.
      bottomNavigationBar: _voice == null
          ? null
          : WatchVoiceBar(
              state: _voice!.state,
              micOn: _voice!.micOn,
              speakerOn: _voice!.speakerOn,
              onCallToggle: _toggleVoice,
              onMicToggle: () => _voice?.toggleMic(),
              onSpeakerToggle: () => _voice?.toggleSpeaker(),
            ),
    );
  }
}
