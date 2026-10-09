// Китайская колонка словаря (упрощённое письмо, `zh`).
//
// Почему отдельно, а не строкой `'zh': …` в каждой записи `../dict/`:
// колонку добавили разом на две с половиной тысячи ключей, и правка каждого
// из пятидесяти семи разделов задела бы файлы, которые в это же время
// правят другие задачи. Здесь те же ключи, сгруппированные по тем же
// разделам. `kStrings` в `../../dict_strings.dart` вливает колонку в каждую
// запись при старте, поэтому для остального кода `kStrings[key]['zh']`
// выглядит как любой другой язык.
//
// Новый ключ словаря обязан получить перевод и здесь — иначе китайский
// экран откатится на английский. Это стережёт
// `test/services/locale_zh_test.dart`.

import 'chat_a.dart';
import 'chat_b.dart';
import 'connect_partner.dart';
import 'date_helpers.dart';
import 'home.dart';
import 'memory_lane.dart';
import 'mid_a.dart';
import 'mid_b.dart';
import 'mid_c.dart';
import 'mid_d.dart';
import 'mid_e.dart';
import 'profile.dart';
import 'small_a.dart';
import 'small_b.dart';
import 'small_c.dart';
import 'small_d.dart';
import 'widget_screen.dart';

const Map<String, String> kZhStrings = {
  ...dateHelpersZh,
  ...smallAZh,
  ...smallBZh,
  ...smallCZh,
  ...smallDZh,
  ...midAZh,
  ...midBZh,
  ...midCZh,
  ...midDZh,
  ...midEZh,
  ...connectPartnerZh,
  ...homeZh,
  ...profileZh,
  ...memoryLaneZh,
  ...widgetScreenZh,
  ...chatAZh,
  ...chatBZh,
};
