import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:video_player/video_player.dart';

import '../../services/locale_service.dart';
import '../../services/pb_media_service.dart';
import '../../services/pocketbase_service.dart';
import '../../services/watch_sync.dart';
import '../../services/watch_voice_service.dart';
import '../../services/watch_channel_service.dart';
import '../../services/watch_history_service.dart';
import '../../widgets/common/m3_loading.dart';
import '../../widgets/watch/watch_voice_bar.dart';

/// Нативный просмотр своего видео вдвоём.
///
/// Кадр рисует сам Flutter, поэтому управление мгновенное, а не через
/// встроенный браузер. Комната — тот же канал Centrifugo, что у сайта: пауза,
/// перемотка и подтяжка времени понятны и вкладке в браузере.
class WatchPlayerScreen extends StatefulWidget {
  final String room;
  final String pairId;

  /// Ссылка на файл: прямая или наша `pb://media/...` (её резолвим сами).
  final String url;
  final String title;

  const WatchPlayerScreen({
    super.key,
    required this.room,
    required this.pairId,
    required this.url,
    this.title = '',
  });

  @override
  State<WatchPlayerScreen> createState() => _WatchPlayerScreenState();
}

class _WatchPlayerScreenState extends State<WatchPlayerScreen>
    with SingleTickerProviderStateMixin {
  /// Расхождение, после которого догоняем партнёра. Меньше — дёргается на
  /// каждой мелочи, больше — заметно расходятся реплики в фильме.
  static const Duration _drift = Duration(milliseconds: 1500);

  VideoPlayerController? _video;
  WatchChannel? _room;
  /// Голосовая связь в комнате: микрофон, звук, соединение между двумя.
  WatchVoiceService? _voice;
  Timer? _heartbeat;
  Timer? _hideControls;

  bool _ready = false;
  bool _applying = false;

  /// Кто второй в комнате. Приходит с первым же сообщением партнёра и решает,
  /// кто задаёт время: отметку шлёт ровно один, иначе двое догоняют друг
  /// друга и видео дёргается назад каждые несколько секунд.
  String _peer = '';
  String _me = '';
  bool _controlsVisible = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final playable = await PbMediaService.instance.resolvePlayable(widget.url);
    final controller = VideoPlayerController.networkUrl(Uri.parse(playable));
    try {
      await controller.initialize();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = LocaleService.current.error);
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }

    controller.addListener(_onPlayerTick);
    final me = PocketBaseService().userId ?? 'app';
    _me = me;
    final room = WatchChannel(widget.room, me);
    await room.connect(_onRoomMessage);
    await room.send('hello');

    // Голос живёт в том же канале, что и команды плеера: отдельный сигналинг
    // ради двух человек — лишняя сущность, а комната у них уже общая.
    final voice = WatchVoiceService(channel: room, me: me);
    voice.addListener(_onVoiceChanged);

    setState(() {
      _video = controller;
      _room = room;
      _voice = voice;
      _ready = true;
    });

    _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      final v = _video;
      if (v == null || !v.value.isPlaying) return;
      // Отметку времени шлёт только ведущий. Обоюдный heartbeat и был
      // причиной рывков: каждый прыгал назад на дорогу чужого сообщения.
      if (!leadsSync(me: _me, peer: _peer)) return;
      room.send('sync',
          at: v.value.position.inMilliseconds / 1000, extra: {'playing': true});
    });
    _scheduleHide();
  }

  // ── разговор с комнатой ────────────────────────────────────────────────────

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  /// Включить или выключить разговор. Микрофон спрашивает сам WebRTC; отказ
  /// оставляет плеер как был, без разговоров.
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

  void _onRoomMessage(Map<String, dynamic> data) {
    // Сообщения голосовой связи (`voice-*`) разбирает сам сервис: плееру они
    // ничего не говорят.
    final voice = _voice;
    if (voice != null && (data['t'] ?? '').toString().startsWith('voice-')) {
      unawaited(voice.handleMessage(data));
      return;
    }
    final v = _video;
    if (v == null) return;
    final at = ((data['at'] ?? 0) as num).toDouble();
    final from = (data['from'] ?? '').toString();
    if (from.isNotEmpty && from != _me && from != _peer) _peer = from;

    switch (data['t']) {
      case 'play':
        _apply(play: true, at: at);
        break;
      case 'pause':
        _apply(play: false, at: at);
        break;
      case 'sync':
        // Ведущий свои же отметки не слушает: он и есть источник времени.
        if (leadsSync(me: _me, peer: _peer)) break;
        final target = catchUpTarget(
          mine: v.value.position,
          theirs: Duration(milliseconds: (at * 1000).round()),
          playing: data['playing'] == true,
          drift: _drift,
        );
        if (target != null) {
          _apply(
            play: data['playing'] == true,
            at: target.inMilliseconds / 1000,
          );
        }
        break;
      case 'hello':
        // Пришедшему позже рассказываем, что смотрим и с какой секунды.
        _room?.send('state',
            at: v.value.position.inMilliseconds / 1000,
            extra: {
              'to': data['from'],
              'url': widget.url,
              'playing': v.value.isPlaying,
            });
        break;
    }
  }

  Future<void> _apply({required bool play, required double at}) async {
    final v = _video;
    if (v == null) return;
    _applying = true;
    final target = Duration(milliseconds: (at * 1000).round());
    if ((v.value.position - target).abs() > _drift) await v.seekTo(target);
    if (play) {
      await v.play();
    } else {
      await v.pause();
    }
    Timer(const Duration(milliseconds: 400), () => _applying = false);
  }

  void _onPlayerTick() {
    if (mounted) setState(() {});
  }

  /// Кнопки нажимает человек — значит команда уходит партнёру.
  Future<void> _togglePlay() async {
    final v = _video;
    if (v == null) return;
    final at = v.value.position.inMilliseconds / 1000;
    if (v.value.isPlaying) {
      await v.pause();
      if (!_applying) await _room?.send('pause', at: at);
    } else {
      await v.play();
      if (!_applying) await _room?.send('play', at: at);
    }
    _scheduleHide();
  }

  Future<void> _seekTo(Duration position) async {
    final v = _video;
    if (v == null) return;
    await v.seekTo(position);
    if (_applying) return;
    await _room?.send(
      v.value.isPlaying ? 'play' : 'pause',
      at: position.inMilliseconds / 1000,
    );
  }

  // ── показ и скрытие кнопок ─────────────────────────────────────────────────

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 3), () {
      if (mounted && (_video?.value.isPlaying ?? false)) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _tapScreen() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _hideControls?.cancel();
    _voice?.removeListener(_onVoiceChanged);
    _voice?.dispose();
    _video?.removeListener(_onPlayerTick);
    final seconds = (_video?.value.position.inSeconds ?? 0);
    if (seconds > 5) {
      // Куда досмотрели — пригодится в «Недавнем».
      unawaited(WatchHistoryService.remember(
        groupId: widget.pairId,
        url: widget.url,
        kind: 'memory',
        title: widget.title,
        seconds: seconds,
      ));
    }
    _video?.dispose();
    unawaited(_room?.dispose() ?? Future<void>.value());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = _video;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error.isNotEmpty
            ? Center(
                child: Text(_error, style: TextStyle(color: cs.onSurface)),
              )
            : !_ready || v == null
                ? const Center(child: M3Loading(color: Colors.white))
                : GestureDetector(
                    onTap: _tapScreen,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: v.value.aspectRatio,
                            child: VideoPlayer(v),
                          ),
                        ),
                        _Controls(
                          visible: _controlsVisible,
                          playing: v.value.isPlaying,
                          position: v.value.position,
                          duration: v.value.duration,
                          title: widget.title,
                          onPlayPause: _togglePlay,
                          onSeek: _seekTo,
                          onClose: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
      ),
      // Голос стоит под кадром и не исчезает вместе со слоем управления: тот
      // прячется через несколько секунд, и вместе с ним пропадала кнопка
      // звонка. Говорить хотят и не глядя в экран, поэтому полоса постоянная.
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

