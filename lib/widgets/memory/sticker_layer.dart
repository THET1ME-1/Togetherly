import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/memory_sticker.dart';
import '../mood_image.dart';

/// Где стоит наклейка [s] на блоке размера [block], в координатах блока:
/// квадрат со стороной в долях ширины блока, центр в долях обеих сторон.
Rect stickerRect(MemorySticker s, Size block) {
  final side = s.size * block.width;
  return Rect.fromCenter(
    center: Offset(s.x * block.width, s.y * block.height),
    width: side,
    height: side,
  );
}

/// Прямоугольник виджета на экране или null, пока он не разложен.
Rect? globalRectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Картинка наклейки, повёрнутая на свой угол.
///
/// Своё настроение пары — квадрат фото или рисунка во весь кадр, поэтому
/// углы у него мягкие, как у плиток настроений. Картинка пропала — на её
/// месте пусто, без заглушки.
class StickerPicture extends StatelessWidget {
  const StickerPicture({
    super.key,
    required this.image,
    required this.side,
    this.angle = 0,
    this.rounded,
  });

  final String image;
  final double side;
  final double angle;

  /// Скруглить углы. null — решает адрес: скругляются «Свои» настроения.
  final bool? rounded;

  @override
  Widget build(BuildContext context) {
    Widget picture = MoodImage(image, width: side, height: side, quietError: true);
    if (rounded ?? isOwnMoodSticker(image)) {
      picture = ClipRSuperellipse(
        borderRadius: BorderRadius.circular(side * 0.26),
        child: picture,
      );
    }
    return Transform.rotate(angle: angle, child: picture);
  }
}

/// Наклейки поверх блока. Наклейка может свисать за край блока наполовину:
/// слой не обрезается, но касание ловится только внутри блока.
class StickerLayer extends StatelessWidget {
  const StickerLayer({
    super.key,
    required this.stickers,
    this.hiddenId,
    this.onTap,
  });

  final List<MemorySticker> stickers;

  /// Наклейка, которую сейчас ставят на место: её рисует редактор поверх
  /// ленты, а на карточке её быть не должно.
  final String? hiddenId;

  final ValueChanged<MemorySticker>? onTap;

  @override
  Widget build(BuildContext context) {
    if (stickers.isEmpty) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final s in stickers)
              if (s.id != hiddenId)
                Positioned.fromRect(
                  rect: stickerRect(s, size),
                  child: _tappable(
                    s,
                    StickerPicture(
                      key: ValueKey('sticker-${s.id}'),
                      image: s.image,
                      side: s.size * size.width,
                      angle: s.angle,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _tappable(MemorySticker s, Widget child) {
    final tap = onTap;
    if (tap == null) return IgnorePointer(child: child);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => tap(s),
      child: child,
    );
  }
}

/// Главный блок пина с наклейками: фото, лист заметки, обложка.
///
/// Блок сообщает о себе карточке ([StickerCardScope]) — по нему редактор
/// знает, куда ставить наклейку, а лента прячет ту, что сейчас двигают.
class StickerAnchor extends StatefulWidget {
  const StickerAnchor({
    super.key,
    required this.stickers,
    required this.child,
    this.onTap,
  });

  final List<MemorySticker> stickers;
  final Widget child;
  final void Function(MemorySticker sticker, StickerAnchorState anchor)? onTap;

  @override
  State<StickerAnchor> createState() => StickerAnchorState();
}

class StickerAnchorState extends State<StickerAnchor> {
  /// Наклейка, которую сейчас переставляют: на карточке её не рисуем.
  final ValueNotifier<String?> hidden = ValueNotifier(null);

  StickerCardScopeState? _scope;

  // Только что поставленная или убранная наклейка. Запись возвращается из
  // кэша через кадр-другой, и без этого на миг мелькало прежнее место.
  MemorySticker? _fresh;
  final Set<String> _gone = {};
  Timer? _forget;

  /// Где блок на экране.
  Rect? get globalRect => globalRectOf(context);

  /// Показать наклейку [s] на новом месте сразу, не дожидаясь записи.
  void expectPlaced(MemorySticker s) {
    setState(() {
      _fresh = s;
      _gone.remove(s.id);
    });
    hidden.value = null;
    _forgetLater();
  }

  /// Спрятать наклейку [id] сразу, не дожидаясь записи.
  void expectRemoved(String id) {
    setState(() {
      _gone.add(id);
      if (_fresh?.id == id) _fresh = null;
    });
    hidden.value = null;
    _forgetLater();
  }

  // Запись так и не пришла (отказ сервера, её удалили) — через пару секунд
  // показываем то, что лежит в записи.
  void _forgetLater() {
    _forget?.cancel();
    _forget = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _fresh = null;
        _gone.clear();
      });
    });
  }

  @override
  void didUpdateWidget(StickerAnchor old) {
    super.didUpdateWidget(old);
    final fresh = _fresh;
    if (fresh != null &&
        widget.stickers.any((s) =>
            s.id == fresh.id &&
            s.x == fresh.x &&
            s.y == fresh.y &&
            s.size == fresh.size &&
            s.angle == fresh.angle)) {
      _fresh = null;
    }
    _gone.removeWhere((id) => widget.stickers.every((s) => s.id != id));
  }

  /// Наклейки, которые сейчас видны на блоке.
  List<MemorySticker> get shown => _shown;

  List<MemorySticker> get _shown {
    final fresh = _fresh;
    if (fresh == null && _gone.isEmpty) return widget.stickers;
    final out = [
      for (final s in widget.stickers)
        if (!_gone.contains(s.id) && s.id != fresh?.id) s,
    ];
    if (fresh != null) out.add(fresh);
    return out;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.findAncestorStateOfType<StickerCardScopeState>();
    if (!identical(scope, _scope)) {
      _scope?._detach(this);
      _scope = scope?.._attach(this);
    }
  }

  @override
  void dispose() {
    _forget?.cancel();
    _scope?._detach(this);
    hidden.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    // Стопка стоит всегда, даже без наклеек: появись она с первой
    // наклейкой — Flutter пересоздал бы блок вместе с плеером внутри.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: ValueListenableBuilder<String?>(
            valueListenable: hidden,
            builder: (_, id, _) => StickerLayer(
              stickers: _shown,
              hiddenId: id,
              onTap: onTap == null ? null : (s) => onTap(s, this),
            ),
          ),
        ),
      ],
    );
  }
}

/// Карточка ленты, внутри которой есть блок с наклейками.
///
/// Долгое нажатие ловит карточка, а не блок: через неё меню находит блок и
/// знает, где сама карточка — её редактор оставляет светлой над затемнённой
/// лентой.
class StickerCardScope extends StatefulWidget {
  const StickerCardScope({super.key, required this.child});

  final Widget child;

  static StickerCardScopeState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<StickerCardScopeState>();

  @override
  State<StickerCardScope> createState() => StickerCardScopeState();
}

class StickerCardScopeState extends State<StickerCardScope> {
  StickerAnchorState? _anchor;

  /// Блок с наклейками этой карточки, если он есть и стоит на экране.
  StickerAnchorState? get anchor =>
      _anchor != null && _anchor!.mounted ? _anchor : null;

  /// Где карточка на экране.
  Rect? get globalRect => globalRectOf(context);

  void _attach(StickerAnchorState a) => _anchor = a;

  void _detach(StickerAnchorState a) {
    if (identical(_anchor, a)) _anchor = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
