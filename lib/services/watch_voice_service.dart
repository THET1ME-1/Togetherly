import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'pb_data_service.dart';
import 'watch_channel_service.dart';

/// Состояние голосовой связи в комнате просмотра.
enum VoiceCallState {
  /// Микрофон выключен, связи нет.
  off,

  /// Договариваемся о соединении.
  connecting,

  /// Слышим друг друга.
  live,

  /// Соединение оборвалось, пробуем снова.
  failed,
}

/// Голос между двумя в комнате совместного просмотра.
///
/// Разговор идёт напрямую между устройствами (WebRTC), сервер только знакомит
/// их: предложения и ответы летят тем же каналом `watch:<код>`, что и команды
/// плеера. Ретранслятор (TURN) подключается, когда прямой дороги нет — у
/// российских операторов сплошной CGNAT, и без него связь просто не встаёт.
///
/// Кто звонит первым, решает код комнаты и uid: чтобы двое не начали
/// договариваться одновременно и не перебили друг друга, предложение делает
/// тот, чей uid «больше». Второй ждёт и отвечает.
class WatchVoiceService extends ChangeNotifier {
  WatchVoiceService({required this.channel, required this.me});

  final WatchChannel channel;

  /// Наш uid в комнате.
  final String me;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;
  final List<RTCIceCandidate> _pending = [];
  String _peer = '';
  bool _polite = false;
  bool _negotiating = false;

  VoiceCallState _state = VoiceCallState.off;
  VoiceCallState get state => _state;

  bool _micOn = false;
  bool _speakerOn = true;

  /// Микрофон включён (нас слышно).
  bool get micOn => _micOn;

  /// Звук включён (мы слышим).
  bool get speakerOn => _speakerOn;

  bool get active => _state != VoiceCallState.off;

  void _set(VoiceCallState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  /// Включить микрофон и позвать собеседника.
  Future<void> start() async {
    if (_state != VoiceCallState.off) return;
    _set(VoiceCallState.connecting);
    try {
      _local = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      _micOn = true;
      await _ensurePeer();
      // Зовём собеседника: он поднимет свою сторону и ответит.
      await channel.send('voice-hello', extra: {'uid': me});
      notifyListeners();
    } catch (e) {
      debugPrint('WatchVoice.start failed: $e');
      await stop();
      _set(VoiceCallState.failed);
    }
  }

  /// Выключить микрофон и разорвать связь.
  Future<void> stop() async {
    _negotiating = false;
    _pending.clear();
    try {
      await channel.send('voice-bye', extra: {'uid': me});
    } catch (_) {/* канал мог уже закрыться */}
    await _local?.dispose();
    _local = null;
    await _remote?.dispose();
    _remote = null;
    await _pc?.close();
    _pc = null;
    _peer = '';
    _micOn = false;
    _set(VoiceCallState.off);
  }

  /// Заглушить или вернуть свой микрофон, не разрывая связь.
  void toggleMic() {
    final track = _local?.getAudioTracks().firstOrNull;
    if (track == null) return;
    _micOn = !_micOn;
    track.enabled = _micOn;
    notifyListeners();
  }

  /// Заглушить или вернуть звук собеседника.
  void toggleSpeaker() {
    _speakerOn = !_speakerOn;
    for (final t in _remote?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = _speakerOn;
    }
    notifyListeners();
  }

  /// Разбор сообщений комнаты. Возвращает true, если сообщение наше и экрану
  /// его показывать не нужно.
  Future<bool> handleMessage(Map<String, dynamic> msg) async {
    final type = (msg['t'] ?? '').toString();
    if (!type.startsWith('voice-')) return false;
    final from = (msg['from'] ?? msg['uid'] ?? '').toString();

    switch (type) {
      case 'voice-hello':
        // Нас зовут. Если микрофон уже включён — отвечаем предложением, если
        // нет, сообщение просто игнорируем: навязывать разговор нельзя.
        if (_state == VoiceCallState.off) return true;
        _peer = from;
        _polite = me.compareTo(from) < 0;
        if (!_polite) await _offer();
        break;
      case 'voice-offer':
        if (_state == VoiceCallState.off) return true;
        _peer = from;
        _polite = me.compareTo(from) < 0;
        await _ensurePeer();
        await _pc!.setRemoteDescription(
            RTCSessionDescription(msg['sdp']?.toString(), 'offer'));
        await _drainPending();
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        await channel.send('voice-answer',
            extra: {'uid': me, 'sdp': answer.sdp});
        break;
      case 'voice-answer':
        if (_pc == null) return true;
        await _pc!.setRemoteDescription(
            RTCSessionDescription(msg['sdp']?.toString(), 'answer'));
        await _drainPending();
        break;
      case 'voice-ice':
        final c = RTCIceCandidate(
          msg['candidate']?.toString(),
          msg['sdpMid']?.toString(),
          (msg['sdpMLineIndex'] as num?)?.toInt(),
        );
        // Кандидат мог приехать раньше описания — тогда держим его до тех пор,
        // пока соединению будет куда его положить.
        if (_pc == null || (await _pc!.getRemoteDescription()) == null) {
          _pending.add(c);
        } else {
          await _pc!.addCandidate(c);
        }
        break;
      case 'voice-bye':
        if (from == _peer) await stop();
        break;
    }
    return true;
  }

  Future<void> _ensurePeer() async {
    if (_pc != null) return;
    final ice = await PbDataService().iceServers();
    _pc = await createPeerConnection({
      'iceServers': ice,
      'sdpSemantics': 'unified-plan',
    });

    for (final track in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await _pc!.addTrack(track, _local!);
    }

    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      channel.send('voice-ice', extra: {
        'uid': me,
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    _pc!.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remote = event.streams.first;
      for (final t in _remote!.getAudioTracks()) {
        t.enabled = _speakerOn;
      }
      _set(VoiceCallState.live);
    };
    _pc!.onConnectionState = (s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _set(VoiceCallState.live);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _set(VoiceCallState.failed);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _set(VoiceCallState.connecting);
          break;
        default:
          break;
      }
    };
  }

  Future<void> _offer() async {
    if (_negotiating) return;
    _negotiating = true;
    try {
      await _ensurePeer();
      final offer = await _pc!.createOffer({'offerToReceiveAudio': 1});
      await _pc!.setLocalDescription(offer);
      await channel.send('voice-offer', extra: {'uid': me, 'sdp': offer.sdp});
    } catch (e) {
      debugPrint('WatchVoice._offer failed: $e');
      _set(VoiceCallState.failed);
    } finally {
      _negotiating = false;
    }
  }

  Future<void> _drainPending() async {
    if (_pc == null) return;
    for (final c in _pending) {
      try {
        await _pc!.addCandidate(c);
      } catch (e) {
        debugPrint('WatchVoice: кандидат не лёг: $e');
      }
    }
    _pending.clear();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
