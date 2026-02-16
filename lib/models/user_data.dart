import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Gender { male, female }

class UserData extends ChangeNotifier {
  String _displayName = '';
  String _email = '';
  String _avatarUrl = '';
  Gender? _gender;
  bool _isRegistered = false;
  bool _hasSeenWelcome = false;

  // ── Getters ──
  String get displayName => _displayName;
  String get email => _email;
  String get avatarUrl => _avatarUrl;
  Gender? get gender => _gender;
  bool get isRegistered => _isRegistered;
  bool get hasSeenWelcome => _hasSeenWelcome;

  bool get isMale => _gender == Gender.male;
  bool get isFemale => _gender == Gender.female;

  Color get themeAccent {
    if (_gender == Gender.male) return const Color(0xFF4A90D9);
    if (_gender == Gender.female) return const Color(0xFFEE2B6C);
    return const Color(0xFFEE2B6C); // default
  }

  Color get themeAccentLight {
    if (_gender == Gender.male) return const Color(0xFFE3F0FF);
    if (_gender == Gender.female) return const Color(0xFFFEEAF1);
    return const Color(0xFFFEEAF1);
  }

  String get initials {
    if (_displayName.isEmpty) return '?';
    final parts = _displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return _displayName[0].toUpperCase();
  }

  // ── Persistence ──
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasSeenWelcome = prefs.getBool('hasSeenWelcome') ?? false;
      _isRegistered = prefs.getBool('isRegistered') ?? false;
      _displayName = prefs.getString('displayName') ?? '';
      _email = prefs.getString('email') ?? '';
      _avatarUrl = prefs.getString('avatarUrl') ?? '';
      final genderStr = prefs.getString('gender');
      if (genderStr == 'male') _gender = Gender.male;
      if (genderStr == 'female') _gender = Gender.female;
    } catch (e) {
      // Platform channel may not be ready (e.g. during hot restart).
      // Defaults are already set — just continue.
      debugPrint('SharedPreferences load failed: $e');
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenWelcome', _hasSeenWelcome);
      await prefs.setBool('isRegistered', _isRegistered);
      await prefs.setString('displayName', _displayName);
      await prefs.setString('email', _email);
      await prefs.setString('avatarUrl', _avatarUrl);
      await prefs.setString(
        'gender',
        _gender == Gender.male
            ? 'male'
            : _gender == Gender.female
            ? 'female'
            : '',
      );
    } catch (e) {
      debugPrint('SharedPreferences save failed: $e');
    }
  }

  // ── Actions ──
  Future<void> markWelcomeSeen() async {
    _hasSeenWelcome = true;
    await _save();
    notifyListeners();
  }

  Future<void> register({
    required String displayName,
    required String email,
    required Gender gender,
    String avatarUrl = '',
  }) async {
    _displayName = displayName;
    _email = email;
    _gender = gender;
    _avatarUrl = avatarUrl;
    _isRegistered = true;
    await _save();
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
    await _save();
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Keep hasSeenWelcome true
    _isRegistered = false;
    _displayName = '';
    _email = '';
    _avatarUrl = '';
    _gender = null;
    await prefs.setBool('isRegistered', false);
    await prefs.remove('displayName');
    await prefs.remove('email');
    await prefs.remove('avatarUrl');
    await prefs.remove('gender');
    notifyListeners();
  }
}
