import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Состояние модели распознавания QR.
enum MlkitModuleState {
  /// Спрашиваем сервисы Google, есть ли модель.
  checking,

  /// Можно сканировать.
  ready,

  /// Модели нет, но её можно скачать.
  needsInstall,

  /// Качается прямо сейчас.
  installing,

  /// Сервисов Google на телефоне нет — сканировать нечем.
  unavailable,
}

/// Ход установки: состояние и доля. `percent == -1` значит, что общий размер
/// ещё не назван и полосу рисовать не из чего.
class MlkitInstallProgress {
  final MlkitModuleState state;
  final int percent;

  const MlkitInstallProgress(this.state, this.percent);

  bool get hasPercent => percent >= 0;
}

/// Модель распознавания QR не лежит в APK — её ставят сервисы Google по
/// требованию (минус 5,5 МБ из каждой сборки). Здесь — тонкая обёртка над
/// нативным `MlkitModuleChannel`.
///
/// Скачивает GMS в своём процессе, поэтому загрузка переживает и уход с экрана,
/// и выгрузку приложения из памяти: вернувшись, человек застаёт либо готовую
/// модель, либо ту же загрузку с того же места. Отменить её мы не можем — и не
/// должны.
///
/// На iOS сканирование делает система (Vision), качать нечего: там сразу
/// [MlkitModuleState.ready].
class MlkitModuleService {
  static const MethodChannel _channel = MethodChannel('love_app/mlkit_module');
  static const EventChannel _progress =
      EventChannel('love_app/mlkit_module/progress');

  /// Платформу берём из `defaultTargetPlatform`, а не из `Platform.isAndroid`:
  /// так тест подменяет её и проверяет разбор ответов канала на любом хосте.
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<MlkitModuleState> status() async {
    if (!_isAndroid) return MlkitModuleState.ready;
    try {
      final raw = await _channel.invokeMethod<String>('status');
      return _parse(raw);
    } on PlatformException {
      return MlkitModuleState.unavailable;
    } on MissingPluginException {
      // Старый нативный слой (сборка без канала) — не мешаем сканеру
      // пробовать: с вшитой моделью он и так работает.
      return MlkitModuleState.ready;
    }
  }

  /// Тихая загрузка «когда-нибудь»: сервисы Google выберут удобный момент.
  /// Зовём заранее, на экране подключения, чтобы к нажатию «сканировать»
  /// модель уже стояла.
  static Future<void> warmUp() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('warmUp');
    } catch (_) {
      // Прогрев — вежливость, а не обязанность.
    }
  }

  /// Запускает установку. Возвращает false, если сервисы Google отказали.
  static Future<bool> install() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('install') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Stream<MlkitInstallProgress> watchProgress() {
    if (!_isAndroid) {
      return const Stream<MlkitInstallProgress>.empty();
    }
    return _progress.receiveBroadcastStream().map((event) {
      final map = (event as Map?) ?? const {};
      return MlkitInstallProgress(
        _parse(map['state']?.toString()),
        (map['percent'] as num?)?.toInt() ?? -1,
      );
    });
  }

  static MlkitModuleState _parse(String? raw) => switch (raw) {
        'ready' => MlkitModuleState.ready,
        'needsInstall' => MlkitModuleState.needsInstall,
        'installing' => MlkitModuleState.installing,
        _ => MlkitModuleState.unavailable,
      };
}
