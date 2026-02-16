import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

/// Единый сервис для работы с Firebase.
/// Хитрости для бесплатности:
///  • Минимум документов — 1 user + 1 inviteCode + 1 pair на пару
///  • Кэшируем локально, читаем из Firestore только при старте
///  • Слушаем ОДИН документ пары (1 snapshot listener = мало чтений)
///  • Не используем Cloud Functions (они платные)
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._();
  factory FirebaseService() => _instance;
  FirebaseService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  // ══════════════════════════════════════════════
  //  AUTH
  // ══════════════════════════════════════════════

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;

  /// Вход через Google → Firebase Auth (бесплатно и безлимитно)
  Future<User?> signInWithGoogle() async {
    try {
      final googleAccount = await _googleSignIn.signIn();
      if (googleAccount == null) return null; // пользователь отменил

      final googleAuth = await googleAccount.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      debugPrint('Firebase Auth: signing in...');
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      debugPrint('Firebase Auth success: ${user.uid}');

      // Создаём/обновляем документ пользователя (1 запись)
      try {
        debugPrint('Firestore: saving user profile...');
        await _db
            .collection('users')
            .doc(user.uid)
            .set({
              'displayName': user.displayName ?? '',
              'email': user.email ?? '',
              'avatarUrl': user.photoURL ?? '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
        debugPrint('Firestore: user profile saved');
      } catch (e) {
        debugPrint('Firestore save failed: $e');
        // Продолжаем даже если Firestore не работает
      }

      return user;
    } catch (e) {
      debugPrint('signInWithGoogle failed: $e');
      rethrow;
    }
  }

  /// Выход
  Future<void> signOut() async {
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (_) {}
    await _auth.signOut();
  }

  // ══════════════════════════════════════════════
  //  USER PROFILE
  // ══════════════════════════════════════════════

  /// Сохраняет профиль в Firestore (1 запись)
  Future<void> saveUserProfile({
    required String displayName,
    required String email,
    required String gender,
    String avatarUrl = '',
  }) async {
    final u = currentUser;
    if (u == null) return;
    try {
      await _db
          .collection('users')
          .doc(u.uid)
          .set({
            'displayName': displayName,
            'email': email,
            'gender': gender,
            'avatarUrl': avatarUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('saveUserProfile failed: $e');
    }
  }

  /// Загружает профиль (1 чтение)
  Future<Map<String, dynamic>?> loadUserProfile() async {
    final u = currentUser;
    if (u == null) return null;
    try {
      final doc = await _db
          .collection('users')
          .doc(u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      return doc.data();
    } catch (e) {
      debugPrint('loadUserProfile failed: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════
  //  INVITE CODES — Реальное приглашение
  // ══════════════════════════════════════════════

  /// Генерация и сохранение инвайт-кода (2 записи: user + inviteCodes)
  Future<String> generateInviteCode() async {
    final u = currentUser;
    if (u == null) {
      debugPrint('generateInviteCode: not logged in, returning empty');
      return ''; // Вернём пустую строку если не авторизован
    }

    try {
      // Проверяем, нет ли уже кода
      debugPrint('Firestore: checking existing invite code...');
      final userDoc = await _db
          .collection('users')
          .doc(u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      final existingCode = userDoc.data()?['inviteCode'] as String?;
      if (existingCode != null && existingCode.isNotEmpty) {
        debugPrint('Invite code exists: $existingCode');
        return existingCode;
      }

      // Генерим уникальный код
      String code;
      bool exists;
      do {
        code = _generateCode();
        final codeDoc = await _db
            .collection('inviteCodes')
            .doc(code)
            .get()
            .timeout(const Duration(seconds: 5));
        exists = codeDoc.exists;
      } while (exists);

      debugPrint('Firestore: saving invite code $code...');
      // Сохраняем код → владелец
      final batch = _db.batch();
      batch.set(_db.collection('inviteCodes').doc(code), {
        'ownerUid': u.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(_db.collection('users').doc(u.uid), {'inviteCode': code});
      await batch.commit().timeout(const Duration(seconds: 10));

      debugPrint('Invite code saved: $code');
      return code;
    } catch (e) {
      debugPrint('generateInviteCode failed: $e');
      return ''; // Возвращаем пустую строку при ошибке
    }
  }

  /// Генерация НОВОГО уникального кода (для каждой группы свой).
  /// Не проверяет существующий код пользователя — всегда генерирует новый.
  Future<String> generateNewInviteCode({String? oldCode}) async {
    final u = currentUser;
    if (u == null) return '';

    try {
      // Удаляем старый код если передан
      if (oldCode != null && oldCode.isNotEmpty) {
        await _db.collection('inviteCodes').doc(oldCode).delete();
      }

      // Генерим уникальный код
      String code;
      bool exists;
      do {
        code = _generateCode();
        final codeDoc = await _db
            .collection('inviteCodes')
            .doc(code)
            .get()
            .timeout(const Duration(seconds: 5));
        exists = codeDoc.exists;
      } while (exists);

      debugPrint('Firestore: saving new invite code $code...');
      await _db
          .collection('inviteCodes')
          .doc(code)
          .set({'ownerUid': u.uid, 'createdAt': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 10));

      debugPrint('New invite code saved: $code');
      return code;
    } catch (e) {
      debugPrint('generateNewInviteCode failed: $e');
      return '';
    }
  }

  /// Перегенерация кода (удаляем старый, создаём новый)
  Future<String> regenerateInviteCode({String? oldCode}) async {
    return generateNewInviteCode(oldCode: oldCode);
  }

  // ══════════════════════════════════════════════
  //  PAIRING — Реальное подключение партнёра
  // ══════════════════════════════════════════════

  /// Ввод кода партнёра → создание пары
  /// Возвращает {success, message, partnerName}
  Future<Map<String, dynamic>> acceptInviteCode(String code) async {
    final u = currentUser;
    if (u == null) return {'success': false, 'message': 'Не авторизован'};

    code = code.toUpperCase().trim();

    // 1. Находим код (1 чтение)
    final codeDoc = await _db.collection('inviteCodes').doc(code).get();
    if (!codeDoc.exists) {
      return {'success': false, 'message': 'Код не найден'};
    }

    final ownerUid = codeDoc.data()!['ownerUid'] as String;

    // Нельзя пригласить себя
    if (ownerUid == u.uid) {
      return {'success': false, 'message': 'Это ваш собственный код!'};
    }

    // 2. Проверяем что владелец не в паре (1 чтение)
    final ownerDoc = await _db.collection('users').doc(ownerUid).get();
    if (!ownerDoc.exists) {
      return {'success': false, 'message': 'Пользователь не найден'};
    }
    if ((ownerDoc.data()?['pairId'] ?? '').toString().isNotEmpty) {
      return {'success': false, 'message': 'Этот человек уже в паре'};
    }

    // 3. Загружаем свой профиль (мульти-группы: разрешаем несколько пар)
    final myDoc = await _db.collection('users').doc(u.uid).get();

    // 4. Создаём документ пары (1 запись)
    final pairRef = _db.collection('pairs').doc();
    final now = FieldValue.serverTimestamp();
    final ownerData = ownerDoc.data()!;
    final myData = myDoc.data()!;

    final batch = _db.batch();

    // Документ пары
    batch.set(pairRef, {
      'user1': ownerUid,
      'user1Name': ownerData['displayName'] ?? 'Партнёр',
      'user1Avatar': ownerData['avatarUrl'] ?? '',
      'user2': u.uid,
      'user2Name': myData['displayName'] ?? u.displayName ?? 'Партнёр',
      'user2Avatar': myData['avatarUrl'] ?? u.photoURL ?? '',
      'startDate': now,
      'createdAt': now,
    });

    // Обновляем обоих пользователей (pairId = последний, pairIds = массив всех)
    batch.update(_db.collection('users').doc(ownerUid), {
      'pairId': pairRef.id,
      'pairIds': FieldValue.arrayUnion([pairRef.id]),
    });
    batch.update(_db.collection('users').doc(u.uid), {
      'pairId': pairRef.id,
      'pairIds': FieldValue.arrayUnion([pairRef.id]),
    });

    // Удаляем оба инвайт-кода — они больше не нужны
    batch.delete(_db.collection('inviteCodes').doc(code));
    final myCode = myData['inviteCode'] as String?;
    if (myCode != null && myCode.isNotEmpty) {
      batch.delete(_db.collection('inviteCodes').doc(myCode));
    }

    await batch.commit(); // 1 батч-запись

    return {
      'success': true,
      'message': 'Вы в паре!',
      'partnerName': ownerData['displayName'] ?? 'Партнёр',
      'partnerAvatar': ownerData['avatarUrl'] ?? '',
      'pairId': pairRef.id,
      'startDate': DateTime.now(), // server timestamp не вернётся сразу
    };
  }

  /// Загружает данные пары по pairId напрямую (1 чтение документа pairs)
  /// Используется когда Connection уже знает свой pairId.
  Future<Map<String, dynamic>?> loadPairById(String pairId) async {
    final u = currentUser;
    if (u == null || pairId.isEmpty) return null;

    try {
      final pairDoc = await _db
          .collection('pairs')
          .doc(pairId)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!pairDoc.exists) return null;

      final data = pairDoc.data()!;
      final isUser1 = data['user1'] == u.uid;
      return {
        'pairId': pairId,
        'partnerName': isUser1 ? data['user2Name'] : data['user1Name'],
        'partnerAvatar': isUser1 ? data['user2Avatar'] : data['user1Avatar'],
        'startDate': (data['startDate'] as Timestamp?)?.toDate(),
        'raw': data,
      };
    } catch (e) {
      debugPrint('loadPairById($pairId) failed: $e');
      return null;
    }
  }

  /// Загружает данные последней пары из профиля (2 чтения: user + pair).
  /// Используется только для первичного обнаружения пары, когда pairId неизвестен.
  Future<Map<String, dynamic>?> loadPairData() async {
    final u = currentUser;
    if (u == null) return null;

    try {
      final userDoc = await _db
          .collection('users')
          .doc(u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      final pairId = userDoc.data()?['pairId'] as String?;
      if (pairId == null || pairId.isEmpty) return null;

      return await loadPairById(pairId);
    } catch (e) {
      debugPrint('loadPairData failed: $e');
      return null;
    }
  }

  /// Слушаем изменения пары в реальном времени (1 snapshot listener)
  /// Хитрость: snapshot listener считается как 1 чтение при подключении
  /// + 1 чтение за каждое изменение. Для пары = почти ничего.
  /// Слушаем КОНКРЕТНУЮ пару. Не отменяем предыдущие подписки —
  /// у каждой Connection свой listener.
  StreamSubscription? listenToPair({
    required String pairId,
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    return _db.collection('pairs').doc(pairId).snapshots().listen((snap) {
      if (snap.exists) {
        final data = snap.data()!;
        final isUser1 = data['user1'] == uid;
        onData({
          'pairId': pairId,
          'partnerName': isUser1 ? data['user2Name'] : data['user1Name'],
          'partnerAvatar': isUser1 ? data['user2Avatar'] : data['user1Avatar'],
          'startDate': (data['startDate'] as Timestamp?)?.toDate(),
          'raw': data,
        });
      } else {
        onData(null);
      }
    });
  }

  /// Разорвать конкретную пару (по pairId)
  Future<void> unpairById(String pairId) async {
    final u = currentUser;
    if (u == null || pairId.isEmpty) return;

    final pairDoc = await _db.collection('pairs').doc(pairId).get();
    if (!pairDoc.exists) return;

    final data = pairDoc.data()!;
    final partnerId = data['user1'] == u.uid ? data['user2'] : data['user1'];

    final batch = _db.batch();
    batch.delete(_db.collection('pairs').doc(pairId));
    // Удаляем из массива pairIds и очищаем pairId если это последняя пара
    batch.update(_db.collection('users').doc(u.uid), {
      'pairIds': FieldValue.arrayRemove([pairId]),
    });
    if (partnerId != null) {
      batch.update(_db.collection('users').doc(partnerId as String), {
        'pairIds': FieldValue.arrayRemove([pairId]),
      });
    }
    await batch.commit();

    // Обновляем pairId: ставим другую пару или пустую строку
    final myDoc = await _db.collection('users').doc(u.uid).get();
    final remainingPairs = (myDoc.data()?['pairIds'] as List<dynamic>?) ?? [];
    await _db.collection('users').doc(u.uid).update({
      'pairId': remainingPairs.isNotEmpty ? remainingPairs.last : '',
    });
    if (partnerId != null) {
      final partnerDoc = await _db
          .collection('users')
          .doc(partnerId as String)
          .get();
      final partnerPairs =
          (partnerDoc.data()?['pairIds'] as List<dynamic>?) ?? [];
      await _db.collection('users').doc(partnerId).update({
        'pairId': partnerPairs.isNotEmpty ? partnerPairs.last : '',
      });
    }
  }

  /// Разорвать пару (legacy — разрывает последнюю)
  Future<void> unpair() async {
    final u = currentUser;
    if (u == null) return;

    final userDoc = await _db.collection('users').doc(u.uid).get();
    final pairId = userDoc.data()?['pairId'] as String?;
    if (pairId == null || pairId.isEmpty) return;

    await unpairById(pairId);
  }

  // ══════════════════════════════════════════════
  //  REAL-TIME LISTENERS
  // ══════════════════════════════════════════════

  /// Слушаем документ текущего юзера в реальном времени.
  /// Срабатывает при любом изменении (pairId, pairIds, profile и т.д.)
  StreamSubscription? listenToUserDoc({
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    final u = currentUser;
    if (u == null) return null;

    return _db.collection('users').doc(u.uid).snapshots().listen((snap) {
      if (snap.exists) {
        onData(snap.data());
      } else {
        onData(null);
      }
    });
  }

  // ══════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
