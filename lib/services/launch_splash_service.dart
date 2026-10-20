import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/launch_splash.dart';

/// Выбранная заставка при запуске и её файлы на диске.
///
/// Играет заставка только с диска: при запуске сети ждать нельзя, а пока
/// выбранная не скачалась, приложение запускается как раньше. Выбор живёт на
/// телефоне (как вид чата), на аккаунт не уезжает.
class LaunchSplashService extends ChangeNotifier {
  LaunchSplashService._();

  static final LaunchSplashService instance = LaunchSplashService._();

  static const String prefsKey = 'launch_splash';

  /// Папка заставок; тест подменяет её временной.
  @visibleForTesting
  static Future<Directory> Function() rootDir =
      () async => Directory('${(await getApplicationSupportDirectory()).path}/launch_splash');

  /// Загрузка файла; null — не вышло. Тест подменяет её.
  @visibleForTesting
  static Future<List<int>?> Function(String url) fetch = _fetch;

  String _selected = '';
  bool _loaded = false;
  final Map<String, Future<bool>> _downloads = {};

  /// Ключ выбранной заставки, '' — без заставки.
  String get selected => _selected;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _selected = prefs.getString(prefsKey) ?? '';
    _loaded = true;
  }

  /// Выбрать заставку (null — без заставки) и скачать её. Чужие папки
  /// удаляются: на телефоне лежит только выбранная.
  Future<bool> select(LaunchSplash? splash) async {
    await load();
    _selected = splash?.key ?? '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, _selected);
    notifyListeners();
    await _dropAllBut(_selected);
    if (splash == null) return true;
    return ensureDownloaded(splash);
  }

  /// Кладёт файлы заставки на диск. Лежащее уже не качает; новая выкладка
  /// той же заставки приходит с новыми именами файлов и качается заново.
  Future<bool> ensureDownloaded(LaunchSplash splash) {
    final running = _downloads[splash.key];
    if (running != null) return running;
    final job = _download(splash);
    _downloads[splash.key] = job;
    job.whenComplete(() {
      _downloads.remove(splash.key);
    });
    return job;
  }

  Future<bool> _download(LaunchSplash splash) async {
    final dir = Directory('${(await rootDir()).path}/${splash.key}');
    try {
      await dir.create(recursive: true);
      final local = <String, String>{};
      for (final name in splash.fileNames) {
        final url = splash.files[name]!;
        final file = File('${dir.path}/${_fileName(url, name)}');
        if (!file.existsSync() || file.lengthSync() == 0) {
          final bytes = await fetch(url);
          if (bytes == null || bytes.isEmpty) return false;
          // Сперва во временный файл: оборванная запись не выдаст себя за
          // готовую картинку.
          final part = File('${file.path}.part');
          await part.writeAsBytes(bytes, flush: true);
          await part.rename(file.path);
        }
        local[name] = file.path;
      }
      // Описание ложится последним: есть оно — значит, все файлы на месте.
      await File('${dir.path}/splash.json').writeAsString(jsonEncode(splash.withFiles(local).toJson()));
      _dropStale(dir, local.values.toSet());
      return true;
    } catch (e) {
      debugPrint('LaunchSplash: не скачалась ${splash.key}: $e');
      return false;
    }
  }

  /// Заставка для этого запуска: выбрана, идёт по датам и все её файлы на
  /// диске. Только диск и память — зовётся до `runApp`.
  Future<LaunchSplash?> readyForLaunch(DateTime now) async {
    try {
      await load();
      if (_selected.isEmpty) return null;
      final manifest = File('${(await rootDir()).path}/$_selected/splash.json');
      if (!manifest.existsSync()) return null;
      final splash = LaunchSplash.fromJson(jsonDecode(await manifest.readAsString()) as Map<String, dynamic>);
      if (splash == null || !splash.isOn(now)) return null;
      for (final name in splash.fileNames) {
        final file = File(splash.files[name]!);
        if (!file.existsSync() || file.lengthSync() == 0) return null;
      }
      return splash;
    } catch (e) {
      debugPrint('LaunchSplash: не прочитать с диска: $e');
      return null;
    }
  }

  /// Пришёл каталог. Выбранную, которой в нём больше нет (запись выключили),
  /// снимаем с диска — играть она перестаёт, а выбор остаётся: вернётся
  /// запись — докачается из «Оформления». Новую выкладку докачиваем сразу.
  Future<void> syncWithCatalog(List<LaunchSplash> splashes) async {
    await load();
    if (_selected.isEmpty) return;
    LaunchSplash? current;
    for (final s in splashes) {
      if (s.key == _selected) current = s;
    }
    if (current == null) {
      await _dropAllBut('');
      return;
    }
    await ensureDownloaded(current);
  }

  /// Картинки заставки, разжатые для проигрывателя.
  static Future<Map<String, ui.Image>> decode(LaunchSplash splash) async {
    final images = <String, ui.Image>{};
    for (final name in splash.fileNames) {
      if (name == 'still') continue;
      final codec = await ui.instantiateImageCodec(await File(splash.files[name]!).readAsBytes());
      images[name] = (await codec.getNextFrame()).image;
      codec.dispose();
    }
    return images;
  }

  Future<void> _dropAllBut(String keep) async {
    try {
      final root = await rootDir();
      if (!root.existsSync()) return;
      for (final entry in root.listSync()) {
        if (entry is Directory && entry.uri.pathSegments.where((s) => s.isNotEmpty).last != keep) {
          entry.deleteSync(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('LaunchSplash: не убрать старое: $e');
    }
  }

  void _dropStale(Directory dir, Set<String> keep) {
    for (final entry in dir.listSync()) {
      if (entry is File && !entry.path.endsWith('splash.json') && !keep.contains(entry.path)) {
        entry.deleteSync();
      }
    }
  }

  /// Имя файла на диске — имя из адреса: у новой выкладки оно другое.
  static String _fileName(String url, String fallback) {
    final last = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
    final safe = last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    return safe.isEmpty ? '$fallback.webp' : safe;
  }

  static Future<List<int>?> _fetch(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  void debugReset() {
    _selected = '';
    _loaded = false;
    _downloads.clear();
  }
}
