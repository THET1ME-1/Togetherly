import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

import '../models/mood_entry.dart';
import '../models/pair_data.dart';
import '../models/timer_item.dart';
import 'home_widget_service.dart';
import 'mood_service.dart';

/// Данные для виджетов нового каталога: «Вместе», «Настроение — плитки»,
/// «Кольцо года» и «Календарь лет».
///
/// Раньше их писал только экран «Виджеты». Кто добавлял виджет из системной
/// галереи, ни разу не заглянув на этот экран, видел пустые плитки — и считал,
/// что виджет сломан. На Android это отчасти прикрывало фоновое обновление
/// через WorkManager, а на iOS фонового обновления нет вовсе, поэтому там пусто
/// оставалось насовсем.
///
/// Теперь тот же набор пишется с главного экрана при каждом обновлении виджетов.
/// Экран «Виджеты» свои вызовы сохранил: там данные нужны сразу после правки
/// настроек, не дожидаясь возврата на главную.
class CatalogWidgetSync {
  CatalogWidgetSync._();

  static const _months = <String>[
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  static String _dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.characters.first.toUpperCase();
  }

  /// Доля дня в шкале виджета: 20..100. `-1` — отметки нет.
  static int _percentOf(MoodEntry? e) =>
      e == null ? -1 : (((e.score - 1) / 4) * 80 + 20).round().clamp(20, 100);

  /// Записать данные всех виджетов каталога.
  ///
  /// [memoriesCount] — сколько воспоминаний у пары; влияет только на
  /// «Календарь лет». Ошибки глушим: виджеты не стоят сорванного экрана.
  static Future<void> sync({
    required PairData pair,
    required MoodService moods,
    required String myName,
    required String myAvatarUrl,
    TimerItem? systemTimer,
    TimerItem? defaultTimer,
    int memoriesCount = 0,
  }) async {
    try {
      final hws = HomeWidgetService.instance;
      final timer = defaultTimer ?? systemTimer;
      final start = timer?.startDate ?? pair.startDate;
      final days = timer != null
          ? timer.daysElapsed.abs()
          : (start != null ? DateTime.now().difference(start).inDays : 0);

      final partnerName = pair.partnerDisplayName.trim();
      final names =
          [myName.trim(), partnerName].where((n) => n.isNotEmpty).join(' + ');

      await hws.syncTogether(
        groupId: pair.pairId,
        days: days,
        startDate: start == null ? '' : 'С ${_dayMonth(start)} ${start.year}',
        start: start,
        myInitial: _initial(myName),
        partnerInitial: _initial(partnerName),
        names: names,
        anniversary: start == null ? '' : _dayMonth(start),
        myAvatarUrl: myAvatarUrl,
        partnerAvatarUrl: pair.partnerAvatarUrl,
      );

      await hws.syncYearWidgets(
        groupId: pair.pairId,
        start: start,
        memoriesCount: memoriesCount,
        startDateLabel: start == null ? '' : 'с ${_dayMonth(start)} ${start.year}',
      );

      await _syncMoodTiles(pair: pair, moods: moods);
    } catch (e) {
      debugPrint('CatalogWidgetSync.sync failed: $e');
    }
  }

  static Future<void> _syncMoodTiles({
    required PairData pair,
    required MoodService moods,
  }) async {
    final today = DateTime.now();
    final partnerUid = pair.partnerUid;

    MoodEntry? first(List<MoodEntry> list) =>
        list.isNotEmpty ? list.first : null;

    final week = <List<int>>[];
    var matched = 0;
    // От понедельника этой недели к воскресенью — тот же порядок, что в виджете.
    final monday = today.subtract(Duration(days: today.weekday - 1));
    for (var i = 0; i < 7; i++) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final mine = first(moods.myEntriesForDay(day));
      final theirs = partnerUid.isEmpty
          ? null
          : first(moods.partnerEntriesForDay(partnerUid, day));
      week.add([_percentOf(mine), _percentOf(theirs)]);
      if (mine != null && theirs != null && mine.score == theirs.score) {
        matched++;
      }
    }

    final myToday = first(moods.myEntriesForDay(today));
    final partnerToday = partnerUid.isEmpty
        ? null
        : first(moods.partnerEntriesForDay(partnerUid, today));

    await HomeWidgetService.instance.syncMoodTiles(
      groupId: pair.pairId,
      // Подпись по полу: «Устал» парню, «Устала» девушке.
      myLabel: myToday == null
          ? ''
          : (MoodOption.byId(myToday.moodId)
                  ?.localizedLabelFor(HomeWidgetService.instance.cachedMyGender) ??
              ''),
      myMoodId: myToday?.moodId ?? '',
      partnerLabel: partnerToday == null
          ? ''
          : (MoodOption.byId(partnerToday.moodId)?.localizedLabelFor(
                  HomeWidgetService.instance.cachedPartnerGender) ??
              ''),
      partnerName: pair.partnerDisplayName.trim(),
      week: week,
      matchedDays: matched,
    );
  }
}
