// Из фотографии человек выбирает цвет, а не получает его молча: снимок даёт
// шесть-восемь заметных оттенков, и какой из них «наш», знает только он.
// Задача разбора — не решить за него, а убрать из ряда то, что выбирать
// бессмысленно: почти одинаковые оттенки и серую кашу впереди живого цвета.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/photo_seed.dart';

void main() {
  group('кандидаты из снимка', () {
    test('порядок задаёт заметность цвета на кадре', () {
      final out = pickSeedCandidates(const [
        SeedCandidate(Color(0xFF1685A2), 120),
        SeedCandidate(Color(0xFFF0A81C), 900),
        SeedCandidate(Color(0xFF7C5CFF), 400),
      ]);
      expect(out, const [
        Color(0xFFF0A81C),
        Color(0xFF7C5CFF),
        Color(0xFF1685A2),
      ]);
    });

    test('почти одинаковые оттенки схлопываются в один', () {
      // Два соседних розовых на закате различает пипетка, но не глаз: в ряду
      // из шести кружков это выглядит как две одинаковые кнопки.
      final out = pickSeedCandidates(const [
        SeedCandidate(Color(0xFFFF7E9B), 500),
        SeedCandidate(Color(0xFFFF8199), 480),
      ]);
      expect(out, hasLength(1));
      expect(out.single, const Color(0xFFFF7E9B));
    });

    test('серое уходит в хвост, но не пропадает', () {
      final out = pickSeedCandidates(const [
        SeedCandidate(Color(0xFF8A8A8A), 900),
        SeedCandidate(Color(0xFF1685A2), 100),
      ]);
      expect(out.first, const Color(0xFF1685A2));
      expect(out, contains(const Color(0xFF8A8A8A)));
    });

    test('чёрно-белый снимок всё равно даёт из чего выбрать', () {
      final out = pickSeedCandidates(const [
        SeedCandidate(Color(0xFF303030), 900),
        SeedCandidate(Color(0xFFBFBFBF), 400),
      ]);
      expect(out, hasLength(2));
    });

    test('длинный ряд обрезается', () {
      final many = List.generate(
          20, (i) => SeedCandidate(Color(0xFF000000 + i * 0x00121317), 100 - i));
      expect(pickSeedCandidates(many).length, lessThanOrEqualTo(6));
    });

    test('пустой разбор не роняет экран', () {
      expect(pickSeedCandidates(const []), isEmpty);
    });
  });
}
