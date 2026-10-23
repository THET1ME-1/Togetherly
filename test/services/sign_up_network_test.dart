// TOG-16: отзыв из США — «при создании аккаунта постоянно «почта не
// найдена»». В рваной сети запрос на создание аккаунта не доезжал до сервера
// и обрывался по сроку, а проверочный вход следом доходил и получал «неверные
// данные»: аккаунта-то нет. Экран регистрации переводил этот отказ как
// «Некорректный email». На деле оборвалась связь, о ней и надо сказать.
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:love_app/services/pb_auth_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/utils/auth_failure.dart';

http.Response _json(Object body, int code) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('создание не дошло, а вход отказал — это обрыв связи, а не плохая почта',
      () {
    fakeAsync((async) {
      PocketBaseService().debugUse(PocketBase(
        'https://togetherly.day',
        httpClientFactory: () => MockClient((req) {
          if (req.url.path.endsWith('/auth-with-password')) {
            return Future.value(_json({
              'code': 400,
              'message': 'Failed to authenticate.',
              'data': {},
            }, 400));
          }
          // Создание аккаунта молчит: провайдер его не пропускает.
          return Completer<http.Response>().future;
        }),
      ));

      Object? error;
      PbAuthService()
          .signUpWithEmail(
            email: 'anya@example.com',
            password: 'Secret!23',
            displayName: 'Аня',
          )
          .then<void>((_) {}, onError: (Object e) => error = e);
      async.elapse(const Duration(seconds: 70));

      expect(error, isNotNull);
      expect(AuthFailure.of(error!).isNetwork, isTrue, reason: '$error');
    });
  });

  test('почта и правда занята чужим аккаунтом — разговор про почту остаётся', () {
    fakeAsync((async) {
      PocketBaseService().debugUse(PocketBase(
        'https://togetherly.day',
        httpClientFactory: () => MockClient((req) async {
          if (req.url.path.endsWith('/auth-with-password')) {
            return _json({
              'code': 400,
              'message': 'Failed to authenticate.',
              'data': {},
            }, 400);
          }
          return _json({
            'code': 400,
            'message': 'Failed to create record.',
            'data': {
              'email': {
                'code': 'validation_not_unique',
                'message': 'Value must be unique.',
              },
            },
          }, 400);
        }),
      ));

      Object? error;
      PbAuthService()
          .signUpWithEmail(
            email: 'taken@example.com',
            password: 'Secret!23',
            displayName: 'Аня',
          )
          .then<void>((_) {}, onError: (Object e) => error = e);
      async.elapse(const Duration(seconds: 5));

      expect(error, isNotNull);
      expect(AuthFailure.of(error!).isNetwork, isFalse, reason: '$error');
    });
  });
}
