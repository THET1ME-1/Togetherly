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
import '../../services/cinema_chrome.dart';
import '../../services/network/server_route.dart';
import '../../widgets/memory_save/floating_note.dart';
import '../../services/locale_service.dart';
import '../../services/pocketbase_service.dart';
import '../../models/reels_source.dart';
import '../../services/reels/reels_feed.dart';
import '../../services/plus_service.dart';
import '../../services/reels/reel_save.dart';
import '../../services/reels/reels_invite.dart';
import '../../services/reels/reels_proxy.dart';
import '../../services/reels/reels_telemetry.dart';
import '../../services/watch_channel_service.dart';
import '../../services/watch_history_service.dart';
import '../../services/watch_room_service.dart';
import '../../services/screen_awake.dart';
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

  /// Пара, чью историю просмотров пополняем.
  final String pairId;

  /// Ленты вдвоём: короткие ролики по очереди из лент обоих. Комната та же,
  /// а ленту выбранной площадки этого телефона держит скрытый браузер
  /// ([ReelsFeed]).
  final bool reels;

  /// Чья площадка подаёт ленту этого телефона (выбор в листе перед лентами).
  final ReelsSource reelsSource;

  /// Открыть комнату нативным окном браузера поверх приложения, а не
  /// встроенным в экран (iPhone, доля людей с сервера — `roomOpensNatively`).
  /// Встроенный браузер на iPhone терял касания у каждого четвёртого: палец
  /// сначала проходит через Flutter. У нативного окна Flutter на пути нет.
  final bool nativeWindow;

  /// Номер сборки — метка для замера касаний на странице.
  final int build;

  const WatchRoomScreen({
    super.key,
    required this.room,
    required this.pairId,
    this.videoUrl,
    this.reels = false,
    this.reelsSource = ReelsSource.shorts,
    this.nativeWindow = false,
    this.build = 0,
  });

  @override
  State<WatchRoomScreen> createState() => _WatchRoomScreenState();
}

class _WatchRoomScreenState extends State<WatchRoomScreen> with WidgetsBindingObserver {
  bool _loading = true;

  /// На странице включён режим «кино»: панели спрятаны, телефон набок,
  /// страница во весь экран (TOG-43).
  bool _cinema = false;

  /// Страница комнаты: ей уходит состояние звонка, от неё приходят нажатия.
  InAppWebViewController? _web;

  /// Своё подключение к каналу комнаты — рядом с тем, что держит страница
  /// внутри WebView. Второе соединение нужно потому, что голос идёт мимо
  /// браузера: WebRTC поднимает приложение, а сигналинг живёт в том же канале.
  WatchChannel? _room;
  WatchVoiceService? _voice;

  /// Лента площадки этого телефона — только в режиме лент.
  ReelsFeed? _feed;

  /// Комната идёт нативным окном. Сбрасывается, если окно не открылось:
  /// тогда комната встаёт прежним встроенным браузером.
  late bool _native = widget.nativeWindow && !widget.reels;

