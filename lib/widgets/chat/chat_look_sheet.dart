import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/chat_look.dart';
import '../app_sheet.dart';
import 'bubble_looks.dart';

/// Название вида в листе выбора.
String chatLookName(ChatLook look) => switch (look) {
  ChatLook.cozy => trKey('chatLookCozy'),
  ChatLook.material => trKey('chatLookMaterial'),
  ChatLook.sticker => trKey('chatLookSticker'),
  ChatLook.pixel => trKey('chatLookPixel'),
};

/// Лист «Вид сообщений»: четыре карточки с живыми превью, касание выбирает.
/// Отдаёт выбранный вид или null, если лист закрыли.
Future<ChatLook?> showChatLookSheet(
  BuildContext context, {
  required ChatLook current,
  required Color mine,
  required Color partner,
}) {
  return showAppSheet<ChatLook>(
    context,
    builder: (ctx) => SheetScaffold(
      title: trKey('chatLookTitle'),
      child: StickerBoilScope(
        active: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.05,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final look in ChatLook.values)
                ChatLookCard(
                  look: look,
                  selected: look == current,
                  mine: mine,
                  partner: partner,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(ctx).pop(look);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Карточка вида: два маленьких пузыря тем же painter'ом, что в чате.
class ChatLookCard extends StatelessWidget {
  const ChatLookCard({
    super.key,
    required this.look,
    required this.selected,
    required this.mine,
    required this.partner,
    required this.onTap,
  });

  final ChatLook look;
  final bool selected;
  final Color mine;
  final Color partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.secondaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _MiniBubble(
                        look: look,
                        color: partner,
                        left: true,
                        width: 84,
                        seed: 3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _MiniBubble(
                        look: look,
                        color: mine,
                        left: false,
                        width: 64,
                        seed: 8,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chatLookName(look),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? cs.onSecondaryContainer
                            : cs.onSurface,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: cs.primary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBubble extends StatelessWidget {
  const _MiniBubble({
    required this.look,
    required this.color,
    required this.left,
    required this.width,
    required this.seed,
  });

  final ChatLook look;
  final Color color;
  final bool left;
  final double width;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF23191A);
    final bar = Container(
      height: 6,
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(3),
      ),
    );
    final double pad = look == ChatLook.sticker ? kStickerInset + 8 : 9;
    final double low = look == ChatLook.pixel ? PixelBubblePainter.tailDrop : 0;
    final painter = switch (look) {
      ChatLook.sticker => StickerBubblePainter(
        color: color,
        seed: seed,
        frame: StickerBoilScope.of(context),
      ),
      ChatLook.pixel => PixelBubblePainter(color: color, tailLeft: left),
      ChatLook.material => _PlainBubble(
        color: color,
        left: left,
        crooked: false,
      ),
      ChatLook.cozy => _PlainBubble(color: color, left: left, crooked: true),
    };
    final child = CustomPaint(
      painter: painter,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + low),
          child: bar,
        ),
      ),
    );
    return look == ChatLook.cozy || look == ChatLook.sticker
        ? Transform.rotate(angle: left ? -.03 : .025, child: child)
        : child;
  }
}

/// Наш и обычный вид для превью: кривые углы или ровные со срезом.
class _PlainBubble extends CustomPainter {
  const _PlainBubble({
    required this.color,
    required this.left,
    required this.crooked,
  });
  final Color color;
  final bool left;
  final bool crooked;

  @override
  void paint(Canvas canvas, Size size) {
    final r = crooked
        ? RRect.fromRectAndCorners(
            Offset.zero & size,
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(9),
            bottomLeft: const Radius.circular(8),
            bottomRight: const Radius.circular(13),
          )
        : RRect.fromRectAndCorners(
            Offset.zero & size,
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(left ? 4 : 12),
            bottomRight: Radius.circular(left ? 12 : 4),
          );
    canvas.drawRRect(r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PlainBubble old) =>
      old.color != color || old.left != left || old.crooked != crooked;
}
