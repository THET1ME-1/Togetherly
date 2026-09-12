/// Раскрытые разделы и карточки каталога виджетов.
///
/// Состояние жило только в памяти экрана: уход на главную и обратно возвращал
/// умолчания — «Уже стоят» свёрнуты, новый каталог раскрыт. Человек, которому
/// нужен старый список, разворачивал его при каждом заходе заново (жалоба
/// 12.09.2026). Теперь набор раскрытого лежит в prefs: это привычка
/// конкретного человека, а не общее имущество пары, и на сервер ему незачем.
class WidgetPanels {
  const WidgetPanels._();

  /// Ключ в SharedPreferences. Список строк, а не флаг на каждый раздел:
  /// карточек в каталоге прибавляется, и восемь отдельных ключей пришлось бы
  /// заводить и читать по одному.
  static const String prefsKey = 'widget_panels_expanded';

  static const String legacySection = 'legacy_section';
  static const String newSection = 'new_section';
  static const String pairWidget = 'pair_widget';
  static const String petalTimer = 'petal_timer';
  static const String daysCounter = 'days_counter';
  static const String photoDay = 'photo_day';
  static const String partnerPhoto = 'partner_photo';
  static const String photoGrid = 'photo_grid';

  /// Порядок здесь задаёт и порядок записи — чтобы одно и то же состояние
  /// всегда давало одну и ту же строку в prefs.
  static const List<String> known = [
    legacySection,
    newSection,
    pairWidget,
    petalTimer,
    daysCounter,
    photoDay,
    partnerPhoto,
    photoGrid,
  ];

  /// Что раскрыто при самом первом заходе: новый каталог (ради него экран и
  /// перестроили) и карточка «Фото дня».
  static const Set<String> byDefault = {newSection, photoDay};

  /// Разбор сохранённого. `null` — настройки ещё нет, берём умолчания; пустой
  /// список — человек свернул всё, и возвращать ему умолчания нельзя, иначе
  /// свернуть новый каталог насовсем будет невозможно.
  static Set<String> restore(List<String>? saved) {
    if (saved == null) return {...byDefault};
    return saved.where(known.contains).toSet();
  }

  /// Что класть в prefs. Незнакомое (ключ из будущей версии, чужая запись) не
  /// переносим, порядок постоянный.
  static List<String> store(Set<String> expanded) =>
      known.where(expanded.contains).toList();
}

/// Выбранный размер в карточке каталога: `widgetType` → номер варианта.
///
/// Тот же случай, что и с раскрытыми разделами: выбор жил в памяти экрана и
/// пропадал при уходе с него. Хранится строками «тип:номер» — в prefs нет
/// словарей, а json ради двух полей заводить незачем.
class WidgetSizeChoice {
  const WidgetSizeChoice._();

  static const String prefsKey = 'widget_size_choice';

  static Map<String, int> restore(List<String>? saved) {
    final out = <String, int>{};
    for (final line in saved ?? const <String>[]) {
      final i = line.lastIndexOf(':');
      if (i <= 0) continue;
      final index = int.tryParse(line.substring(i + 1));
      if (index == null || index < 0) continue;
      out[line.substring(0, i)] = index;
    }
    return out;
  }

  static List<String> store(Map<String, int> choice) {
    final keys = choice.keys.toList()..sort();
    return [for (final k in keys) '$k:${choice[k]}'];
  }
}
