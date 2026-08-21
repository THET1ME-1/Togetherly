import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/chat/note_shapes.dart';

/// Формы фигурок — не картинки, а числа: 180 радиусов от центра безопасной
/// зоны. Отсюда и проверки: профиль полный, радиусы конечны, форма занимает
/// всю рамку и не вылезает за неё, а морф между любой парой остаётся формой.
void main() {
  test('каждая форма отдаёт полный профиль из конечных радиусов', () {
    expect(kNoteShapes.length, 10);
    for (final s in kNoteShapes) {
      expect(s.profile.length, NoteShape.rays, reason: s.id);
      for (final r in s.profile) {
        expect(r.isFinite && r > 0, isTrue, reason: '${s.id}: радиус $r');
      }
    }
  });

  test('безопасный радиус равен самому короткому лучу', () {
    for (final s in kNoteShapes) {
      final min = s.profile.reduce(math.min);
      expect(s.safeRadius, closeTo(min, 0.006), reason: s.id);
    }
  });

  test('лицо помещается: у всех форм безопасный радиус не ниже 0,6', () {
    for (final s in kNoteShapes) {
      expect(s.safeRadius, greaterThanOrEqualTo(0.6), reason: s.id);
    }
  });

  test('форма вписана в рамку и занимает её почти целиком', () {
    const size = Size(200, 200);
    for (final s in kNoteShapes) {
      final b = s.pathIn(size).getBounds();
      expect(b.left, greaterThanOrEqualTo(-0.6), reason: '${s.id} слева');
      expect(b.top, greaterThanOrEqualTo(-0.6), reason: '${s.id} сверху');
      expect(b.right, lessThanOrEqualTo(200.6), reason: '${s.id} справа');
      expect(b.bottom, lessThanOrEqualTo(200.6), reason: '${s.id} снизу');
      expect(math.max(b.width, b.height), greaterThan(190), reason: s.id);
    }
  });

  test('центр безопасной зоны лежит внутри формы', () {
    const size = Size(200, 200);
    for (final s in kNoteShapes) {
      expect(s.pathIn(size).contains(s.centerIn(size)), isTrue, reason: s.id);
    }
  });

  test('морф между любой парой даёт форму без разрывов', () {
    const size = Size(160, 160);
    for (final a in kNoteShapes) {
      for (final b in kNoteShapes) {
        for (final t in const [0.0, 0.37, 0.5, 1.0]) {
          final p = lerpNoteProfile(a.profile, b.profile, t);
          expect(p.length, NoteShape.rays);
          for (final r in p) {
            expect(r.isFinite && r > 0, isTrue, reason: '${a.id}→${b.id} @$t');
          }
          final path = noteShapePath(
            profile: p,
            size: size,
            centerX: lerpDouble(a.centerX, b.centerX, t)!,
            centerY: lerpDouble(a.centerY, b.centerY, t)!,
          );
          expect(path.getBounds().isEmpty, isFalse, reason: '${a.id}→${b.id}');
        }
      }
    }
  });

  test('контур режется по доле длины и не даёт NaN', () {
    const size = Size(240, 240);
    for (final s in kNoteShapes) {
      for (final t in const [0.0, 0.01, 0.5, 0.999, 1.0]) {
        final arc = noteShapeArc(s.pathIn(size), t);
        final b = arc.getBounds();
        expect(b.left.isFinite && b.top.isFinite, isTrue,
            reason: '${s.id} @$t');
      }
    }
  });

  group('линейка обода', () {
    // Обод бежит по шестьдесят раз в секунду в ленте и на весь экран. Пока
    // дуга резалась через computeMetrics().extractPath, путь из ста
    // восьмидесяти отрезков обмерялся заново на КАЖДЫЙ кадр — на телефоне
    // экран переставал отвечать.
    double lengthOf(Path path) {
      var total = 0.0;
      for (final m in path.computeMetrics()) {
        total += m.length;
      }
      return total;
    }

    test('дуга занимает свою долю периметра', () {
      const size = Size(240, 240);
      for (final s in kNoteShapes) {
        final ruler = NoteArcRuler(
          profile: s.profile,
          size: size,
          centerX: s.centerX,
          centerY: s.centerY,
        );
        final full = lengthOf(ruler.arc(1));
        expect(full, greaterThan(0), reason: s.id);
        for (final p in const [0.25, 0.5, 0.8]) {
          final part = lengthOf(ruler.arc(p));
          expect(part / full, closeTo(p, 0.02), reason: '${s.id} @$p');
        }
      }
    });

    test('нулевая доля не рисует ничего', () {
      final s = kNoteShapes.first;
      final ruler = NoteArcRuler(
        profile: s.profile,
        size: const Size(200, 200),
        centerX: s.centerX,
        centerY: s.centerY,
      );
      expect(ruler.arc(0).computeMetrics().isEmpty, isTrue);
    });

    test('линейка узнаёт смену размера и формы', () {
      final a = kNoteShapes.first;
      final b = kNoteShapes.last;
      final ruler = NoteArcRuler(
        profile: a.profile,
        size: const Size(200, 200),
        centerX: a.centerX,
        centerY: a.centerY,
      );
      expect(ruler.matches(a.profile, const Size(200, 200), a.centerX, a.centerY),
          isTrue);
      expect(ruler.matches(a.profile, const Size(220, 220), a.centerX, a.centerY),
          isFalse);
      expect(ruler.matches(b.profile, const Size(200, 200), b.centerX, b.centerY),
          isFalse);
    });
  });

  test('форма ищется по имени, незнакомое имя откатывается на круг', () {
    expect(noteShapeById('heart').id, 'heart');
    expect(noteShapeById('star').id, 'star');
    expect(noteShapeById('нет такой').id, kNoteShapes.first.id);
    expect(noteShapeById(null).id, kNoteShapes.first.id);
  });
}
