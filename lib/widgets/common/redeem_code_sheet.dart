import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/locale_service.dart';
import '../../utils/redeem_code.dart';
import '../app_sheet.dart';

/// Ввод кода из бота крупными ячейками: `TG-4F2A-B79C`.
///
/// Раньше это была одна строка обычного поля: код набирали вслепую, дефисы
/// ставили руками, а про алфавит без нуля и единицы никто не знал — набрал
/// «O» вместо «0», получил отказ сервера и гадаешь, где ошибся.
///
/// Здесь символ вне алфавита просто не вводится, дефисы расставляются сами, а
/// клавиатура ограничена буквами и цифрами.
class RedeemCodeSheet extends StatefulWidget {
  const RedeemCodeSheet({super.key});

  /// Открывает лист и возвращает код без дефисов либо null, если закрыли.
  static Future<String?> show(BuildContext context) =>
      showAppSheet<String>(context, builder: (_) => const RedeemCodeSheet());

  @override
  State<RedeemCodeSheet> createState() => _RedeemCodeSheetState();
}

class _RedeemCodeSheetState extends State<RedeemCodeSheet> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  String get _value => RedeemCode.digits(_ctrl.text);

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!RedeemCode.isComplete(_value)) return;
    Navigator.pop(context, _value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = LocaleService.current;
    final ready = RedeemCode.isComplete(_value);

    return SheetScaffold(
      title: s.redeemCodeTitle,
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: ready ? _submit : null,
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text(s.redeemCodeApply),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.redeemCodeHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            // Ячейки — картинка, а текст живёт в невидимом поле под ними:
            // так остаются системная вставка из буфера и автоподстановка кода,
            // ради которых люди и копируют его из чата с ботом.
            Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 0,
                  child: SizedBox(
                    height: 1,
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [_CodeFormatter()],
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _focus.requestFocus,
                  child: _cells(cs),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              s.redeemCodeAlphabet,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cells(ColorScheme cs) {
    final v = _value;
    // Две группы по четыре после префикса: ровно так код показывает бот.
    final groups = <List<int>>[
      [0, 1],
      [2, 3, 4, 5],
      [6, 7, 8, 9],
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var g = 0; g < groups.length; g++) ...[
          if (g > 0)
            Text('–',
                style: TextStyle(fontSize: 20, color: cs.onSurfaceVariant)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final i in groups[g])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _cell(cs, i < v.length ? v[i] : null,
                      active: i == v.length),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _cell(ColorScheme cs, String? ch, {required bool active}) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 34,
        height: 46,
        decoration: BoxDecoration(
          color: ch == null ? cs.surfaceContainerHighest : cs.primaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          ch ?? '',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
      );
}

/// Пропускает только символы алфавита кода и держит длину.
class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue value,
  ) {
    final text = RedeemCode.digits(value.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
