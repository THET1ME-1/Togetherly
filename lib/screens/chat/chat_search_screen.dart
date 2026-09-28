import 'dart:async';

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/chat_msg.dart';
import '../../models/chat_search.dart';
import '../../models/shape_note.dart';
import '../../models/voice_note.dart';
import '../../services/locale_service.dart';
import '../../services/pb_data_service.dart';
import '../../utils/safe_launch.dart';
import '../../widgets/common/m3_loading.dart';
import '../../widgets/storage_image.dart';
import 'note_viewer_screen.dart';

/// Поиск по переписке пары (28.09.2026).
///
/// На телефоне лежит только хвост чата, поэтому ищет сервер (hotpath) по всей
/// истории. Касание по найденному закрывает экран и отдаёт сообщение чату —
/// тот подгружает ленту до него и подсвечивает. Кружки открываются сразу в
/// полноэкранном просмотре, ссылки — ещё и в браузере.
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({super.key, required this.groupId, required this.myUid, this.searcher});

  final String groupId;
  final String myUid;

  /// Подмена сервера в тестах: по фильтру отдаёт найденное (null — нет связи).
  @visibleForTesting
  final Future<List<ChatMsg>?> Function(String filter)? searcher;

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  static const int _page = 40;

  final TextEditingController _query = TextEditingController();
  ChatSearchKind _kind = ChatSearchKind.all;
  Timer? _debounce;

  List<ChatMsg> _items = const [];
  bool _loading = false;
  bool _failed = false;
  bool _hasMore = false;

  /// Номер запроса: ответ устаревшего запроса (человек уже печатает дальше)
  /// не должен затереть свежий.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(reset: true));
  }

  void _setKind(ChatSearchKind k) {
    if (k == _kind) return;
    setState(() => _kind = k);
    _search(reset: true);
  }

  Future<void> _search({required bool reset}) async {
    final before = reset || _items.isEmpty ? null : _items.last.ts;
    final filter = chatSearchFilter(
      groupId: widget.groupId,
      kind: _kind,
      query: _query.text,
      beforeTs: before,
    );
    final seq = ++_seq;
    if (filter == null) {
      setState(() {
        _items = const [];
        _hasMore = false;
        _failed = false;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) _items = const [];
    });
    final List<ChatMsg>? got;
    if (widget.searcher != null) {
      got = await widget.searcher!(filter);
    } else {
      final recs = await PbDataService().searchChat(filter, limit: _page);
      got = recs == null ? null : [for (final r in recs) ChatMsg.fromPb(r)];
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (got == null) {
        _failed = true;
        return;
      }
      final found = got;
      _items = reset ? found : [..._items, ...found];
      _hasMore = found.length >= _page;
    });
  }

  String _label(ChatSearchKind k) => switch (k) {
        ChatSearchKind.all => trKey('chatSearchAll'),
        ChatSearchKind.memories => trKey('chatSearchMemories'),
        ChatSearchKind.voice => trKey('chatSearchVoice'),
        ChatSearchKind.notes => trKey('chatSearchNotes'),
        ChatSearchKind.links => trKey('chatSearchLinks'),
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(reset: true),
                      decoration: InputDecoration(
                        hintText: trKey('chatSearchHint'),
                        filled: true,
                        fillColor: cs.surfaceContainerHigh,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: _query.clear,
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                itemCount: ChatSearchKind.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final k = ChatSearchKind.values[i];
                  final on = k == _kind;
                  return Material(
                    color: on ? cs.secondaryContainer : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(19),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(19),
                      onTap: () => _setKind(k),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: Text(
                            _label(k),
                            style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(child: _body(cs)),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme cs) {
    if (_loading && _items.isEmpty) {
      return Center(child: M3Loading(size: 44, color: cs.primary));
    }
    String? note;
    if (_failed) {
      note = trKey('chatSearchOffline');
    } else if (_items.isEmpty) {
      final short = _kind == ChatSearchKind.all &&
          _query.text.trim().length < kChatSearchMinChars;
      note = short ? trKey('chatSearchTypeMore') : trKey('chatSearchEmpty');
    }
    if (note != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            note,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Onest', fontSize: 15, color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    if (_kind == ChatSearchKind.notes) return _notesGrid(cs);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, i) {
        if (i == _items.length) return _more(cs);
        return _row(cs, _items[i], first: i == 0, last: i == _items.length - 1 && !_hasMore);
      },
    );
  }

  Widget _more(ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: _loading
              ? M3Loading(size: 32, color: cs.primary)
              : TextButton(
                  onPressed: () => _search(reset: false),
                  child: Text(LocaleService.current.loadMore),
                ),
        ),
      );

  String _when(ChatMsg m) {
    final d = DateTime.fromMillisecondsSinceEpoch(m.ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _row(ColorScheme cs, ChatMsg m, {required bool first, required bool last}) {
    final mine = m.uid == widget.myUid;
    final who = mine ? trKey('chatSearchYou') : m.name;
    // Блоки как в настройках: крайние скруглены сильнее, между ними зазор.
    final radius = BorderRadius.vertical(
      top: Radius.circular(first ? 24 : 8),
      bottom: Radius.circular(last ? 24 : 8),
    );
    Widget? lead;
    Widget body;
    Widget? trail;
    switch (_kind) {
      case ChatSearchKind.memories:
        final thumb = m.pinThumb ?? '';
        lead = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: 48,
            child: thumb.isEmpty
                ? ColoredBox(
                    color: cs.secondaryContainer,
                    child: Icon(Icons.push_pin_rounded, color: cs.onSecondaryContainer),
                  )
                : StorageImage(imageUrl: thumb, fit: BoxFit.cover, memCacheWidth: 144),
          ),
        );
        body = Text(m.pinTitle ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Onest', fontSize: 15, color: cs.onSurface));
      case ChatSearchKind.voice:
        lead = CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.mic_rounded, color: cs.onPrimaryContainer),
        );
        body = Text(VoiceNote.formatDuration(m.voice?.duration ?? Duration.zero),
            style: TextStyle(fontFamily: 'Onest', fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface));
      case ChatSearchKind.links:
        final link = firstLink(m.text);
        body = _highlighted(cs, m.text);
        if (link != null) {
          trail = IconButton(
            icon: Icon(Icons.open_in_new_rounded, color: cs.primary),
            onPressed: () => safeLaunchString(link),
          );
        }
      default:
        body = _highlighted(cs, m.text);
    }
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () => Navigator.of(context).pop(m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$who · ${_when(m)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: mine ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    body,
                  ],
                ),
              ),
              if (trail != null) trail,
            ],
          ),
        ),
      ),
    );
  }

  /// Текст с подсветкой совпадений. Длинный — с окном вокруг первого
  /// совпадения, чтобы найденное слово не уехало за многоточие.
  Widget _highlighted(ColorScheme cs, String text) {
    var t = text.replaceAll('\n', ' ');
    var ranges = matchRanges(t, _query.text);
    if (ranges.isNotEmpty && ranges.first.$1 > 60) {
      // Режем по границе слова, а не посреди него.
      var cut = ranges.first.$1 - 30;
      final space = t.lastIndexOf(' ', cut);
      if (space > 0 && cut - space < 20) cut = space + 1;
      t = '…${t.substring(cut)}';
      ranges = matchRanges(t, _query.text);
    }
    final base = TextStyle(fontFamily: 'Onest', fontSize: 15, height: 1.3, color: cs.onSurface);
    final spans = <TextSpan>[];
    var at = 0;
    for (final (a, b) in ranges) {
      if (a > at) spans.add(TextSpan(text: t.substring(at, a)));
      spans.add(TextSpan(
        text: t.substring(a, b),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: cs.onTertiaryContainer,
          backgroundColor: cs.tertiaryContainer,
        ),
      ));
      at = b;
    }
    if (at < t.length) spans.add(TextSpan(text: t.substring(at)));
    return Text.rich(TextSpan(style: base, children: spans), maxLines: 3, overflow: TextOverflow.ellipsis);
  }

  Widget _notesGrid(ColorScheme cs) {
    final notes = _items.where((m) => m.isNote).toList(growable: false);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
      ),
      itemCount: notes.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == notes.length) return _more(cs);
        final m = notes[i];
        final thumb = m.note?.thumbUrl ?? '';
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => NoteViewerScreen(notes: notes, index: i, myUid: widget.myUid),
          )),
          child: Column(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipOval(
                    child: thumb.isEmpty || !thumb.startsWith('pb://') && !thumb.startsWith('http')
                        ? ColoredBox(
                            color: cs.surfaceContainerHigh,
                            child: Icon(Icons.videocam_rounded, color: cs.onSurfaceVariant),
                          )
                        : StorageImage(imageUrl: thumb, fit: BoxFit.cover, memCacheWidth: 260),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ShapeNote.formatDuration(m.note?.duration ?? Duration.zero),
                style: TextStyle(fontFamily: 'Onest', fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}
