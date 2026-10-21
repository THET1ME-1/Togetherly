import '../services/frame_gift_service.dart';
import 'gift.dart';

/// Пришедшие подарки, которые эта сборка умеет показать, в прежнем порядке
/// (новые первыми).
///
/// Сервер отдаёт все подарки, что ждут ответа, а показать сборка может не
/// каждый: подарок сезона она узнаёт из каталога, а каталог мог ещё не
/// доехать. Главная брала первый подарок списка, и незнакомый прятал
/// карточку целиком вместе со всеми знакомыми под ним (TOG-10, 21.10.2026).
/// Отданную рамку показывает свой лист, её сборка знает всегда.
List<Map<String, dynamic>> shownIncomingGifts(List<Map<String, dynamic>> gifts) => [
  for (final g in gifts)
    if (_showable((g['gift_key'] ?? '').toString())) g,
];

bool _showable(String key) =>
    key.isNotEmpty && (FrameGiftService.frameKeyOf(key) != null || GiftCatalog.byKey(key) != null);
