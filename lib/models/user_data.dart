import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import 'profile_icon.dart';

enum Gender { male, female }

class UserData extends ChangeNotifier {
  String _displayName = '';
  String _email = '';
  String _avatarUrl = '';
  Gender? _gender;
  bool _isRegistered = false;
  bool _hasSeenWelcome = false;
  String _uid = '';
  String? _badge;

  // ── Дата рождения (только день+месяц важны для поздравлений) ──
  DateTime? _birthDate;

  // ── Коины и премиум-контент ──
  // Локальные значения — только КЭШ. Источник правды — Firestore,
  // изменения идут исключительно через серверные Cloud Functions.
  int _coins = 0;
  final Set<int> _ownedThemes = <int>{};
  // Купленные профильные иконки (КЭШ; источник правды — Firestore/сервер).
  final Set<String> _ownedIcons = <String>{};
  // Иконки-награды, выданные вручную (Sponsor/Helper).
  final Set<String> _grantedBadges = <String>{};
  bool _devCoinsGranted = false;
  int _adRewardsToday = 0;
  String _adRewardsDate = ''; // YYYY-MM-DD UTC; '' = ещё не получал

  /// Максимум rewarded-просмотров в сутки (зеркало AD_REWARDS_PER_DAY на сервере)
  static const int adRewardsDailyLimit = 3;

  /// Монет за один просмотр рекламы (зеркало AD_REWARD_AMOUNT на сервере)
  static const int adRewardAmount = 3;

  final FirebaseService _fb = FirebaseService();

  // ── Getters ──
  String get displayName => _displayName;
  String get email => _email;
  String get avatarUrl => _avatarUrl;
  Gender? get gender => _gender;
  bool get isRegistered => _isRegistered;
  bool get hasSeenWelcome => _hasSeenWelcome;
  String get uid => _uid;
  String? get badge => _badge;

  set badge(String? value) {
    _badge = value;
    notifyListeners();
  }

  bool get isMale => _gender == Gender.male;
  bool get isFemale => _gender == Gender.female;

  DateTime? get birthDate => _birthDate;

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

  // ── Коины ─────────────────────────────────────────────────────────────────
  int get coins => _coins;

  bool _dailyBonusClaimedThisSession = false;
  bool get dailyBonusClaimedThisSession => _dailyBonusClaimedThisSession;

  /// Сколько rewarded-просмотров пользователь сделал сегодня (UTC).
  /// Если последняя дата начисления — не сегодня, возвращает 0.
  int get adRewardsToday {
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    return _adRewardsDate == today ? _adRewardsToday : 0;
  }

  /// Сколько ещё просмотров доступно сегодня.
  int get adRewardsRemaining =>
      (adRewardsDailyLimit - adRewardsToday).clamp(0, adRewardsDailyLimit);

  /// Список ID разблокированных премиум-тем
  Set<int> get ownedThemes => Set.unmodifiable(_ownedThemes);

  /// Доступна ли тема (free или куплена)
  bool hasTheme(int id) {
    final t = AppThemes.byIndex(id);
    return !t.isPremium || _ownedThemes.contains(id);
  }

  // ── Профильные иконки ───────────────────────────────────────────────────────
  /// Купленные иконки (id из [ProfileIcon.all]).
  Set<String> get ownedIcons => Set.unmodifiable(_ownedIcons);

  /// Иконки-награды, выданные вручную (Sponsor/Helper).
  Set<String> get grantedBadges => Set.unmodifiable(_grantedBadges);

  /// Закреплённая рядом с именем иконка. null — не выбрана.
  String? get equippedIcon =>
      (_badge != null && _badge!.isNotEmpty) ? _badge : null;

  /// Доступна ли иконка пользователю (куплена или выдана).
  bool ownsIcon(String id) =>
      _ownedIcons.contains(id) || _grantedBadges.contains(id);

  /// Все доступные пользователю иконки (купленные + выданные), без дублей.
  Set<String> get availableIcons => {..._ownedIcons, ..._grantedBadges};

  /// Применяет результат, пришедший с сервера (callable function).
  /// Используется как единственный путь обновления баланса/owned.
  void _applyServerResult(Map<String, dynamic> result) {
    final coins = result['coins'];
    if (coins is num) _coins = coins.toInt();
    final owned = result['ownedThemes'];
    if (owned is List) {
      _ownedThemes
        ..clear()
        ..addAll(owned.whereType<num>().map((e) => e.toInt()));
    }
    final ownedI = result['ownedIcons'];
    if (ownedI is List) {
      _ownedIcons
        ..clear()
        ..addAll(ownedI.whereType<String>());
    }
    unawaited(_saveLocal());
    notifyListeners();
  }

