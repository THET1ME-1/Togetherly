import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/xmas_text.dart';
import '../../models/user_data.dart';
import '../../models/xmas_tree.dart';
import '../../models/xmas_tree_geometry.dart';
import '../../services/catalog_service.dart';
import '../../services/locale_service.dart';
import '../../services/offline/media_view_cache.dart';
import '../../services/xmas_tree_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/xmas/toy_sheets.dart';
import '../../widgets/xmas/tree_stage.dart';
import '../chest_screen.dart';

/// Комната из Gemini (`xt_room_day` / `xt_room_dusk`), 704×1520. Ёлка встаёт
/// горшком в центр коврика, снег идёт за стеклом окна, у камина дышит отсвет.
const double _roomW = 704, _roomH = 1520;
const Offset _rug = Offset(352, 1298);
const Rect _glass = Rect.fromLTRB(60, 250, 330, 684);
const Offset _fire = Offset(616, 1062);

/// Экран ёлки пары (вариант В макета «Наряжаем ёлку», 26.11.2026): ёлка во
/// весь экран в комнате, снизу плавающая панель. Игрушку берут в листе
/// «Игрушки», она ждёт над панелью: касание по ветке вешает, её же можно
/// перетащить. Повешенную двигают пальцем, утащенная с хвои снимается, долгое
/// нажатие показывает, кто её повесил.
class XmasTreeScreen extends StatefulWidget {
  const XmasTreeScreen({
    super.key,
    required this.theme,
    required this.groupId,
    required this.season,
    required this.partnerName,
    this.userData,
  });

  final AppTheme theme;
  final String groupId;
  final int season;
  final String partnerName;
  final UserData? userData;

  @override
  State<XmasTreeScreen> createState() => _XmasTreeScreenState();
}

class _XmasTreeScreenState extends State<XmasTreeScreen> with TickerProviderStateMixin {
  final _stageKey = GlobalKey();
  late final AnimationController _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  String? _pick;
  XtGhost? _ghost;
  String? _dragId;
  Offset _dragOffset = Offset.zero;
  String? _toast;
  Timer? _toastTimer;
  Set<String> _known = {};

