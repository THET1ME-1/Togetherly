import 'dart:typed_data';

import 'package:love_app/models/custom_mood.dart';
import 'package:love_app/services/custom_mood_service.dart';

/// Набор своих настроений в памяти вместо PocketBase.
class FakeCustomMoodStore implements CustomMoodStore {
  FakeCustomMoodStore([List<CustomMood>? moods]) : moods = [...?moods];

  final List<CustomMood> moods;

  /// Что пришло в последнем create.
  ({String groupId, String label, int score, Uint8List png, String emoji})? created;

  /// Что пришло в последнем rename.
  ({String recordId, String label, int score})? renamed;

  final List<String> removed = [];

  /// Отказ сервера на следующую операцию.
  bool failNext = false;

  int loads = 0;

  @override
  Future<List<CustomMood>> load(String groupId) async {
    loads++;
    return List.of(moods);
  }

  @override
  Future<CustomMood?> create({
    required String groupId,
    required String label,
    required int score,
    required Uint8List png,
    String emoji = '',
  }) async {
    if (failNext) {
      failNext = false;
      return null;
    }
    created = (groupId: groupId, label: label, score: score, png: png, emoji: emoji);
    final mood = CustomMood(
      id: 'new${moods.length}',
      groupId: groupId,
      authorUid: 'me',
      moodId: 'custom_new${moods.length}',
      label: label,
      emoji: emoji,
      imageUrl: 'assets/images/new emodji/Счастье.webp',
      score: score,
    );
    moods.add(mood);
    return mood;
  }

  @override
  Future<bool> rename({required String recordId, required String label, required int score}) async {
    if (failNext) {
      failNext = false;
      return false;
    }
    renamed = (recordId: recordId, label: label, score: score);
    return true;
  }

  @override
  Future<bool> remove(String recordId) async {
    if (failNext) {
      failNext = false;
      return false;
    }
    removed.add(recordId);
    moods.removeWhere((m) => m.id == recordId);
    return true;
  }
}

/// Своё настроение для тестов: картинка из сборки, чтобы сетка не ходила в сеть.
CustomMood ownMood(
  String id, {
  int score = 3,
  String emoji = '',
  String author = 'me',
  String label = '',
  String image = 'assets/images/new emodji/Счастье.webp',
}) =>
    CustomMood(
      id: id,
      groupId: 'g1',
      authorUid: author,
      moodId: 'custom_$id',
      label: label.isEmpty ? id : label,
      emoji: emoji,
      imageUrl: image,
      score: score,
    );
