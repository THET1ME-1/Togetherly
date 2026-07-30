import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/coloring_outline.dart';

/// Состояние загруженной раскраски.
enum ColoringUploadStatus {
  /// Файл принят, обработка ещё не закончена.
  processing,

  /// Контур готов, раскраску можно открывать.
  ready,

  /// Не картинка или контур не замкнут — рисовать по такому нельзя.
  failed,
}

/// Одна загруженная раскраска.
class ColoringUpload {
  const ColoringUpload({
    required this.id,
    required this.title,
    required this.status,
    this.ratio = 1.0,
    this.error = '',
    this.sourcePath = '',
  });

  final String id;
  final String title;
  final ColoringUploadStatus status;

  /// Пропорция листа: ширина к высоте. Граница половин остаётся вертикальной
  /// по центру при любом значении.
  final double ratio;

  /// Понятная человеку причина отказа.
  final String error;

  /// Исходник на диске. Держим до конца обработки: если приложение закрыли на
  /// середине, работа продолжится с него при следующем запуске.
  final String sourcePath;

  bool get isReady => status == ColoringUploadStatus.ready;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status.name,
        'ratio': ratio,
        'error': error,
        'source': sourcePath,
      };

  static ColoringUpload fromJson(Map<String, dynamic> j) => ColoringUpload(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        status: ColoringUploadStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => ColoringUploadStatus.processing,
        ),
        ratio: (j['ratio'] as num?)?.toDouble() ?? 1.0,
        error: (j['error'] ?? '').toString(),
        sourcePath: (j['source'] ?? '').toString(),
      );

  ColoringUpload copyWith({
    ColoringUploadStatus? status,
    double? ratio,
    String? error,
  }) =>
      ColoringUpload(
        id: id,
        title: title,
        status: status ?? this.status,
        ratio: ratio ?? this.ratio,
        error: error ?? this.error,
        sourcePath: sourcePath,
      );
}

/// Очередь обработки своих раскрасок.
///
/// Картинку принимаем сразу: карточка появляется в каталоге в тот же миг, с
/// пометкой «готовим». Тяжёлая часть — разбор пикселей, прозрачный фон и
/// проверка на утечку заливки — уходит в отдельный isolate через [compute],
/// поэтому интерфейс не замирает и приложением можно пользоваться дальше.
///
/// Работа переживает закрытие приложения: исходник лежит на диске, состояние —
/// в prefs. При следующем запуске [resume] дообрабатывает всё, что осталось в
/// «готовим». Дорисовывать контур в фоне при полностью выключенном приложении
/// iOS не даёт вовсе, а на Android это стоило бы фоновой службы ради пары
/// секунд счёта — дешевле продолжить при возврате.
class ColoringUploadQueue extends ChangeNotifier {
  ColoringUploadQueue._();
  static final ColoringUploadQueue instance = ColoringUploadQueue._();

  static const String _prefsKey = 'coloring_uploads';

  final List<ColoringUpload> _items = [];
  bool _busy = false;

  List<ColoringUpload> get items => List.unmodifiable(_items);

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/coloring');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  String outlinePath(Directory dir, String id) => '${dir.path}/$id.png';

  /// Поднимает список с диска и доводит до конца прерванное.
  Future<void> resume() async {
    if (_items.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    _items
      ..clear()
      ..addAll(raw.map((s) {
        try {
          return ColoringUpload.fromJson(jsonDecode(s) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }).whereType<ColoringUpload>());
    notifyListeners();

    for (final item in _items.where(
        (i) => i.status == ColoringUploadStatus.processing)) {
      unawaited(_process(item));
    }
  }

  /// Принимает файл и сразу возвращает управление: карточка уже в списке.
  Future<ColoringUpload> add(File source, {required String title}) async {
    final dir = await _dir();
    final id = 'own_${DateTime.now().millisecondsSinceEpoch}';
    final saved = await source.copy('${dir.path}/$id.src');

    final item = ColoringUpload(
      id: id,
      title: title.trim().isEmpty ? 'Моя раскраска' : title.trim(),
      status: ColoringUploadStatus.processing,
      sourcePath: saved.path,
    );
    _items.insert(0, item);
    await _save();
    notifyListeners();

    unawaited(_process(item));
    return item;
  }

  Future<void> remove(String id) async {
    final item = _items.firstWhere((i) => i.id == id,
        orElse: () => const ColoringUpload(
            id: '', title: '', status: ColoringUploadStatus.failed));
    if (item.id.isEmpty) return;
    _items.removeWhere((i) => i.id == id);
    final dir = await _dir();
    for (final path in [item.sourcePath, outlinePath(dir, id)]) {
      if (path.isEmpty) continue;
      final f = File(path);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> _process(ColoringUpload item) async {
    // По одной за раз: две обработки разом съедают память на слабом телефоне,
    // а выигрыша нет — считает всё равно один isolate.
    if (_busy) return;
    _busy = true;
    try {
      final src = File(item.sourcePath);
      if (!src.existsSync()) {
        await _update(item.id,
            status: ColoringUploadStatus.failed, error: 'Файл потерялся');
        return;
      }
      final bytes = await src.readAsBytes();
      final result = await compute(_prepareInIsolate, bytes);

      if (result == null) {
        await _update(item.id,
            status: ColoringUploadStatus.failed,
            error: 'Это не картинка или её не удалось прочитать');
        return;
      }
      if (result.leaks) {
        await _update(item.id,
            status: ColoringUploadStatus.failed,
            error: 'Линии не замкнуты: заливка растечётся по всему листу');
        return;
      }

      final dir = await _dir();
      await File(outlinePath(dir, item.id)).writeAsBytes(result.png);
      // Исходник больше не нужен: контур готов и лежит рядом.
      try {
        src.deleteSync();
      } catch (_) {}
      await _update(item.id,
          status: ColoringUploadStatus.ready, ratio: result.ratio);
    } catch (e) {
      await _update(item.id,
          status: ColoringUploadStatus.failed, error: 'Не получилось: $e');
    } finally {
      _busy = false;
      // Следующая в очереди, если она есть.
      final next = _items.firstWhere(
        (i) => i.status == ColoringUploadStatus.processing,
        orElse: () => const ColoringUpload(
            id: '', title: '', status: ColoringUploadStatus.failed),
      );
      if (next.id.isNotEmpty) unawaited(_process(next));
    }
  }

  Future<void> _update(String id,
      {required ColoringUploadStatus status,
      double? ratio,
      String error = ''}) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx < 0) return;
    _items[idx] = _items[idx].copyWith(status: status, ratio: ratio, error: error);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _prefsKey, _items.map((i) => jsonEncode(i.toJson())).toList());
  }
}

/// Точка входа в isolate. Возвращает null вместо исключения: через границу
/// isolate ошибки летят плохо, а вызывающему хватит «не вышло».
ColoringOutline? _prepareInIsolate(Uint8List bytes) {
  try {
    return prepareColoringOutline(bytes);
  } catch (_) {
    return null;
  }
}