/// Слой управления: появляется и уходит плавно, кнопки — крупные и круглые,
/// как велит язык форм Material 3.
class _Controls extends StatelessWidget {
  final bool visible;
  final bool playing;
  final Duration position;
  final Duration duration;
  final String title;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onClose;


  const _Controls({
    required this.visible,
    required this.playing,
    required this.position,
    required this.duration,
    required this.title,
    required this.onPlayPause,
    required this.onSeek,
    required this.onClose,
  });

  static String _stamp(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds;

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.72),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(color: Colors.white),
                    ),
                  ),
                  // Кнопок разговора здесь больше нет: они уехали в полосу
                  // под кадром. Слой управления сам прячется через несколько
                  // секунд, и вместе с ним пропадала возможность позвонить —
                  // а поговорить люди хотят и не глядя в экран.
                  const SizedBox(width: 12),
                ],
              ),
              const Spacer(),
              // Кнопка «играть» подрастает и меняет значок с переливом —
              // движение здесь важнее любой другой мелочи в кадре.
              AnimatedScale(
                scale: visible ? 1 : 0.85,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Material(
                  color: cs.primary,
                  shape: const CircleBorder(),
                  elevation: 0,
                  child: InkWell(
                    onTap: onPlayPause,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          key: ValueKey<bool>(playing),
                          color: cs.onPrimary,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 6,
                        activeTrackColor: cs.primary,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: cs.primary,
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                      ),
                      child: Slider(
                        value: position.inMilliseconds
                            .clamp(0, total)
                            .toDouble(),
                        max: total.toDouble(),
                        onChanged: (v) =>
                            onSeek(Duration(milliseconds: v.round())),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_stamp(position),
                            style: text.labelMedium?.copyWith(color: Colors.white)),
                        Text(_stamp(duration),
                            style: text.labelMedium?.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
