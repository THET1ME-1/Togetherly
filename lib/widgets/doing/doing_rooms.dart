import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/cloud_mascot.dart';
import '../../models/doing.dart';
import '../../services/catalog_service.dart';
import '../common/guide_mascot.dart';
import '../storage_image.dart';

/// Виджет «Чем заняты» внутри приложения: две комнатки, как на рабочем столе.
///
/// Здесь Ту двигается: на рабочем столе виджеты двигаться не умеют, и
/// анимацию человек видит только в этом превью. Рисунок повторяет нативный
/// (`DoingWidgetProvider.kt`, `DoingWidget.swift`): стена в горошек, мягкий
/// пол, внизу плашка «аватарка + время» и рядом название занятия, на стыке
/// сердце. Все размеры — в сотых долях ширины, как там.

/// Одна половина превью.
class DoingRoomLook {
  const DoingRoomLook({required this.wall, this.doing = const Doing.none(), this.avatarUrl = ''});

  /// Цвет стены: выбранный человеком или роль темы.
  final Color wall;
  final Doing doing;
  final String avatarUrl;
}

const Color _paperLight = Color(0xFFFFFDFC);
const Color _paperDark = Color(0xFFFFF1F3);
const Color _pen = Color(0xFF4B2A31);
const Color _heart = Color(0xFFE8556F);

class DoingRooms extends StatelessWidget {
  const DoingRooms({super.key, required this.my, required this.partner, this.now});

  final DoingRoomLook my;
  final DoingRoomLook partner;

  /// Момент показа: занятие старше трёх часов уже погасло. В тесте задаётся.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final paper = Theme.of(context).brightness == Brightness.dark ? _paperDark : _paperLight;
    final when = now ?? DateTime.now();

