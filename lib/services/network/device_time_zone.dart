import 'package:flutter/services.dart';

/// Часовой пояс телефона по имени города (`Europe/Kyiv`). Отвечают
/// MainActivity.kt и AppDelegate.swift; по поясу [serverRouteWanted] решает,
/// нужен ли обход для Украины, при любом языке телефона.
const timeZoneChannel = MethodChannel('love_app/time_zone');

/// Имя пояса или null, если система не ответила: фоновый движок (каналы
/// главного экрана ему не видны), тесты, сборка без этого канала.
Future<String?> deviceTimeZone() async {
  try {
    return await timeZoneChannel.invokeMethod<String>('name');
  } catch (_) {
    return null;
  }
}
