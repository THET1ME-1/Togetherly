import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/memory.dart';
import '../models/pair_book.dart';
import '../services/locale_service.dart';
import '../services/pair_book_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../utils/share_origin.dart';
import '../widgets/common/m3_loading.dart';

/// Книга пары: воспоминания за выбранные даты одним PDF.
///
/// Экран отдельный, а не лист: тут выбирают период, ждут сборку и делятся
/// готовым файлом — три шага подряд, и каждый со своим состоянием.
class PairBookScreen extends StatefulWidget {
  const PairBookScreen({
    super.key,
    required this.memories,
    required this.theme,
    required this.coupleTitle,
    required this.secretUnlocked,
  });

  /// Всё, что уже загружено в ленте: книга собирается из того же списка, что
  /// человек видит, — иначе в ней появилось бы то, чего он на экране не нашёл.
  final List<Memory> memories;
  final AppTheme theme;

  /// Имена пары для обложки.
  final String coupleTitle;

  /// Снят ли замок с секретных записей. Закрытый замок держит их вне книги.
  final bool secretUnlocked;

  @override
  State<PairBookScreen> createState() => _PairBookScreenState();
}

class _PairBookScreenState extends State<PairBookScreen> {
  BookPeriod _period = BookPeriod.allTime;
  DateTimeRange? _custom;
  bool _busy = false;
  int _done = 0;
  int _total = 0;
  File? _ready;

  AppStrings get _s => LocaleService.current;

  BookRange get _range {
    if (_period == BookPeriod.custom) {
      final picked = _custom;
      return BookRange(from: picked?.start, to: picked?.end);
    }
    return bookRangeOf(_period);
  }

  List<Memory> get _picked => memoriesForBook(
        widget.memories,
        from: _range.from,
        to: _range.to,
        secretUnlocked: widget.secretUnlocked,
      );

  String get _periodLabel {
    final range = _range;
    if (range.from == null) return _s.bookPeriodAll;
    final from = _s.dayLogDate(range.from!);
    final to = range.to == null ? '' : _s.dayLogDate(range.to!);
    return to.isEmpty ? from : '$from — $to';
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _custom,
    );
    if (picked == null) return;
    setState(() {
      _custom = picked;
      _period = BookPeriod.custom;
      _ready = null;
    });
  }

  Future<void> _build() async {
    final memories = _picked;
    if (memories.isEmpty) return;
    setState(() {
      _busy = true;
      _done = 0;
      _total = memories.length;
      _ready = null;
    });
    try {
      final file = await PairBookService.instance.build(
        memories: memories,
        coupleTitle: widget.coupleTitle,
        periodLabel: _periodLabel,
        footer: '${memories.length} ${_s.memoriesUnit(memories.length)}',
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _ready = file;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_s.bookFailed)));
    }
  }

  Future<void> _share() async {
    final file = _ready;
    if (file == null) return;
    // Якорь снимается ДО первого await: без него лист «Поделиться» не
    // открывается на iPad, и кнопка выглядит мёртвой (реджект 2.1(a)).
    final origin = shareOriginFromContext(context);
    await Share.shareXFiles([XFile(file.path)], sharePositionOrigin: origin);
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
    final picked = _picked;
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text(_s.bookTitle),
          backgroundColor: cs.surface,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              _s.bookLead,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 14,
                height: 1.35,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final period in BookPeriod.values)
                  ChoiceChip(
                    label: Text(_labelOf(period)),
                    selected: _period == period,
                    showCheckmark: false,
                    onSelected: (_) {
                      if (period == BookPeriod.custom) {
                        _pickDates();
                        return;
                      }
                      setState(() {
                        _period = period;
                        _ready = null;
                      });
                    },
                  ),
              ],
            ),
            if (_period == BookPeriod.custom) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDates,
                icon: const Icon(Icons.event_rounded),
                label: Text(_custom == null ? _s.bookPickDates : _periodLabel),
              ),
            ],
            const SizedBox(height: 22),
            _summary(cs, picked.length),
            const SizedBox(height: 22),
            if (_busy) ...[
              Center(child: M3Loading(color: cs.primary)),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                  value: _total == 0 ? null : _done / _total),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${_s.bookBuilding} · $_done / $_total',
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 12.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: picked.isEmpty ? null : _build,
                  icon: const Icon(Icons.menu_book_rounded),
                  label: Text(_s.bookBuild),
                ),
              ),
              if (_ready != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _share,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(_s.bookShare),
                  ),
                ),
              ],
            ],
            if (!widget.secretUnlocked &&
                widget.memories.any((m) => m.isSecret)) ...[
              const SizedBox(height: 18),
              Text(
                _s.bookSecretHint,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 12.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(ColorScheme cs, int count) {
    final tooMany = count > kBookSoftLimit;
    final text = count == 0
        ? _s.bookEmpty
        : '$count ${_s.memoriesUnit(count)} · $_periodLabel';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          if (tooMany) ...[
            const SizedBox(height: 6),
            Text(
              _s.bookTooMany,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 12.5,
                color: cs.error,
              ),
            ),
          ],
          if (_ready != null) ...[
            const SizedBox(height: 6),
            Text(
              _s.bookReady,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _labelOf(BookPeriod period) => switch (period) {
        BookPeriod.allTime => _s.bookPeriodAll,
        BookPeriod.thisYear => _s.bookPeriodYear,
        BookPeriod.thisMonth => _s.bookPeriodMonth,
        BookPeriod.custom => _s.bookPeriodCustom,
      };
}