    return AspectRatio(
      aspectRatio: 338 / 158,
      child: LayoutBuilder(
        builder: (context, box) {
          final u = box.maxWidth / 100;
          return ClipRRect(
            borderRadius: BorderRadius.circular(7.7 * u),
            child: ColoredBox(
              color: paper,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(child: _Room(look: my, mine: true, paper: paper, u: u, now: when)),
                      SizedBox(width: 1.1 * u),
                      Expanded(child: _Room(look: partner, mine: false, paper: paper, u: u, now: when)),
                    ],
                  ),
                  // Сердце на стыке половин.
                  Container(
                    width: 9.6 * u,
                    height: 9.6 * u,
                    decoration: ShapeDecoration(
                      color: paper,
                      shape: CircleBorder(side: BorderSide(color: _pen.withValues(alpha: 0.12), width: 0.35 * u)),
                    ),
                    child: Icon(Icons.favorite_rounded, size: 5.4 * u, color: _heart),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Room extends StatelessWidget {
  const _Room({required this.look, required this.mine, required this.paper, required this.u, required this.now});

  final DoingRoomLook look;
  final bool mine;
  final Color paper;
  final double u;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final doing = look.doing.shownAt(now);
    final label = doing.isNone ? '' : (doing.isOwn ? doing.text : trKey('doing.${doing.id}'));
    final time = doing.isNone ? '' : doingTime(doing.atMs);
    final inner = Radius.circular(2.6 * u);

    final who = _Chip(
      paper: paper,
      u: u,
      child: Padding(
        padding: EdgeInsets.all(0.7 * u),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: mine ? TextDirection.ltr : TextDirection.rtl,
          children: [
            _Avatar(url: look.avatarUrl, mine: mine, paper: paper, side: 6.6 * u),
            if (time.isNotEmpty)
              Padding(
                padding: EdgeInsetsDirectional.only(start: u, end: 1.3 * u),
                child: Text(time, textDirection: TextDirection.ltr, style: _text(3 * u, FontWeight.w600)),
              ),
          ],
        ),
      ),
    );

    final act = label.isEmpty
        ? null
        : Flexible(
            child: _Chip(
              paper: paper,
              u: u,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 2.1 * u),
                child: Center(
                  widthFactor: 1,
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _text(3.05 * u, FontWeight.w700)),
                ),
              ),
            ),
          );

    return ClipRRect(
      borderRadius: mine ? BorderRadius.horizontal(right: inner) : BorderRadius.horizontal(left: inner),
      child: CustomPaint(
        painter: _RoomPainter(wall: look.wall, floor: roomFloor(look.wall), u: u),
        child: LayoutBuilder(
          builder: (context, box) {
            final side = (box.maxHeight - 5.6 * u).clamp(10.0, 37.4 * u);
            return Stack(
              children: [
                // Кадр занятия занимает верх половины.
                Positioned(
                  top: 0.4 * u,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: CatalogArtAnim(
                      doing.artKey ?? kCloudIdleArtKey,
                      key: ValueKey(doing.artKey ?? kCloudIdleArtKey),
                      side: side,
                      fallbackKey: kCloudIdleArtKey,
                      whileLoading: _still(doing.artKey ?? kCloudIdleArtKey, side),
                    ),
                  ),
                ),
                // Нижняя строка: аватарка со временем во внешнем углу, рядом занятие.
                Positioned(
                  left: 1.6 * u,
                  right: 1.6 * u,
                  bottom: 2.2 * u,
                  child: Row(
                    textDirection: mine ? TextDirection.ltr : TextDirection.rtl,
                    children: [who, if (act != null) SizedBox(width: 0.9 * u), ?act],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  TextStyle _text(double size, FontWeight weight) =>
      TextStyle(fontFamily: 'Onest', fontSize: size, fontWeight: weight, color: _pen, height: 1);

  /// Неподвижный кадр занятия на время, пока качается анимация. Лист выбора
  /// уже положил его в кэш, поэтому половина не стоит пустой.
  Widget _still(String key, double side) {
    final url = CatalogService.instance.giftArt(key)?.stillUrl;
    if (url == null || url.isEmpty) return SizedBox.square(dimension: side);
    return StorageImage(imageUrl: url, width: side, height: side, fit: BoxFit.contain);
  }
}

/// Бумажная плашка с тонким контуром: без него на белой стене её не видно.
class _Chip extends StatelessWidget {
  const _Chip({required this.paper, required this.u, required this.child});

  final Color paper;
  final double u;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        height: 8 * u,
        decoration: ShapeDecoration(
          color: paper,
          shape: StadiumBorder(side: BorderSide(color: _pen.withValues(alpha: 0.12), width: 0.35 * u)),
        ),
        child: child,
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.mine, required this.paper, required this.side});

  final String url;
  final bool mine;
  final Color paper;
  final double side;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Фото в профиле нет: кружок с силуэтом, как на рабочем столе.
    final empty = Container(
      width: side,
      height: side,
      decoration: BoxDecoration(color: mine ? scheme.primary : scheme.tertiary, shape: BoxShape.circle),
      child: Icon(Icons.person_rounded, size: side * 0.72, color: paper),
    );
    if (url.isEmpty) return empty;
    // Аватарки лежат ссылкой pb://, её раскрывает StorageImage (с токеном
    // файла); с проверкой на http превью рисовало силуэт вместо лица.
    return ClipOval(
      child: StorageImage(
        imageUrl: url,
        width: side,
        height: side,
        fit: BoxFit.cover,
        memCacheWidth: (side * 3).toInt(),
        placeholder: (_, _) => empty,
        errorWidget: (_, _, _) => empty,
      ),
    );
  }
}

/// Стена в горошек и мягкий пол.
class _RoomPainter extends CustomPainter {
  const _RoomPainter({required this.wall, required this.floor, required this.u});

  final Color wall;
  final Color floor;
  final double u;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = wall);

    final paint = Paint()..color = floor;
    final step = 6.2 * u;
    for (var y = 2 * u + step / 2; y < size.height; y += step) {
      for (var x = 1.4 * u + step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.85 * u, paint);
      }
    }
    canvas.drawOval(
      Rect.fromLTRB(-0.14 * size.width, size.height - 11.5 * u, size.width * 1.14, size.height + 10.5 * u),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RoomPainter old) => old.wall != wall || old.floor != floor || old.u != u;
}