  XmasTreeService get _svc => XmasTreeService.instance;
  String get _me => widget.userData?.uid ?? _svc.myUid;
  String get _lang => LocaleService.instance.language.code;
  String _name(String toy) => CatalogService.instance.xmasToy(toy)?.name(_lang) ?? toy;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onState);
    unawaited(CatalogService.instance.ensureXmasArt());
    unawaited(_svc.bind(widget.groupId, widget.season, _me).then((_) {
      _known = {for (final t in _svc.state?.toys ?? const <TreeToy>[]) t.id};
      _svc.markSeen();
    }));
  }

  @override
  void dispose() {
    _svc.removeListener(_onState);
    _svc.markSeen();
    _ambient.dispose();
    _toastTimer?.cancel();
    super.dispose();
  }

  /// Партнёр повесил игрушку — короткая строка сверху.
  void _onState() {
    final toys = _svc.state?.toys ?? const <TreeToy>[];
    final now = {for (final t in toys) t.id};
    if (_known.isNotEmpty) {
      for (final t in toys) {
        if (!_known.contains(t.id) && t.author != _me && !t.id.startsWith('tmp')) {
          _say(xt('xt.partnerHung', {'name': widget.partnerName, 'toy': _name(t.toy)}));
        }
      }
    }
    _known = now;
    if (mounted) setState(() {});
  }

  void _say(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  bool get _archived => xtActiveSeason(xtNow()) != widget.season;

  // ── касания по ёлке ──

  XtFrame? get _frame {
    final box = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? null : XtFrame(box.size.width);
  }

  Offset? _unitsFromGlobal(Offset global) {
    final box = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return XtFrame(box.size.width).toUnits(box.globalToLocal(global));
  }

  Future<void> _hangAt(String toy, Offset u) async {
    final kind = _svc.state?.tree.kind ?? 'fir';
    if (!xtCanHang(kind, u.dx, u.dy)) {
      _say(xt('xt.notHere'));
      return;
    }
    HapticFeedback.selectionClick();
    final err = await _svc.hang(toy, (u.dx * 10).round() / 10, (u.dy * 10).round() / 10);
    if (!mounted) return;
    if (err == 'full') _say(xt('xt.full'));
    if (err == 'offline') _say(xt('xt.failed'));
    if (err == 'not_owned') unawaited(_svc.refresh());
    if ((_svc.freeToys[toy] ?? 0) <= 0 && _pick == toy) setState(() => _pick = null);
  }

  void _onTap(TapUpDetails d) {
    final f = _frame, s = _svc.state;
    if (f == null || s == null) return;
    final u = f.toUnits(d.localPosition);
    if (_pick != null) {
      unawaited(_hangAt(_pick!, u - const Offset(0, 5)));
    } else if (xtToyAt(s.tree.kind, s.toys, u) == null) {
      _say(xt('xt.pickFirst'));
    }
  }

  Future<void> _onLongPress(LongPressStartDetails d) async {
    final f = _frame, s = _svc.state;
    if (f == null || s == null) return;
    final t = xtToyAt(s.tree.kind, s.toys, f.toUnits(d.localPosition));
    if (t == null) return;
    HapticFeedback.mediumImpact();
    final who = t.author == _me ? (widget.userData?.displayName ?? '') : widget.partnerName;
    final off = await showToyInfo(context, toy: t, who: who);
    if (off == true) _takeOff(t);
  }

  void _takeOff(TreeToy t) {
    unawaited(_svc.remove(t.id));
    _say(t.author == _me ? xt('xt.backToBox', {'toy': _name(t.toy)}) : xt('xt.backToPartner', {'toy': _name(t.toy), 'name': widget.partnerName}));
  }

  void _onPanStart(DragStartDetails d) {
    final f = _frame, s = _svc.state;
    if (f == null || s == null) return;
    final u = f.toUnits(d.localPosition);
    final t = xtToyAt(s.tree.kind, s.toys, u);
    if (t == null) return;
    setState(() {
      _dragId = t.id;
      _dragOffset = Offset(t.x, t.y) - u;
      _ghost = XtGhost(t.toy, Offset(t.x, t.y));
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final f = _frame;
    if (_dragId == null || f == null || _ghost == null) return;
    setState(() => _ghost = XtGhost(_ghost!.toy, f.toUnits(d.localPosition) + _dragOffset));
  }

  void _onPanEnd(DragEndDetails _) {
    final id = _dragId, g = _ghost, s = _svc.state;
    setState(() {
      _dragId = null;
      _ghost = null;
    });
    if (id == null || g == null || s == null) return;
    final t = s.toys.where((o) => o.id == id).firstOrNull;
    if (t == null) return;
    if (xtCanHang(s.tree.kind, g.at.dx, g.at.dy)) {
      unawaited(_svc.move(id, (g.at.dx * 10).round() / 10, (g.at.dy * 10).round() / 10));
    } else {
      _takeOff(t);
    }
  }

  // ── игрушка «в руке» тащится с плашки ──

  void _handDrag(Offset global) {
    final u = _unitsFromGlobal(global);
    if (u == null || _pick == null) return;
    setState(() => _ghost = XtGhost(_pick!, u - const Offset(0, 6)));
  }

  void _handDrop() {
    final g = _ghost, p = _pick;
    setState(() => _ghost = null);
    if (g == null || p == null) return;
    unawaited(_hangAt(p, g.at));
  }

  Future<void> _openPicker([String cat = 'all']) async {
    final r = await showToyPicker(context, cat: cat, onCoins: widget.userData?.applyServerCoins);
    if (!mounted || r == null) return;
    switch (r) {
      case ToyPickHang(:final toy):
        setState(() => _pick = toy);
      case ToyPickChest():
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChestScreen(
            theme: widget.theme,
            groupId: widget.groupId,
            partnerName: widget.partnerName,
            onCoins: widget.userData?.applyServerCoins,
            userData: widget.userData,
          ),
          settings: const RouteSettings(name: '/chest'),
        ));
        unawaited(_svc.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ProfileTheme.themeFor(widget.theme);
    final cs = theme.colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final s = _svc.state;
    final tree = s?.tree ?? const PairTree();
    final toys = s?.toys ?? const <TreeToy>[];
    final mine = toys.where((t) => t.author == _me).length;
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth, h = c.maxHeight;
          final k = math.max(w / _roomW, h / _roomH);
          final ox = (w - _roomW * k) / 2, oy = h - _roomH * k;
          Offset room(Offset p) => Offset(ox + p.dx * k, oy + p.dy * k);
          final rug = room(_rug);
          final side = math.min(w * 1.13, h * 0.58);
          final stageTop = rug.dy - (101.5 + 8) / kXtSpan * side;
          final glass = Rect.fromPoints(room(_glass.topLeft), room(_glass.bottomRight));
          final fire = room(_fire);
          final pad = MediaQuery.paddingOf(context);
          return Stack(
            children: [
              Positioned.fill(child: _Room(dark: dark)),
              Positioned.fromRect(rect: glass, child: _WindowSnow(anim: _ambient)),
              // отсвет шириной в 600 точек комнаты: камин и пол перед ним
              Positioned(left: fire.dx - 300 * k, top: fire.dy - 300 * k, width: 600 * k, height: 600 * k, child: _FireGlow(anim: _ambient)),
              Positioned(
                left: rug.dx - side / 2,
                top: stageTop,
                width: side,
                height: side,
                child: GestureDetector(
                  key: _stageKey,
                  behavior: HitTestBehavior.translucent,
                  onTapUp: _onTap,
                  onLongPressStart: _onLongPress,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: TreeStage(side: side, tree: tree, toys: toys, ghost: _ghost, hidden: _dragId),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopBar(
                        title: xt('xt.title', {'s': xtSeasonLabel(widget.season)}),
                        subtitle: xt('xt.split', {'me': mine, 'name': widget.partnerName, 'him': toys.length - mine}),
                        me: widget.userData?.displayName ?? '',
                        partner: widget.partnerName,
                      ),
                      if (_archived)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: _Banner(text: xt('xt.archived')),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: pad.top + (_archived ? 132 : 70),
                child: _Toast(text: _toast),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: pad.bottom + 92,
                child: _HandChip(
                  toy: _pick,
                  label: _pick == null ? '' : xt('xt.hand', {'toy': _name(_pick!)}),
                  onClose: () => setState(() => _pick = null),
                  onDrag: _handDrag,
                  onDrop: _handDrop,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: pad.bottom + 18,
                child: Center(
                  child: _Toolbar(
                    tree: tree,
                    onStar: () => _svc.setTree(star: !tree.star),
                    onGarland: () => _svc.setTree(garland: !tree.garland),
                    onStyle: () => _openPicker('tree'),
                    onToys: () => _openPicker(),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _Room extends StatelessWidget {
  const _Room({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final debug = xtDebugArt;
    if (debug != null) {
      return Image(image: debug(dark ? 'xt_room_dusk' : 'xt_room_day'), fit: BoxFit.cover, alignment: Alignment.bottomCenter);
    }
    return ListenableBuilder(
      listenable: CatalogService.instance,
      builder: (context, _) {
        final art = CatalogService.instance.giftArt(dark ? 'xt_room_dusk' : 'xt_room_day');
        final url = art?.lgUrl ?? art?.smUrl;
        final cs = Theme.of(context).colorScheme;
        if (url == null) return ColoredBox(color: cs.surfaceContainer);
        return Image(
          image: CachedNetworkImageProvider(url, cacheManager: OfflineImageCacheManager.instance),
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
          gaplessPlayback: true,
          frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
            opacity: frame == null && !sync ? 0 : 1,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            child: child,
          ),
          errorBuilder: (_, _, _) => ColoredBox(color: cs.surfaceContainer),
        );
      },
    );
  }
}

/// Снег за стеклом окна: несколько хлопьев медленно падают и покачиваются.
class _WindowSnow extends StatelessWidget {
  const _WindowSnow({required this.anim});
  final Animation<double> anim;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, c) {
        final r = c.maxWidth / 2;
        return ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(r)),
          child: CustomPaint(painter: _SnowPainter(anim), size: Size(c.maxWidth, c.maxHeight)),
        );
      }),
    );
  }
}

class _SnowPainter extends CustomPainter {
  _SnowPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.9);
    final t = anim.value * 24;
    for (var i = 0; i < 18; i++) {
      final speed = 1 / (6 + (i % 5) * 1.4);
      final y = ((t * speed + i * 0.137) % 1.0) * (size.height + 8) - 4;
      final x = ((i * 37) % 100) / 100 * size.width + math.sin(t * 0.8 + i) * 4;
      canvas.drawCircle(Offset(x, y), i % 3 == 0 ? 1.2 : 1.7, p);
    }
  }

  @override
  bool shouldRepaint(_SnowPainter old) => false;
}

/// Отсвет огня: тёплое пятно у камина мягко дышит.
class _FireGlow extends StatelessWidget {
  const _FireGlow({required this.anim});
  final Animation<double> anim;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = anim.value * 24;
          final o = still ? 0.55 : 0.5 + 0.18 * math.sin(t * 2.4) + 0.08 * math.sin(t * 5.3);
          return Opacity(
            opacity: o.clamp(0, 1).toDouble(),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [Color(0x66FFBE5A), Color(0x00FF963C)], stops: [0, 1]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.subtitle, required this.me, required this.partner});
  final String title, subtitle, me, partner;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget ava(String name, Color bg, Color fg) => Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(color: cs.surface, width: 2)),
          child: Text(name.isEmpty ? '·' : name.characters.first.toUpperCase(),
              style: TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: xt('xt.back'),
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          SizedBox(
            width: 56,
            height: 32,
            child: Stack(
              children: [
                Positioned(left: 0, child: ava(me, cs.primaryContainer, cs.onPrimaryContainer)),
                Positioned(left: 22, child: ava(partner, cs.tertiaryContainer, cs.onTertiaryContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(Icons.history_rounded, color: cs.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: cs.onTertiaryContainer))),
        ],
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text});
  final String? text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedSlide(
        offset: text == null ? const Offset(0, -0.3) : Offset.zero,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: text == null ? 0 : 1,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(18)),
            child: Text(text ?? '', style: TextStyle(fontSize: 13, height: 1.35, color: cs.onInverseSurface)),
          ),
        ),
      ),
    );
  }
}

