import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_entry.dart';

void main() {
  group('MoodOption.score — happy tier (5)', () {
    const happyIds = [
      'happy',
      'starstruck',
      'yummy',
      'laughing',
      'grin',
      'kiss',
      'love',
      'blessed',
      'laughing_hard',
    ];
    for (final id in happyIds) {
      test(id, () {
        final mood = MoodOption.all.firstWhere(
          (m) => m.id == id,
          orElse: () => MoodOption(
            id: id,
            imagePath: '',
            label: '',
            color: const Color(0xFF000000),
          ),
        );
        expect(mood.score, 5, reason: 'Expected $id to score 5');
      });
    }
  });

  group('MoodOption.score — content tier (4)', () {
    const contentIds = ['winking', 'flush', 'smirking', 'cool', 'blush'];
    for (final id in contentIds) {
      test(id, () {
        final mood = MoodOption.all.firstWhere(
          (m) => m.id == id,
          orElse: () => MoodOption(
            id: id,
            imagePath: '',
            label: '',
            color: const Color(0xFF000000),
          ),
        );
        expect(mood.score, 4, reason: 'Expected $id to score 4');
      });
    }
  });

  group('MoodOption.score — neutral tier (3)', () {
    const neutralIds = [
      'no_expression',
      'secret',
      'mute',
      'sleepy',
      'surprised',
      'shy',
    ];
    for (final id in neutralIds) {
      test(id, () {
        final mood = MoodOption.all.firstWhere(
          (m) => m.id == id,
          orElse: () => MoodOption(
            id: id,
            imagePath: '',
            label: '',
            color: const Color(0xFF000000),
          ),
        );
        expect(mood.score, 3, reason: 'Expected $id to score 3');
      });
    }
  });

  group('MoodOption.score — sad tier (2)', () {
    const sadIds = ['sad', 'tired', 'confused', 'annoyed'];
    for (final id in sadIds) {
      test(id, () {
        final mood = MoodOption.all.firstWhere(
          (m) => m.id == id,
          orElse: () => MoodOption(
            id: id,
            imagePath: '',
            label: '',
            color: const Color(0xFF000000),
          ),
        );
        expect(mood.score, 2, reason: 'Expected $id to score 2');
      });
    }
  });

  group('MoodOption.score — bad tier (1)', () {
    const badIds = ['crying', 'angry', 'dead', 'vomiting', 'scared'];
    for (final id in badIds) {
      test(id, () {
        final mood = MoodOption.all.firstWhere(
          (m) => m.id == id,
          orElse: () => MoodOption(
            id: id,
            imagePath: '',
            label: '',
            color: const Color(0xFF000000),
          ),
        );
        expect(mood.score, 1, reason: 'Expected $id to score 1');
      });
    }
  });

  test('unknown id defaults to score 3', () {
    const unknown = MoodOption(
      id: 'totally_unknown',
      imagePath: '',
      label: '',
      color: Color(0xFF000000),
    );
    expect(unknown.score, 3);
  });

  test('all predefined moods have non-empty id, label, imagePath', () {
    for (final m in MoodOption.all) {
      expect(m.id, isNotEmpty, reason: 'id is empty');
      expect(m.label, isNotEmpty, reason: 'label is empty for ${m.id}');
      expect(m.imagePath, isNotEmpty, reason: 'imagePath is empty for ${m.id}');
    }
  });

  test('all predefined moods have score in valid range 1..5', () {
    for (final m in MoodOption.all) {
      expect(
        m.score,
        inInclusiveRange(1, 5),
        reason: '${m.id} has invalid score ${m.score}',
      );
    }
  });
}
