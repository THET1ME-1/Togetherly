import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_msg.dart';
import '../models/memory.dart';
import '../models/pair_data.dart';
import '../models/user_data.dart';
import '../services/chat_service.dart';
import '../services/firebase_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/storage_image.dart';
import 'memory_lane_screen.dart';

/// Цена смены фона чата в монетах (зеркало CONSUMABLE_PRICES на сервере).
const int _kChatBgPrice = 20;
const String _kChatBgAction = 'chat_background';

/// Постоянный текстовый чат пары. История целиком в RTDB → ноль Firestore-чтений.
class ChatScreen extends StatefulWidget {
  final PairData pairData;
  final AppTheme theme;
  final String myDisplayName;
  final UserData? userData;

  const ChatScreen({
    super.key,
    required this.pairData,
    required this.theme,
    required this.myDisplayName,
    this.userData,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chat = ChatService.instance;
  final FirebaseService _fb = FirebaseService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  String get _groupId => widget.pairData.pairId;
  String get _myUid => _fb.uid ?? '';
  AppTheme get _t => widget.theme;

  /// Пины для @-подсказок (грузятся один раз, cache-first → 0 серверных чтений).
  List<Memory> _pins = [];

  /// Сообщение, которое сейчас редактируем (null — обычная отправка).
  ChatMsg? _editing;

  /// Прикреплённый к набираемому сообщению пин.
  Memory? _attachedPin;

  /// Текущий @-запрос для подсказок (null — подсказок нет).
  String? _mentionQuery;
  int _lastMessageTs = 0;

  /// Путь к локальному фону чата (null — фон не задан).
  String? _bgPath;

  /// Окно подгрузки истории. Не грузим всю переписку сразу — стартуем с
  /// небольшого окна и расширяем его при прокрутке к началу (экономит трафик
  /// RTDB: onValue иначе тянул бы весь срез на каждое новое сообщение).
  static const int _kPageSize = 30;
  int _limit = _kPageSize;
  late Stream<List<ChatMsg>> _messagesStream;
  bool _loadingMore = false;
  bool _hasMore = true;
  double? _retainFromBottom;
  bool _didInitialScroll = false;
  bool _lastIsMine = false;

  /// Идёт отправка — блокирует повторный тап, чтобы не уехал дубликат при плохой сети.
  bool _sending = false;

  /// Ключ маркера «Новые сообщения» — чтобы открыть чат на месте остановки чтения.
  final GlobalKey _unreadKey = GlobalKey();
  bool _hasUnreadMarker = false;

  /// ts последнего прочтения на момент ОТКРЫТИЯ чата — фиксируем до markRead,
  /// чтобы отрисовать разделитель «Новые сообщения» над первым непрочитанным.
  int _openLastRead = -1;

  /// Последний полученный срез — фолбэк, пока пересоздаём поток при пагинации
  /// (иначе StreamBuilder на миг показал бы спиннер вместо списка).
  List<ChatMsg> _lastMessages = const [];

  /// Минимальный ts прочтения среди остальных участников. Своё сообщение
  /// «прочитано» (✓✓), если его ts ≤ этого значения, иначе «отправлено» (✓).
  int _partnerReadTs = 0;
  StreamSubscription<Map<String, int>>? _readsSub;

  @override
  void initState() {
    super.initState();
    // Пока этот чат открыт — foreground-пуш о новом сообщении не дублируем.
    FirebaseService.activeChatGroupId = _groupId;
    _messagesStream = _chat.watchMessages(_groupId, limit: _limit);
    _captureUnreadAnchor();
    _watchPartnerReads();
    _chat.ensureMember(_groupId);
    _loadPins();
    _loadBackground();
    _controller.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
  }

  /// Фиксируем ts последнего прочтения ДО того, как markRead его перезапишет —
  /// нужно для разделителя «Новые сообщения».
  Future<void> _captureUnreadAnchor() async {
    final ts = await _chat.lastReadTs(_groupId);
    if (mounted) setState(() => _openLastRead = ts);
  }

  /// Слушаем статусы прочтения партнёра(ов) для галочек ✓/✓✓ на своих
  /// сообщениях. «Прочитано» = минимальный ts среди всех, кроме меня.
  void _watchPartnerReads() {
    _readsSub = _chat.watchReads(_groupId).listen(
      (reads) {
        if (!mounted) return;
        int? minOthers;
        reads.forEach((uid, ts) {
          if (uid == _myUid) return;
          minOthers = (minOthers == null || ts < minOthers!) ? ts : minOthers;
        });
        final next = minOthers ?? 0;
        if (next != _partnerReadTs) setState(() => _partnerReadTs = next);
      },
      onError: (e) => debugPrint('watchReads error: $e'),
    );
  }

  Future<void> _loadBackground() async {
    final path = await _chat.backgroundPath(_groupId);
    if (!mounted) return;
    if (path != null && File(path).existsSync()) {
      setState(() => _bgPath = path);
    } else if (path != null) {
      // Файл пропал (очистка кэша/переустановка) — сбрасываем.
      await _chat.clearBackground(_groupId);
    }
  }

  @override
  void dispose() {
    if (FirebaseService.activeChatGroupId == _groupId) {
      FirebaseService.activeChatGroupId = null;
    }
    _readsSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    if (_lastMessageTs > 0) _chat.markRead(_groupId, _lastMessageTs);
    super.dispose();
  }

  // ── Пагинация истории ───────────────────────────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    // Прокрутили к началу списка — подгружаем более старые сообщения.
    if (pos.pixels <= pos.minScrollExtent + 80) _loadMore();
  }

  void _loadMore() {
    _loadingMore = true;
    // Запоминаем расстояние от низа: контент добавится сверху, и так вьюпорт
    // не «прыгнет» после расширения окна.
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      _retainFromBottom = pos.maxScrollExtent - pos.pixels;
    }
    setState(() {
      _limit += _kPageSize;
      _messagesStream = _chat.watchMessages(_groupId, limit: _limit);
    });
  }

