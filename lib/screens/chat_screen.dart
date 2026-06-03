import 'package:flutter/material.dart';

import '../models/chat_msg.dart';
import '../models/memory.dart';
import '../models/pair_data.dart';
import '../services/chat_service.dart';
import '../services/firebase_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import 'memory_lane_screen.dart';

/// Постоянный текстовый чат пары. История целиком в RTDB → ноль Firestore-чтений.
class ChatScreen extends StatefulWidget {
  final PairData pairData;
  final AppTheme theme;
  final String myDisplayName;

  const ChatScreen({
    super.key,
    required this.pairData,
    required this.theme,
    required this.myDisplayName,
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

  @override
  void initState() {
    super.initState();
    _chat.ensureMember(_groupId);
    _loadPins();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    if (_lastMessageTs > 0) _chat.markRead(_groupId, _lastMessageTs);
    super.dispose();
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
    final text = _controller.text.trim();
    if (text.isEmpty && _attachedPin == null) return;

    if (_editing != null) {
      await _chat.edit(
        groupId: _groupId,
        messageId: _editing!.id,
        newText: text,
      );
    } else {
      await _chat.send(
        groupId: _groupId,
        senderName: widget.myDisplayName,
        text: text.isEmpty ? '📌' : text,
        pinId: _attachedPin?.id,
        pinTitle: _attachedPin != null ? _memoryLabel(_attachedPin!) : null,
      );
    }
    _controller.clear();
    setState(() {
      _editing = null;
      _attachedPin = null;
      _mentionQuery = null;
    });
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
        title: Text(
          s.chatTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMsg>>(
              stream: _chat.watchMessages(_groupId),
              builder: (context, snap) {
                final messages = snap.data ?? const [];
                if (messages.isNotEmpty) {
                  _lastMessageTs = messages.last.ts;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _chat.markRead(_groupId, _lastMessageTs);
                  });
                }
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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _buildBubble(messages[i]),
                );
              },
            ),
          ),
          if (_mentionQuery != null && _mentionResults.isNotEmpty)
            _buildMentionList(),
          _buildComposer(s),
        ],
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
          if (msg.pinId != null)
            GestureDetector(
              onTap: () => _openPin(msg.pinId!),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isMine
                      ? Colors.white.withOpacity(0.20)
                      : _t.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.push_pin_rounded,
                        size: 14,
                        color: isMine ? Colors.white : _t.primary),
                    const SizedBox(width: 5),
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
                  ],
                ),
              ),
            ),
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
      child: GestureDetector(
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
                ],
              ),
            ],
          ),
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
            leading: Text(m.typeEmoji, style: const TextStyle(fontSize: 20)),
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
