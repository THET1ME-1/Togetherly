import 'package:flutter/material.dart';

import '../../models/avatar_frame.dart';
import '../../models/chest.dart';
import '../../services/pb_auth_service.dart';
import '../../services/pocketbase_service.dart';
import '../avatar_widget.dart';
import '../common/badge_image.dart';
import '../common/coin_image.dart';
import '../common/gift_image.dart';

/// Неподвижный кадр сундука из сборки — пока живой едет из каталога.
const String kChestStill = 'assets/images/gifts/chest.webp';

/// Картинка приза сундука, живая: монета TY, подарок, билет Togetherly+ или
/// рамка — на твоей же аватарке, чтобы сразу было видно, как она сидит.
///
/// [side] — сторона рисунка, как у [GiftImage]: файл с полем 176/144 рисуется
/// крупнее и выходит за квадрат, поэтому приз в сундуке занимает ровно то
/// место, что на макете.
class ChestPrizeImage extends StatelessWidget {
  const ChestPrizeImage(this.prize, {super.key, required this.side});

  final ChestPrize prize;
  final double side;

  @override
  Widget build(BuildContext context) {
    switch (prize.kind) {
      case ChestPrizeKind.coins:
        // У CoinImage сторона — весь файл вместе с полем.
        final full = side * 176 / 144;
        return SizedBox.square(
          dimension: side,
          child: OverflowBox(
            maxWidth: full,
            maxHeight: full,
            child: CoinImage(side: full, animated: true),
          ),
        );
      case ChestPrizeKind.gift:
        return GiftImage(prize.key, side: side);
      case ChestPrizeKind.plus:
        return GiftImage('chest_plus', side: side);
      case ChestPrizeKind.badge:
        return BadgeImage(prize.badge?.id, side: side);
      case ChestPrizeKind.frame:
        // Рамка крупнее аватарки: вся картинка рамки занимает [side].
        final avatar = side / AvatarFrame.scale;
        return SizedBox.square(
          dimension: side,
          child: Center(
            child: AvatarWidget(
              uid: PocketBaseService().userId ?? '',
              name: PbAuthService().currentProfile()?['displayName'] as String?,
              size: avatar,
              primary: Theme.of(context).colorScheme.primary,
              frame: prize.frameKey ?? '',
            ),
          ),
        );
    }
  }
}
