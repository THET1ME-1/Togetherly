// Разбор TOG-16 нашёл в журнале сервера 150–180 отказов в сутки: «password
// cannot be blank» на создании пользователя от самого приложения. Правка
// профиля шла общим путём «нет записи — создать», и если аккаунта на сервере
// уже нет (удалён, а сессия на телефоне осталась), приложение пыталось завести
// пользователя без пароля. Сервер отказывал всегда, отказ только занимал его.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:love_app/services/pb_data_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

http.Response _json(Object body, int code) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('профиля нет на сервере — правка не пытается завести пользователя', () async {
    final calls = <String>[];
    PocketBaseService().debugUse(PocketBase(
      'https://togetherly.day',
      httpClientFactory: () => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'POST') {
          return _json({
            'code': 400,
            'message': 'Failed to create record.',
            'data': {
              'password': {'code': 'validation_required', 'message': 'Cannot be blank.'},
            },
          }, 400);
        }
        return _json({
          'code': 404,
          'message': "The requested resource wasn't found.",
          'data': {},
        }, 404);
      }),
    ));

    final ok = await PbDataService()
        .updateUserProfile('u2c3l2xokvbpkvj', {'notifChat': true});

    expect(ok, isFalse);
    expect(calls.where((c) => c.startsWith('POST')), isEmpty,
        reason: 'создать пользователя без пароля нельзя, запрос только занимает сервер');
  });
}
