import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import '../models/memory.dart';
import '../models/comment.dart';
import '../models/timer_item.dart';

/// Единый сервис для работы с Firebase.
/// Поддерживает группы от 2 до 10 участников + совместные воспоминания.
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._();
  factory FirebaseService() => _instance;
  FirebaseService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  // ══════════════════════════════════════════════
  //  AUTH
  // ══════════════════════════════════════════════

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;

  Future<User?> signInWithGoogle() async {
    try {
      final googleAccount = await _googleSignIn.signIn().timeout(
        const Duration(seconds: 30),
      );
      if (googleAccount == null) return null;

      final googleAuth = await googleAccount.authentication.timeout(
        const Duration(seconds: 15),
      );
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      debugPrint('Firebase Auth: signing in...');
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      debugPrint('Firebase Auth success: ${user.uid}');

      try {
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
      } catch (e) {
        debugPrint('Firestore save failed: $e');
      }

      return user;
    } catch (e) {
      debugPrint('signInWithGoogle failed: $e');
      rethrow;
    }
  }

  /// Создание аккаунта через email/пароль
  Future<User?> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      debugPrint('Firebase Auth: creating account with email...');
      final userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));
      final user = userCredential.user;
      if (user == null) return null;

      // Обновляем displayName
      await user.updateDisplayName(displayName);
      await user.reload();

      debugPrint('Firebase Auth success: ${user.uid}');

      try {
        await _db
            .collection('users')
            .doc(user.uid)
            .set({
              'displayName': displayName,
              'email': email,
              'avatarUrl': '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Firestore save failed: $e');
      }

      return _auth.currentUser;
    } catch (e) {
      debugPrint('signUpWithEmailPassword failed: $e');
      rethrow;
    }
  }

  /// Вход через email/пароль
  Future<User?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('Firebase Auth: signing in with email...');
      final userCredential = await _auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));
      return userCredential.user;
    } catch (e) {
      debugPrint('signInWithEmailPassword failed: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (_) {}
    await _auth.signOut();
  }

  // ══════════════════════════════════════════════
  //  EMAIL LINK AUTHENTICATION (Passwordless)
  // ══════════════════════════════════════════════

  /// Отправить ссылку для входа на электронную почту
  Future<bool> sendSignInLinkToEmail(String email) async {
    try {
      debugPrint('Firebase Auth: sending sign-in link to $email');

      final actionCodeSettings = ActionCodeSettings(
        // URL для перенаправления - используем web.app домен
        url: 'https://togetherly-d4856.web.app/',
        handleCodeInApp: true,
        androidPackageName: 'com.example.love_app',
        androidInstallApp: true,
        androidMinimumVersion: '21',
      );

      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );

      debugPrint('Sign-in link sent successfully');
      return true;
    } catch (e) {
      debugPrint('sendSignInLinkToEmail failed: $e');
      return false;
    }
  }

  /// Проверить, является ли ссылка ссылкой для входа
  bool isSignInWithEmailLink(String emailLink) {
    return _auth.isSignInWithEmailLink(emailLink);
  }

  /// Войти используя ссылку из email
  Future<User?> signInWithEmailLink({
    required String email,
    required String emailLink,
  }) async {
    try {
      debugPrint('Firebase Auth: signing in with email link...');

      final userCredential = await _auth.signInWithEmailLink(
        email: email,
        emailLink: emailLink,
      );

      final user = userCredential.user;
      if (user == null) return null;

      debugPrint('Firebase Auth success: ${user.uid}');

      // Сохранить профиль в Firestore
      try {
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
      } catch (e) {
        debugPrint('Firestore save failed: $e');
      }

      return user;
    } catch (e) {
      debugPrint('signInWithEmailLink failed: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════
  //  USER PROFILE
  // ══════════════════════════════════════════════

  Future<void> saveUserProfile({
    required String displayName,
    required String email,
    required String gender,
    String avatarUrl = '',
    bool clearPairData = false,
  }) async {
    final u = currentUser;
    if (u == null) return;
    try {
      final data = {
        'displayName': displayName,
        'email': email,
        'gender': gender,
        'avatarUrl': avatarUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Clear pair data if this is a new registration
      if (clearPairData) {
        data['pairId'] = '';
        data['pairIds'] = [];
      }

      await _db
          .collection('users')
          .doc(u.uid)
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('saveUserProfile failed: $e');
    }
  }

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
  //  INVITE CODES
  // ══════════════════════════════════════════════

  Future<String> generateInviteCode() async {
    final u = currentUser;
    if (u == null) return '';

    try {
      final userDoc = await _db
          .collection('users')
          .doc(u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      final existingCode = userDoc.data()?['inviteCode'] as String?;
      if (existingCode != null && existingCode.isNotEmpty) {
        return existingCode;
      }

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

      final batch = _db.batch();
      batch.set(_db.collection('inviteCodes').doc(code), {
        'ownerUid': u.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(_db.collection('users').doc(u.uid), {'inviteCode': code});
      await batch.commit().timeout(const Duration(seconds: 10));

      return code;
    } catch (e) {
      debugPrint('generateInviteCode failed: $e');
      return '';
    }
  }

  Future<String> generateNewInviteCode({String? oldCode}) async {
    final u = currentUser;
    if (u == null) return '';

    try {
      if (oldCode != null && oldCode.isNotEmpty) {
        await _db.collection('inviteCodes').doc(oldCode).delete();
      }

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

      await _db
          .collection('inviteCodes')
          .doc(code)
          .set({'ownerUid': u.uid, 'createdAt': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 10));

      return code;
    } catch (e) {
      debugPrint('generateNewInviteCode failed: $e');
      return '';
    }
  }

  /// Create invite code tied to a specific group (for adding more members)
  Future<String> generateGroupInviteCode(
    String groupId, {
    String? oldCode,
  }) async {
    final u = currentUser;
    if (u == null) return '';

    try {
      if (oldCode != null && oldCode.isNotEmpty) {
        await _db.collection('inviteCodes').doc(oldCode).delete();
      }

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

      await _db
          .collection('inviteCodes')
          .doc(code)
          .set({
            'ownerUid': u.uid,
            'groupId': groupId,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));

      return code;
    } catch (e) {
      debugPrint('generateGroupInviteCode failed: $e');
      return '';
    }
  }

  Future<String> regenerateInviteCode({String? oldCode}) async {
    return generateNewInviteCode(oldCode: oldCode);
  }

  // ══════════════════════════════════════════════
  //  GROUPS (replaces old PAIRING)
  //
  //  Firestore structure:
  //    groups/{groupId}:
  //      members: [uid1, uid2, ...]
  //      memberNames: {uid1: "Alice", uid2: "Bob"}
  //      memberAvatars: {uid1: "url", uid2: "url"}
  //      maxMembers: 2 | 10
  //      startDate: Timestamp
  //      createdAt: Timestamp
  //
  //    users/{uid}:
  //      pairId: "last groupId" (legacy compat)
  //      pairIds: ["groupId1", "groupId2"]
  // ══════════════════════════════════════════════

  /// Accept invite code → join or create a group.
  Future<Map<String, dynamic>> acceptInviteCode(String code) async {
    final u = currentUser;
    if (u == null) return {'success': false, 'message': 'Не авторизован'};

    code = code.toUpperCase().trim();
    debugPrint('acceptInviteCode: looking up code $code');

    try {
      final codeDoc = await _db.collection('inviteCodes').doc(code).get();
      if (!codeDoc.exists) {
        debugPrint('acceptInviteCode: code not found');
        return {'success': false, 'message': 'Код не найден'};
      }

      final ownerUid = codeDoc.data()!['ownerUid'] as String;
      if (ownerUid == u.uid) {
        return {'success': false, 'message': 'Это ваш собственный код!'};
      }

      // Check if there's a groupId tied to this code
      final codeGroupId = codeDoc.data()!['groupId'] as String?;
      debugPrint('acceptInviteCode: owner=$ownerUid, groupId=$codeGroupId');

      final ownerDoc = await _db.collection('users').doc(ownerUid).get();
      if (!ownerDoc.exists) {
        return {'success': false, 'message': 'Пользователь не найден'};
      }
      final ownerData = ownerDoc.data()!;

      final myDoc = await _db.collection('users').doc(u.uid).get();
      final myData = myDoc.data() ?? {};

      // If code has a groupId → join existing group
      if (codeGroupId != null && codeGroupId.isNotEmpty) {
        debugPrint('acceptInviteCode: code has groupId, joining $codeGroupId');
        return _joinExistingGroup(
          groupId: codeGroupId,
          code: code,
          myData: myData,
          ownerUid: ownerUid,
          ownerData: ownerData,
        );
      }

      // Code has no groupId — check if the owner already has a group
      final ownerPairId = ownerData['pairId'] as String?;
      if (ownerPairId != null && ownerPairId.isNotEmpty) {
        debugPrint(
          'acceptInviteCode: owner has pairId=$ownerPairId, trying to join',
        );
        try {
          final groupDoc = await _db
              .collection('groups')
              .doc(ownerPairId)
              .get();
          if (groupDoc.exists) {
            final groupData = groupDoc.data()!;
            final groupMembers = List<String>.from(groupData['members'] ?? []);
            if (groupMembers.contains(ownerUid) &&
                !groupMembers.contains(u.uid)) {
              return _joinExistingGroup(
                groupId: ownerPairId,
                code: code,
                myData: myData,
                ownerUid: ownerUid,
                ownerData: ownerData,
              );
            }
          }
        } catch (e) {
          debugPrint('acceptInviteCode: reading owner group failed: $e');
          // Can't read group (not a member) — just create a new one
        }
      }

      // Also check owner's pairIds list for any group we can join
      final ownerPairIds = ownerData['pairIds'] as List<dynamic>?;
      if (ownerPairIds != null && ownerPairIds.isNotEmpty) {
        for (var pid in ownerPairIds) {
          final pidStr = pid.toString();
          if (pidStr.isEmpty) continue;
          try {
            final groupDoc = await _db.collection('groups').doc(pidStr).get();
            if (groupDoc.exists) {
              final groupData = groupDoc.data()!;
              final groupMembers = List<String>.from(
                groupData['members'] ?? [],
              );
              if (groupMembers.contains(ownerUid) &&
                  !groupMembers.contains(u.uid)) {
                return _joinExistingGroup(
                  groupId: pidStr,
                  code: code,
                  myData: myData,
                  ownerUid: ownerUid,
                  ownerData: ownerData,
                );
              }
            }
          } catch (e) {
            debugPrint('acceptInviteCode: reading group $pidStr failed: $e');
            // Can't read group — skip
          }
        }
      }

      // Owner has no group yet — create a new 2-person group (pair)
      debugPrint(
        'acceptInviteCode: creating new group for $ownerUid + ${u.uid}',
      );
      return _createNewGroup(
        code: code,
        ownerUid: ownerUid,
        ownerData: ownerData,
        myData: myData,
      );
    } catch (e) {
      debugPrint('acceptInviteCode FAILED: $e');
      return {'success': false, 'message': 'Ошибка: $e'};
    }
  }

  /// Create a brand new group between owner and current user.
  Future<Map<String, dynamic>> _createNewGroup({
    required String code,
    required String ownerUid,
    required Map<String, dynamic> ownerData,
    required Map<String, dynamic> myData,
  }) async {
    final u = currentUser!;
    final groupRef = _db.collection('groups').doc();
    final now = FieldValue.serverTimestamp();

    // Step 1: Create the group document (allowed by create rule)
    await groupRef.set({
      'members': [ownerUid, u.uid],
      'memberNames': {
        ownerUid: ownerData['displayName'] ?? 'Partner',
        u.uid: myData['displayName'] ?? u.displayName ?? 'Partner',
      },
      'memberAvatars': {
        ownerUid: ownerData['avatarUrl'] ?? '',
        u.uid: myData['avatarUrl'] ?? u.photoURL ?? '',
      },
      'maxMembers': 2,
      'startDate': now,
      'createdAt': now,
    });
    debugPrint('_createNewGroup: group ${groupRef.id} created');

    // Step 2: Update MY user document (allowed — own doc)
    await _db.collection('users').doc(u.uid).update({
      'pairId': groupRef.id,
      'pairIds': FieldValue.arrayUnion([groupRef.id]),
    });
    debugPrint('_createNewGroup: my user doc updated');

    // Step 3: Update OWNER's user document (allowed by new rules — only pairId/pairIds)
    try {
      await _db.collection('users').doc(ownerUid).update({
        'pairId': groupRef.id,
        'pairIds': FieldValue.arrayUnion([groupRef.id]),
      });
      debugPrint('_createNewGroup: owner user doc updated');
    } catch (e) {
      debugPrint(
        '_createNewGroup: owner doc update failed (owner will pick it up via listener): $e',
      );
      // Not critical — owner's real-time listener will detect the group
    }

    // Step 4: Delete invite code (allowed by new rules)
    try {
      await _db.collection('inviteCodes').doc(code).delete();
      debugPrint('_createNewGroup: invite code $code deleted');
    } catch (e) {
      debugPrint('_createNewGroup: could not delete invite code: $e');
    }

    return {
      'success': true,
      'message': 'Connected!',
      'partnerName': ownerData['displayName'] ?? 'Partner',
      'partnerAvatar': ownerData['avatarUrl'] ?? '',
      'pairId': groupRef.id,
      'startDate': DateTime.now(),
      'members': [
        {
          'uid': ownerUid,
          'name': ownerData['displayName'] ?? 'Partner',
          'avatar': ownerData['avatarUrl'] ?? '',
        },
        {
          'uid': u.uid,
          'name': myData['displayName'] ?? u.displayName ?? 'You',
          'avatar': myData['avatarUrl'] ?? u.photoURL ?? '',
        },
      ],
    };
  }

  /// Join an existing group by groupId.
  Future<Map<String, dynamic>> _joinExistingGroup({
    required String groupId,
    required String code,
    required Map<String, dynamic> myData,
    required String ownerUid,
    required Map<String, dynamic> ownerData,
  }) async {
    final u = currentUser!;
    debugPrint('_joinExistingGroup: trying to join group $groupId');

    // Try to read the group doc directly
    Map<String, dynamic>? groupData;
    List<String> members;
    int maxMembers;

    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        debugPrint('_joinExistingGroup: group $groupId not found');
        return {'success': false, 'message': 'Group not found'};
      }
      groupData = groupDoc.data()!;
      members = List<String>.from(groupData['members'] ?? []);
      maxMembers = (groupData['maxMembers'] as int?) ?? 10;
    } catch (e) {
      // Can't read group (not a member yet) — that's expected
      // We know the group exists because the owner has it, so just proceed
      debugPrint(
        '_joinExistingGroup: cant read group (expected), will add self directly',
      );
      members = [ownerUid]; // We know owner is there
      maxMembers = 10;
      groupData = null;
    }

    if (members.contains(u.uid)) {
      return {'success': false, 'message': 'Вы уже в этой группе'};
    }
    if (members.length >= maxMembers) {
      return {
        'success': false,
        'message': 'Группа заполнена (макс $maxMembers)',
      };
    }

    final myName = myData['displayName'] ?? u.displayName ?? 'Partner';
    final myAvatar = myData['avatarUrl'] ?? u.photoURL ?? '';

    // Step 1: Add self to group (allowed by new rules — uid will be in new members)
    try {
      await _db.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayUnion([u.uid]),
        'memberNames.${u.uid}': myName,
        'memberAvatars.${u.uid}': myAvatar,
      });
      debugPrint('_joinExistingGroup: added self to group');
    } catch (e) {
      debugPrint('_joinExistingGroup: failed to update group: $e');
      return {
        'success': false,
        'message': 'Не удалось присоединиться к группе',
      };
    }

    // Step 2: Update MY user document
    try {
      await _db.collection('users').doc(u.uid).update({
        'pairId': groupId,
        'pairIds': FieldValue.arrayUnion([groupId]),
      });
      debugPrint('_joinExistingGroup: my user doc updated');
    } catch (e) {
      debugPrint('_joinExistingGroup: user doc update failed: $e');
    }

    // Step 3: Delete code if group is now full
    if (members.length + 1 >= maxMembers) {
      try {
        await _db.collection('inviteCodes').doc(code).delete();
      } catch (e) {
        debugPrint('_joinExistingGroup: code delete failed: $e');
      }
    }

    // Build response from groupData if available, otherwise from owner data
    final memberNames = groupData != null
        ? Map<String, dynamic>.from(groupData['memberNames'] ?? {})
        : <String, dynamic>{ownerUid: ownerData['displayName'] ?? 'Partner'};
    final memberAvatars = groupData != null
        ? Map<String, dynamic>.from(groupData['memberAvatars'] ?? {})
        : <String, dynamic>{ownerUid: ownerData['avatarUrl'] ?? ''};
    memberNames[u.uid] = myName;
    memberAvatars[u.uid] = myAvatar;

    final otherUid = members.isNotEmpty ? members.first : ownerUid;
    return {
      'success': true,
      'message': 'Joined the group!',
      'partnerName': memberNames[otherUid] ?? 'Partner',
      'partnerAvatar': memberAvatars[otherUid] ?? '',
      'pairId': groupId,
      'startDate': groupData != null
          ? ((groupData['startDate'] as Timestamp?)?.toDate() ?? DateTime.now())
          : DateTime.now(),
      'members': [...members, u.uid]
          .map(
            (uid) => {
              'uid': uid,
              'name': memberNames[uid] ?? '',
              'avatar': memberAvatars[uid] ?? '',
            },
          )
          .toList(),
    };
  }

  /// Update group maxMembers
  Future<void> updateGroupMaxMembers(String groupId, int maxMembers) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'maxMembers': maxMembers,
      });
    } catch (e) {
      debugPrint('updateGroupMaxMembers failed: $e');
    }
  }

  /// Update group relationship type with all fields
  Future<void> updateGroupRelationshipType(
    String groupId, {
    required String type,
    required int maxMembers,
    String customLabel = '',
    String customEmoji = '',
  }) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'relationshipType': type,
        'maxMembers': maxMembers,
        'customRelationshipLabel': customLabel,
        'customRelationshipEmoji': customEmoji,
      });
    } catch (e) {
      debugPrint('updateGroupRelationshipType failed: $e');
    }
  }

  /// Add a custom relationship type to the group's shared list
  Future<void> addCustomRelationshipType(
    String groupId,
    Map<String, String> entry,
  ) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'customRelationshipTypes': FieldValue.arrayUnion([entry]),
      });
    } catch (e) {
      debugPrint('addCustomRelationshipType failed: $e');
    }
  }

  /// Update a custom relationship type in the group's shared list
  Future<void> updateCustomRelationshipType(
    String groupId,
    Map<String, String> entry,
  ) async {
    try {
      final doc = await _db.collection('groups').doc(groupId).get();
      final data = doc.data();
      if (data == null) return;

      final list = List<Map<String, dynamic>>.from(
        (data['customRelationshipTypes'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      final idx = list.indexWhere((e) => e['id'] == entry['id']);
      if (idx != -1) {
        list[idx] = entry;
        await _db.collection('groups').doc(groupId).update({
          'customRelationshipTypes': list,
        });
      }
    } catch (e) {
      debugPrint('updateCustomRelationshipType failed: $e');
    }
  }

  /// Delete a custom relationship type from the group's shared list
  Future<void> deleteCustomRelationshipType(String groupId, String id) async {
    try {
      final doc = await _db.collection('groups').doc(groupId).get();
      final data = doc.data();
      if (data == null) return;

      final list = List<Map<String, dynamic>>.from(
        (data['customRelationshipTypes'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      list.removeWhere((e) => e['id'] == id);
      await _db.collection('groups').doc(groupId).update({
        'customRelationshipTypes': list,
      });
    } catch (e) {
      debugPrint('deleteCustomRelationshipType failed: $e');
    }
  }

  /// Load group data by groupId
  Future<Map<String, dynamic>?> loadPairById(String pairId) async {
    final u = currentUser;
    if (u == null || pairId.isEmpty) return null;

    try {
      final doc = await _db
          .collection('groups')
          .doc(pairId)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!doc.exists) {
        // Backward compat: try 'pairs' collection
        final pairDoc = await _db
            .collection('pairs')
            .doc(pairId)
            .get()
            .timeout(const Duration(seconds: 10));
        if (!pairDoc.exists) return null;
        return _parseLegacyPairDoc(pairId, pairDoc.data()!);
      }

      return _parseGroupDoc(pairId, doc.data()!);
    } catch (e) {
      debugPrint('loadPairById($pairId) failed: $e');
      return null;
    }
  }

  Map<String, dynamic> _parseGroupDoc(
    String groupId,
    Map<String, dynamic> data,
  ) {
    final u = currentUser!;
    final members = List<String>.from(data['members'] ?? []);
    final memberNames = Map<String, dynamic>.from(data['memberNames'] ?? {});
    final memberAvatars = Map<String, dynamic>.from(
      data['memberAvatars'] ?? {},
    );

    final otherUids = members.where((m) => m != u.uid).toList();
    final partnerUid = otherUids.isNotEmpty ? otherUids.first : '';

    return {
      'pairId': groupId,
      'partnerName': memberNames[partnerUid] ?? '',
      'partnerAvatar': memberAvatars[partnerUid] ?? '',
      'startDate': (data['startDate'] as Timestamp?)?.toDate(),
      'members': members
          .map(
            (uid) => {
              'uid': uid,
              'name': memberNames[uid] ?? '',
              'avatar': memberAvatars[uid] ?? '',
            },
          )
          .toList(),
      'maxMembers': data['maxMembers'] ?? 2,
      'memberMoods': data['memberMoods'] as Map<String, dynamic>? ?? {},
      'currentStatus': data['currentStatus'] as Map<String, dynamic>?,
      'customStatuses': data['customStatuses'] as List<dynamic>?,
      'relationshipType': data['relationshipType'] as String?,
      'customRelationshipLabel': data['customRelationshipLabel'] as String?,
      'customRelationshipEmoji': data['customRelationshipEmoji'] as String?,
      'customRelationshipTypes':
          data['customRelationshipTypes'] as List<dynamic>?,
      'raw': data,
    };
  }

  Map<String, dynamic> _parseLegacyPairDoc(
    String pairId,
    Map<String, dynamic> data,
  ) {
    final u = currentUser!;
    final isUser1 = data['user1'] == u.uid;
    return {
      'pairId': pairId,
      'partnerName': isUser1 ? data['user2Name'] : data['user1Name'],
      'partnerAvatar': isUser1 ? data['user2Avatar'] : data['user1Avatar'],
      'startDate': (data['startDate'] as Timestamp?)?.toDate(),
      'members': [
        {
          'uid': data['user1'],
          'name': data['user1Name'] ?? '',
          'avatar': data['user1Avatar'] ?? '',
        },
        {
          'uid': data['user2'],
          'name': data['user2Name'] ?? '',
          'avatar': data['user2Avatar'] ?? '',
        },
      ],
      'maxMembers': 2,
      'raw': data,
    };
  }

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

  /// Listen to group changes in real-time
  StreamSubscription? listenToPair({
    required String pairId,
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    return _db
        .collection('groups')
        .doc(pairId)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
          // Skip if data is only from cache and not yet confirmed by server
          if (snap.metadata.hasPendingWrites) {
            debugPrint('listenToPair: skipping snapshot with pending writes');
            return;
          }

          if (snap.exists) {
            final parsedData = _parseGroupDoc(pairId, snap.data()!);
            debugPrint(
              'listenToPair: updated group data, members=${parsedData['members']?.length}',
            );
            onData(parsedData);
          } else {
            debugPrint('listenToPair: group document deleted or not found');
            // Fallback: try legacy pairs collection
            _db
                .collection('pairs')
                .doc(pairId)
                .get(const GetOptions(source: Source.server))
                .then((pairSnap) {
                  if (pairSnap.exists) {
                    onData(_parseLegacyPairDoc(pairId, pairSnap.data()!));
                  } else {
                    onData(null);
                  }
                })
                .catchError((_) {
                  onData(null);
                });
          }
        });
  }

  /// Remove me from a group (or delete if ≤2 members)
  Future<void> unpairById(String groupId) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;

    var groupDoc = await _db.collection('groups').doc(groupId).get();

    if (groupDoc.exists) {
      final data = groupDoc.data()!;
      final members = List<String>.from(data['members'] ?? []);

      if (members.length <= 2) {
        // Delete the whole group
        final batch = _db.batch();
        batch.delete(_db.collection('groups').doc(groupId));
        for (final member in members) {
          batch.update(_db.collection('users').doc(member), {
            'pairIds': FieldValue.arrayRemove([groupId]),
          });
        }
        await batch.commit();

        for (final member in members) {
          final memberDoc = await _db.collection('users').doc(member).get();
          final remaining =
              (memberDoc.data()?['pairIds'] as List<dynamic>?) ?? [];
          await _db.collection('users').doc(member).update({
            'pairId': remaining.isNotEmpty ? remaining.last : '',
          });
        }
      } else {
        // Just leave the group
        debugPrint(
          'unpairById: leaving group $groupId (${members.length} members)',
        );

        // Update group document first to remove this member
        await _db.collection('groups').doc(groupId).update({
          'members': FieldValue.arrayRemove([u.uid]),
          'memberNames.${u.uid}': FieldValue.delete(),
          'memberAvatars.${u.uid}': FieldValue.delete(),
          'memberMoods.${u.uid}': FieldValue.delete(),
        });

        debugPrint('unpairById: removed from group, updating user doc');

        // Then update user's pairIds
        await _db.collection('users').doc(u.uid).update({
          'pairIds': FieldValue.arrayRemove([groupId]),
        });

        // Update user's active pairId
        final myDoc = await _db.collection('users').doc(u.uid).get();
        final remaining = (myDoc.data()?['pairIds'] as List<dynamic>?) ?? [];
        await _db.collection('users').doc(u.uid).update({
          'pairId': remaining.isNotEmpty ? remaining.last : '',
        });

        debugPrint('unpairById: successfully left group');
      }
      return;
    }

    // Fallback: legacy pairs collection
    final pairDoc = await _db.collection('pairs').doc(groupId).get();
    if (!pairDoc.exists) return;

    final pData = pairDoc.data()!;
    final partnerId = pData['user1'] == u.uid ? pData['user2'] : pData['user1'];

    final batch = _db.batch();
    batch.delete(_db.collection('pairs').doc(groupId));
    batch.update(_db.collection('users').doc(u.uid), {
      'pairId': '',
      'pairIds': FieldValue.arrayRemove([groupId]),
    });
    if (partnerId != null) {
      batch.update(_db.collection('users').doc(partnerId as String), {
        'pairId': '',
        'pairIds': FieldValue.arrayRemove([groupId]),
      });
    }
    await batch.commit();
  }

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
  //  MEMORIES — shared timeline for each group
  //  Firestore: groups/{groupId}/memories/{memoryId}
  // ══════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════════════════
  // FILE UPLOAD (Storage)
  // ══════════════════════════════════════════════════════════════════════════════

  /// Upload file to Firebase Storage and return download URL
  /// [path] - file path on device
  /// [destination] - storage path (e.g. 'memories/groupId/filename.jpg')
  Future<String?> uploadFile(String path, String destination) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('uploadFile: File does not exist: $path');
        return null;
      }

      final fileSize = await file.length();
      debugPrint(
        'uploadFile: Starting upload of $destination ($fileSize bytes)',
      );
      debugPrint('uploadFile: Storage bucket = ${_storage.bucket}');

      final ref = _storage.ref().child(destination);

      // Determine content type from extension
      final ext = path.split('.').last.toLowerCase();
      String? contentType;
      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        contentType = 'image/$ext';
      } else if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        contentType = 'video/$ext';
      } else if (['mp3', 'aac', 'wav', 'ogg', 'm4a', 'flac'].contains(ext)) {
        contentType = 'audio/$ext';
      }

      final metadata = contentType != null
          ? SettableMetadata(contentType: contentType)
          : null;

      final uploadTask = ref.putFile(file, metadata);

      // Monitor upload progress
      uploadTask.snapshotEvents.listen((event) {
        final progress = event.bytesTransferred / event.totalBytes;
        debugPrint(
          'uploadFile: Progress ${(progress * 100).toStringAsFixed(1)}%',
        );
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('uploadFile: Success! URL = $downloadUrl');
      return downloadUrl;
    } on FirebaseException catch (e) {
      debugPrint(
        'uploadFile FirebaseException: code=${e.code} message=${e.message}',
      );
      if (e.code == 'object-not-found') {
        debugPrint(
          'uploadFile: Firebase Storage bucket may not be activated. '
          'Go to Firebase Console → Storage → Get Started to enable it.',
        );
      }
      return null;
    } catch (e) {
      debugPrint('uploadFile failed: $e');
      return null;
    }
  }

  /// Удалить файл из Firebase Storage по его download URL.
  Future<void> deleteFileByUrl(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
      debugPrint('deleteFileByUrl: deleted $url');
    } catch (e) {
      debugPrint('deleteFileByUrl failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // MEMORIES (CRUD)
  // ══════════════════════════════════════════════════════════════════════════════

  Future<Memory?> addMemory({
    required String groupId,
    required MemoryType type,
    String? imageUrl,
    String? videoUrl,
    String? caption,
    String? locationName,
    double? latitude,
    double? longitude,
    String? musicTitle,
    String? musicArtist,
    String? musicUrl,
    String? musicCoverUrl,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return null;

    try {
      final userDoc = await _db.collection('users').doc(u.uid).get();
      final name = userDoc.data()?['displayName'] ?? u.displayName ?? '';
      final avatar = userDoc.data()?['avatarUrl'] ?? u.photoURL ?? '';

      final ref = _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .doc();
      final memory = Memory(
        id: ref.id,
        groupId: groupId,
        authorUid: u.uid,
        authorName: name,
        authorAvatar: avatar,
        type: type,
        createdAt: DateTime.now(),
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        caption: caption,
        locationName: locationName,
        latitude: latitude,
        longitude: longitude,
        musicTitle: musicTitle,
        musicArtist: musicArtist,
        musicUrl: musicUrl,
        musicCoverUrl: musicCoverUrl,
      );

      await ref.set(memory.toFirestore());
      return memory;
    } catch (e) {
      debugPrint('addMemory failed: $e');
      return null;
    }
  }

  Future<void> updateMemory({
    required String groupId,
    required String memoryId,
    String? caption,
    String? locationName,
    String? musicTitle,
    String? musicArtist,
    String? imageUrl,
    bool? isPinned,
  }) async {
    try {
      final updates = <String, dynamic>{'editedAt': Timestamp.now()};
      if (caption != null) updates['caption'] = caption;
      if (locationName != null) updates['locationName'] = locationName;
      if (musicTitle != null) updates['musicTitle'] = musicTitle;
      if (musicArtist != null) updates['musicArtist'] = musicArtist;
      if (imageUrl != null) updates['imageUrl'] = imageUrl;
      if (isPinned != null) updates['isPinned'] = isPinned;

      await _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .doc(memoryId)
          .update(updates);
    } catch (e) {
      debugPrint('updateMemory failed: $e');
    }
  }

  Future<void> deleteMemory({
    required String groupId,
    required String memoryId,
    String? imageUrl,
    String? videoUrl,
    String? musicUrl,
    String? musicCoverUrl,
  }) async {
    try {
      // Delete associated files from Firebase Storage
      final urls = [imageUrl, videoUrl, musicUrl, musicCoverUrl];
      for (final url in urls) {
        if (url != null && url.contains('firebasestorage')) {
          try {
            await _storage.refFromURL(url).delete();
            debugPrint('Deleted storage file: $url');
          } catch (e) {
            debugPrint('Failed to delete storage file: $e');
          }
        }
      }

      // Delete Firestore document
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .doc(memoryId)
          .delete();
    } catch (e) {
      debugPrint('deleteMemory failed: $e');
    }
  }

  Future<void> togglePinMemory({
    required String groupId,
    required String memoryId,
    required bool isPinned,
  }) async {
    await updateMemory(
      groupId: groupId,
      memoryId: memoryId,
      isPinned: isPinned,
    );
  }

  Future<List<Memory>> loadMemories({
    required String groupId,
    int limit = 50,
  }) async {
    try {
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get()
          .timeout(const Duration(seconds: 10));

      return snap.docs
          .map((d) => Memory.fromFirestore(d.id, d.data()))
          .toList();
    } catch (e) {
      debugPrint('loadMemories failed: $e');
      return [];
    }
  }

  StreamSubscription? listenToMemories({
    required String groupId,
    required void Function(List<Memory> memories) onData,
    int limit = 100,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('memories')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .listen((snap) {
          final memories = snap.docs
              .map((d) => Memory.fromFirestore(d.id, d.data()))
              .toList();
          onData(memories);
        });
  }

  // ══════════════════════════════════════════════
  //  COMMENTS
  // ══════════════════════════════════════════════

  CollectionReference _commentsRef(String groupId, String memoryId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('memories')
        .doc(memoryId)
        .collection('comments');
  }

  Future<void> addComment({
    required String groupId,
    required String memoryId,
    required String text,
  }) async {
    final user = currentUser;
    if (user == null) return;
    final comment = MemoryComment(
      id: '',
      authorUid: user.uid,
      authorName: user.displayName ?? 'User',
      authorAvatar: user.photoURL ?? '',
      text: text,
      createdAt: DateTime.now(),
    );
    try {
      await _commentsRef(groupId, memoryId).add(comment.toFirestore());
    } catch (e) {
      debugPrint('addComment failed: $e');
    }
  }

  Future<void> deleteComment({
    required String groupId,
    required String memoryId,
    required String commentId,
  }) async {
    try {
      await _commentsRef(groupId, memoryId).doc(commentId).delete();
    } catch (e) {
      debugPrint('deleteComment failed: $e');
    }
  }

  Stream<List<MemoryComment>> commentsStream({
    required String groupId,
    required String memoryId,
  }) {
    return _commentsRef(groupId, memoryId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => MemoryComment.fromFirestore(
                  d.id,
                  d.data() as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  // ══════════════════════════════════════════════
  //  MOOD
  //  Firestore: groups/{groupId} → memberMoods.{uid}: {imagePath, label, updatedAt}
  // ══════════════════════════════════════════════

  /// Save the current user's mood to the group document
  Future<void> setMood({
    required String groupId,
    required String imagePath,
    required String label,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).update({
        'memberMoods.${u.uid}': {
          'imagePath': imagePath,
          'label': label,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });
    } catch (e) {
      debugPrint('setMood failed: $e');
    }
  }

  /// Clear the current user's mood
  Future<void> clearMood({required String groupId}) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).update({
        'memberMoods.${u.uid}': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('clearMood failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  RELATIONSHIP STATUS
  //  Firestore: groups/{groupId} → currentStatus: {...}, customStatuses: [...]
  // ══════════════════════════════════════════════

  /// Set the group's current relationship status
  Future<void> setGroupStatus(String groupId, dynamic status) async {
    if (groupId.isEmpty) return;
    try {
      final statusData = status is Map<String, dynamic>
          ? status
          : (status as dynamic).toJson();
      await _db.collection('groups').doc(groupId).update({
        'currentStatus': statusData,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('setGroupStatus failed: $e');
    }
  }

  /// Clear the group's current relationship status
  Future<void> clearGroupStatus(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).update({
        'currentStatus': FieldValue.delete(),
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('clearGroupStatus failed: $e');
    }
  }

  /// Add a custom status to the group
  Future<void> addCustomStatus(String groupId, dynamic status) async {
    if (groupId.isEmpty) return;
    try {
      final statusData = status is Map<String, dynamic>
          ? status
          : (status as dynamic).toJson();
      await _db.collection('groups').doc(groupId).update({
        'customStatuses': FieldValue.arrayUnion([statusData]),
      });
    } catch (e) {
      debugPrint('addCustomStatus failed: $e');
    }
  }

  /// Update a custom status in the group
  Future<void> updateCustomStatus(String groupId, dynamic status) async {
    if (groupId.isEmpty) return;
    try {
      final statusData = status is Map<String, dynamic>
          ? status
          : (status as dynamic).toJson();

      // Get current custom statuses
      final doc = await _db.collection('groups').doc(groupId).get();
      final data = doc.data();
      if (data == null) return;

      final customStatuses = List<Map<String, dynamic>>.from(
        (data['customStatuses'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      // Find and update the status
      final index = customStatuses.indexWhere(
        (s) => s['id'] == statusData['id'],
      );
      if (index != -1) {
        customStatuses[index] = statusData;
        await _db.collection('groups').doc(groupId).update({
          'customStatuses': customStatuses,
        });

        // Also update currentStatus if it matches
        final currentStatus = data['currentStatus'] as Map<String, dynamic>?;
        if (currentStatus != null && currentStatus['id'] == statusData['id']) {
          await _db.collection('groups').doc(groupId).update({
            'currentStatus': statusData,
          });
        }
      }
    } catch (e) {
      debugPrint('updateCustomStatus failed: $e');
    }
  }

  /// Delete a custom status from the group
  Future<void> deleteCustomStatus(String groupId, String statusId) async {
    if (groupId.isEmpty) return;
    try {
      // Get current custom statuses
      final doc = await _db.collection('groups').doc(groupId).get();
      final data = doc.data();
      if (data == null) return;

      final customStatuses = List<Map<String, dynamic>>.from(
        (data['customStatuses'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      // Remove the status
      customStatuses.removeWhere((s) => s['id'] == statusId);

      final updates = <String, dynamic>{'customStatuses': customStatuses};

      // Also clear currentStatus if it matches
      final currentStatus = data['currentStatus'] as Map<String, dynamic>?;
      if (currentStatus != null && currentStatus['id'] == statusId) {
        updates['currentStatus'] = FieldValue.delete();
      }

      await _db.collection('groups').doc(groupId).update(updates);
    } catch (e) {
      debugPrint('deleteCustomStatus failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  TIMERS (synced across group)
  // ══════════════════════════════════════════════

  /// Save full timers list to group document
  Future<void> saveTimers({
    required String groupId,
    required List<Map<String, dynamic>> timers,
  }) async {
    try {
      debugPrint(
        'FirebaseService: сохраняю ${timers.length} таймеров в группу $groupId',
      );
      await _db.collection('groups').doc(groupId).update({'timers': timers});
      debugPrint('FirebaseService: таймеры успешно сохранены');
    } catch (e) {
      debugPrint('FirebaseService: ошибка сохранения таймеров - $e');
      // Если документ группы не существует или нет поля timers - пробуем set
      try {
        debugPrint('FirebaseService: пробую создать поле timers через set...');
        await _db.collection('groups').doc(groupId).set({
          'timers': timers,
        }, SetOptions(merge: true));
        debugPrint('FirebaseService: таймеры сохранены через set');
      } catch (e2) {
        debugPrint(
          'FirebaseService: критическая ошибка сохранения таймеров - $e2',
        );
      }
    }
  }

  /// Listen to timers changes in real-time
  StreamSubscription? listenToTimers({
    required String groupId,
    required void Function(List<TimerItem> timers) onData,
  }) {
    return _db.collection('groups').doc(groupId).snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      final timersList = data['timers'] as List<dynamic>?;
      if (timersList != null) {
        final timers = timersList
            .map((e) => TimerItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        onData(timers);
      } else {
        onData([]);
      }
    });
  }

  // ══════════════════════════════════════════════
  //  MOOD CALENDAR
  //  Firestore: groups/{groupId}/moodCalendar/{uid}/entries/{entryId}
  // ══════════════════════════════════════════════

  /// Add a mood entry for the current user
  Future<void> addMoodEntry({
    required String groupId,
    required Map<String, dynamic> entry,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('moodCalendar')
          .doc(u.uid)
          .collection('entries')
          .doc(entry['id'] as String)
          .set(entry);
    } catch (e) {
      debugPrint('addMoodEntry failed: $e');
    }
  }

  /// Delete a mood entry
  Future<void> deleteMoodEntry({
    required String groupId,
    required String entryId,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('moodCalendar')
          .doc(u.uid)
          .collection('entries')
          .doc(entryId)
          .delete();
    } catch (e) {
      debugPrint('deleteMoodEntry failed: $e');
    }
  }

  /// Listen to mood entries for a specific user in real-time
  StreamSubscription? listenToMoodEntries({
    required String groupId,
    required String uid,
    required void Function(List<Map<String, dynamic>> entries) onData,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('moodCalendar')
        .doc(uid)
        .collection('entries')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snap) {
          final entries = snap.docs.map((d) => d.data()).toList();
          onData(entries);
        });
  }

  // ══════════════════════════════════════════════
  //  DAILY REFLECTION
  // ══════════════════════════════════════════════

  /// Сохранить / обновить ответ пользователя на вопрос дня.
  /// Путь: groups/{groupId}/reflections/{YYYY-MM-DD}
  Future<void> saveReflectionAnswer({
    required String groupId,
    required String question,
    required String answer,
    required String authorName,
  }) async {
    final uid = this.uid;
    if (uid == null) return;
    final dayKey = _reflectionDayKey(DateTime.now());
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('reflections')
          .doc(dayKey)
          .set({
            'question': question,
            'updatedAt': FieldValue.serverTimestamp(),
            'answers.$uid': {
              'text': answer,
              'authorName': authorName,
              'createdAt': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('saveReflectionAnswer failed: $e');
    }
  }

  /// Слушать рефлексию текущего дня в реальном времени.
  StreamSubscription listenToTodayReflection({
    required String groupId,
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    final dayKey = _reflectionDayKey(DateTime.now());
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('reflections')
        .doc(dayKey)
        .snapshots()
        .listen((snap) => onData(snap.exists ? snap.data() : null));
  }

  static String _reflectionDayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ══════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