  /// Гарантирует, что баланс не упадёт ниже [floor].
  /// Вызывается после оптимистичного начисления, пока SSV ещё не подтвердил.
  void ensureCoinsAtLeast(int floor) {
    if (_coins < floor) {
      _coins = floor;
      notifyListeners();
    }
  }

  /// Оптимистичное начисление награды за рекламу — до подтверждения сервером.
  /// Даёт мгновенный отклик UI; сервер потом подтвердит через SSV.
  void applyOptimisticAdReward(int amount) {
    _coins += amount;
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    if (_adRewardsDate != today) {
      _adRewardsDate = today;
      _adRewardsToday = 0;
    }
    _adRewardsToday += 1;
    _saveLocal();
    notifyListeners();
  }

  /// Перезагружает coins/ownedThemes с сервера.
  Future<void> refreshCoinsFromServer() async {
    try {
      final data = await _fb.loadUserProfile(fromServer: true);
      if (data == null) return;
      final cloudCoins = data['coins'];
      if (cloudCoins is num) _coins = cloudCoins.toInt();
      final cloudOwned = data['ownedThemes'];
      if (cloudOwned is List) {
        _ownedThemes
          ..clear()
          ..addAll(cloudOwned.whereType<num>().map((e) => e.toInt()));
      }
      final cloudOwnedIcons = data['ownedIcons'];
      if (cloudOwnedIcons is List) {
        _ownedIcons
          ..clear()
          ..addAll(cloudOwnedIcons.whereType<String>());
      }
      await _saveLocal();
      notifyListeners();
    } catch (e) {
      debugPrint('refreshCoinsFromServer failed: $e');
    }
  }

  /// Ежедневный бонус. Возвращает true при успешном начислении (false если cooldown).
  Future<bool> claimDailyBonus() async {
    final r = await _fb.callGrantDailyBonus();
    if (r == null) return false;
    _applyServerResult(r);
    final awarded = r['ok'] == true;
    if (awarded) {
      _dailyBonusClaimedThisSession = true;
      notifyListeners();
    }
    return awarded;
  }

  /// Награда за добавление воспоминания (1 🪙/день).
  /// Возвращает кол-во начисленных монет, или 0 если cooldown/ошибка.
  Future<int> claimMemoryReward() async {
    final r = await _fb.callGrantMemoryReward();
    if (r == null) return 0;
    _applyServerResult(r);
    return (r['ok'] == true) ? (r['awarded'] as num?)?.toInt() ?? 0 : 0;
  }

  /// Единоразовая награда за приглашение партнёра (50 🪙).
  /// Возвращает кол-во начисленных монет, или 0 если уже выдано.
  Future<int> claimPartnerInviteReward() async {
    final r = await _fb.callGrantPartnerInviteReward();
    if (r == null) return 0;
    _applyServerResult(r);
    return (r['ok'] == true) ? (r['awarded'] as num?)?.toInt() ?? 0 : 0;
  }

  /// Награда за 7-дневный стрик настроения обоих (10 🪙 раз в 7 дней).
  /// Возвращает кол-во начисленных монет, или 0 если cooldown.
  Future<int> claimMoodStreakReward(String groupId) async {
    final r = await _fb.callGrantMoodStreakReward(groupId);
    if (r == null) return 0;
    _applyServerResult(r);
    return (r['ok'] == true) ? (r['awarded'] as num?)?.toInt() ?? 0 : 0;
  }

  /// Пытается купить тему на сервере. Возвращает true при успехе.
  Future<bool> purchaseTheme(int themeId) async {
    final t = AppThemes.byIndex(themeId);
    if (!t.isPremium) return true; // free
    if (_ownedThemes.contains(themeId)) return true;
    final r = await _fb.callPurchaseTheme(themeId);
    if (r == null) return false;
    _applyServerResult(r);
    return _ownedThemes.contains(themeId);
  }

