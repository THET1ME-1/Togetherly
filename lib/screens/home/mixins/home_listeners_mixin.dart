import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/memory.dart';
import '../../../models/pair_data.dart';
import '../../../models/mood_entry.dart';
import '../../../services/firebase_service.dart';
import '../../../services/home_widget_service.dart';
import '../../../services/mood_service.dart';
import '../../../services/timer_service.dart';
import '../../../services/widget_service.dart';

/// Mixin that handles widget synchronization and real-time listeners
mixin HomeListenersMixin<T extends StatefulWidget> on State<T> {
  late final FirebaseService fb;
  late final HomeWidgetService homeWidgetService;
  late final MoodService moodService;
  late final TimerService timerService;
  late final WidgetService widgetService;
  late final PairData pairData;

  List<Memory> recentMemories = [];
  StreamSubscription? memorySub;

  /// Initialize services - call this in initState
  void initListeners({
    required FirebaseService firebaseService,
    required HomeWidgetService hws,
    required MoodService moodSvc,
    required TimerService timerSvc,
    required WidgetService widgetSvc,
    required PairData pair,
  }) {
    fb = firebaseService;
    homeWidgetService = hws;
    moodService = moodSvc;
    timerService = timerSvc;
    widgetService = widgetSvc;
    pairData = pair;
  }

  /// Start listening to memory updates
  void startMemoryListener() {
    memorySub?.cancel();
    final groupId = pairData.pairId;
    if (groupId.isEmpty || !pairData.isPaired) {
      recentMemories = [];
      return;
    }
    memorySub = fb.listenToMemories(
      groupId: groupId,
      limit: 10,
      onData: (memories) {
        if (mounted) {
          setState(() => recentMemories = memories);
        }
      },
    );
  }

  /// Cancel memory listener
  void cancelMemoryListener() {
    memorySub?.cancel();
  }

  /// Sync all home widgets with current data
  Future<void> syncHomeWidgets({
    required String displayName,
    String myGender = '',
  }) async {
    if (!pairData.isPaired) return;

    final myName = displayName;
    final partnerName = pairData.partnerDisplayName;

    final partnerGender = widgetService.firstPartnerData?.gender ?? '';

    await homeWidgetService.syncAllBoundWidgets(
      activeGroupId: pairData.pairId,
      activeTimers: timerService.timers,
      activeSysTimer: timerService.systemTimer,
      activeStartDate: pairData.startDate,
      coupleNames: '$myName & $partnerName',
      emoji: pairData.relationshipEmoji,
      myGender: myGender,
      partnerGender: partnerGender,
    );

    // Sync the mood widget from today's Mood Calendar entries
    await _syncMoodWidget(displayName);
  }

  /// Sync mood widget with current mood data
  Future<void> _syncMoodWidget(String displayName) async {
    if (!pairData.isPaired) return;
    final today = DateTime.now();

    // Get current user's mood
    final myEntries = moodService.myEntriesForDay(today);
    final myEntry = myEntries.isNotEmpty ? myEntries.first : null;

    // Get partner's mood
    final partnerUid = pairData.partners.isNotEmpty
        ? pairData.partners.first.uid
        : '';
    final partnerEntries = partnerUid.isNotEmpty
        ? moodService.partnerEntriesForDay(partnerUid, today)
        : <MoodEntry>[];
    final partnerEntry = partnerEntries.isNotEmpty
        ? partnerEntries.first
        : null;

    await HomeWidgetService.instance.syncMood(
      moodEmojiAssetPath: myEntry?.imagePath ?? '',
      moodLabel: myEntry?.localizedLabel ?? '',
      userName: displayName,
      partnerMoodEmojiAssetPath: partnerEntry?.imagePath ?? '',
      partnerMoodLabel: partnerEntry?.localizedLabel ?? '',
      partnerUserName: pairData.partnerDisplayName,
    );
  }
}
