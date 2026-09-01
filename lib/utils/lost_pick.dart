import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Снимок, уцелевший после смерти процесса, и то, куда его несли.
///
/// Пока человек листает системную галерею, наше приложение стоит в фоне, и
/// система вправе его убить — на бюджетных телефонах это происходит за
/// считанные секунды. Выбранный снимок при этом не пропадает: Android держит
/// его у плагина и отдаёт при следующем запуске. Забрать его нужно нам, иначе
/// человек возвращается в приложение, не находит своего фото и считает, что
/// оно сломано (жалоба 01.09.2026, realme C67).
class LostPick {
  const LostPick({required this.intent, required this.files});

  /// Куда человек нёс снимок: `memory`, `avatar` и так далее.
  final String intent;

  /// Уцелевшие файлы. Пустым не бывает — иначе восстанавливать нечего.
  final List<XFile> files;
}

/// Намерение «снимок нёс в ленту воспоминаний».
const String kPickIntentMemory = 'memory';

/// Ключ намерения. Живёт в настройках, потому что обязан пережить процесс.
const String kLostPickIntentKey = 'lost_pick_intent';

/// Намерение, с которым сейчас открывают галерею.
///
/// Пишется ДО вызова пикера: после него писать уже некому.
Future<void> rememberPickIntent(String intent) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLostPickIntentKey, intent);
  } catch (e) {
    // Не смогли запомнить — потеряем только восстановление, сам выбор цел.
    debugPrint('rememberPickIntent failed: $e');
  }
}

/// Снимает намерение: выбор вернулся своим ходом, восстанавливать нечего.
Future<void> forgetPickIntent() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kLostPickIntentKey);
  } catch (e) {
    debugPrint('forgetPickIntent failed: $e');
  }
}

/// Решение о том, что делать с уцелевшим результатом.
///
/// [accept] ограничивает набор намерений, которые берёт на себя вызывающий:
/// аватар и обложку восстанавливает не этот путь, у них своя форма и своя
/// обрезка.
LostPick? lostPickFrom({
  required String? intent,
  required List<XFile> files,
  Set<String>? accept,
}) {
  if (files.isEmpty) return null;
  // Файл без намерения класть некуда, а подсунуть снимок в случайную форму
  // хуже, чем не подсунуть вовсе.
  if (intent == null || intent.isEmpty) return null;
  if (accept != null && !accept.contains(intent)) return null;
  return LostPick(intent: intent, files: files);
}

/// Забирает у Android результат, потерянный вместе с процессом.
///
/// Возвращает `null`, когда терять было нечего — это обычный случай.
Future<LostPick?> recoverLostPick({
  ImagePicker? picker,
  Set<String>? accept,
}) async {
  // Механизм существует только на Android: на iOS система приложение во время
  // выбора не убивает, и `retrieveLostData` там всегда пуст.
  if (!Platform.isAndroid) return null;
  try {
    final response = await (picker ?? ImagePicker()).retrieveLostData();
    if (response.isEmpty) return null;
    if (response.exception != null) {
      debugPrint('recoverLostPick: ${response.exception!.code}');
      return null;
    }
    final files = response.files ??
        (response.file != null ? <XFile>[response.file!] : const <XFile>[]);
    final prefs = await SharedPreferences.getInstance();
    final intent = prefs.getString(kLostPickIntentKey);
    final lost = lostPickFrom(intent: intent, files: files, accept: accept);
    if (lost != null) await prefs.remove(kLostPickIntentKey);
    return lost;
  } catch (e) {
    // Восстановление — подарок, а не обязанность: сорвалось, значит человек
    // выберет снимок заново.
    debugPrint('recoverLostPick failed: $e');
    return null;
  }
}
