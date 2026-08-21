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

  test('форма ищется по имени, незнакомое имя откатывается на круг', () {
    expect(noteShapeById('heart').id, 'heart');
    expect(noteShapeById('star').id, 'star');
    expect(noteShapeById('нет такой').id, kNoteShapes.first.id);
    expect(noteShapeById(null).id, kNoteShapes.first.id);
  });
}