  /// Управление прокруткой после отрисовки очередного среза сообщений.
  void _afterMessagesLayout() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    // Подгрузили старые — восстанавливаем позицию (держим расстояние от низа).
    if (_loadingMore) {
      if (_retainFromBottom != null) {
        final target = (pos.maxScrollExtent - _retainFromBottom!)
            .clamp(0.0, pos.maxScrollExtent);
        _scrollController.jumpTo(target);
      }
      _loadingMore = false;
      _retainFromBottom = null;
      return;
    }

    // Первая отрисовка — встаём в самый низ, затем (если есть непрочитанные)
    // подскролливаем к маркеру «Новые сообщения» — туда, где остановилось чтение.
    if (!_didInitialScroll) {
      _didInitialScroll = true;
      _scrollController.jumpTo(pos.maxScrollExtent);
      if (_hasUnreadMarker) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToUnread());
      }
      return;
    }

    // Новое сообщение: прокручиваем вниз, только если пользователь уже у низа
    // или это его собственное сообщение (как в мессенджерах).
    final nearBottom = pos.maxScrollExtent - pos.pixels < 160;
    if (nearBottom || _lastIsMine) {
      _scrollController.jumpTo(pos.maxScrollExtent);
    }
  }

  /// Плавно показывает маркер «Новые сообщения» у верхнего края, если он
  /// уже построен (находится близко к низу — обычный случай при паре непрочитанных).
  void _scrollToUnread() {
    final ctx = _unreadKey.currentContext;
    if (ctx == null || !_scrollController.hasClients) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.12, // маркер чуть ниже верхнего края вьюпорта
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadPins() async {
    if (_groupId.isEmpty) return;
    final res = await _fb.loadMemories(
      groupId: _groupId,
      limit: 50,
      cacheFirst: true,
    );
    if (!mounted) return;
    setState(() => _pins = res.memories);
  }

  String _memoryLabel(Memory m) {
    final title = (m.title ?? '').trim();
    if (title.isNotEmpty) return title;
    final caption = (m.caption ?? '').trim();
    if (caption.isNotEmpty) {
      return caption.length > 30 ? '${caption.substring(0, 30)}…' : caption;
    }
    final loc = (m.locationName ?? '').trim();
    if (loc.isNotEmpty) return loc;
    final mus = (m.musicTitle ?? '').trim();
    if (mus.isNotEmpty) return mus;
    return m.typeLabel;
  }

  // ── @-подсказки ────────────────────────────────────────────────────────────

  void _onTextChanged() {
    final text = _controller.text;
    final sel = _controller.selection.baseOffset;
    if (sel < 0) {
      if (_mentionQuery != null) setState(() => _mentionQuery = null);
      return;
    }
    // Ищем последний '@' перед курсором без пробела после него.
    final upToCursor = text.substring(0, sel);
    final atIndex = upToCursor.lastIndexOf('@');
    if (atIndex == -1) {
      if (_mentionQuery != null) setState(() => _mentionQuery = null);
      return;
    }
    final afterAt = upToCursor.substring(atIndex + 1);
    if (afterAt.contains(' ') || afterAt.contains('\n')) {
      if (_mentionQuery != null) setState(() => _mentionQuery = null);
      return;
    }
    setState(() => _mentionQuery = afterAt.toLowerCase());
  }

  List<Memory> get _mentionResults {
    final q = _mentionQuery;
    if (q == null) return const [];
    final matches = _pins.where((m) {
      final label = _memoryLabel(m).toLowerCase();
      return q.isEmpty || label.contains(q);
    }).toList();
    return matches.take(6).toList();
  }

  /// Вставляет '@' в конец и открывает список пинов (кнопка-скрепка).
  void _triggerPinPicker() {
    final text = _controller.text;
    final needsAt = !text.endsWith('@');
    if (needsAt) {
      _controller.text = text.isEmpty || text.endsWith(' ')
          ? '$text@'
          : '$text @';
    }
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _focusNode.requestFocus();
    setState(() => _mentionQuery = '');
  }

  void _selectMention(Memory m) {
    // Убираем '@query' из поля и прикрепляем пин.
    final text = _controller.text;
    final sel = _controller.selection.baseOffset;
    final upToCursor = text.substring(0, sel);
    final atIndex = upToCursor.lastIndexOf('@');
    if (atIndex != -1) {
      final newText = text.substring(0, atIndex) + text.substring(sel);
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(offset: atIndex);
    }
    setState(() {
      _attachedPin = m;
      _mentionQuery = null;
    });
  }

  // ── Отправка / редактирование ───────────────────────────────────────────────

  Future<void> _send() async {
    // Защита от повторной отправки: при плохой сети await может «висеть»,
    // и повторный тап по кнопке отправил бы дубликат.
    if (_sending) return;
    final text = _controller.text.trim();
    final editing = _editing;
    final pin = _attachedPin;
    if (text.isEmpty && pin == null) return;

    // Оптимистично очищаем ввод СРАЗУ (до сети). RTDB с offline-persistence
    // ставит одну запись в очередь и доставит её ровно один раз при реконнекте,
    // поэтому очистка до await безопасна и исключает дубликаты.
    _sending = true;
    _controller.clear();
    setState(() {
      _editing = null;
      _attachedPin = null;
      _mentionQuery = null;
    });

    try {
      if (editing != null) {
        await _chat.edit(
          groupId: _groupId,
          messageId: editing.id,
          newText: text,
        );
      } else {
        await _chat.send(
          groupId: _groupId,
          senderName: widget.myDisplayName,
          text: text.isEmpty ? '📌' : text,
          pinId: pin?.id,
          pinTitle: pin != null ? _memoryLabel(pin) : null,
          pinThumb: pin != null ? _memoryThumb(pin) : null,
        );
      }
    } finally {
      _sending = false;
    }
  }

  void _startEdit(ChatMsg msg) {
    setState(() {
      _editing = msg;
      _attachedPin = null;
      _mentionQuery = null;
    });
    _controller.text = msg.text;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _focusNode.requestFocus();
  }

  Future<void> _confirmDelete(ChatMsg msg) async {
    final s = LocaleService.current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.chatDeleteConfirm(msg.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
            child: Text(s.chatDeleteMessage),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _chat.delete(groupId: _groupId, messageId: msg.id);
    }
  }

  void _openPin(String pinId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryLaneScreen(
          pairData: widget.pairData,
          theme: _t,
          initialMemoryId: pinId,
        ),
        settings: const RouteSettings(name: '/memory_lane'),
      ),
    );
  }

  // ── Фон чата ────────────────────────────────────────────────────────────────

  Future<void> _changeBackground() async {
    final s = LocaleService.current;
    final hasBg = _bgPath != null;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/logo/logo.jpg',
                      width: 30,
                      height: 30,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    s.chatBgTitle,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.image_outlined, color: _t.primary),
              title: Text(hasBg ? s.chatBgChange : s.chatBgSet),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/icons/coin.webp',
                      width: 18, height: 18),
                  const SizedBox(width: 3),
                  Text('$_kChatBgPrice',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              onTap: () => Navigator.pop(ctx, 'change'),
            ),
            if (hasBg)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.shade400),
                title: Text(s.chatBgRemove),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == 'remove') {
      await _chat.clearBackground(_groupId);
      if (mounted) setState(() => _bgPath = null);
      return;
    }
    if (action != 'change') return;

    final ud = widget.userData;
    if (ud == null) return;

    if (ud.coins < _kChatBgPrice) {
      _toast(s.notEnoughCoins);
      return;
    }

    // Подтверждение с предупреждением о цене каждой смены.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.chatBgTitle),
        content: Text(s.chatBgConfirmBody(_kChatBgPrice)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _t.primary),
            child: Text(s.buyThemeConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Сначала выбираем фото — если пользователь отменит, списания не будет.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;

    // Списываем монеты на сервере (каждый раз).
    final ok = await ud.spendCoins(_kChatBgAction);
    if (!ok) {
      _toast(s.notEnoughCoins);
      return;
    }

    // Копируем во внутреннюю папку приложения, чтобы фон пережил очистку кэша.
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.contains('.')
          ? picked.path.substring(picked.path.lastIndexOf('.'))
          : '.jpg';
      final dest =
          '${dir.path}/chat_bg_${_groupId}_${DateTime.now().millisecondsSinceEpoch}$ext';
      await File(picked.path).copy(dest);
      // Удаляем прежний фон-файл, чтобы не копить мусор.
      final old = _bgPath;
      await _chat.setBackgroundPath(_groupId, dest);
      if (old != null && old != dest) {
        try {
          final f = File(old);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _bgPath = dest);
        _toast(s.chatBgCharged);
      }
    } catch (e) {
      _toast('Не удалось сохранить фон');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showMessageMenu(ChatMsg msg) {
    final s = LocaleService.current;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
            ListTile(
              leading: Icon(Icons.edit_rounded, color: _t.primary),
              title: Text(s.chatEditMessage),
              onTap: () {
                Navigator.pop(ctx);
                _startEdit(msg);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Colors.red.shade400),
              title: Text(s.chatDeleteMessage),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(msg);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Базовый набор системных эмодзи-реакций.
  static const List<String> _reactionEmojis = [
    '❤️', '😂', '👍', '😮', '😢', '🔥',
  ];

  /// Пикер реакций (по двойному тапу). Тап по уже выбранному эмодзи — снимает.
  void _showReactionPicker(ChatMsg msg) {
    final mine = msg.reactions[_myUid];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in _reactionEmojis)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _chat.setReaction(
                          groupId: _groupId,
                          messageId: msg.id,
                          emoji: mine == e ? null : e,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: mine == e
                              ? _t.primary.withOpacity(0.18)
                              : Colors.transparent,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 30)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Чипы-реакции под баблом: агрегируем эмодзи по количеству. Тап по чипу
  /// со своей реакцией снимает её, по чужой — ставит такую же себе.
  Widget _buildReactionChips(ChatMsg msg, bool isMine) {
    final counts = <String, int>{};
    for (final e in msg.reactions.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    final mine = msg.reactions[_myUid];
    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        bottom: 2,
        left: isMine ? 0 : 6,
        right: isMine ? 6 : 0,
      ),
      child: Wrap(
        spacing: 4,
        children: [
          for (final entry in counts.entries)
            GestureDetector(
              onTap: () => _chat.setReaction(
                groupId: _groupId,
                messageId: msg.id,
                emoji: mine == entry.key ? null : entry.key,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: mine == entry.key
                        ? _t.primary
                        : Colors.grey.shade300,
                    width: mine == entry.key ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.key, style: const TextStyle(fontSize: 13)),
                    if (entry.value > 1) ...[
                      const SizedBox(width: 3),
                      Text(
                        '${entry.value}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    return Scaffold(
      backgroundColor: _t.bgGradient.last,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: Colors.grey.shade900,
        // Кнопка фона — слева сверху, рядом с «назад».
        leadingWidth: 96,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BackButton(),
            IconButton(
              padding: EdgeInsets.zero,
              tooltip: s.chatBgTitle,
              icon: Icon(Icons.wallpaper_rounded, color: _t.primary),
              onPressed: _changeBackground,
            ),
          ],
        ),
        title: Text(
          s.chatTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Stack(
        children: [
          // Свой фон чата (локальный, у каждого свой).
          if (_bgPath != null)
            Positioned.fill(
              child: Image.file(
                File(_bgPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          // Лёгкая вуаль для читаемости пузырей поверх любого фото.
          if (_bgPath != null)
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.06)),
            ),
          Column(
            children: [
              Expanded(
            child: StreamBuilder<List<ChatMsg>>(
              stream: _messagesStream,
              builder: (context, snap) {
                // Во время пересоздания потока (пагинация) держим прошлый срез.
                if (snap.data != null) _lastMessages = snap.data!;
                final messages = snap.data ?? _lastMessages;
                if (messages.isNotEmpty) {
                  _lastMessageTs = messages.last.ts;
                  _lastIsMine = messages.last.uid == _myUid;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _chat.markRead(_groupId, _lastMessageTs);
                  });
                }
                // Меньше, чем просили → достигли начала истории.
                _hasMore = messages.length >= _limit;

                if (snap.connectionState == ConnectionState.waiting &&
                    messages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      s.chatEmpty,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  );
                }

                final items = _buildItems(messages);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _afterMessagesLayout();
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _buildItem(items[i]),
                );
              },
            ),
          ),
              if (_mentionQuery != null && _mentionResults.isNotEmpty)
                _buildMentionList(),
              _buildComposer(s),
            ],
          ),
        ],
      ),
    );
  }

  /// Превращает плоский список сообщений в список элементов с разделителями:
  /// заголовки дат (как в Telegram) и маркер «Новые сообщения».
  List<Object> _buildItems(List<ChatMsg> messages) {
    final items = <Object>[];
    DateTime? lastDay;
    bool unreadShown = false;
    for (final m in messages) {
      final d = DateTime.fromMillisecondsSinceEpoch(m.ts);
      final day = DateTime(d.year, d.month, d.day);
      if (lastDay == null || day != lastDay) {
        items.add(_DateHeader(day));
        lastDay = day;
      }
      // Разделитель — над первым непрочитанным сообщением партнёра.
      if (!unreadShown &&
          _openLastRead > 0 &&
          m.ts > _openLastRead &&
          m.uid != _myUid) {
        items.add(const _UnreadMarker());
        unreadShown = true;
      }
      items.add(m);
    }
    _hasUnreadMarker = unreadShown;
    return items;
  }

  Widget _buildItem(Object item) {
    if (item is _DateHeader) return _buildDateHeader(item.day);
    if (item is _UnreadMarker) return _buildUnreadMarker();
    return _buildBubble(item as ChatMsg);
  }

  Widget _buildDateHeader(DateTime day) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          LocaleService.current.chatDateHeader(day),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadMarker() {
    return Container(
      key: _unreadKey,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: _t.primary.withOpacity(0.12),
      child: Center(
        child: Text(
          LocaleService.current.chatNewMessages,
          style: TextStyle(
            color: _t.primary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMsg msg) {
    final isMine = msg.uid == _myUid;
    final s = LocaleService.current;

    final bubbleColor = isMine ? _t.primary : Colors.white;
    final textColor = isMine ? Colors.white : Colors.grey.shade900;
    final metaColor = isMine
        ? Colors.white.withOpacity(0.8)
        : Colors.grey.shade500;

    Widget content;
    if (msg.deleted) {
      content = Text(
        s.chatDeletedPlaceholder,
        style: TextStyle(
          color: isMine ? Colors.white70 : Colors.grey.shade400,
          fontStyle: FontStyle.italic,
          fontSize: 14,
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (msg.pinId != null) _buildPinChip(msg, isMine),
          if (msg.text.isNotEmpty)
            Text(
              msg.text,
              style: TextStyle(color: textColor, fontSize: 15, height: 1.25),
            ),
        ],
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            // Двойной тап — реакции (на любое сообщение, кроме удалённого).
            onDoubleTap: msg.deleted ? null : () => _showReactionPicker(msg),
            onLongPress:
                (isMine && !msg.deleted) ? () => _showMessageMenu(msg) : null,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              content,
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (msg.isEdited) ...[
                    Text(
                      s.chatEdited,
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: metaColor,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    _formatTime(msg.editedTs ?? msg.ts),
                    style: TextStyle(fontSize: 10, color: metaColor),
                  ),
                  // Галочки прочтения только на своих неудалённых сообщениях.
                  if (isMine && !msg.deleted) ...[
                    const SizedBox(width: 4),
                    Icon(
                      msg.ts <= _partnerReadTs
                          ? Icons.done_all_rounded
                          : Icons.done_rounded,
                      size: 14,
                      color: msg.ts <= _partnerReadTs
                          ? const Color(0xFF8FD3FF) // прочитано — голубые ✓✓
                          : metaColor, // отправлено — приглушённая ✓
                    ),
                  ],
                ],
              ),
            ],
          ),
            ),
          ),
          if (msg.reactions.isNotEmpty) _buildReactionChips(msg, isMine),
        ],
      ),
    );
  }

  /// URL миниатюры пина: обложка для музыки/книги, кадр/фото для остального.
  String? _memoryThumb(Memory m) {
    if (m.type == MemoryType.music) return m.musicCoverUrl;
    if (m.type == MemoryType.book) return m.bookCoverUrl;
    return m.imageUrl ??
        (m.imageUrls?.isNotEmpty == true ? m.imageUrls!.first : null);
  }

  /// Квадратная миниатюра пина: картинка по [thumb], иначе [emoji].
  Widget _pinThumbView({
    required String? thumb,
    required String emoji,
    required double size,
    double radius = 6,
    double emojiSize = 20,
  }) {
    final fallback = Center(
      child: Text(emoji, style: TextStyle(fontSize: emojiSize)),
    );
    if (thumb == null || thumb.isEmpty) {
      return SizedBox(width: size, height: size, child: fallback);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: StorageImage(
          imageUrl: thumb,
          fit: BoxFit.cover,
          memCacheWidth: 120,
          memCacheHeight: 120,
          errorWidget: (_, _, _) => fallback,
        ),
      ),
    );
  }

  /// Чип прикреплённого пина внутри сообщения — с миниатюрой предпросмотра.
  Widget _buildPinChip(ChatMsg msg, bool isMine) {
    // Миниатюра: из самого сообщения, иначе ищем пин в загруженном списке.
    Memory? mem;
    for (final p in _pins) {
      if (p.id == msg.pinId) {
        mem = p;
        break;
      }
    }
    final thumb = msg.pinThumb ?? (mem != null ? _memoryThumb(mem) : null);
    final emoji = mem?.typeEmoji ?? '📌';
    return GestureDetector(
      onTap: () => _openPin(msg.pinId!),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isMine ? Colors.white.withOpacity(0.20) : _t.primaryLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pinThumbView(
              thumb: thumb,
              emoji: emoji,
              size: 36,
              radius: 8,
              emojiSize: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                msg.pinTitle ?? 'Pin',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isMine ? Colors.white : _t.primary,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildMentionList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      color: Colors.white,
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: _mentionResults.map((m) {
          return ListTile(
            dense: true,
            leading: _pinThumbView(
              thumb: _memoryThumb(m),
              emoji: m.typeEmoji,
              size: 40,
            ),
            title: Text(
              _memoryLabel(m),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(m.typeLabel,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            onTap: () => _selectMention(m),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildComposer(AppStrings s) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      // Когда клавиатура открыта, Scaffold уже поднимает композер над ней —
      // добавлять инсет системной навигации не нужно (иначе двойной отступ
      // и большой зазор между полем и клавиатурой).
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 +
            (MediaQuery.of(context).viewInsets.bottom > 0
                ? 0
                : MediaQuery.of(context).viewPadding.bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editing != null)
            _buildBanner(
              icon: Icons.edit_rounded,
              label: '${s.chatEditMessage}: ${_editing!.text}',
              onClose: () {
                setState(() => _editing = null);
                _controller.clear();
              },
            ),
          if (_attachedPin != null)
            _buildBanner(
              icon: Icons.push_pin_rounded,
              label: _memoryLabel(_attachedPin!),
              onClose: () => setState(() => _attachedPin = null),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Прикрепить пин — вставляет '@' и открывает подсказки
              GestureDetector(
                onTap: _triggerPinPicker,
                child: Container(
                  width: 40,
                  height: 44,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.push_pin_rounded,
                    color: _t.primary,
                    size: 22,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: s.chatHint,
                    hintMaxLines: 1,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _send,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _t.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _editing != null
                        ? Icons.check_rounded
                        : Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBanner({
    required IconData icon,
    required String label,
    required VoidCallback onClose,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: _t.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: _t.primary, width: 3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _t.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: Colors.grey.shade500,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Элемент-разделитель: заголовок даты в ленте чата.
class _DateHeader {
  final DateTime day;
  const _DateHeader(this.day);
}

/// Элемент-разделитель: маркер «Новые сообщения».
class _UnreadMarker {
  const _UnreadMarker();
}
