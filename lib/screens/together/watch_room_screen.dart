import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/call_record.dart';
import '../../models/exit_guard.dart';
import '../../services/chat_service.dart';
import '../../widgets/memory_save/floating_note.dart';
import '../../services/locale_service.dart';
import '../../services/pocketbase_service.dart';
import '../../models/reels_source.dart';
import '../../services/reels/reels_feed.dart';
import '../../services/reels/reel_save.dart';
import '../../services/reels/reels_proxy.dart';
import '../../services/watch_channel_service.dart';
import '../../services/watch_history_service.dart';
import '../../services/watch_room_service.dart';
import '../../services/watch_voice_service.dart';
import '../../utils/share_origin.dart';
import '../../widgets/common/m3_loading.dart';

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

  /// Комнату открыли сразу после рекламы — метка для замера касаний.
  final bool afterAd;

  /// Пара, чью историю просмотров пополняем.
  final String pairId;

  /// Ленты вдвоём: короткие ролики по очереди из лент обоих. Комната та же,
  /// а ленту выбранной площадки этого телефона держит скрытый браузер
  /// ([ReelsFeed]).
  final bool reels;

  /// Чья площадка подаёт ленту этого телефона (выбор в листе перед лентами).
  final ReelsSource reelsSource;

  const WatchRoomScreen({
    super.key,
    required this.room,
    required this.pairId,
    this.videoUrl,
    this.afterAd = false,
    this.reels = false,
    this.reelsSource = ReelsSource.shorts,
  });

  @override
  State<WatchRoomScreen> createState() => _WatchRoomScreenState();
}

class _WatchRoomScreenState extends State<WatchRoomScreen> with WidgetsBindingObserver {
  bool _loading = true;

  /// Страница комнаты: ей уходит состояние звонка, от неё приходят нажатия.
  InAppWebViewController? _web;

  /// Своё подключение к каналу комнаты — рядом с тем, что держит страница
  /// внутри WebView. Второе соединение нужно потому, что голос идёт мимо
  /// браузера: WebRTC поднимает приложение, а сигналинг живёт в том же канале.
  WatchChannel? _room;
  WatchVoiceService? _voice;

  /// Лента площадки этого телефона — только в режиме лент.
  ReelsFeed? _feed;

  @override
  void initState() {
    super.initState();
    unawaited(_openVoice());
    WidgetsBinding.instance.addObserver(this);
    if (widget.reels) unawaited(_startFeed());
  }

  /// Скрытая страница раскачивается несколько секунд — поднимаем её сразу,
  /// пока грузится комната. Посредник для TikTok нужен обоим: ролик из ленты
  /// партнёра играет и у того, кто сам выбрал другую площадку.
  Future<void> _startFeed() async {
    await ReelsProxy.enable();
    if (!mounted) return;
    final feed = ReelsFeed(widget.reelsSource, onIds: _pushFeed, onThumbs: _pushThumbs);
    _feed = feed;
    await feed.start();
  }

