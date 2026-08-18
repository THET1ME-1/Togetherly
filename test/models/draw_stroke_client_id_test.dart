// У штриха появился собственный идентификатор, придуманный телефоном.
//
// До 18.08.2026 локальный id в базу не уходил вовсе, и свой оптимистичный штрих
// сверялся с пришедшей записью на глаз: автор, номер, цвет, толщина и
// координаты концов (`_looksLikeSameStroke`). Ложное совпадение стирало штрих,
// промах его задваивал. Теперь идентификатор едет вместе с данными, а эвристика
// остаётся только для записей, сделанных прежними сборками.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';

void main() {
  DrawStroke stroke({String? clientId}) => DrawStroke(
        id: 'local-1',
        clientId: clientId,
        userId: 'u1',
        colorValue: 0xFF223344,
        strokeWidth: 3,
        points: const [DrawPoint(0.1, 0.2), DrawPoint(0.3, 0.4)],
        orderIndex: 5,
      );

  test('идентификатор уезжает в запись и читается обратно', () {
    final map = stroke(clientId: 'abc123').toFirestore();
    expect(map['clientId'], 'abc123');

    final back = DrawStroke.fromFirestore(map, 'server-id');
    expect(back.clientId, 'abc123');
    expect(back.id, 'server-id', reason: 'id записи остаётся серверным');
  });

  test('без идентификатора поле в записи не заводится', () {
    expect(stroke().toFirestore().containsKey('clientId'), isFalse,
        reason: 'старым записям лишнее поле ни к чему');
  });

  test('запись прежней сборки читается без идентификатора', () {
    final old = {
      'userId': 'u1',
      'colorValue': 0xFF000000,
      'strokeWidth': 4.0,
      'points': [
        {'x': 0.0, 'y': 0.0},
      ],
      'orderIndex': 1,
    };
    expect(DrawStroke.fromFirestore(old, 'rec1').clientId, isNull);
  });

  test('разбор вида фигуры доступен снаружи модели', () {
    expect(parseShapeType('circle'), DrawShapeType.circle);
    expect(parseShapeType('нет такой'), isNull);
    expect(parseShapeType(null), isNull);
  });
}
