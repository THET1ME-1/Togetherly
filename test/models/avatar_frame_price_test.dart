import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/avatar_frame.dart';

/// Треть зимних рамок продаётся в магазине (решение владельца 26.11.2026):
/// цена приходит полем `price` записи каталога, без цены рамка — из сундука.
void main() {
  Map<String, dynamic> row(Object? price) => {
        'id': 'frame_ny_lights',
        'kind': 'frame',
        'enabled': true,
        'sort': 800,
        'price': price,
        'data': {'key': 'ny_lights', 'rarity': 'common', 'set': 'winter', 'still': 'https://x/still.png', 'name': {'ru': 'Гирлянда'}},
      };

  test('цена из записи каталога — рамка продаётся', () {
    final f = AvatarFrame.fromCatalog(row(60))!;
    expect(f.price, 60);
    expect(f.forSale, isTrue);
    expect(f.featureKey, 'frame:frame_ny_lights');
  });

  test('без цены рамка только из сундука', () {
    expect(AvatarFrame.fromCatalog(row(0))!.forSale, isFalse);
    expect(AvatarFrame.fromCatalog(row(null))!.forSale, isFalse);
  });
}
