import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';

enum Gender { male, female }

class UserData extends ChangeNotifier {
  String _displayName = '';
  String _email = '';
  String _avatarUrl = '';
  Gender? _gender;
  bool _isRegistered = false;
  bool _hasSeenWelcome = false;
  String _uid = '';

  final FirebaseService _fb = FirebaseService();

  // ── Getters ──
  String get displayName => _displayName;
  String get email => _email;
  String get avatarUrl => _avatarUrl;
  Gender? get gender => _gender;
  bool get isRegistered => _isRegistered;
  bool get hasSeenWelcome => _hasSeenWelcome;
  String get uid => _uid;

  bool get isMale => _gender == Gender.male;
  bool get isFemale => _gender == Gender.female;

  // ── Тема оформления ──────────────────────────────────────────────────────
  int _themeId = -1; // -1 → используется тема по умолчанию (pink)
  bool _blobAnimationEnabled = true;

  int get themeId {
    if (_themeId >= 0 && _themeId < AppThemes.all.length) return _themeId;
    return 0; // default = pink
  }

  /// Полный объект активной темы со всеми цветами
  AppTheme get theme => AppThemes.byIndex(themeId);

  // Алиасы для удобства (используются в экранах)
  bool get isPurpleTheme => themeId == 1;
  Color get themeAccent => theme.primary;
  Color get themeAccentLight => theme.primaryLight;
  String get themeName => theme.name;

  /// Whether the timer card shows a morphing blob shape (true by default)
  bool get blobAnimationEnabled => _blobAnimationEnabled;

  String get initials {
    if (_displayName.isEmpty) return '?';
    final parts = _displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return _displayName[0].toUpperCase();
  }

  // ── Persistence (локальный кэш + Firestore) ──
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasSeenWelcome = prefs.getBool('hasSeenWelcome') ?? false;
      _isRegistered = prefs.getBool('isRegistered') ?? false;
      _displayName = prefs.getString('displayName') ?? '';
      _email = prefs.getString('email') ?? '';
      _avatarUrl = prefs.getString('avatarUrl') ?? '';
      _uid = prefs.getString('uid') ?? '';
      final genderStr = prefs.getString('gender');
      if (genderStr == 'male') _gender = Gender.male;
      if (genderStr == 'female') _gender = Gender.female;
      _themeId = prefs.getInt('themeId') ?? -1;
      _blobAnimationEnabled = prefs.getBool('blobAnimationEnabled') ?? true;

      // Если авторизован → подтягиваем из облака
      if (_fb.isLoggedIn && _isRegistered) {
        _uid = _fb.uid ?? _uid;
        await _syncFromFirestore();
      }
    } catch (e) {
      debugPrint('SharedPreferences load failed: $e');
    }
    notifyListeners();
  }

  Future<void> _syncFromFirestore() async {
    try {
      final data = await _fb.loadUserProfile();
      if (data != null) {
        _displayName = data['displayName'] ?? _displayName;
        _email = data['email'] ?? _email;
        _avatarUrl = data['avatarUrl'] ?? _avatarUrl;
        final g = data['gender'] as String?;
        if (g == 'male') _gender = Gender.male;
        if (g == 'female') _gender = Gender.female;
        await _saveLocal();
      }
    } catch (e) {
      debugPrint('Firestore sync failed: $e');
    }
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenWelcome', _hasSeenWelcome);
      await prefs.setBool('isRegistered', _isRegistered);
      await prefs.setString('displayName', _displayName);
      await prefs.setString('email', _email);
      await prefs.setString('avatarUrl', _avatarUrl);
      await prefs.setString('uid', _uid);
      await prefs.setString(
        'gender',
        _gender == Gender.male
            ? 'male'
            : _gender == Gender.female
            ? 'female'
            : '',
      );
      await prefs.setInt('themeId', _themeId);
      await prefs.setBool('blobAnimationEnabled', _blobAnimationEnabled);
    } catch (e) {
      debugPrint('SharedPreferences save failed: $e');
    }
  }

  // ── Actions ──
  Future<void> markWelcomeSeen() async {
    _hasSeenWelcome = true;
    await _saveLocal();
    notifyListeners();
  }

  Future<void> register({
    required String displayName,
    required String email,
    required Gender gender,
    String avatarUrl = '',
    bool isReturningUser = false, // For login - don't clear data
  }) async {
    // Clear old connection data when registering new user
    final prefs = await SharedPreferences.getInstance();
    final storedUid = prefs.getString('uid') ?? '';
    final currentUid = _fb.uid ?? '';

    // isNewUser = UID changed AND this is NOT a returning user (login)
    final isNewUser =
        storedUid != currentUid && currentUid.isNotEmpty && !isReturningUser;

    // If UID changed and this is fresh registration, clear ALL old data
    if (isNewUser) {
      await prefs.remove('connections');
      await prefs.remove('activeConnectionIndex');
      await prefs.remove('user_timers');
      await prefs.remove('timer_selected_time_unit');
      debugPrint(
        'Cleared old connections & timers for new user: $storedUid -> $currentUid',
      );
    }

    _displayName = displayName;
    _email = email;
    _gender = gender;
    _avatarUrl = avatarUrl;
    _isRegistered = true;
    _uid = _fb.uid ?? '';

    await _saveLocal();

    if (_fb.isLoggedIn) {
      await _fb.saveUserProfile(
        displayName: displayName,
        email: email,
        gender: gender == Gender.male ? 'male' : 'female',
        avatarUrl: avatarUrl,
        clearPairData: isNewUser, // Clear Firestore pair data for new users
      );
    }
    notifyListeners();
  }

  Future<void> updateProfile({
    String? displayName,
    String? email,
    String? avatarUrl,
    Gender? gender,
  }) async {
    if (displayName != null) _displayName = displayName;
    if (email != null) _email = email;
    if (avatarUrl != null) _avatarUrl = avatarUrl;
    if (gender != null) _gender = gender;
    await _saveLocal();

    if (_fb.isLoggedIn) {
      await _fb.saveUserProfile(
        displayName: _displayName,
        email: _email,
        gender: _gender == Gender.male ? 'male' : 'female',
        avatarUrl: _avatarUrl,
      );
    }
    notifyListeners();
  }

  Future<void> setThemeId(int id) async {
    if (id < 0 || id >= AppThemes.all.length) return;
    _themeId = id;
    await _saveLocal();
    notifyListeners();
  }

  Future<void> setBlobAnimationEnabled(bool value) async {
    _blobAnimationEnabled = value;
    await _saveLocal();
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await _fb.signOut();
    _isRegistered = false;
    _displayName = '';
    _email = '';
    _avatarUrl = '';
    _gender = null;
    _uid = '';
    await prefs.setBool('isRegistered', false);
    await prefs.remove('displayName');
    await prefs.remove('email');
    await prefs.remove('avatarUrl');
    await prefs.remove('gender');
    await prefs.remove('uid');
    // Clear connection data as well
    await prefs.remove('connections');
    await prefs.remove('activeConnectionIndex');
    await prefs.remove('preferredPartnerUid');
    // Clear timer data so new user doesn't see old timers
    await prefs.remove('user_timers');
    await prefs.remove('timer_selected_time_unit');
    notifyListeners();
  }
}
