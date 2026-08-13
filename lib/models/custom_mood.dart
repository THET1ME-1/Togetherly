import 'dart:math';

import 'package:flutter/material.dart';

import 'mood_entry.dart';

/// Настроение, которое пара завела сама (Togetherly+).
///
/// Просьба из отзыва: «добавить своё настроение со своим эмодзи и текстом».
/// Источника три — эмодзи, фотография и рисунок, — но хранится любое из них
/// одинаково: картинкой 512×512 в записи `custom_moods`. Эмодзи рисуется в
/// эту же картинку при создании, и тогда своё настроение работает везде, где
/// работают встроенные: сетка выбора, календарь, виджеты рабочего стола и
/// экран партнёра — включая тех, у кого сборка старее.
///
/// Сам символ остаётся в поле `emoji` — по нему форма правки открывается с тем,
/// что человек выбрал, а не с готовой картинкой.
class CustomMood {
  /// id записи `custom_moods`.
  final String id;
  final String groupId;
  final String authorUid;

  /// Идентификатор настроения (`custom_<8 знаков>`) — он уезжает в отметку и
  /// в статистику наравне со встроенными.
  final String moodId;

  final String label;

  /// Исходный символ, если настроение сделано из эмодзи. Для фотографии и
  /// рисунка пусто.
  final String emoji;

  /// Готовый адрес картинки. Файл лежит открытым, как у каталожных паков:
  /// его тянут и виджеты рабочего стола, где сессии PocketBase нет вовсе.
  final String imageUrl;

  /// Балл по общей шкале 1…5 — от тяжёлого к светлому. На нём держатся разделы
  /// сетки, календарь и статистика пары, поэтому человек выбирает его сам.
  final int score;

  final int sort;

  const CustomMood({
    required this.id,
    required this.groupId,
    required this.authorUid,
    required this.moodId,
    required this.label,
    required this.emoji,
    required this.imageUrl,
    required this.score,
    this.sort = 0,
  });

  /// Своё настроение в том же виде, в каком живут встроенные.
  MoodOption toMoodOption() => MoodOption(
        id: moodId,
        imagePath: imageUrl,
        label: label,
        color: colorOfScore(score),
        labelEn: label,
        scoreOverride: score,
      );

  static const int _neutralScore = 3;

  /// Балл в границах общей шкалы.
  static int clampScore(int raw) => raw.clamp(1, 5);

  /// Цвет по баллу — тот же набор, которым красятся встроенные настроения:
  /// точки календаря и подсветка в сетке остаются на одной шкале.
  static Color colorOfScore(int score) {
    switch (clampScore(score)) {
      case 5:
        return const Color(0xFFFFC800);
      case 4:
        return const Color(0xFFF06EAF);
      case 3:
        return const Color(0xFF7A7FA8);
      case 2:
        return const Color(0xFF6E8FBF);
      default:
        return const Color(0xFFA066D8);
    }
  }

  static const String _prefix = 'custom_';
  static final Random _rnd = Random();

  /// Новый идентификатор настроения. Восемь знаков хватает: набор живёт внутри
  /// одной пары, а не в общем каталоге.
  static String newMoodId() {
    const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final buf = StringBuffer(_prefix);
    for (var i = 0; i < 8; i++) {
      buf.write(abc[_rnd.nextInt(abc.length)]);
    }
    return buf.toString();
  }

  /// Своё ли это настроение. По нему экраны решают, показывать ли правку.
  static bool isCustom(String moodId) => moodId.startsWith(_prefix);

  /// Запись коллекции → модель. [fileUrl] строит адрес файла: у PocketBase он
  /// собирается из имени коллекции, id записи и имени файла.
  factory CustomMood.fromMap(
    Map<String, dynamic> d, {
    required String Function(String id, String file) fileUrl,
  }) {
    final id = (d['id'] ?? '').toString();
    final file = (d['image'] ?? '').toString();
    return CustomMood(
      id: id,
      groupId: (d['group_id'] ?? '').toString(),
      authorUid: (d['author_uid'] ?? '').toString(),
      moodId: (d['mood_id'] ?? '').toString(),
      label: (d['label'] ?? '').toString(),
      emoji: (d['emoji'] ?? '').toString(),
      imageUrl: file.isEmpty ? '' : fileUrl(id, file),
      score: clampScore((d['score'] as num?)?.toInt() ?? _neutralScore),
      sort: (d['sort'] as num?)?.toInt() ?? 0,
    );
  }
}
