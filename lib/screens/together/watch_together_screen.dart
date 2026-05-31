import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../services/firebase_service.dart';
import '../../services/together_session_service.dart';

/// Совместный просмотр YouTube. Синхронизация play/pause/seek идёт через RTDB
/// (TogetherSessionService) — ноль Firestore-чтений. Видео стримится с серверов
/// YouTube напрямую на каждое устройство.
class WatchTogetherScreen extends StatefulWidget {
  /// ID группы (пары) — ключ RTDB-сессии.
  final String pairId;

  /// UID партнёра — нужен хосту, чтобы сразу прописать обоих в members.
  final String partnerUid;

  /// YouTube videoId. Для хоста — стартовое видео; гость получит его из RTDB.
  final String videoId;

  /// true — этот клиент создаёт сеанс; false — присоединяется к существующему.
  final bool isHost;

  const WatchTogetherScreen({
    super.key,
    required this.pairId,
    required this.partnerUid,
    required this.videoId,
    required this.isHost,
  });

  @override
  State<WatchTogetherScreen> createState() => _WatchTogetherScreenState();
}

class _WatchTogetherScreenState extends State<WatchTogetherScreen> {
  final _session = TogetherSessionService.instance;
  final _fb = FirebaseService();

  late YoutubePlayerController _controller;
  StreamSubscription<LiveSessionState?>? _sessionSub;
  StreamSubscription<Set<String>>? _presenceSub;
  Timer? _heartbeat;

  Set<String> _present = {};

  // Громкость видео — локальная (у каждого своя, не синкается → 0 записей).
  int _volume = 100;
  bool _muted = false;

  String get _uid => _fb.uid ?? '';

  // Якорь для расчёта ожидаемой позиции: фиксируем позицию и локальное время
  // её получения — так расчёт не зависит от расхождения часов устройств.
  int _remoteBaseMs = 0;
  int _remoteBaseAt = 0;
  bool _remotePlaying = false;

  String _currentMediaId = '';
  bool _lastIsPlaying = false;
  int _lastPosMs = 0;
  bool _ended = false;

  // Эхо-подавление по времени, а не флагом: seekTo/play/pause у плеера
  // применяются АСИНХРОННО (JS round-trip), и их событие приходит уже после
  // того, как синхронный флаг сброшен. Поэтому после применения удалённого
  // состояния глушим локальные пуши на окно времени, иначе устройства
  // зацикливаются, пиная друг друга («срабатывает через раз»).
  DateTime _suppressLocalUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // Кто сейчас «ведущий» — только он шлёт heartbeat, чтобы оба не пушили
  // одновременно и не создавали ping-pong микро-перемоток.
  late bool _iAmController = widget.isHost;

