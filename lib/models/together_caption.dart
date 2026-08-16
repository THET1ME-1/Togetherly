import '../services/locale_service.dart';
import 'year_progress.dart';

/// Подпись «сколько уже вместе» для виджета «Дней вместе» и его превью.
///
/// Виджет считал годы делением `дни / 365` и печатал результат всегда — у пары
/// младше года выходило «0 лет уже ❤️». Строка стоит первой, поэтому именно её
/// человек и обводит красным, называя счётчик сломанным (жалоба со снимком
/// экрана, 15.08.2026).
///
/// Правило: есть годовщина — говорим годами, нет — месяцами, а в первый месяц
/// молчим совсем. Число дней и так стоит крупно в середине виджета, и «0
/// месяцев уже» читалось бы такой же поломкой, как прежние «0 лет».
///
/// Годы и месяцы берутся календарные, из [YearProgress]: пара празднует
/// годовщину в свою дату, а не через 365 суток.
String togetherAlreadyCaption(YearProgress progress, AppStrings strings) {
  if (progress.yearsCompleted >= 1) {
    return strings.yearsAlready(progress.yearsCompleted);
  }
  if (progress.monthsCompleted >= 1) {
    return strings.monthsAlready(progress.monthsCompleted);
  }
  return '';
}
