// Украинская колонка словаря (`uk`).
//
// Лежит отдельно по той же причине, что китайская (см. `../zh/zh.dart`):
// колонку добавили разом на две с половиной тысячи ключей, не трогая
// разделы `../dict/`. `kStrings` в `../../dict_strings.dart` вливает её в
// каждую запись при старте.
//
// Новый ключ словаря обязан получить перевод и здесь, иначе украинский
// экран откатится на английский. Это стережёт
// `test/services/locale_uk_test.dart`.

import 'chat_a.dart';
import 'chat_b.dart';
import 'connect_partner.dart';
import 'date_helpers.dart';
import 'home.dart';
import 'launch_splash.dart';
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
import 'stickers.dart';
import 'widget_screen.dart';

const Map<String, String> kUkStrings = {
  ...dateHelpersUk,
  ...smallAUk,
  ...smallBUk,
  ...smallCUk,
  ...smallDUk,
  ...midAUk,
  ...midBUk,
  ...midCUk,
  ...midDUk,
  ...midEUk,
  ...connectPartnerUk,
  ...homeUk,
  ...profileUk,
  ...memoryLaneUk,
  ...widgetScreenUk,
  ...stickersUk,
  ...launchSplashUk,
  ...chatAUk,
  ...chatBUk,
};

/// Мужские формы там, где у слова есть род: настроения «Втомився»,
/// «Хворий». Ложатся в запись словаря ключом `uk_m`, как `ru_m` у русского.
const Map<String, String> kUkMaleStrings = smallDUkMale;