  static const int _driftThresholdMs = 1500;
  static const int _seekJumpMs = 2000; // скачок позиции = пользовательский seek
  static const Duration _suppressWindow = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    _currentMediaId = widget.videoId;
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        enableCaption: false,
        hideControls: false,
      ),
    )..addListener(_onPlayerEvent);

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (widget.isHost) {
      await _session.startSession(
        pairId: widget.pairId,
        partnerUid: widget.partnerUid,
        activity: TogetherActivity.youtube,
        mediaId: widget.videoId,
      );
      await _fb.setActiveSession(
        groupId: widget.pairId,
        activity: TogetherActivity.youtube.id,
        mediaId: widget.videoId,
        hostName: _fb.displayName,
      );
    } else {
      await _session.joinPresence(widget.pairId);
    }
    _sessionSub = _session.watch(widget.pairId).listen(_onRemoteState);
    _presenceSub = _session.watchPresence(widget.pairId).listen((p) {
      if (mounted) setState(() => _present = p);
    });
    _heartbeat = Timer.periodic(const Duration(seconds: 8), (_) => _maybeHeartbeat());
  }

  // ── Применение удалённого состояния к плееру ──────────────────────────────
  void _onRemoteState(LiveSessionState? state) {
    if (!mounted) return;
    if (state == null) {
      // Сеанс завершён партнёром.
      if (!_ended) _exit(closedByPartner: true);
      return;
    }
    // Наш собственный апдейт, вернувшийся через onValue — игнорируем эхо.
    if (state.controllerUid == _uid && state.seq == _session.lastLocalSeq) {
      return;
    }

    // Удалённое состояние пришло от партнёра → ведущий теперь он.
    _iAmController = false;

    // Смена видео.
    if (state.mediaId.isNotEmpty && state.mediaId != _currentMediaId) {
      _currentMediaId = state.mediaId;
      _suppressLocalUntil = DateTime.now().add(_suppressWindow);
      _controller.load(state.mediaId);
    }

    // Якорим позицию по моменту получения (обходит расхождение часов).
    final nowLocal = DateTime.now().millisecondsSinceEpoch;
    _remoteBaseMs = state.positionMs;
    _remoteBaseAt = nowLocal;
    _remotePlaying = state.isPlaying;

    final target = _expectedRemoteMs();
    final curMs = _controller.value.position.inMilliseconds;
    final needSeek = (curMs - target).abs() > _driftThresholdMs;
    final needPlay = state.isPlaying && !_controller.value.isPlaying;
    final needPause = !state.isPlaying && _controller.value.isPlaying;

    // Глушим локальные пуши до того, как применяем — событие плеера придёт
    // асинхронно и попадёт в окно.
    if (needSeek || needPlay || needPause) {
      _suppressLocalUntil = DateTime.now().add(_suppressWindow);
    }
    if (needSeek) {
      _controller.seekTo(Duration(milliseconds: target));
    }
    if (needPlay) {
      _controller.play();
    } else if (needPause) {
      _controller.pause();
    }
    _lastIsPlaying = state.isPlaying;
    _lastPosMs = target;
    if (mounted) setState(() {});
  }

  int _expectedRemoteMs() {
    if (!_remotePlaying) return _remoteBaseMs;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _remoteBaseAt;
    return _remoteBaseMs + (elapsed > 0 ? elapsed : 0);
  }

  // ── Локальные действия пользователя → пуш в RTDB ──────────────────────────
  void _onPlayerEvent() {
    if (_ended) return;
    final v = _controller.value;
    final posMs = v.position.inMilliseconds;
    final playing = v.isPlaying;

    final playStateChanged = playing != _lastIsPlaying;
    final seeked = (posMs - _lastPosMs).abs() > _seekJumpMs;

    // Базовые значения обновляем ВСЕГДА (в т.ч. в окне подавления), иначе
    // после окна старый baseline даст ложный «seek».
    _lastIsPlaying = playing;
    _lastPosMs = posMs;

    // В окне подавления (только что применили удалённое состояние) не пушим —
    // это эхо наших же seekTo/play/pause.
    if (DateTime.now().isBefore(_suppressLocalUntil)) return;

    if (playStateChanged || seeked) {
      _push(playing, posMs);
    }
  }

  void _push(bool playing, int posMs) {
    // Любое наше действие делает нас ведущим (heartbeat теперь шлём мы).
    _iAmController = true;
    _session.pushAction(
      pairId: widget.pairId,
      isPlaying: playing,
      positionMs: posMs,
    );
  }

  // Пульс шлёт только ведущий, чтобы оба устройства не пушили одновременно и
  // не создавали ping-pong микро-перемоток. Даёт партнёру свежий якорь дрейфа.
  void _maybeHeartbeat() {
    if (_ended || !mounted || !_iAmController) return;
    if (!_controller.value.isPlaying) return;
    _push(true, _controller.value.position.inMilliseconds);
  }

  // ── Завершение ────────────────────────────────────────────────────────────
  void _exit({bool closedByPartner = false}) {
    if (_ended) return;
    _ended = true;
    _heartbeat?.cancel();
    _sessionSub?.cancel();
    _presenceSub?.cancel();
    // Очистка fire-and-forget — это вызовы синглтон-сервиса/Firestore, не
    // привязаны к жизненному циклу виджета и завершатся после pop.
    if (widget.isHost) {
      _session.endSession(widget.pairId);
      _fb.clearActiveSession(widget.pairId);
    } else {
      _session.leavePresence(widget.pairId);
    }
    if (!mounted) return;
    if (closedByPartner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Партнёр завершил совместный просмотр')),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _sessionSub?.cancel();
    _presenceSub?.cancel();
    _controller.removeListener(_onPlayerEvent);
    _controller.dispose();
    // Страховка: снимаем презенс/сеанс, если экран закрыли мимо _exit
    // (системный жест/смена роута). Без await — dispose не async.
    if (!_ended) {
      if (widget.isHost) {
        _session.endSession(widget.pairId);
        _fb.clearActiveSession(widget.pairId);
      } else {
        _session.leavePresence(widget.pairId);
      }
    }
    super.dispose();
  }

  bool get _partnerHere =>
      widget.partnerUid.isNotEmpty && _present.contains(widget.partnerUid);

  void _setVolume(int v) {
    setState(() {
      _volume = v;
      _muted = v == 0;
    });
    _controller.setVolume(v);
  }

  void _toggleMute() {
    if (_muted) {
      // Восстанавливаем прежний уровень (или 100, если был 0).
      final restore = _volume == 0 ? 100 : _volume;
      setState(() {
        _muted = false;
        _volume = restore;
      });
      _controller.setVolume(restore);
    } else {
      setState(() => _muted = true);
      _controller.setVolume(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: true,
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Смотрим вместе'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => _exit(),
            ),
            actions: [
              // Счётчик участников сеанса.
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Icon(
                      _partnerHere ? Icons.people_alt_rounded : Icons.person_rounded,
                      size: 18,
                      color: _partnerHere ? Colors.greenAccent : Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_present.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              player,
              const SizedBox(height: 16),
              // Статус подключения партнёра.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _partnerHere ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                    color: _partnerHere ? Colors.greenAccent : Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _partnerHere
                        ? 'Партнёр подключился'
                        : 'Ожидаем партнёра…',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sync, color: Colors.white38, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    _remotePlaying ? 'Синхронизировано · играет' : 'Синхронизировано · пауза',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // ── Громкость видео (локальная) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _muted || _volume == 0
                            ? Icons.volume_off_rounded
                            : (_volume < 50
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded),
                        color: Colors.white,
                      ),
                      onPressed: _toggleMute,
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          value: (_muted ? 0 : _volume).toDouble(),
                          min: 0,
                          max: 100,
                          onChanged: (v) => _setVolume(v.round()),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${_muted ? 0 : _volume}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
