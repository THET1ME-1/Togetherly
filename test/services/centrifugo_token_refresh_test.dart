import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/services/centrifugo_service.dart';

/// Токен Centrifugo выдаёт PocketBase, и на протухшей сессии он отвечает 401.
///
/// Пока это просто пробрасывалось наверх, клиент ходил по кругу: канал пары не
/// подписывался, живые события не приходили, сообщения появлялись только при
/// перечитывании экрана — «сообщения не доходят или приходят с большой
/// задержкой» (жалоба 18.08.2026; 149 отказов 401 за два часа).
class _FakePb extends PocketBase {
  _FakePb(this.answers) : super('http://localhost');

  /// Что вернуть на каждый следующий вызов: либо тело, либо исключение.
  final List<Object> answers;
  int calls = 0;

  @override
  Future<T> send<T extends dynamic>(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    Map<String, dynamic> query = const {},
    Map<String, dynamic> body = const {},
    List<http.MultipartFile> files = const [],
  }) async {
    final answer = answers[calls.clamp(0, answers.length - 1)];
    calls++;
    if (answer is Exception) throw answer;
    return answer as T;
  }
}

void main() {
  test('обычный ответ отдаёт токен', () async {
    final pb = _FakePb([
      {'token': 'jwt-1'}
    ]);
    expect(await CentrifugoService.askToken(pb, '/api/centrifugo/connection-token'),
        'jwt-1');
    expect(pb.calls, 1);
  });

  test('пустой ответ — это ошибка, а не молчаливое отсутствие токена', () async {
    final pb = _FakePb([
      {'token': ''}
    ]);
    expect(
      () => CentrifugoService.askToken(pb, '/api/centrifugo/connection-token'),
      throwsA(isA<StateError>()),
    );
  });

  test('не-401 пробрасывается как есть: сессия тут ни при чём', () async {
    final pb = _FakePb([ClientException(statusCode: 500)]);
    expect(
      () => CentrifugoService.askToken(pb, '/api/centrifugo/connection-token'),
      throwsA(isA<ClientException>()),
    );
    expect(pb.calls, 1, reason: 'повторять запрос на 500 не за чем');
  });
}
