import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';

class PairData extends ChangeNotifier {
  bool _isPaired = false;
  DateTime? _startDate;
  String _myName = 'You';
  String _partnerName = '';
  String _partnerAvatarUrl = '';
  String _inviteCode = '';
  String _pairId = '';
  bool _loading = false;

  StreamSubscription? _pairSub;
  final FirebaseService _fb = FirebaseService();

  // ── Getters ──
  bool get isPaired => _isPaired;
  DateTime? get startDate => _startDate;
  String get myName => _myName;
  String get partnerName => _partnerName;
  String get partnerAvatarUrl => _partnerAvatarUrl;
  String get inviteCode => _inviteCode;
  String get pairId => _pairId;
  bool get loading => _loading;

  String get inviteLink => 'https://togetherly.app/invite/$_inviteCode';

  // ── Counter values ──
  int get daysInLove {
    if (!_isPaired || _startDate == null) return 0;
    return DateTime.now().difference(_startDate!).inDays;
  }

  int get monthsInLove {
    if (!_isPaired || _startDate == null) return 0;
    final now = DateTime.now();
    int months =
        (now.year - _startDate!.year) * 12 + now.month - _startDate!.month;
    if (now.day < _startDate!.day) months--;
    return months;
  }

  Duration get timeInLove {
    if (!_isPaired || _startDate == null) return Duration.zero;
    return DateTime.now().difference(_startDate!);
  }

  // ── Инициализация ──
  Future<void> init({required String myName}) async {
    _myName = myName;

    // Загружаем локальный кэш в любом случае
    await _loadLocal();

    // Если кода нет в кэше — генерируем локальный
    if (_inviteCode.isEmpty) {
      _inviteCode = _generateLocalCode();
      await _saveLocal();
    }
    notifyListeners();

    if (!_fb.isLoggedIn) {
      debugPrint('PairData.init: user not logged in to Firebase');
      return;
    }

    // Пытаемся получить код из Firestore (если доступен)
    final firestoreCode = await _fb.generateInviteCode();
    if (firestoreCode.isNotEmpty && firestoreCode != _inviteCode) {
      _inviteCode = firestoreCode;
      await _saveLocal();
      notifyListeners();
    }

    // Проверяем пару
    await _refreshPairStatus();
  }

  Future<void> _refreshPairStatus() async {
    try {
      final pairData = await _fb.loadPairData();
      if (pairData != null) {
        _isPaired = true;
        _pairId = pairData['pairId'] ?? '';
        _startDate = pairData['startDate'] as DateTime?;

        // Имя и аватар партнёра уже определены в loadPairData
        _partnerName = pairData['partnerName'] ?? '';
        _partnerAvatarUrl = pairData['partnerAvatar'] ?? '';

        await _saveLocal();
        _listenToPair();
      } else {
        _isPaired = false;
        _partnerName = '';
        _partnerAvatarUrl = '';
        _pairId = '';
        _startDate = null;
        await _saveLocal();
      }
    } catch (e) {
      debugPrint('Pair refresh failed: $e');
    }
    notifyListeners();
  }

  void _listenToPair() {
    _pairSub?.cancel();
    if (_pairId.isEmpty) return;

    _pairSub = _fb.listenToPair(
      pairId: _pairId,
      onData: (data) {
        if (data == null) {
          // Пара удалена
          _isPaired = false;
          _pairId = '';
          _partnerName = '';
          _partnerAvatarUrl = '';
          _startDate = null;
          _saveLocal();
          notifyListeners();
          return;
        }

        _partnerName = data['partnerName'] ?? _partnerName;
        _partnerAvatarUrl = data['partnerAvatar'] ?? _partnerAvatarUrl;
        _startDate = data['startDate'] as DateTime? ?? _startDate;
        _saveLocal();
        notifyListeners();
      },
    );
  }

  // ── Actions ──
  void setMyName(String name) {
    _myName = name;
    notifyListeners();
  }

  /// Принять код партнёра — реальная связка через Firestore
  Future<bool> acceptCode(String code) async {
    if (code.toUpperCase() == _inviteCode.toUpperCase()) {
      return false; // нельзя связать себя с собой
    }

    _loading = true;
    notifyListeners();

    try {
      final result = await _fb.acceptInviteCode(code.toUpperCase());
      if (result['success'] == true) {
        await _refreshPairStatus();
        _loading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Accept code failed: $e');
    }

    _loading = false;
    notifyListeners();
    return false;
  }

  /// Свой ли код?
  bool isSelfCode(String code) {
    return code.toUpperCase() == _inviteCode.toUpperCase();
  }

  /// Разорвать пару
  Future<void> unpair() async {
    _loading = true;
    notifyListeners();

    try {
      await _fb.unpair();
    } catch (e) {
      debugPrint('Unpair failed: $e');
    }

    _pairSub?.cancel();
    _isPaired = false;
    _startDate = null;
    _partnerName = '';
    _partnerAvatarUrl = '';
    _pairId = '';

    // Генерируем новый код (с fallback)
    final firestoreCode = await _fb.generateInviteCode();
    _inviteCode = firestoreCode.isNotEmpty
        ? firestoreCode
        : _generateLocalCode();

    _loading = false;
    await _saveLocal();
    notifyListeners();
  }

  /// Перегенерация кода
  Future<void> regenerateCode() async {
    final firestoreCode = await _fb.generateInviteCode();
    _inviteCode = firestoreCode.isNotEmpty
        ? firestoreCode
        : _generateLocalCode();
    await _saveLocal();
    notifyListeners();
  }

  // ── Локальный кэш ──
  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pair_isPaired', _isPaired);
      await prefs.setString('pair_partnerName', _partnerName);
      await prefs.setString('pair_partnerAvatar', _partnerAvatarUrl);
      await prefs.setString('pair_inviteCode', _inviteCode);
      await prefs.setString('pair_pairId', _pairId);
      if (_startDate != null) {
        await prefs.setString('pair_startDate', _startDate!.toIso8601String());
      }
    } catch (_) {}
  }

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isPaired = prefs.getBool('pair_isPaired') ?? false;
      _partnerName = prefs.getString('pair_partnerName') ?? '';
      _partnerAvatarUrl = prefs.getString('pair_partnerAvatar') ?? '';
      _inviteCode = prefs.getString('pair_inviteCode') ?? '';
      _pairId = prefs.getString('pair_pairId') ?? '';
      final sd = prefs.getString('pair_startDate');
      if (sd != null) _startDate = DateTime.tryParse(sd);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pairSub?.cancel();
    super.dispose();
  }

  // ── Helpers ──
  static String _generateLocalCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
