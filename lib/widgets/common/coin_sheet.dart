import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_sheet.dart';
import 'coin_image.dart';

/// Монета TY крупно: нажали на ценник — снизу выезжает рисованная монета во
/// весь лист и крутится. Касание по ней закрывает лист.
Future<void> showCoinSheet(BuildContext context) {
  return showAppSheet<void>(
    context,
    builder: (ctx) {
      final side = math.min(MediaQuery.sizeOf(ctx).width * 0.78, 340.0);
      return SheetScaffold(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(ctx).pop(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Center(child: CoinImage(side: side, animated: true)),
          ),
        ),
      );
    },
  );
}
