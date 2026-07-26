/// Счёт дней для барабанов выбора даты.
///
/// Отдельно от экрана, потому что тут единственное место, где легко ошибиться:
/// 31 марта при переключении на февраль обязано стать 28 или 29, а не уехать
/// в 3 марта, как это делает `DateTime(year, 2, 31)`.
class DateWheel {
  const DateWheel._();

  /// Сколько дней в месяце. Февраль считается по правилу високосного года,
  /// включая столетия: 2000 високосный, 1900 нет.
  static int daysInMonth(int year, int month) {
    const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && isLeap(year)) return 29;
    return lengths[month - 1];
  }

  static bool isLeap(int year) =>
      year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

  /// День, который останется выбранным после смены месяца или года.
  ///
  /// Барабан дня короче не становится сам: если стояло 31-е, а месяц стал
  /// апрелем, выбор прижимается к 30-му.
  static int clampDay(int day, int year, int month) {
    final last = daysInMonth(year, month);
    if (day < 1) return 1;
    return day > last ? last : day;
  }

  /// Собирает дату, не давая ей перескочить в следующий месяц.
  static DateTime build({
    required int year,
    required int month,
    required int day,
    int hour = 0,
    int minute = 0,
  }) =>
      DateTime(year, month, clampDay(day, year, month), hour, minute);
}