class _HandChip extends StatelessWidget {
  const _HandChip({required this.toy, required this.label, required this.onClose, required this.onDrag, required this.onDrop});
  final String? toy;
  final String label;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = toy == null ? null : CatalogService.instance.xmasToy(toy!);
    return AnimatedSlide(
      offset: toy == null ? const Offset(0, 0.4) : Offset.zero,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: toy == null ? 0 : 1,
        duration: const Duration(milliseconds: 320),
        child: IgnorePointer(
          ignoring: toy == null,
          child: GestureDetector(
            onPanUpdate: (d) => onDrag(d.globalPosition),
            onPanEnd: (_) => onDrop(),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
              decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(99)),
              child: Row(
                children: [
                  SizedBox.square(dimension: 36, child: t == null ? null : XtArt(t.pickArt, side: 36)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onInverseSurface))),
                  IconButton(
                    tooltip: xt('xt.putBack'),
                    onPressed: onClose,
                    icon: Icon(Icons.close_rounded, color: cs.onInverseSurface),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.tree, required this.onStar, required this.onGarland, required this.onStyle, required this.onToys});
  final PairTree tree;
  final VoidCallback onStar, onGarland, onStyle, onToys;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tog(IconData icon, String tip, bool on, VoidCallback tap) => IconButton(
          tooltip: tip,
          isSelected: on,
          onPressed: tap,
          style: IconButton.styleFrom(
            fixedSize: const Size(48, 48),
            backgroundColor: on ? cs.secondaryContainer : Colors.transparent,
            foregroundColor: on ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          ),
          icon: Icon(icon),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(99)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              tog(Icons.star_rounded, xt('xt.star'), tree.star, onStar),
              tog(Icons.lightbulb_rounded, xt('xt.garland'), tree.garland, onGarland),
              tog(Icons.park_rounded, xt('xt.style'), false, onStyle),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            onPressed: onToys,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(xt('xt.toys'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}