  /// Покупает профильную иконку на сервере. Возвращает true при успехе.
  /// Списание монет и запись в ownedIcons делает Cloud Function `purchaseIcon`
  /// (защищено от обхода цены/двойного списания).
  Future<bool> purchaseIcon(ProfileIcon icon) async {
    if (icon.grantOnly) return false; // награды не продаются
    if (_ownedIcons.contains(icon.id)) return true; // уже куплена
    final r = await _fb.callPurchaseIcon(icon.id);
    if (r == null) return false;
    _applyServerResult(r);
    return _ownedIcons.contains(icon.id);
  }

  /// Закрепляет иконку рядом с именем (или снимает, если [id] == null/'').
  /// badge не влияет на экономику — пишется напрямую (как и раньше).
  /// Закрепить можно только доступную (купленную/выданную) иконку.
  Future<void> setBadgeIcon(String? id) async {
    final clear = id == null || id.isEmpty;
    if (!clear && !ownsIcon(id)) return; // нельзя закрепить чужую иконку
    _badge = clear ? null : id;
    await _saveLocal();
    await _fb.setBadge(_badge ?? '');
    notifyListeners();
  }

  /// Выдаёт иконку-награду (Sponsor/Helper). Идемпотентно.
  /// Если у пользователя ещё нет закреплённой иконки — закрепляет автоматически.
  /// Грант определяется по e-mail в [main] (та же модель доверия, что и раньше).
  Future<void> grantSpecialBadge(String id) async {
    final added = _grantedBadges.add(id);
    final autoEquip = _badge == null || _badge!.isEmpty;
    if (!added && !autoEquip) return; // ничего не изменилось — без записи
    if (autoEquip) _badge = id;
    await _saveLocal();
    await _fb.saveGrantedBadges(
      _grantedBadges.toList(),
      badge: _badge,
    );
    notifyListeners();
  }

  /// Начисляет монеты после успешной IAP-покупки.
  ///
  /// Вызывается из [IapService] после того, как магазин подтвердил транзакцию.
  /// Передаёт [productId] и [purchaseToken] на сервер; сервер валидирует
  /// idempotency и начисляет монеты в Firestore.
  ///
  /// Возвращает новый баланс или null при сетевой / серверной ошибке.
  Future<int?> purchaseCoins({
    required String productId,
    required String purchaseToken,
  }) async {
    final r = await _fb.callGrantCoinsPurchase(
      productId: productId,
      purchaseToken: purchaseToken,
    );
    if (r == null) return null;
    _applyServerResult(r);
    return _coins;
  }

  /// Единоразовая серверная выдача монет разработчику (проверка email
  /// делается на сервере по auth-токену, обойти невозможно).
  Future<void> _maybeGrantDevCoins() async {
    if (_devCoinsGranted) return; // быстрый локальный шорткат
    final r = await _fb.callGrantDevCoins();
    if (r == null) return;
    _applyServerResult(r);
    if (r['ok'] == true) {
      _devCoinsGranted = true;
      await _saveLocal();
    }
  }

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
      _badge = prefs.getString('badge');
      _coins = prefs.getInt('coins') ?? 0;
      _devCoinsGranted = prefs.getBool('devCoinsGranted') ?? false;
      _adRewardsToday = prefs.getInt('adRewardsToday') ?? 0;
      _adRewardsDate = prefs.getString('adRewardsDate') ?? '';
      final bdMs = prefs.getInt('birthDate');
      _birthDate = bdMs != null
          ? DateTime.fromMillisecondsSinceEpoch(bdMs)
          : null;
      _ownedThemes
        ..clear()
        ..addAll(
          (prefs.getStringList('ownedThemes') ?? const <String>[])
              .map(int.tryParse)
              .whereType<int>(),
        );
      _ownedIcons
        ..clear()
        ..addAll(prefs.getStringList('ownedIcons') ?? const <String>[]);
      _grantedBadges
        ..clear()
        ..addAll(prefs.getStringList('grantedBadges') ?? const <String>[]);

