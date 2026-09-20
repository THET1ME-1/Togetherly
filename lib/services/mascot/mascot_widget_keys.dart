import '../../models/mascot_widget_data.dart';
import 'mascot_frame_render.dart';

/// Классы-провайдеры виджета: в Android размер выбирается до установки, и
/// каждый размер — свой приёмник. Будить надо все четыре, иначе обновится
/// только тот, что лежит на столе последним.
const List<String> kMascotWidgetProviders = [
  'MascotWidget4x1Provider',
  'MascotWidget2x2Provider',
  'MascotWidget4x2Provider',
  'MascotWidget4x4Provider',
];

/// Подписи виджета. Их собирает приложение: у расширений нет локализации, и
/// всё, что они считают сами, рано или поздно оказывается русским или неверным.
class MascotWidgetLabels {
  final String stage;
  final String streak;
  final String next;

  /// Подписи сна кладутся ОБЕ: ночь наступает без участия приложения, и
  /// нативу надо чем-то заменить строку в 23:00.
  final String sleepDay;
  final String sleepNight;

  final String record;

  const MascotWidgetLabels({
    required this.stage,
    required this.streak,
    required this.next,
    required this.sleepDay,
    required this.sleepNight,
    required this.record,
  });
}

/// Всё, что уезжает в `HomeWidgetPreferences` про маскота пары.
///
/// Отдельная чистая функция, потому что состав ключей — договор с нативной
/// стороной, и его надо проверять тестом, а не глазами на устройстве.
Map<String, String> mascotWidgetKeys({
  required String groupId,
  required MascotWidgetData data,
  required MascotWidgetLabels labels,
  required Map<MascotWidgetFrame, String> framePaths,
  required int framePx,
}) {
  final g = groupId.isEmpty ? 'solo' : groupId;

  // Пустая строка значащая: снятый кадр надо перебить, иначе виджет покажет
  // прежнего персонажа. Отсутствующий ключ натив просто не заметит.
  String path(MascotWidgetFrame frame) => framePaths[frame] ?? '';

  return {
    'mascot_${g}_frame_day': path(MascotWidgetFrame.day),
    'mascot_${g}_frame_night': path(MascotWidgetFrame.night),
    'mascot_${g}_frame_sad': path(MascotWidgetFrame.sad),
    'mascot_${g}_frame_px': '$framePx',
    'mascot_${g}_id': data.mascotId,
    'mascot_${g}_name': data.name,
    'mascot_${g}_streak': '${data.streakDays}',
    'mascot_${g}_progress': '${data.percent}',
    'mascot_${g}_sad': data.sad ? '1' : '0',
    'mascot_${g}_sleep_from': '${data.sleep.from}',
    'mascot_${g}_sleep_to': '${data.sleep.to}',
    'mascot_${g}_record': '${data.recordStreak}',
    'mascot_${g}_stage_label': labels.stage,
    'mascot_${g}_streak_label': labels.streak,
    'mascot_${g}_next_label': labels.next,
    'mascot_${g}_sleep_label_day': labels.sleepDay,
    'mascot_${g}_sleep_label_night': labels.sleepNight,
    'mascot_${g}_record_label': labels.record,
    'mascot_latest_group': g,
  };
}
