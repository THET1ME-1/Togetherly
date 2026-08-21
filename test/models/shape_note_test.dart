import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/shape_note.dart';

void main() {
  group('ShapeNote.fromFields', () {
    test('без ссылки фигурки нет — это обычное сообщение', () {
      expect(
        ShapeNote.fromFields(
            url: '', ms: 5000, shape: 'heart', thumb: '', hearts: ''),
        isNull,
      );
      expect(
        ShapeNote.fromFields(
            url: null, ms: null, shape: null, thumb: null, hearts: null),
        isNull,
      );
    });

    test('собирает длительность, форму и обложку', () {
      final n = ShapeNote.fromFields(
        url: 'pb://media/abc/note.mp4',
        ms: 8400,
        shape: 'star',
        thumb: 'pb://media/abc/thumb.webp',
        hearts: '1.5,3.2',
      )!;
      expect(n.duration, const Duration(milliseconds: 8400));
      expect(n.shapeId, 'star');
      expect(n.hasThumb, isTrue);
      expect(n.isLocalFile, isFalse);
      expect(n.hearts, [1.5, 3.2]);
    });

    test('файл из очереди отправки лежит на устройстве', () {
      final n = ShapeNote.fromFields(
        url: '/data/user/0/app/files/note_outbox/note_1.mp4',
        ms: 1000,
        shape: 'circle',
        thumb: '',
        hearts: null,
      )!;
      expect(n.isLocalFile, isTrue);
      expect(n.hasThumb, isFalse);
    });
  });

  group('сердечки', () {
    test('битая отметка не роняет остальные', () {
      expect(ShapeNote.decodeHearts('1.0,хрень,2.5'), [1.0, 2.5]);
      expect(ShapeNote.decodeHearts('  '), isEmpty);
      expect(ShapeNote.decodeHearts(null), isEmpty);
    });

    test('порядок восстанавливается по времени', () {
      expect(ShapeNote.decodeHearts('7,1.5,3'), [1.5, 3.0, 7.0]);
    });

    test('отрицательных секунд не бывает', () {
      expect(ShapeNote.decodeHearts('-2,3'), [3.0]);
    });

    test('пишем с десятыми — точнее человек не тапнет', () {
      expect(ShapeNote.encodeHearts([1.23, 4.56]), '1.2,4.6');
    });

    test('поле не растёт без предела: держим последние отметки', () {
      final many = List<double>.generate(45, (i) => i.toDouble());
      final packed = ShapeNote.encodeHearts(many);
      final back = ShapeNote.decodeHearts(packed);
      expect(back.length, ShapeNote.maxHearts);
      expect(back.last, 44.0);
    });
  });

  test('подпись длительности как под голосовым', () {
    expect(ShapeNote.formatDuration(const Duration(seconds: 7)), '0:07');
    expect(ShapeNote.formatDuration(const Duration(seconds: 62)), '1:02');
  });
}
