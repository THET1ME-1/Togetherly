import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Blob keyframe — stores 8 border-radius percentage values
//  matching the CSS syntax:  tl tr br bl / tl tr br bl
//  (horizontal radii first, then vertical radii)
//
//  Values are 0..1 fractions of size. For a smooth organic look we keep
//  them in a narrow band (0.38 – 0.58) and keep bottom corners very
//  stable so the "Days / Months / Time" bar is never clipped.
// ─────────────────────────────────────────────────────────────────────────────
class _BlobKeyframe {
  final List<double> rx; // [tl, tr, br, bl] horizontal, 0..1 fraction
  final List<double> ry; // [tl, tr, br, bl] vertical,   0..1 fraction

  const _BlobKeyframe({required this.rx, required this.ry});

  static _BlobKeyframe lerp(_BlobKeyframe a, _BlobKeyframe b, double t) {
    return _BlobKeyframe(
      rx: List.generate(4, (i) => lerpDouble(a.rx[i], b.rx[i], t)!),
      ry: List.generate(4, (i) => lerpDouble(a.ry[i], b.ry[i], t)!),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Blob keyframes — gentle, organic variations.
//
//  Top corners (tl, tr) — wide motion for a fluid organic look.
//  Bottom corners (br, bl) — FIXED at round-rect baseline (~0.09–0.12)
//  so the "Days / Months / Time" toggle bar is never clipped.
// ─────────────────────────────────────────────────────────────────────────────
final _kBlobs = <_BlobKeyframe>[
  // keyframe 0 — resting / balanced
  _BlobKeyframe(rx: [0.46, 0.54, 0.10, 0.10], ry: [0.48, 0.48, 0.11, 0.11]),
  // keyframe 1 — lean top-left
  _BlobKeyframe(rx: [0.40, 0.56, 0.10, 0.10], ry: [0.42, 0.52, 0.11, 0.11]),
  // keyframe 2 — lean top-right
  _BlobKeyframe(rx: [0.54, 0.42, 0.10, 0.10], ry: [0.52, 0.44, 0.11, 0.11]),
  // keyframe 3 — wider top, stable bottom
  _BlobKeyframe(rx: [0.48, 0.52, 0.10, 0.10], ry: [0.40, 0.54, 0.11, 0.11]),
  // keyframe 4 — subtle wave
  _BlobKeyframe(rx: [0.44, 0.50, 0.10, 0.10], ry: [0.50, 0.46, 0.11, 0.11]),
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
  //  Smooth superellipse-style path. Every corner uses a cubic bezier with
  //  the standard 90° arc constant (k ≈ 0.5523) so curves are always round.
  // ─────────────────────────────────────────────────────────────────────────
  static Path _buildPath(Size size, _BlobKeyframe shape, double roundedCorner) {
    final w = size.width;
    final h = size.height;
    const kB = 0.5523; // bezier constant for perfect 90° arc

    // Round-rect baseline (32 px corners) as fractions
    final rrx = (32.0 / w).clamp(0.0, 0.5);
    final rry = (32.0 / h).clamp(0.0, 0.5);

    final ep = roundedCorner.clamp(0.0, 1.0);

    // Lerp from blob shape → round-rect
    double lr(double blobR, double rrR) => blobR + (rrR - blobR) * ep;

    final tlrx = lr(shape.rx[0], rrx) * w;
    final tlry = lr(shape.ry[0], rry) * h;
    final trrx = lr(shape.rx[1], rrx) * w;
    final trry = lr(shape.ry[1], rry) * h;
    final brrx = lr(shape.rx[2], rrx) * w;
    final brry = lr(shape.ry[2], rry) * h;
    final blrx = lr(shape.rx[3], rrx) * w;
    final blry = lr(shape.ry[3], rry) * h;

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
