import '../dict_strings.dart';

/// Профильная иконка («бейдж»), которую пользователь может купить за коины
/// и закрепить рядом со своим именем.
///
/// Источник правды о ценах — сервер (functions/index.js,
/// `PROFILE_ICON_PRICES`). Этот каталог — клиентское зеркало для отображения.
/// Все списания монет идут только через Cloud Function `purchaseIcon`.
class ProfileIcon {
  /// Идентификатор = имя файла без расширения (`assets/images/icons/<id>.webp`).
  final String id;

  /// Цена в коинах. 0 — иконка не продаётся (выдаётся только вручную).
  final int price;

  /// true для специальных наград (Sponsor / Helper): их нельзя купить,
  /// они выдаются разработчиком за вклад в проект.
  final bool grantOnly;

  const ProfileIcon({
    required this.id,
    required this.price,
    this.grantOnly = false,
  });

  /// Путь к ассету. Имена файлов всегда латиницей — см. каталог ниже.
  String get asset => 'assets/images/icons/$id.webp';

  /// Название и подпись живут в словаре: ключи считаются из id, язык там
  /// колонка (`lib/l10n/dict/profile_icons.dart`).
  String get name => trKey('picon_${id}_name');
  String get description => trKey('picon_${id}_desc');

  // ── Каталог ────────────────────────────────────────────────────────────────
  // Цены сверены с functions/index.js → PROFILE_ICON_PRICES.
  // Common = 20, Rare = 35, Premium = 50, Grant-only = 0.

  static const List<ProfileIcon> all = <ProfileIcon>[
    // ── Common (20) ──
    ProfileIcon(id: 'Paw', price: 20),
    ProfileIcon(id: 'Sun', price: 20),
    ProfileIcon(id: 'Moon', price: 20),
    ProfileIcon(id: 'Rainbow', price: 20),
    ProfileIcon(id: 'Bunny', price: 20),
    ProfileIcon(id: 'Frog', price: 20),
    // ── Rare (35) ──
    ProfileIcon(id: 'Lucky', price: 35),
    ProfileIcon(id: 'UFO', price: 35),
    ProfileIcon(id: 'Together', price: 35),
    // ── Premium (50) ──
    ProfileIcon(id: 'Soulmate', price: 50),
    ProfileIcon(id: 'Perfect Match', price: 50),
    ProfileIcon(id: 'Inseparable', price: 50),
    // ── Grant-only (награды за вклад в проект) ──
    ProfileIcon(id: 'Sponsor', price: 0, grantOnly: true),
    ProfileIcon(id: 'Helper', price: 0, grantOnly: true),
    ProfileIcon(id: 'Fish', price: 0, grantOnly: true),
  ];

  /// Иконки, доступные для покупки (исключая grant-only).
  static List<ProfileIcon> get purchasable =>
      all.where((i) => !i.grantOnly).toList(growable: false);

  /// Поиск по id. Возвращает null, если иконки нет в каталоге.
  static ProfileIcon? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final icon in all) {
      if (icon.id == id) return icon;
    }
    return null;
  }
}
