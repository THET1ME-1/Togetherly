import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mood_entry.dart';

/// One-time migration from 50 old emoji emotions to 17 new ones.
///
/// Run [runIfNeeded] after the user's group is known. The migration is
/// idempotent — entries already using new paths are skipped.
class EmotionMigrationService {
  EmotionMigrationService._();
  static final EmotionMigrationService instance = EmotionMigrationService._();

  static const String _kDoneKey = 'emotion_v2_migration_done';
  static const int _kNotificationId = 7777;
  static const String _kChannelId = 'emotion_update_v2';

  // Maps old moodId → new moodId (null = no equivalent, delete entry).
  static const Map<String, String?> _oldToNewId = {
    'sad': 'sad',
    'winking': 'winking',
    'liar': 'liar',
    'greed': null,
    'crying': 'very_sad',
    'starstruck': 'happy',
    'happy': 'happy',
    'no_expression': 'no_emotion',
    'disappointment': 'hurt',
    'disappointed': 'sad',
    'yummy': null,
    'crying_hard': 'very_sad',
    'angry': 'anger',
    'blush': 'embarrassed',
    'dead': null,
    'crazy': null,
    'cool': 'cool',
    'angry_rage': 'anger',
    'disappointed_bad': 'very_sad',
    'laughing': 'laugh',
    'surprised': 'surprise',
    'devil': 'devil',
    'dizzy': null,
    'drooling': 'drooling',
    'flush': 'embarrassed',
    'grimacing': null,
    'grin': 'laugh',
    'kiss': 'kiss',
    'secret': null,
    'scared': 'fear',
    'rolling_eyes': null,
    'mute': null,
    'love': 'love',
    'angry_furious': 'anger',
    'laughing_hard': 'laugh',
    'shy': 'embarrassed',
    'sick': 'sick',
    'sick_fever': 'sick',
    'annoyed': 'hurt',
    'sleepy': 'missing',
    'smirking': 'laugh',
    'surprised_shock': 'surprise',
    'cold': null,
    'blessed': 'happy',
    'astonished': 'surprise',
    'vomiting': 'sick',
    'unamused': 'no_emotion',
    'tired': 'missing',
    'sweating': 'anxiety',
    'confused': 'embarrassed',
  };

  final _db = FirebaseFirestore.instance;
  final _notifPlugin = FlutterLocalNotificationsPlugin();
  bool _notifReady = false;

  /// Runs migration once. Safe to call on every app open — exits early if
  /// migration already completed.
  Future<void> runIfNeeded({
    required String groupId,
    required String uid,
  }) async {
    if (groupId.isEmpty || uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kDoneKey) ?? false) return;

      await _migrateEntries(groupId: groupId, uid: uid);
      await _showUpdateNotification();

      await prefs.setBool(_kDoneKey, true);
      debugPrint('EmotionMigrationService: migration complete');
    } catch (e) {
      debugPrint('EmotionMigrationService.runIfNeeded failed: $e');
      // Don't set flag on failure so it retries next launch.
    }
  }

  Future<void> _migrateEntries({
    required String groupId,
    required String uid,
  }) async {
    final entriesRef = _db
        .collection('groups')
        .doc(groupId)
        .collection('moodCalendar')
        .doc(uid)
        .collection('entries');

    final snapshot = await entriesRef.get();
    if (snapshot.docs.isEmpty) return;

    final now = DateTime.now();
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    // Firestore allows max 500 ops per batch.
    final batches = <WriteBatch>[_db.batch()];
    int opsInBatch = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final imagePath = data['imagePath'] as String? ?? '';
      final moodId = data['moodId'] as String? ?? '';

      // Skip entries already using new paths.
      if (!imagePath.startsWith('assets/images/emoji/')) continue;

      // Today's entry — always delete so user picks fresh.
      final ts = (data['timestamp'] as Timestamp?)?.toDate();
      if (ts != null) {
        final dayKey =
            '${ts.year.toString().padLeft(4, '0')}-'
            '${ts.month.toString().padLeft(2, '0')}-'
            '${ts.day.toString().padLeft(2, '0')}';
        if (dayKey == todayKey) {
          batches.last.delete(doc.reference);
          opsInBatch++;
          if (opsInBatch >= 490) {
            batches.add(_db.batch());
            opsInBatch = 0;
          }
          continue;
        }
      }

      // Past entries — map to closest new emotion or delete.
      final newId = _oldToNewId[moodId];
      final newOption = newId != null ? MoodOption.byId(newId) : null;

      if (newOption == null) {
        batches.last.delete(doc.reference);
      } else {
        batches.last.update(doc.reference, {
          'moodId': newOption.id,
          'imagePath': newOption.imagePath,
          'label': newOption.label,
        });
      }

      opsInBatch++;
      if (opsInBatch >= 490) {
        batches.add(_db.batch());
        opsInBatch = 0;
      }
    }

    for (final batch in batches) {
      await batch.commit();
    }
  }

  Future<void> _showUpdateNotification() async {
    try {
      await _initNotif();
      await _notifPlugin.show(
        id: _kNotificationId,
        title: 'Эмоции обновились ✨',
        body: 'Мы обновили дизайн эмоций — выбери свою новую!',
        notificationDetails: NotificationDetails(
          android: const AndroidNotificationDetails(
            _kChannelId,
            'Обновления',
            channelDescription: 'Обновления приложения',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@drawable/ic_notification',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('EmotionMigrationService._showUpdateNotification failed: $e');
    }
  }

  Future<void> _initNotif() async {
    if (_notifReady) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(),
    );
    await _notifPlugin.initialize(settings: settings);

    if (Platform.isAndroid) {
      final androidPlugin = _notifPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kChannelId,
          'Обновления',
          description: 'Обновления приложения',
          importance: Importance.defaultImportance,
          playSound: false,
          enableVibration: false,
        ),
      );
    }
    _notifReady = true;
  }
}
