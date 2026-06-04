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

  // Эфемерный чат сеанса (RTDB, 0 Firestore-чтений).
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  final List<ChatMessage> _messages = [];
  StreamSubscription<ChatMessage>? _chatSub;

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

  // Последнее ПРИМЕНЁННОЕ действие партнёра (seq + кто его сделал). pushAction
  // всегда инкрементит seq, а правки presence/chat — нет. Поэтому если seq и
  // контроллер не изменились, пришедший onValue — это всего лишь обновление
  // презенса/чата в том же узле, и трогать плеер не нужно (иначе сообщения в
  // чате вызывают микро-перемотки видео).
  int _lastRemoteSeq = -1;
  String _lastRemoteController = '';

  /// YouTube вернул ошибку встраивания (101/150 — владелец запретил
  /// воспроизведение вне youtube.com). Такое видео не проиграть нигде, кроме
  /// сайта/приложения YouTube — показываем понятное сообщение.
  bool _embedError = false;

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
    _chatSub = _session.watchChatMessages(widget.pairId).listen((m) {
      if (!mounted) return;
      setState(() => _messages.add(m));
      _scrollChatToBottom();
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

    // Тот же seq и контроллер, что уже применяли → это правка presence/chat в
    // том же узле, а не новое действие плеера. Не пере-якорим и не дёргаем плеер.
    if (state.seq == _lastRemoteSeq &&
        state.controllerUid == _lastRemoteController) {
      return;
    }
    _lastRemoteSeq = state.seq;
    _lastRemoteController = state.controllerUid;

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

    // Ошибки встраивания YouTube: 101 и 150 — владелец запретил
    // воспроизведение вне youtube.com. 100 — видео удалено/приватное.
    final embedBlocked =
        v.errorCode == 101 || v.errorCode == 150 || v.errorCode == 100;
    if (embedBlocked != _embedError && mounted) {
      setState(() => _embedError = embedBlocked);
    }

    // Во время буферизации/догрузки YouTube кратко отдаёт isPlaying=false и
    // прыгающую позицию — это НЕ действие пользователя. Реагируем только на
    // устойчивые playing/paused, иначе у партнёра видео дёргается (стоп-старт
    // «играет секунду — встало»). Базовые значения тоже не сдвигаем, чтобы
    // реальный seek, случившийся вокруг буфера, не потерялся.
    final st = v.playerState;
    if (st != PlayerState.playing && st != PlayerState.paused) return;

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

  void _sendChat() {
    final t = _chatCtrl.text.trim();
    if (t.isEmpty) return;
    _session.sendChatMessage(pairId: widget.pairId, text: t);
    _chatCtrl.clear();
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _sessionSub?.cancel();
    _presenceSub?.cancel();
    _chatSub?.cancel();
    _chatCtrl.dispose();
    _chatScroll.dispose();
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

  // Сеанс всегда 1-на-1, поэтому «партнёр на месте» = в презенсе есть любой
  // uid, кроме моего. Не завязываемся на конкретный widget.partnerUid: он может
  // прийти пустым/неверным, и тогда висело бы «ожидаем партнёра», хотя оба тут.
  bool get _partnerHere => _present.any((u) => u.isNotEmpty && u != _uid);

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

  Widget _buildEmbedErrorOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.92),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline_rounded,
              color: Colors.white70, size: 40),
          const SizedBox(height: 14),
          const Text(
            'Это видео нельзя смотреть вместе',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Автор ролика запретил воспроизведение вне YouTube. '
            'Выберите другое видео — большинство роликов работает.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: () => _exit(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('Выбрать другое'),
          ),
        ],
      ),
    );
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
              Stack(
                children: [
                  player,
                  if (_embedError)
                    Positioned.fill(child: _buildEmbedErrorOverlay()),
                ],
              ),
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
              const SizedBox(height: 12),
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
              const Divider(color: Colors.white12, height: 16),
              Expanded(child: _buildChatList()),
              _buildChatInput(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChatList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'Напишите первое сообщение 💬',
          style: TextStyle(color: Colors.white24, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      controller: _chatScroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final mine = m.uid == _uid;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            decoration: BoxDecoration(
              color: mine ? const Color(0xFFEC4899) : Colors.white12,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              m.text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatInput() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatCtrl,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendChat(),
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Сообщение…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white10,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: Color(0xFFEC4899)),
              onPressed: _sendChat,
            ),
          ],
        ),
      ),
    );
  }
}
