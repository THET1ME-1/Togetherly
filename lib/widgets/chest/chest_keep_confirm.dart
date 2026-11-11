import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/gift.dart';
import '../common/app_dialog.dart';

/// Спрашивает перед «Оставить себе» у подарка из сундука.
///
/// Кнопки «Подарить» и «Оставить себе» стоят рядом, и «оставить» срабатывала
/// с первого касания, а «подарить» — только после записки. Промах не
/// исправить из приложения: оставленный подарок подарить уже нельзя
/// (`/api/chest/give` отвечает `already_used`). Так подарок девушке ушёл себе
/// на полку (письмо в поддержку 11.11.2026). Подарить по-прежнему можно без
/// лишнего шага.
Future<bool> confirmChestKeep(BuildContext context, String giftKey) {
  final title = GiftCatalog.byKey(giftKey)?.title ?? giftKey;
  return AppDialog.confirm(
    context,
    title: trKey('chestKeepAskTitle').replaceAll('{gift}', title),
    message: trKey('chestKeepAskBody'),
    confirmLabel: trKey('chestKeep'),
  );
}