      // Если авторизован → подтягиваем из облака
      if (_fb.isLoggedIn && _isRegistered) {
        _uid = _fb.uid ?? _uid;
        await _syncFromFirestore();
        await _maybeGrantDevCoins();
      }
    } catch (e) {
      debugPrint('SharedPreferences load failed: $e');
    }
    notifyListeners();
  }

  Future<void> _syncFromFirestore() async {
    try {
      final data = await _fb.loadUserProfile(fromServer: true);
      if (data != null) {
        _displayName = data['displayName'] ?? _displayName;
        _email = data['email'] ?? _email;
        // Only overwrite local avatar if Firestore has a real non-empty value.
        // An empty string in Firestore means the field was accidentally cleared —
        // preserve whatever the user set locally in that case.
        final firestoreAvatar = data['avatarUrl'] as String? ?? '';
        if (firestoreAvatar.isNotEmpty) _avatarUrl = firestoreAvatar;
        final g = data['gender'] as String?;
        if (g == 'male') _gender = Gender.male;
        if (g == 'female') _gender = Gender.female;
        _badge = data['badge'] as String?;

        final cloudCoins = data['coins'];
        if (cloudCoins is int) _coins = cloudCoins;
        final cloudOwned = data['ownedThemes'];
        if (cloudOwned is List) {
          _ownedThemes
            ..clear()
            ..addAll(cloudOwned.whereType<int>());
        }
        final cloudOwnedIcons = data['ownedIcons'];
        if (cloudOwnedIcons is List) {
          _ownedIcons
            ..clear()
            ..addAll(cloudOwnedIcons.whereType<String>());
        }
        final cloudGrantedBadges = data['grantedBadges'];
        if (cloudGrantedBadges is List) {
          _grantedBadges
            ..clear()
            ..addAll(cloudGrantedBadges.whereType<String>());
        }
        final cloudGranted = data['devCoinsGranted'];
        if (cloudGranted is bool) _devCoinsGranted = cloudGranted;

        final cloudAdCount = data['adRewardsToday'];
        if (cloudAdCount is num) _adRewardsToday = cloudAdCount.toInt();
        final cloudAdDate = data['adRewardsDate'];
        if (cloudAdDate is String) _adRewardsDate = cloudAdDate;

        final bdRaw = data['birthDate'];
        if (bdRaw is Timestamp) {
          _birthDate = bdRaw.toDate();
        } else if (bdRaw is String && bdRaw.isNotEmpty) {
          _birthDate = DateTime.tryParse(bdRaw);
        }

        await _saveLocal();

        // Propagate name/avatar to all group documents on every login so
        // partners always see the real name even if the user never explicitly
        // edited their profile after connecting (fixes 'Partner' fallback).
        if (_displayName.isNotEmpty) {
          unawaited(_fb.updateNameInGroups(_displayName));
        }
        if (_avatarUrl.isNotEmpty) {
          unawaited(_fb.updateAvatarInGroups(_avatarUrl));
        }
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
      if (_birthDate != null) {
        await prefs.setInt('birthDate', _birthDate!.millisecondsSinceEpoch);
      } else {
        await prefs.remove('birthDate');
      }
      if (_badge != null) {
        await prefs.setString('badge', _badge!);
      } else {
        await prefs.remove('badge');
      }
      await prefs.setInt('coins', _coins);
      await prefs.setBool('devCoinsGranted', _devCoinsGranted);
      await prefs.setInt('adRewardsToday', _adRewardsToday);
      await prefs.setString('adRewardsDate', _adRewardsDate);
      await prefs.setStringList(
        'ownedThemes',
        _ownedThemes.map((e) => e.toString()).toList(),
      );
      await prefs.setStringList('ownedIcons', _ownedIcons.toList());
      await prefs.setStringList('grantedBadges', _grantedBadges.toList());
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
      // Синхронизируем монеты/темы с сервера — важно после переустановки,
      // когда SharedPreferences очищены, но Firestore хранит реальный баланс.
      await _syncFromFirestore();
      await _maybeGrantDevCoins();
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
      // Propagate name/avatar changes to all groups so partners receive
      // the update via the group real-time listener.
      if (displayName != null) {
        await _fb.updateNameInGroups(_displayName);
      }
      if (avatarUrl != null) {
        await _fb.updateAvatarInGroups(_avatarUrl);
      }
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

  Future<void> updateBirthDate(DateTime? date) async {
    _birthDate = date;
    await _saveLocal();
    await _fb.updateMyBirthDate(date);
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
    _coins = 0;
    _devCoinsGranted = false;
    _ownedThemes.clear();
    _ownedIcons.clear();
    _grantedBadges.clear();
    _badge = null;
    _adRewardsToday = 0;
    _adRewardsDate = '';
    await prefs.remove('coins');
    await prefs.remove('devCoinsGranted');
    await prefs.remove('ownedThemes');
    await prefs.remove('ownedIcons');
    await prefs.remove('grantedBadges');
    await prefs.remove('badge');
    await prefs.remove('adRewardsToday');
    await prefs.remove('adRewardsDate');
    notifyListeners();
  }
}
