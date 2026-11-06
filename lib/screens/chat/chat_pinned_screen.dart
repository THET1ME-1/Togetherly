import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/chat_msg.dart';
import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/common/app_dialog.dart';

/// Все закреплённые сообщения пары (06.11.2026, как в Telegram): пузыри по
/// датам, от старого к новому. Касание по пузырю или по стрелке закрывает
/// экран и отдаёт сообщение чату — тот прокручивает ленту к нему. Долгое
/// нажатие открепляет одно, кнопка внизу — все сразу.
class ChatPinnedScreen extends StatefulWidget {
  const ChatPinnedScreen({
    super.key,
    required this.pinned,
    required this.myUid,
    required this.partnerName,
    required this.quoteOf,
    required this.onUnpin,
  });

  /// По возрастанию времени сообщения (`pinnedMessages`).
  final List<ChatMsg> pinned;
  final String myUid;
  final String partnerName;

  /// Подпись сообщения: у голосового и фигурки текста нет.
  final String Function(ChatMsg) quoteOf;
  final Future<void> Function(ChatMsg) onUnpin;

  @override
  State<ChatPinnedScreen> createState() => _ChatPinnedScreenState();
}

/// «1 закреплённое», «2 закреплённых», «21 закреплённое».
String pinnedCountTitle(int n, String lang) {
  final one = (lang == 'ru' || lang == 'uk') ? n % 10 == 1 && n % 100 != 11 : n == 1;
  return trKey(one ? 'cpCountOne' : 'cpCountMany').replaceAll('{0}', '$n');
}

class _ChatPinnedScreenState extends State<ChatPinnedScreen> {
  late final List<ChatMsg> _items = [...widget.pinned];

  Future<void> _unpin(ChatMsg m) async {
    HapticFeedback.mediumImpact();
    setState(() => _items.removeWhere((x) => x.id == m.id));
    await widget.onUnpin(m);
    if (mounted && _items.isEmpty) Navigator.of(context).pop();
  }

  Future<void> _unpinAll() async {
    final ok = await AppDialog.confirm(
      context,
      message: trKey('cpUnpinAllAsk'),
      confirmLabel: trKey('cpUnpinAll'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final all = [..._items];
    setState(_items.clear);
    for (final m in all) {
      await widget.onUnpin(m);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = LocaleService.instance.language.code;
    final s = LocaleService.current;
    final rows = <Widget>[];
    DateTime? lastDay;
    for (final m in _items) {
      final d = DateTime.fromMillisecondsSinceEpoch(m.ts);
      final day = DateTime(d.year, d.month, d.day);
      if (day != lastDay) {
        rows.add(_dateChip(cs, s.chatDateHeader(day)));
        lastDay = day;
      }
      rows.add(_bubbleRow(cs, m));
    }
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          pinnedCountTitle(_items.length, lang),
          style: TextStyle(fontFamily: ProfileTheme.displayFont, fontSize: 19, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                children: [
                  ...rows,
                  const SizedBox(height: 10),
                  Text(
                    trKey('cpHoldHint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.tonal(
                  onPressed: _items.isEmpty ? null : _unpinAll,
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  child: Text(trKey('cpUnpinAll')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateChip(ColorScheme cs, String label) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
          child: Text(
            label,
            style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
          ),
        ),
      );

  Widget _bubbleRow(ColorScheme cs, ChatMsg m) {
    final mine = m.uid == widget.myUid;
    final bg = mine ? cs.primary : cs.surfaceContainerHigh;
    final fg = mine ? cs.onPrimary : cs.onSurface;
    final t = DateTime.fromMillisecondsSinceEpoch(m.ts);
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final name = widget.partnerName.trim().isEmpty ? m.name : widget.partnerName.trim();
    final bubble = Flexible(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(mine ? 20 : 6),
          bottomRight: Radius.circular(mine ? 6 : 20),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(m),
          onLongPress: () => _unpin(m),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!mine)
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.primary),
                  ),
                Text(
                  widget.quoteOf(m),
                  style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 15.5, height: 1.35, color: fg),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    time,
                    style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 11.5, color: fg.withValues(alpha: 0.72)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final jump = IconButton.filledTonal(
      onPressed: () => Navigator.of(context).pop(m),
      tooltip: trKey('cpShowInChat'),
      iconSize: 18,
      style: IconButton.styleFrom(backgroundColor: cs.surfaceContainerHigh, foregroundColor: cs.onSurfaceVariant),
      icon: const Icon(Icons.arrow_forward_rounded),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: mine ? [const SizedBox(width: 40), jump, const SizedBox(width: 6), bubble] : [bubble, const SizedBox(width: 6), jump, const SizedBox(width: 40)],
      ),
    );
  }
}
