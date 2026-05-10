import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mascot.dart';
import '../services/mascot_service.dart';
import '../theme/app_theme.dart';

const String _kHiddenKey = 'mascot_hidden';
const String _kOnboardingKey = 'mascot_onboarding_shown';

/// Floating mascot overlay rendered inside the home screen Stack.
/// Draggable + pinch-to-scale. Position and scale sync via [MascotService].
class ActiveMascotWidget extends StatefulWidget {
  final MascotService mascotService;
  final AppTheme theme;
  final VoidCallback onOpenGallery;

  const ActiveMascotWidget({
    super.key,
    required this.mascotService,
    required this.theme,
    required this.onOpenGallery,
  });

  @override
  State<ActiveMascotWidget> createState() => _ActiveMascotWidgetState();
}

class _ActiveMascotWidgetState extends State<ActiveMascotWidget>
    with SingleTickerProviderStateMixin {
  bool _hidden = false;
  bool _onboardingShown = false;

  // Gesture tracking
  Offset _position = Offset.zero; // screen-space position of mascot center
  double _scale = 1.0;
  bool _positionInitialized = false;

  // Pinch state
  double _baseScale = 1.0;

  // Push-debounce for Firestore writes
  Timer? _syncTimer;

  // Entrance animation
  late AnimationController _entranceCtrl;
  late Animation<double> _entranceAnim;

  MascotService get _svc => widget.mascotService;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _entranceAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.elasticOut,
    );

    _loadPrefs();
    _svc.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _syncTimer?.cancel();
    _svc.removeListener(_onServiceChanged);
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hidden = prefs.getBool(_kHiddenKey) ?? false;
      _onboardingShown = prefs.getBool(_kOnboardingKey) ?? false;
    });
  }

  void _onServiceChanged() {
    final state = _svc.state;
    if (!_positionInitialized && mounted) {
      // First sync: adopt group position/scale
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final size = MediaQuery.of(context).size;
        setState(() {
          _position = Offset(
            state.positionX * size.width,
            state.positionY * size.height,
          );
          _scale = state.scale.clamp(0.4, 3.0);
          _positionInitialized = true;
        });
        _entranceCtrl.forward(from: 0);
        if (!_onboardingShown) _showOnboarding();
      });
    }
    if (mounted) setState(() {});
  }

  void _showOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingKey, true);
    if (!mounted) return;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        bottom: 120,
        left: 0,
        right: 0,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 400),
              builder: (_, v, child) => Opacity(opacity: v, child: child),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Это маскот вашей группы! 🎉',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      entry.remove();
      if (mounted) setState(() => _onboardingShown = true);
    });
  }

  // ── Gestures ─────────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _baseScale = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _scale = (_baseScale * d.scale).clamp(0.4, 3.0);
      _position += d.focalPointDelta;
      _clampPosition();
    });
    _scheduleSyncTimer();
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _scheduleSync();
  }

  void _clampPosition() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final half = 40.0 * _scale;
    _position = Offset(
      _position.dx.clamp(half, size.width - half),
      _position.dy.clamp(half, size.height - half),
    );
  }

  void _scheduleSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 300), _scheduleSync);
  }

  void _scheduleSync() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    _svc.updatePosition(
      x: (_position.dx / size.width).clamp(0.0, 1.0),
      y: (_position.dy / size.height).clamp(0.0, 1.0),
      scale: _scale,
    );
  }

  // ── Menu ─────────────────────────────────────────────────────────────────

  void _onTap() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: widget.theme.primary),
              title: const Text('Перейти в галерею'),
              onTap: () {
                Navigator.of(ctx).pop();
                widget.onOpenGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined,
                  color: Colors.grey),
              title: const Text('Скрыть'),
              onTap: () async {
                Navigator.of(ctx).pop();
                setState(() => _hidden = true);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(_kHiddenKey, true);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mascot = _svc.activeMascot;
    if (mascot == null || _hidden || !_positionInitialized) {
      return const SizedBox.shrink();
    }

    final mascotSize = 80.0 * _scale;

    return Positioned(
      left: _position.dx - mascotSize / 2,
      top: _position.dy - mascotSize / 2,
      child: ScaleTransition(
        scale: _entranceAnim,
        child: GestureDetector(
          onTap: _onTap,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: SizedBox(
            width: mascotSize,
            height: mascotSize,
            child: _MascotImage(mascot: mascot, service: _svc),
          ),
        ),
      ),
    );
  }
}

// ── Mascot image renderer ─────────────────────────────────────────────────────

class _MascotImage extends StatelessWidget {
  final Mascot mascot;
  final MascotService service;

  const _MascotImage({required this.mascot, required this.service});

  @override
  Widget build(BuildContext context) {
    final asset = service.resolvedAssetForMood(mascot);
    if (asset != null) {
      return SvgPicture.asset(asset, fit: BoxFit.contain);
    }
    if (mascot.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: mascot.imageUrl!,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => const Icon(Icons.face, size: 40),
      );
    }
    return const Icon(Icons.face, size: 40);
  }
}

/// Standalone helper to un-hide the mascot (call from profile/settings).
Future<void> showMascotOverlay() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kHiddenKey, false);
}
