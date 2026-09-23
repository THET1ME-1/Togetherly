import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/upload_failure.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:pocketbase/pocketbase.dart';

/// Почему не залилось фото или видео.
///
/// Человек видел «Убедитесь, что Firebase Storage включён», хотя Firebase давно
/// выключен и файлы идут в PocketBase: заливка сводила любую ошибку к null, и ни
/// человек, ни панель крашей причины не знали.
void main() {
  group('причина по ошибке', () {
    test('обрыв сокета — сеть', () {
      expect(
        classifyUploadError(const SocketException('Connection reset by peer')),
        UploadFailure.network,
      );
    });

    test('истёк срок заливки — сеть', () {
      expect(
        classifyUploadError(TimeoutException('upload', Duration(seconds: 60))),
        UploadFailure.network,
      );
    });

    test('PocketBase не получил ответа (statusCode 0) — сеть', () {
      expect(
        classifyUploadError(ClientException(statusCode: 0, isAbort: true)),
        UploadFailure.network,
      );
    });

    test('401 — сессия истекла', () {
      expect(
        classifyUploadError(ClientException(statusCode: 401)),
        UploadFailure.sessionExpired,
      );
    });

    test('человек не вошёл — сессия истекла, какой бы ни был ответ', () {
      expect(
        classifyUploadError(
          ClientException(statusCode: 400),
          loggedIn: false,
        ),
        UploadFailure.sessionExpired,
      );
    });

    test('обрыв сети при выходе из сессии — всё равно сеть', () {
      expect(
        classifyUploadError(
          const SocketException('Network is unreachable'),
          loggedIn: false,
        ),
        UploadFailure.network,
      );
    });

    test('413 от прокси — файл слишком большой', () {
      expect(
        classifyUploadError(ClientException(statusCode: 413)),
        UploadFailure.tooLarge,
      );
    });

    test('отказ PocketBase по лимиту размера поля — файл слишком большой', () {
      final e = ClientException(
        statusCode: 400,
        response: {
          'code': 400,
          'message': 'Failed to create record.',
          'data': {
            'file': {
              'code': 'validation_file_size_limit',
              'message': 'Failed to upload "file" - the maximum allowed file '
                  'size is 5242880 bytes.',
            },
          },
        },
      );
      expect(classifyUploadError(e), UploadFailure.tooLarge);
    });

    test('500 — прочее', () {
      expect(
        classifyUploadError(ClientException(statusCode: 500)),
        UploadFailure.other,
      );
    });

    test('ошибка чтения файла — прочее', () {
      expect(
        classifyUploadError(const FileSystemException('Cannot open file')),
        UploadFailure.other,
      );
    });
  });

  group('что слать в Bugsink', () {
    test('обрыв сети — не краш', () {
      expect(
        uploadErrorWorthReporting(const SocketException('Connection reset')),
        isFalse,
      );
      expect(
        uploadErrorWorthReporting(ClientException(statusCode: 0)),
        isFalse,
      );
    });

    test('истёкшая сессия лечится входом, а не разбором', () {
      expect(
        uploadErrorWorthReporting(ClientException(statusCode: 401)),
        isFalse,
      );
    });

    test('сервер упал — шлём', () {
      expect(
        uploadErrorWorthReporting(ClientException(statusCode: 500)),
        isTrue,
      );
    });

    test('истёк срок — шлём: по размеру видно, хватает ли срока', () {
      expect(
        uploadErrorWorthReporting(
          TimeoutException('upload', Duration(seconds: 60)),
        ),
        isTrue,
      );
    });

    test('непонятная ошибка в самом приложении — шлём', () {
      expect(uploadErrorWorthReporting(StateError('boom')), isTrue);
    });
  });

  group('текст для человека', () {
    late AppStrings ru;
    late AppStrings en;

    setUp(() {
      LocaleService.instance.setLanguage(AppLanguage.ru);
      ru = LocaleService.instance.strings;
      LocaleService.instance.setLanguage(AppLanguage.en);
      en = LocaleService.instance.strings;
    });

    test('ни одна причина не поминает Firebase', () {
      for (final lang in AppLanguage.values) {
        LocaleService.instance.setLanguage(lang);
        final s = LocaleService.instance.strings;
        for (final f in UploadFailure.values) {
          for (final video in [false, true]) {
            final text = uploadFailureText(f, s, video: video);
            expect(text, isNotEmpty, reason: '${lang.code} $f');
            expect(
              text.toLowerCase(),
              isNot(contains('firebase')),
              reason: '${lang.code} $f video=$video',
            );
          }
        }
      }
    });

    test('причины различимы: четыре разных текста', () {
      for (final s in [ru, en]) {
        final photo = UploadFailure.values
            .map((f) => uploadFailureText(f, s, video: false))
            .toSet();
        expect(photo, hasLength(UploadFailure.values.length));
      }
    });

    test('сессия истекла — просим войти заново', () {
      expect(
        uploadFailureText(UploadFailure.sessionExpired, ru, video: false)
            .toLowerCase(),
        contains('войдите'),
      );
    });

    test('прочее для фото и видео — разные строки', () {
      expect(
        uploadFailureText(UploadFailure.other, ru, video: false),
        isNot(uploadFailureText(UploadFailure.other, ru, video: true)),
      );
    });
  });
}