  /// Свёрнутое приложение: ленты засыпают. Плееры страницы и скрытая лента
  /// иначе крутят видео, пока человека нет, а при возврате просыпаются разом —
  /// отсюда лаги после разворота (жалоба 04.10.2026).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.reels) return;
    final away = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (state != AppLifecycleState.resumed && !away) return;
    unawaited(_web?.evaluateJavascript(source: 'window.reelsSleep && window.reelsSleep(${away ? 'true' : 'false'})'));
    unawaited(away ? (_feed?.sleep() ?? Future<void>.value()) : (_feed?.wake() ?? Future<void>.value()));
  }

  /// Ролик в лентах идёт во весь экран, под строку состояния. Странице
  /// нужно знать, где кончаются строка и системные кнопки: env() в WebView
  /// отвечает по-разному, поэтому отступы передаём сами.
  String _insetScript(EdgeInsets pad) => '(function(){var s=document.documentElement.style;'
      "s.setProperty('--app-top','${pad.top.toStringAsFixed(1)}px');"
      "s.setProperty('--app-bottom','${pad.bottom.toStringAsFixed(1)}px');})();";

  /// Свежие номера ленты — странице, которая ждёт первый ролик.
  void _pushFeed(List<String> ids) {
    final web = _web;
    if (web == null || ids.isEmpty) return;
    unawaited(web.evaluateJavascript(source: 'window.reelsFeedPush && window.reelsFeedPush(${jsonEncode(ids)})'));
  }

  /// Обложки роликов копятся здесь: лента может принести их раньше, чем
  /// загрузится страница, — тогда отдаём их в [_onPageLoaded].
  final Map<String, String> _thumbs = {};

  void _pushThumbs(Map<String, String> thumbs) {
    _thumbs.addAll(thumbs);
    if (_thumbs.length > 400) _thumbs.remove(_thumbs.keys.first);
    final web = _web;
    if (web == null) return;
    unawaited(web.evaluateJavascript(source: 'window.reelsThumbsPush && window.reelsThumbsPush(${jsonEncode(thumbs)})'));
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
    voice.onCallEnded = (talked, peer) => _recordCall(me, talked, peer);
    setState(() {
      _room = room;
      _voice = voice;
    });
    _pushVoice();
  }

  /// Разговор кончился — запись «Звонок · 4:12» в чат пары. Пишет один из
  /// двоих (`writesCallRecord`), иначе в истории было бы по две записи.
  /// Работает и после ухода с экрана: отбой при закрытии тоже разговор.
  void _recordCall(String me, Duration talked, String peer) {
    if (talked < kMinCallRecord || widget.pairId.isEmpty) return;
    if (!writesCallRecord(me: me, peer: peer)) return;
    final ms = talked.inMilliseconds;
    unawaited(
      ChatService.instance.send(
        groupId: widget.pairId,
        senderName: PocketBaseService().userName,
        text: callRecordText(LocaleService.current.chatCallTitle, ms),
        callMs: ms,
      ),
    );
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
    _pushVoice();
  }

  /// Отдаёт странице состояние звонка.
  ///
  /// Кнопка живёт в шапке комнаты и красится её токенами, поэтому приложение
  /// только рассказывает, что происходит: покой, ждём ответа, говорим, не
  /// вышло. Имена состояний и действий разбирает `voiceBridge` в `room.js`,
  /// сверяет их `test/screens/watch_room_voice_bridge_test.dart`.
  void _pushVoice() {
    final web = _web;
    if (web == null) return;
    final voice = _voice;
    final state = switch (voice?.state) {
      null || VoiceCallState.off => 'off',
      VoiceCallState.connecting => 'connecting',
      VoiceCallState.live => 'live',
      VoiceCallState.failed => 'failed',
    };
    final data = jsonEncode({'state': state, 'micOn': voice?.micOn ?? true, 'speakerOn': voice?.speakerOn ?? true});
    unawaited(web.evaluateJavascript(source: 'window.watchVoiceState && window.watchVoiceState($data)'));
  }

  /// Нажатие на странице: позвонить, положить трубку, приглушить микрофон.
  Future<void> _onVoiceAction(String action) async {
    final voice = _voice;
    // Канал ещё не поднялся — звонить некуда, страница просто останется
    // в покое: своего состояния она не выдумывает.
    if (voice == null) return;
    switch (action) {
      case 'call':
        if (!voice.active) await _toggleVoice();
      case 'hangup':
        if (voice.active) await voice.stop();
      case 'mic':
        voice.toggleMic();
    }
    _pushVoice();
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocaleService.current.voiceNoPermission)));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice?.removeListener(_onVoiceChanged);
    _voice?.dispose();
    unawaited(_room?.dispose() ?? Future<void>.value());
    unawaited(_feed?.dispose() ?? Future<void>.value());
    if (widget.reels) unawaited(ReelsProxy.disable());
    super.dispose();
  }

  /// Адрес открытой комнаты: с роликом, если пришли из карточки или карусели,
  /// и со своим именем — иначе страница подписывает обоих «Гость».
  String get _url => WatchRoomService.siteUrl(
    widget.room,
    src: widget.videoUrl,
    name: PocketBaseService().userName,
    afterAd: widget.afterAd,
    reels: widget.reels,
    feed: widget.reels ? widget.reelsSource.key : null,
  );

  /// Ссылка для партнёра — без ролика и без имени: он войдёт в ту же комнату,
  /// получит источник от нас по каналу и подпишется своим именем.
  String get _inviteUrl => WatchRoomService.siteUrl(widget.room);

  Future<void> _share() async {
    // Без якоря на iPad лист не открывается вовсе, и кнопка выглядит мёртвой —
    // ровно за это прилетал реджект 2.1(a) по «Scan to Connect».
    await Share.share(_inviteUrl, sharePositionOrigin: shareOriginFromContext(context));
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _inviteUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(LocaleService.current.linkCopied), behavior: SnackBarBehavior.floating));
  }

  /// Когда последний раз нажимали «назад».
  ///
  /// Выход из комнаты останавливает кино у обоих, и промахнуться легко:
  /// «случайно нажимаешь и тебя выбрасывает с комнаты» (просьба пары,
  /// 20.09.2026). Первое нажатие предупреждает, второе выпускает.
  DateTime? _backAt;

  /// Отпускать ли из комнаты. Первое нажатие показывает подсказку.
  bool _allowLeave() {
    final now = DateTime.now();
    if (exitOnBack(lastPress: _backAt, now: now)) return true;
    _backAt = now;
    showFloatingNote(
      context,
      LocaleService.current.watchRoomBackAgain,
      icon: Icons.logout_rounded,
      duration: kExitWindow,
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_allowLeave() && mounted) Navigator.of(context).pop();
      },
      // В лентах строка состояния светлыми значками по чёрному.
      child: widget.reels
          ? AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light,
              child: _roomScaffold(context, s, cs),
            )
          : _roomScaffold(context, s, cs),
    );
  }

  Widget _roomScaffold(BuildContext context, AppStrings s, ColorScheme cs) {
    return Scaffold(
      // Ленты идут по чёрному полю во весь экран: светлая полоса над роликом
      // выглядела бы чужой рамкой.
      backgroundColor: widget.reels ? Colors.black : cs.surface,
      // Своей шапки нет: её рисует страница комнаты — «назад», код,
      // «скопировать», «поделиться», звонок и сворачивание. Две шапки подряд
      // съедали высоту и повторяли одно и то же (28.09.2026).
      body: SafeArea(
        // В лентах ролик заходит под строку состояния, как в TikTok: чёрная
        // полоса над ним читалась пустой шапкой. Отступ кнопкам страница
        // берёт из `_insetScript`.
        top: !widget.reels,
        bottom: false,
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_url)),
              // Касание в зоне комнаты сразу уходит браузеру, не дожидаясь арены
              // жестов Flutter: на iPhone после рекламы оно иначе терялось, и
              // страница не отвечала ни на что (обращения 164, 178, 183, 190).
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
              },
              // Сессия для пропуска: в комнату пары пускают только участников,
              // и без неё страница попросила бы войти ещё раз.
              initialUserScripts: UnmodifiableListView([
                UserScript(
                  source: WatchRoomService.authScript(
                    token: PocketBaseService.instance.pb.authStore.token,
                    name: PocketBaseService().userName,
                  ),
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
                if (widget.reels)
                  UserScript(
                    source: _insetScript(MediaQuery.paddingOf(context)),
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                  ),
              ]),
              initialSettings: InAppWebViewSettings(
                // Видео должно запускаться командой партнёра, а не только пальцем.
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                javaScriptEnabled: true,
                transparentBackground: true,
                supportZoom: false,
              ),
              onWebViewCreated: (c) {
                _web = c;
                // Кнопка звонка стоит в шапке комнаты, а связь поднимает
                // приложение: у страницы нет ни микрофона пары, ни сигналинга.
                // Кнопки шапки страницы: «назад», «скопировать», «поделиться».
                c.addJavaScriptHandler(
                  handlerName: 'watchBack',
                  callback: (_) {
                    if (mounted && _allowLeave()) Navigator.of(context).pop();
                    return null;
                  },
                );
                c.addJavaScriptHandler(
                  handlerName: 'watchCopy',
                  callback: (_) {
                    _copy();
                    return null;
                  },
                );
                c.addJavaScriptHandler(
                  handlerName: 'watchShare',
                  callback: (_) {
                    _share();
                    return null;
                  },
                );
                c.addJavaScriptHandler(
                  handlerName: 'watchVoice',
                  callback: (args) {
                    final info = (args.isNotEmpty && args.first is Map)
                        ? Map<String, dynamic>.from(args.first as Map)
                        : const <String, dynamic>{};
                    unawaited(_onVoiceAction((info['action'] ?? '').toString()));
                    return null;
                  },
                );
                // Ленты: страница просит номера роликов, сообщает, что играет
                // из нашей ленты, и отправляет ссылку на ролик.
                c.addJavaScriptHandler(
                  handlerName: 'reelsFeed',
                  callback: (args) async {
                    final feed = _feed;
                    if (feed == null) return const <String>[];
                    final info = (args.isNotEmpty && args.first is Map)
                        ? Map<String, dynamic>.from(args.first as Map)
                        : const <String, dynamic>{};
                    final need = int.tryParse('${info['need'] ?? 8}') ?? 8;
                    return feed.take(need.clamp(1, 20));
                  },
                );
                c.addJavaScriptHandler(
                  handlerName: 'reelsWatching',
                  callback: (args) {
                    final info = (args.isNotEmpty && args.first is Map)
                        ? Map<String, dynamic>.from(args.first as Map)
                        : const <String, dynamic>{};
                    unawaited(_feed?.watching((info['id'] ?? '').toString()) ?? Future<void>.value());
                    return null;
                  },
                );
                // «Обновить рекомендации»: скрытая лента начинается заново.
                c.addJavaScriptHandler(
                  handlerName: 'reelsRefresh',
                  callback: (_) async {
                    await _feed?.refresh();
                    return null;
                  },
                );
                // Закладка: ролик ложится в ленту воспоминаний пары.
                c.addJavaScriptHandler(
                  handlerName: 'reelsSave',
                  callback: (args) async {
                    final info = (args.isNotEmpty && args.first is Map)
                        ? Map<String, dynamic>.from(args.first as Map)
                        : const <String, dynamic>{};
                    final ok = await ReelSave.save(
                      groupId: widget.pairId,
                      key: (info['key'] ?? '').toString(),
                    );
                    return {'ok': ok};
                  },
                );
                c.addJavaScriptHandler(
                  handlerName: 'reelsShare',
                  callback: (args) async {
                    final info = (args.isNotEmpty && args.first is Map)
                        ? Map<String, dynamic>.from(args.first as Map)
                        : const <String, dynamic>{};
                    final url = (info['url'] ?? '').toString();
                    if (url.isEmpty || !mounted) return null;
                    await Share.share(url, sharePositionOrigin: shareOriginFromContext(context));
                    return null;
                  },
                );
                // Комната сама сообщает, что включили: иначе приложение не знает,
                // что происходит внутри встроенного браузера.
                c.addJavaScriptHandler(
                  handlerName: 'watchSource',
                  callback: (args) {
                    final info = (args.isNotEmpty && args.first is Map)
                        ? Map<String, dynamic>.from(args.first as Map)
                        : const <String, dynamic>{};
                    unawaited(
                      WatchHistoryService.remember(
                        groupId: widget.pairId,
                        url: (info['url'] ?? '').toString(),
                        kind: (info['kind'] ?? '').toString(),
                        title: (info['title'] ?? '').toString(),
                        thumb: (info['thumb'] ?? '').toString(),
                      ),
                    );
                    return null;
                  },
                );
              },
              onLoadStop: (c, _) {
                if (mounted) setState(() => _loading = false);
                // Страница перезагрузилась (поворот, возврат назад) — она снова
                // ничего не знает про звонок.
                _pushVoice();
                if (widget.reels) {
                  unawaited(c.evaluateJavascript(source: _insetScript(MediaQuery.paddingOf(context))));
                  if (_thumbs.isNotEmpty) _pushThumbs(Map.of(_thumbs));
                }
              },
            ),
            if (_loading) Center(child: M3Loading(color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
    );
  }
}
