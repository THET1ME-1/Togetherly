import 'package:love_app/models/profile_icon.dart';
import 'package:love_app/services/catalog_service.dart';

/// Значки профиля теперь приезжают серверным каталогом, и в тестах его нет.
/// Этот набор повторяет боевой по форме: два платных и два наградных.
const testBadges = <ProfileIcon>[
  ProfileIcon(id: 'Paw', price: 20, sort: 10, smUrl: 'https://x/paw.webp'),
  ProfileIcon(id: 'Lucky', price: 35, rarity: 'rare', sort: 70, smUrl: 'https://x/lucky.webp'),
  ProfileIcon(id: 'Sponsor', price: 0, grantOnly: true, rarity: 'award', sort: 900, smUrl: 'https://x/sponsor.webp'),
  ProfileIcon(id: 'Fish', price: 0, grantOnly: true, rarity: 'award', sort: 920, smUrl: 'https://x/fish.webp'),
];

void installTestBadges() => CatalogService.instance.debugSetBadges(testBadges);
