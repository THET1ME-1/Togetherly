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

  String get _uid => _fb.uid ?? '';

  // Якорь для расчёта ожидаемой позиции: фиксируем позицию и локальное время
  // её получения — так расчёт не зависит от расхождения часов устройств.
  int _remoteBaseMs = 0;
  int _remoteBaseAt = 0;
  bool _remotePlaying = false;

  String _currentMediaId = '';
  bool _applyingRemote = false; // подавляет эхо при применении удалённого состояния
  bool _lastIsPlaying = false;
  int _lastPosMs = 0;
  bool _ended = false;

  static const int _driftThresholdMs = 1500;
  static const int _seekJumpMs = 2500; // скачок позиции = пользовательский seek

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

    // Смена видео.
    if (state.mediaId.isNotEmpty && state.mediaId != _currentMediaId) {
      _currentMediaId = state.mediaId;
      _applyingRemote = true;
      _controller.load(state.mediaId);
      _applyingRemote = false;
    }

    // Якорим позицию по моменту получения (обходит расхождение часов).
    final nowLocal = DateTime.now().millisecondsSinceEpoch;
    _remoteBaseMs = state.positionMs;
    _remoteBaseAt = nowLocal;
    _remotePlaying = state.isPlaying;

    _applyingRemote = true;
    final target = _expectedRemoteMs();
    final curMs = _controller.value.position.inMilliseconds;
    if ((curMs - target).abs() > _driftThresholdMs) {
      _controller.seekTo(Duration(milliseconds: target));
    }
    if (state.isPlaying && !_controller.value.isPlaying) {
      _controller.play();
    } else if (!state.isPlaying && _controller.value.isPlaying) {
      _controller.pause();
    }
    _lastIsPlaying = state.isPlaying;
    _lastPosMs = target;
    _applyingRemote = false;
    if (mounted) setState(() {});
  }

  int _expectedRemoteMs() {
    if (!_remotePlaying) return _remoteBaseMs;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _remoteBaseAt;
    return _remoteBaseMs + (elapsed > 0 ? elapsed : 0);
  }

  // ── Локальные действия пользователя → пуш в RTDB ──────────────────────────
  void _onPlayerEvent() {
    if (_applyingRemote || _ended) return;
    final v = _controller.value;
    final posMs = v.position.inMilliseconds;
    final playing = v.isPlaying;

    final playStateChanged = playing != _lastIsPlaying;
    final seeked = (posMs - _lastPosMs).abs() > _seekJumpMs;

    _lastIsPlaying = playing;
    _lastPosMs = posMs;

    if (playStateChanged || seeked) {
      _push(playing, posMs);
    }
  }

  void _push(bool playing, int posMs) {
    _session.pushAction(
      pairId: widget.pairId,
      isPlaying: playing,
      positionMs: posMs,
    );
  }

  // Пульс шлёт только тот, кто инициировал последнее действие (мы — последний
  // controller, пока партнёр не перехватил), чтобы партнёр корректировал дрейф.
  void _maybeHeartbeat() {
    if (_ended || !mounted) return;
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
            ],
          ),
        );
      },
    );
  }
}
