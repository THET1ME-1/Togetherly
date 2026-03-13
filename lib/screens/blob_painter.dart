import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Blob keyframe — stores corner radii in PIXELS, not percentages.
//  This gives predictable shapes regardless of card size.
//
//  Each keyframe has 4 corner radii: [tl, tr, br, bl]
//  rx = horizontal radius, ry = vertical radius (elliptical corners)
// ─────────────────────────────────────────────────────────────────────────────
class _BlobKeyframe {
  final List<double> rx; // [tl, tr, br, bl] horizontal px
  final List<double> ry; // [tl, tr, br, bl] vertical   px

  const _BlobKeyframe({required this.rx, required this.ry});

  static _BlobKeyframe lerp(_BlobKeyframe a, _BlobKeyframe b, double t) {
    return _BlobKeyframe(
      rx: List.generate(4, (i) => lerpDouble(a.rx[i], b.rx[i], t)!),
      ry: List.generate(4, (i) => lerpDouble(a.ry[i], b.ry[i], t)!),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Blob keyframes — pixel-based, gentle organic shapes.
//
//  Top corners (tl, tr): 50–100 px — visible organic movement.
//  Bottom corners (br, bl): FIXED at 32 px — toggle bar is never clipped.
//  The morph happens only in the top/side regions.
// ─────────────────────────────────────────────────────────────────────────────
const _kBottom = 32.0; // bottom corners are always stable

final _kBlobs = <_BlobKeyframe>[
  // keyframe 0 — balanced, slightly organic
  _BlobKeyframe(
    rx: [72, 64, _kBottom, _kBottom],
    ry: [80, 70, _kBottom, _kBottom],
  ),
  // keyframe 1 — lean top-left wider
  _BlobKeyframe(
    rx: [90, 56, _kBottom, _kBottom],
    ry: [68, 86, _kBottom, _kBottom],
  ),
  // keyframe 2 — lean top-right wider
  _BlobKeyframe(
    rx: [58, 88, _kBottom, _kBottom],
    ry: [84, 60, _kBottom, _kBottom],
  ),
  // keyframe 3 — both tops rounded
  _BlobKeyframe(
    rx: [80, 78, _kBottom, _kBottom],
    ry: [74, 80, _kBottom, _kBottom],
  ),
  // keyframe 4 — asymmetric wave
  _BlobKeyframe(
    rx: [66, 72, _kBottom, _kBottom],
    ry: [88, 66, _kBottom, _kBottom],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
//  BlobClipper
//  blobValue      : 0.0 → (kBlobs.length - 1) cycling through keyframes
//  expandProgress : 0.0 = full blob, 1.0 = full round-rect (32 px radius)
// ─────────────────────────────────────────────────────────────────────────────
class BlobClipper extends CustomClipper<Path> {
  final double blobValue;
  final double expandProgress;

  const BlobClipper({required this.blobValue, required this.expandProgress});

  @override
  Path getClip(Size size) {
    final count = _kBlobs.length;
    final clamped = blobValue.clamp(0.0, (count - 1).toDouble());
    final idx = clamped.floor().clamp(0, count - 1);
    final frac = clamped - idx;
    final next = (idx + 1) % count;
    final blob = _BlobKeyframe.lerp(_kBlobs[idx], _kBlobs[next], frac);
    return _buildPath(size, blob, expandProgress);
  }

  @override
  bool shouldReclip(BlobClipper old) =>
      old.blobValue != blobValue || old.expandProgress != expandProgress;

  // ── Path builder ──────────────────────────────────────────────────────────
  //  Smooth path with cubic bezier corners (k ≈ 0.5523 for perfect 90° arcs).
  //  Radii are in pixels and clamped to half the size to avoid overlap.
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildPath(Size size, _BlobKeyframe shape, double roundedCorner) {
    final w = size.width;
    final h = size.height;
    const kB = 0.5523; // bezier constant for perfect 90° arc
    const rr = 32.0; // round-rect target radius

    final ep = roundedCorner.clamp(0.0, 1.0);

    // Lerp from blob radius → stable 32px; clamp so radii don't exceed half size
    double lr(double blobR) {
      final raw = blobR + (rr - blobR) * ep;
      return raw.clamp(24.0, w * 0.48); // never sharper than 24px
    }

    double lrV(double blobR) {
      final raw = blobR + (rr - blobR) * ep;
      return raw.clamp(24.0, h * 0.48);
    }

    final tlrx = lr(shape.rx[0]);
    final tlry = lrV(shape.ry[0]);
    final trrx = lr(shape.rx[1]);
    final trry = lrV(shape.ry[1]);
    // Bottom corners — always exactly 32px (no blob influence)
    final brrx = rr.clamp(0.0, w * 0.48);
    final brry = rr.clamp(0.0, h * 0.48);
    final blrx = rr.clamp(0.0, w * 0.48);
    final blry = rr.clamp(0.0, h * 0.48);

    final path = Path();

    // Start at TL corner end-point on the top edge
    path.moveTo(tlrx, 0);

    // ── top edge → TR corner ──
    path.lineTo(w - trrx, 0);
    path.cubicTo(w - trrx * (1 - kB), 0, w, trry * (1 - kB), w, trry);

    // ── right edge → BR corner ──
    path.lineTo(w, h - brry);
    path.cubicTo(w, h - brry * (1 - kB), w - brrx * (1 - kB), h, w - brrx, h);

    // ── bottom edge → BL corner ──
    path.lineTo(blrx, h);
    path.cubicTo(blrx * (1 - kB), h, 0, h - blry * (1 - kB), 0, h - blry);

    // ── left edge → TL corner ──
    path.lineTo(0, tlry);
    path.cubicTo(0, tlry * (1 - kB), tlrx * (1 - kB), 0, tlrx, 0);

    path.close();
    return path;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AnimatedBlobClip
//
//  Wraps [child] with a smoothly morphing blob clip.
//  • enabled = false → plain ClipRRect(32px)
//  • enabled = true  → ClipPath with BlobClipper, isolated by RepaintBoundary
//  • expandProgress drives the collapse from blob→roundRect
// ─────────────────────────────────────────────────────────────────────────────
class AnimatedBlobClip extends StatefulWidget {
  final Widget child;
  final bool enabled;

  /// 0.0 = fully collapsed (max blob), 1.0 = fully expanded (round rect)
  final Animation<double> expandAnim;

  const AnimatedBlobClip({
    super.key,
    required this.child,
    required this.enabled,
    required this.expandAnim,
  });

  @override
  State<AnimatedBlobClip> createState() => _AnimatedBlobClipState();
}

class _AnimatedBlobClipState extends State<AnimatedBlobClip>
    with SingleTickerProviderStateMixin {
  late AnimationController _blobCtrl;
  late Animation<double> _blobAnim;

  static const _blobCount = 5; // matches _kBlobs.length
  static const _cycleDuration = Duration(seconds: 18);

  @override
  void initState() {
    super.initState();
    _blobCtrl = AnimationController(vsync: this, duration: _cycleDuration);
    _blobAnim = Tween<double>(
      begin: 0.0,
      end: (_blobCount - 1).toDouble(),
    ).animate(CurvedAnimation(parent: _blobCtrl, curve: Curves.easeInOut));
    if (widget.enabled) _blobCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AnimatedBlobClip old) {
    super.didUpdateWidget(old);
    if (widget.enabled == old.enabled) return;
    if (widget.enabled) {
      _blobCtrl.repeat(reverse: true);
    } else {
      _blobCtrl.stop();
      _blobCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _blobCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_blobAnim, widget.expandAnim]),
      builder: (context, child) {
        return ClipPath(
          clipper: BlobClipper(
            blobValue: _blobAnim.value,
            expandProgress: Curves.easeIn.transform(
              widget.expandAnim.value.clamp(0.0, 1.0),
            ),
          ),
          child: RepaintBoundary(child: child),
        );
      },
      child: widget.child,
    );
  }
}
