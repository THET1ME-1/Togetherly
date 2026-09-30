import 'package:flutter/widgets.dart';

/// Поднимает нижний лист над клавиатурой.
///
/// Модальный лист Flutter сам клавиатуру не обходит: он стоит от низа экрана,
/// и поле в его конце оказывается под ней (отзыв из Play 02.09.2026 про
/// комментарии к воспоминаниям). Обёртка отдаёт высоту клавиатуры отступом
/// снизу, а детям показывает уже нулевой отступ — иначе запасы под клавиатуру
/// внутри листа прибавились бы второй раз.
class LiftAboveKeyboard extends StatelessWidget {
  const LiftAboveKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: child,
      ),
    );
  }
}

/// Открыта ли клавиатура — по контексту ВЫШЕ `Scaffold`.
///
/// Плавающая панель поверх прокрутки встаёт прямо над клавиатурой, а поле
/// ввода прокручивается к нижнему краю экрана, то есть ровно под панель.
/// Поэтому на время набора панель прячут. Спрашивать надо снаружи `Scaffold`:
/// своему `body` он показывает высоту клавиатуры нулём, и изнутри панель
/// клавиатуры не увидит никогда.
bool keyboardOpen(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom > 0;
