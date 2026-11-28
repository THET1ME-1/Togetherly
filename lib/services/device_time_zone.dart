import 'package:flutter/services.dart';

/// Часовой пояс телефона по имени города (`Europe/Kyiv`). Отвечают
/// MainActivity.kt и AppDelegate.swift. Нужен напоминаниям «Наших дат»:
/// сервер шлёт их в 9:00 по часам человека, и только по имени пояса он знает,
/// когда там переводят часы (TOG-61).
const timeZoneChannel = MethodChannel('love_app/time_zone');

/// Имя пояса или null, если система не ответила: фоновый движок (каналы
/// главного экрана ему не видны), тесты, сборка без этого канала.
Future<String?> deviceTimeZone() async {
  try {
    final name = await timeZoneChannel.invokeMethod<String>('name');
    return name == null || name.isEmpty ? null : name;
  } catch (_) {
    return null;
  }
}