  /// Нативное окно комнаты и признак, что закрываем его сами.
  _RoomWindow? _window;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    if (_native) {
      // Окно показывает сама система поверх экрана — открываем после первого
      // кадра, когда у маршрута уже есть место и отступы.
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_openWindow()));
    }
    // В комнате смотрят фильм и не трогают экран: без удержания он гаснет
    // по системному таймеру (жалоба 12.10.2026). Встроенный браузер экран
    // сам не держит, а играет ли ролик, знает только страница, поэтому
    // держим всё время, пока комната открыта.
    ScreenAwake.hold(this);
    unawaited(_openVoice());
    WidgetsBinding.instance.addObserver(this);
    if (widget.reels) unawaited(_startFeed());
    // Ленту запускает купивший — он и зовёт партнёра: тому придёт пуш
    // «Аня зовёт смотреть TikTok», по которому он войдёт без своего Плюса.
    if (widget.reels && PlusService.instance.active) {
      _invited = true;
      unawaited(ReelsInvite.send(widget.pairId, widget.reelsSource));
    }
  }

  bool _invited = false;

  /// Скрытая страница раскачивается несколько секунд — поднимаем её сразу,
  /// пока грузится комната. Посредник для TikTok нужен обоим: ролик из ленты
  /// партнёра играет и у того, кто сам выбрал другую площадку.
  Future<void> _startFeed() async {
    final watch = ReelsWatch(source: widget.reelsSource.key, started: DateTime.now());
    _reelsWatch = watch;
    _reelsStall = Timer(ReelsWatch.limit + const Duration(seconds: 1), _checkReelsStall);
    await ReelsProxy.enable();
    if (!mounted) return;
    final feed = ReelsFeed(widget.reelsSource, onIds: _pushFeed, onThumbs: _pushThumbs, watch: watch);
    _feed = feed;
    await feed.start();
  }

  /// Как собирается своя лента — для отчёта, если ролики так и не придут.
  ReelsWatch? _reelsWatch;
  Timer? _reelsStall;

  /// Свёрнутое приложение лента не грузит, и отчёт о такой «застрявшей»
  /// ленте врал бы: после сворачивания его не шлём.
  bool _reelsLeftApp = false;

  void _checkReelsStall() {
    final watch = _reelsWatch;
    if (!mounted || watch == null || _reelsLeftApp) return;
    final report = watch.check(
      DateTime.now(),
      proxyOn: ReelsProxy.on,
      blocked: ReelsProxy.blocked,
      proxyError: ReelsProxy.lastError,
    );
    if (report != null) ReelsTelemetry.stalled(report);
  }

  /// Свёрнутое приложение: ленты засыпают. Плееры страницы и скрытая лента
  /// иначе крутят видео, пока человека нет, а при возврате просыпаются разом —
  /// отсюда лаги после разворота (жалоба 04.10.2026).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.reels) return;
    final away = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (state != AppLifecycleState.resumed && !away) return;
    if (away) _reelsLeftApp = true;
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
        _say(LocaleService.current.voiceNoPermission);
      }
    }
  }

  // ── нативное окно (iPhone) ───────────────────────────────────────────────

  /// Настройки браузера комнаты — одни на оба окна.
  InAppWebViewSettings _webSettings() => InAppWebViewSettings(
    // Видео должно запускаться командой партнёра, а не только пальцем.
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    javaScriptEnabled: true,
    // Под нативным окном лежит экран приложения, просвечивать ему незачем.
    transparentBackground: !_native,
    supportZoom: false,
    // Движок браузеров на Android один на все окна приложения: лента держит
    // в нём три плеера и скрытую страницу площадки. Без флага его гибель от
    // нехватки памяти уносила приложение целиком (обращение 297).
    useOnRenderProcessGone: true,
  );

  /// Номер жизни страницы: новый номер ставит её заново.
  int _webLife = 0;

  /// Движок браузеров упал или его убила система: страница мертва. Ставим
  /// новую, комната подключится к каналу сама.
  void _onRendererGone() {
    if (!mounted) return;
    setState(() {
      _web = null;
      _webLife++;
      _loading = true;
    });
  }

  /// Скрипты, которые страница получает до своей загрузки.
  UnmodifiableListView<UserScript> _scripts(EdgeInsets pad) => UnmodifiableListView([
    // Сессия для пропуска: в комнату пары пускают только участников, и без
    // неё страница попросила бы войти ещё раз.
    UserScript(
      source: WatchRoomService.authScript(
        token: PocketBaseService.instance.pb.authStore.token,
        name: PocketBaseService().userName,
      ),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    // Лента идёт под строку состояния, нативное окно — во весь экран: обеим
    // страницам отступы сообщаем сами.
    if (widget.reels || _native)
      UserScript(source: _insetScript(pad), injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END),
  ]);

  /// Открывает комнату нативным окном. Не открылось — встраиваем как раньше:
  /// комната важнее способа её показать.
  Future<void> _openWindow() async {
    if (!mounted || _window != null) return;
    final window = _RoomWindow(
      initialUserScripts: _scripts(MediaQuery.paddingOf(context)),
      onCreated: _wire,
      onLoaded: _onPageLoaded,
      onClosed: _onWindowClosed,
    );
    _window = window;
    try {
      await window.openUrlRequest(
        urlRequest: URLRequest(url: WebUri(_url)),
        settings: InAppBrowserClassSettings(
          browserSettings: InAppBrowserSettings(
            // Шапку рисует сама страница: панель браузера ей не нужна.
            hideToolbarTop: true,
            hideUrlBar: true,
            hideProgressBar: true,
            hideCloseButton: true,
            // «Поверх экрана», а не «вместо»: иначе приложение считает себя
            // свёрнутым, гасит отрисовку и присутствие, и звонок рвётся.
            presentationStyle: ModalPresentationStyle.OVER_FULL_SCREEN,
            transitionStyle: ModalTransitionStyle.CROSS_DISSOLVE,
          ),
          webViewSettings: _webSettings(),
        ),
      );
    } catch (e) {
      debugPrint('WatchRoom: нативное окно не открылось — $e');
      _window = null;
      _web = null;
      if (mounted) setState(() => _native = false);
    }
  }

  /// Окно закрылось. Сами закрывали — маршрут снимет тот, кто закрывал;
  /// закрыла система — уходим из комнаты следом, под окном пустой экран.
  void _onWindowClosed() {
    _window = null;
    _web = null;
    if (_leaving || !mounted) return;
    _leaving = true;
    _dropRoute();
  }

  /// Выйти из комнаты: в нативном режиме сперва убрать окно.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _closeWindow();
    if (mounted) _dropRoute();
  }

  Future<void> _closeWindow() async {
    final window = _window;
    _window = null;
    if (window == null) return;
    try {
      if (window.isOpened()) await window.close();
    } catch (e) {
      debugPrint('WatchRoom: окно не закрылось — $e');
    }
    window.dispose();
  }

  /// Снимает свой маршрут, даже если он уже не верхний.
  void _dropRoute() {
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else if (route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  /// Поверх комнаты открыли другой экран (пуш, ссылка). Под нативным окном
  /// его не видно, поэтому комната уступает: окно закрывается.
  Animation<double>? _covered;

  void _onCovered(AnimationStatus status) {
    if (!_native || _leaving || status != AnimationStatus.forward) return;
    unawaited(_leave());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context)?.secondaryAnimation;
    if (identical(next, _covered)) return;
    _covered?.removeStatusListener(_onCovered);
    _covered = next;
    next?.addStatusListener(_onCovered);
  }

  /// Короткое сообщение человеку. Плашку Flutter под нативным окном не
  /// видно, поэтому там её показывает сама страница (`window.roomNote`).
  void _say(String text) {
    if (!mounted) return;
    if (_native) {
      unawaited(
        _web?.evaluateJavascript(source: 'window.roomNote && window.roomNote(${jsonEncode(text)})') ??
            Future<void>.value(),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  /// Страница сообщила, что включили или выключили «кино».
  void _setCinema(bool on) {
    if (on == _cinema || !mounted) return;
    setState(() => _cinema = on);
    unawaited(on ? CinemaChrome.enter() : CinemaChrome.leave());
  }

  @override
  void dispose() {
    if (_cinema) unawaited(CinemaChrome.leave());
    _covered?.removeStatusListener(_onCovered);
    unawaited(_closeWindow());
    ScreenAwake.release(this);
    WidgetsBinding.instance.removeObserver(this);
    _voice?.removeListener(_onVoiceChanged);
    _voice?.dispose();
    unawaited(_room?.dispose() ?? Future<void>.value());
    _reelsStall?.cancel();
    unawaited(_feed?.dispose() ?? Future<void>.value());
    if (widget.reels) unawaited(ReelsProxy.disable());
    if (_invited) unawaited(ReelsInvite.stop(widget.pairId));
    super.dispose();
  }

  /// Адрес открытой комнаты: с роликом, если пришли из карточки или карусели,
  /// и со своим именем — иначе страница подписывает обоих «Гость». Браузер
  /// ходит мимо сетевого клиента Dart, поэтому на запасном пути страницу
  /// открываем прямо на edge (ссылка для партнёра остаётся прежней).
  String get _url => ServerRoute.instance.forNative(WatchRoomService.siteUrl(
    widget.room,
    src: widget.videoUrl,
    name: PocketBaseService().userName,
    reels: widget.reels,
    feed: widget.reels ? widget.reelsSource.key : null,
    build: widget.build,
    nativeWindow: _native,
  ));

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
    _say(LocaleService.current.linkCopied);
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
    if (_native) {
      _say(LocaleService.current.watchRoomBackAgain);
      return false;
    }
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
        // В «кино» «назад» сперва выключает режим, как в плеерах.
        if (_cinema) {
          unawaited(_web?.evaluateJavascript(
                source: 'window.roomExitCinema && window.roomExitCinema()',
              ) ??
              Future<void>.value());
          _setCinema(false);
          return;
        }
        if (_allowLeave() && mounted) unawaited(_leave());
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
        // В «кино» страница ложится во весь экран, иначе по краям оставались
        // поля цвета фона (обращение 488).
        top: !widget.reels && !_cinema,
        left: !_cinema,
        right: !_cinema,
        bottom: false,
        // Нативное окно комнаты система показывает поверх этого экрана: под
        // ним остаётся только ожидание, пока окно открывается и закрывается.
        child: _native ? Center(child: M3Loading(color: cs.primary)) : Stack(
          children: [
            InAppWebView(
              key: ValueKey<int>(_webLife),
              initialUrlRequest: URLRequest(url: WebUri(_url)),
              // Касание в зоне комнаты сразу уходит браузеру, не дожидаясь арены
              // жестов Flutter: на iPhone после рекламы оно иначе терялось, и
              // страница не отвечала ни на что (обращения 164, 178, 183, 190).
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
              },
              initialUserScripts: _scripts(MediaQuery.paddingOf(context)),
              initialSettings: _webSettings(),
              onWebViewCreated: _wire,
              onLoadStop: (c, _) => _onPageLoaded(c),
              onRenderProcessGone: (_, _) => _onRendererGone(),
            ),
            if (_loading) Center(child: M3Loading(color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
    );
  }

  /// Мосты страницы к приложению — одни на встроенный браузер и на нативное
  /// окно.
  void _wire(InAppWebViewController c) {
    _web = c;
    // Кнопка звонка стоит в шапке комнаты, а связь поднимает
    // приложение: у страницы нет ни микрофона пары, ни сигналинга.
    // Кнопки шапки страницы: «назад», «скопировать», «поделиться».
    c.addJavaScriptHandler(
      handlerName: 'watchBack',
      callback: (_) {
        if (mounted && _allowLeave()) unawaited(_leave());
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
      handlerName: 'watchCinema',
      callback: (args) {
        final info = (args.isNotEmpty && args.first is Map) ? args.first as Map : const {};
        _setCinema(info['on'] == true);
        return null;
      },
    );
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
  }

  /// Страница загрузилась (или перезагрузилась — поворот, возврат назад):
  /// она снова ничего не знает про звонок.
  void _onPageLoaded(InAppWebViewController c) {
    if (!mounted) return;
    setState(() => _loading = false);
    // Заново загруженная страница (поворот, гибель движка браузера) открывается
    // без «кино», и окну незачем оставаться без панелей.
    _setCinema(false);
    _pushVoice();
    if (widget.reels || _native) {
      unawaited(c.evaluateJavascript(source: _insetScript(MediaQuery.paddingOf(context))));
    }
    if (widget.reels && _thumbs.isNotEmpty) _pushThumbs(Map.of(_thumbs));
  }
}

/// Нативное окно комнаты: тот же браузер, но своим экраном поверх
/// приложения. Касания идут странице напрямую, мимо Flutter.
class _RoomWindow extends InAppBrowser {
  _RoomWindow({
    required this.onCreated,
    required this.onLoaded,
    required this.onClosed,
    super.initialUserScripts,
  });

  final void Function(InAppWebViewController controller) onCreated;
  final void Function(InAppWebViewController controller) onLoaded;
  final VoidCallback onClosed;

  @override
  void onBrowserCreated() {
    final c = webViewController;
    if (c != null) onCreated(c);
  }

  @override
  void onLoadStop(WebUri? url) {
    final c = webViewController;
    if (c != null) onLoaded(c);
  }

  @override
  void onExit() => onClosed();
}
