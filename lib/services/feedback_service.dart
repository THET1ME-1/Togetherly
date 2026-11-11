import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/feedback.dart';
import 'locale_service.dart';
import 'pocketbase_service.dart';

/// Отправка обращения на свой сервер. Из приложения человек при этом не
/// выходит: ни почтовой программы, ни браузера (требование Google Play).
class FeedbackService {
  const FeedbackService();

  Future<FeedbackSent> send(FeedbackKind kind, String text) async {
    var app = '';
    try {
      final info = await PackageInfo.fromPlatform();
      app = '${info.version} (${info.buildNumber})';
    } catch (_) {
      // Версия нужна только для разбора, без неё обращение всё равно уходит.
    }
    try {
      await PocketBaseService().pb.send(
        '/api/feedback',
        method: 'POST',
        body: {
          'kind': kind.wire,
          'text': text.trim(),
          'app': app,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'lang': LocaleService.instance.language.code,
        },
      ).timeout(const Duration(seconds: 20));
      return FeedbackSent.ok;
    } on ClientException catch (e) {
      debugPrint('Feedback.send отказ: ${e.statusCode}');
      return feedbackSentOf(e.statusCode);
    } catch (e) {
      debugPrint('Feedback.send не ушло: $e');
      return FeedbackSent.failed;
    }
  }
}
