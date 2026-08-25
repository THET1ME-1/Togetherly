import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/models/stroke_transform.dart';

/// Картинку двигают и крутят инструментом «Фото», и каждая правка собирает
/// новую запись штриха. Пока она собиралась в экране руками, копия теряла
/// `layer` и `clientId`: перетащенная заливка проваливалась на нижний слой, а
/// свой штрих переставал узнавать пришедшую с сервера запись.
void main() {
  final image = DrawStroke(
    id: 'fill_1',
    clientId: 'local_1',
    userId: 'u1',
    colorValue: 0xFF00FF00,
    strokeWidth: 0,
    points: const [],
    orderIndex: 7,
    layer: 2,
    imageUrl: 'pb://media/x/y.png',
    imageX: 0.4,
    imageY: 0.4,
    imageWidth: 0.3,
    imageHeight: 0.2,
    imageRotation: 0.5,
  );

  test('перенос картинки не меняет слой и порядок', () {
    final moved = copyImageStroke(image, x: 0.7, y: 0.8);
    expect(moved.layer, 2);
    expect(moved.orderIndex, 7);
    expect(moved.clientId, 'local_1');
    expect(moved.imageX, 0.7);
    expect(moved.imageY, 0.8);
    expect(moved.imageWidth, 0.3);
  });

  test('незаданные поля остаются прежними', () {
    final same = copyImageStroke(image);
    expect(same.imageRotation, 0.5);
    expect(same.imageUrl, 'pb://media/x/y.png');
    expect(same.userId, 'u1');
  });
}
