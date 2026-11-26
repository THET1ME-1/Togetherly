import 'package:flutter/material.dart';

/// Половина блока маскота на главной (декабрь): плитка высотой [height],
/// картинка сверху, внизу название и одна строка. Низ ужимается (`FittedBox`),
/// а не вылезает: при крупном шрифте телефона и пилюле «Вернуть» в 92 точки
/// содержимого иначе не помещалось.
class HomeHalfTile extends StatefulWidget {
  const HomeHalfTile({
    super.key,
    required this.color,
    required this.top,
    required this.bottom,
    required this.onTap,
    this.height = 116,
  });

  final Color color;
  final Widget top;
  final Widget bottom;
  final VoidCallback onTap;
  final double height;

  @override
  State<HomeHalfTile> createState() => _HomeHalfTileState();
}

class _HomeHalfTileState extends State<HomeHalfTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(24)),
          child: LayoutBuilder(
            builder: (context, c) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                widget.top,
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomLeft,
                      child: SizedBox(width: c.maxWidth, child: widget.bottom),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
