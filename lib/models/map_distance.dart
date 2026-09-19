import 'package:intl/intl.dart';

/// Расстояние между двумя людьми на карте «Где мы».
///
/// Ближе пятидесяти метров — «рядом»: GPS ошибается на 5–15 м, и прежние
/// «34 см» показывали шум, а не расстояние. Метры округляются до десятка, до
/// десяти километров остаётся одна цифра после запятой, дальше целые
/// километры с разделителем тысяч. Разделители берутся по языку: «2,9 км»,
/// «2.9 km», «1 609 км». Число и единица держатся неразрывным пробелом.
String formatMapDistance(
  double meters, {
  required String lang,
  required String nearby,
  required String unitM,
  required String unitKm,
}) {
  const nb = ' ';
  if (meters < 50) return nearby;
  if (meters < 995) return '${(meters / 10).round() * 10}$nb$unitM';
  final km = meters / 1000;
  final text = km < 9.95
      ? _format('0.0', lang, km)
      : _format('#,##0', lang, km.round());
  return '${text.replaceAll(' ', nb)}$nb$unitKm';
}

String _format(String pattern, String lang, num value) {
  try {
    return NumberFormat(pattern, lang).format(value);
  } catch (_) {
    return NumberFormat(pattern, 'en').format(value);
  }
}
