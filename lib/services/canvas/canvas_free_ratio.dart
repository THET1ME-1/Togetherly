import 'package:shared_preferences/shared_preferences.dart';

/// Форма, в которой этот телефон рисует холст без листа.
///
/// Холст, созданный до листа, пропорции не хранит: экран рисования кладёт его
/// во всю свободную область (около 0,6 на телефоне), а виджет рисовал его в
/// рамку 0,8, и рисунок на столе выходил перекошенным (отзыв в Google Play на
/// 1.37). Экран рисования запоминает свою форму, виджет берёт её.
String _key(String groupId, String canvasId) => 'canvas_free_ratio_${groupId}_$canvasId';

Future<void> rememberFreeRatio(String groupId, String canvasId, double ratio) async {
  if (!ratio.isFinite || ratio <= 0) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key(groupId, canvasId), ratio);
  } catch (_) {}
}

Future<double?> freeRatioOf(String groupId, String canvasId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_key(groupId, canvasId));
  } catch (_) {
    return null;
  }
}

/// Пропорция картинки виджета: лист, иначе форма с экрана рисования, иначе 0,8.
double widgetSheetRatio({required double? sheet, required double? free}) => sheet ?? free ?? 0.8;
