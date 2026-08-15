import 'dart:async';
import '../utils/safe_launch.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/symbol_catalog.dart';
import '../models/wish.dart';
import '../models/wish_category.dart';
import '../models/wish_reservation.dart';
import '../services/locale_service.dart';
import '../services/plus_service.dart';
import '../services/wish_repository.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../theme/profile_theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/stable_stream_builder.dart';
import '../widgets/storage_image.dart';
import '../widgets/wishes/wish_category_sheet.dart';
import '../widgets/wishes/wish_form_sheet.dart';
import 'plus_screen.dart';

/// «Хочу с тобой» — общий список желаний пары.
///
/// Две вкладки вместо одного списка с разделами: рабочая часть не растёт от
/// архива, а отметка уезжает во вторую вкладку и подтверждается снекбаром с
/// отменой. Записи общие, поэтому отметить сбывшимся может любой из двоих;
/// править и удалять желание оставлено автору.
class WishesScreen extends StatefulWidget {
  const WishesScreen({
    super.key,
    required this.theme,
    required this.groupId,
    required this.myUid,
    required this.myName,
    required this.partnerUid,
    required this.partnerName,
    this.myAvatarUrl,
    this.partnerAvatarUrl,
    this.openFulfilled = false,
    this.sharedUrl = '',
  });

  final AppTheme theme;
  final String groupId;
  final String myUid;
  final String myName;
  final String partnerUid;
  final String partnerName;

  /// Аватары обоих: подпись автора рисуется живым лицом, а не буквой.
  final String? myAvatarUrl;
  final String? partnerAvatarUrl;

  /// Открыть сразу архив — из строки «12 уже сбылось» на главной.
  final bool openFulfilled;

  /// Ссылка из «Поделиться»: экран открывается с готовой формой вещи.
  final String sharedUrl;

  @override
  State<WishesScreen> createState() => _WishesScreenState();
}

class _WishesScreenState extends State<WishesScreen> {
  final WishRepository _repo = WishRepository.instance;
  late bool _fulfilledTab = widget.openFulfilled;

  /// Свои категории пары. Держим их в состоянии экрана, а не тянем в каждый
  /// лист заново: список короткий, а лист открывается поверх и своего потока
  /// уже не получит.
  List<WishKind> _custom = const [];
  StreamSubscription<List<WishKind>>? _customSub;

  /// Вещи, которые я взял на себя. Список приходит только свой: у коллекции
  /// правило чтения `uid = auth.id`, автору сюрприз не виден вовсе.
  Set<String> _reserved = const {};
  Map<String, String> _reservationIds = const {};

  ColorScheme get _cs => Theme.of(context).colorScheme;
  bool get _ru => LocaleService.instance.isRussian;

  String _tr(String ru, String en) => _ru ? ru : en;

  @override
  void initState() {
    super.initState();
    _customSub = _repo.watchCategories(widget.groupId).listen((list) {
      if (mounted) setState(() => _custom = list);
    });
    _loadReservations();
    if (widget.sharedUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addShared());
    }
  }

  /// Форма вещи с подставленной ссылкой — сразу после открытия экрана.
  Future<void> _addShared() async {
    final draft = await _openForm(initialUrl: widget.sharedUrl);
    if (draft == null) return;
    await _repo.add(
      groupId: widget.groupId,
      title: draft.title,
      kind: draft.kind,
      note: draft.note,
      isItem: draft.isItem,
      price: draft.price,
      currency: draft.currency,
      url: draft.url,
      image: draft.image,
      shop: draft.shop,
    );
  }

  Future<void> _loadReservations() async {
    final list = await _repo.loadReservations(widget.groupId);
    if (!mounted) return;
    setState(() {
      _reserved = reservedWishIds(list);
      _reservationIds = {for (final r in list) r.wishId: r.id};
    });
  }

  /// «Дарю» и обратно. Состояние правим на месте: список свой, ждать ответа
  /// сервера ради переключения одной иконки незачем.
  Future<void> _toggleReserve(Wish wish) async {
    final taken = _reserved.contains(wish.id);
    if (taken) {
      final id = _reservationIds[wish.id] ?? '';
      setState(() {
        _reserved = {..._reserved}..remove(wish.id);
        _reservationIds = {..._reservationIds}..remove(wish.id);
      });
      await _repo.release(id);
      return;
    }
    final res = await _repo.reserve(groupId: widget.groupId, wishId: wish.id);
    if (res == null || !mounted) return;
    setState(() {
      _reserved = {..._reserved, wish.id};
      _reservationIds = {..._reservationIds, wish.id: res.id};
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _cs.inverseSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Text(
          _tr('Дарите вы — партнёр не узнает',
              "You're gifting it — your partner won't know"),
          style: AppFonts.onest(size: 14, color: _cs.onInverseSurface),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _customSub?.cancel();
    super.dispose();
  }

  /// Имя того, кто завёл желание. Чужой uid без имени бывает у мигрированных
  /// пар — тогда лучше промолчать, чем показать кусок идентификатора.
  String _nameOf(String uid) {
    if (uid == widget.myUid) return widget.myName;
    if (uid == widget.partnerUid) return widget.partnerName;
    return '';
  }

  String? _avatarOf(String uid) {
    if (uid == widget.myUid) return widget.myAvatarUrl;
    if (uid == widget.partnerUid) return widget.partnerAvatarUrl;
    return null;
  }

  // ── Действия ──────────────────────────────────────────────────────────────

  Future<void> _add() async {
    final draft = await _openForm();
    if (draft == null) return;
    await _repo.add(
      groupId: widget.groupId,
      title: draft.title,
      kind: draft.kind,
      note: draft.note,
      isItem: draft.isItem,
      price: draft.price,
      currency: draft.currency,
      url: draft.url,
      image: draft.image,
      shop: draft.shop,
    );
  }

  Future<void> _edit(Wish wish) async {
    final draft = await _openForm(existing: wish);
    if (draft == null) return;
    await _repo.edit(
      groupId: widget.groupId,
      wish: wish,
      title: draft.title,
      kind: draft.kind,
      note: draft.note,
      isItem: draft.isItem,
      price: draft.price,
      currency: draft.currency,
      url: draft.url,
      image: draft.image,
      shop: draft.shop,
    );
  }

  Future<WishDraft?> _openForm({Wish? existing, String initialUrl = ''}) =>
      showWishFormSheet(
        context,
        theme: widget.theme,
        customKinds: _custom,
        plusGate: PlusService.instance.gate,
        groupId: widget.groupId,
        uid: widget.myUid,
        initialUrl: initialUrl,
        existing: existing,
        onCreateCategory: _createCategory,
        onEditCategory: _editCategory,
        onOfferPlus: _offerPlus,
      );

  /// Своя категория — за Togetherly+. Уже созданными пользуются оба, даже если
  /// Плюс кончился: список пары не должен схлопываться задним числом.
  Future<WishKind?> _createCategory() async {
    final draft = await showWishCategorySheet(context, theme: widget.theme);
    if (draft == null) return null;
    return _repo.addCategory(
      groupId: widget.groupId,
      title: draft.title,
      symbol: draft.symbol,
      note: draft.note,
    );
  }

  Future<void> _editCategory(WishKind kind) async {
    final draft =
        await showWishCategorySheet(context, theme: widget.theme, existing: kind);
    if (draft == null) return;
    await _repo.editCategory(
      groupId: widget.groupId,
      kind: kind,
      title: draft.title,
      symbol: draft.symbol,
      note: draft.note,
    );
  }

  void _offerPlus() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlusScreen(scheme: ProfileTheme.themeFor(widget.theme).colorScheme),
        settings: const RouteSettings(name: '/plus'),
      ),
    );
  }

  Future<void> _toggle(Wish wish) async {
    if (wish.done) {
      await _repo.undone(groupId: widget.groupId, wish: wish);
      return;
    }
    final marked = await _repo.markDone(groupId: widget.groupId, wish: wish);
    if (marked == null || !mounted) return;
    _showDoneSnack(marked);
  }

  void _showDoneSnack(Wish wish) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _cs.inverseSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 5),
        content: Text(
          '${_tr('Сбылось', 'Came true')} · ${wish.title}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.onest(size: 14, color: _cs.onInverseSurface),
        ),
        action: SnackBarAction(
          label: _tr('ОТМЕНИТЬ', 'UNDO'),
          textColor: _cs.inversePrimary,
          onPressed: () => _repo.undone(groupId: widget.groupId, wish: wish),
        ),
      ),
    );
  }

  /// Заметка «как прошло» у сбывшегося: тап по карточке в архиве. В снекбаре
  /// второй кнопке места нет — Material оставляет действию одну.
  Future<void> _editDoneNote(Wish wish) async {
    final text = await AppDialog.prompt(
      context,
      title: _tr('Как прошло', 'How it went'),
      hint: _tr('Пара слов на память', 'A few words to remember'),
      initial: wish.doneNote,
      maxLength: 200,
      maxLines: 3,
    );
    if (text == null) return;
    await _repo.setDoneNote(
      groupId: widget.groupId,
      wish: wish,
      note: text,
    );
  }

  Future<void> _remove(Wish wish) async {
    final ok = await AppDialog.confirm(
      context,
      message: _tr(
        'Удалить «${wish.title}»? Желание пропадёт у обоих.',
        'Delete "${wish.title}"? It will disappear for both of you.',
      ),
      confirmLabel: _tr('Удалить', 'Delete'),
      destructive: true,
    );
    if (!ok) return;
    await _repo.remove(wish.id);
  }

  // ── Экран ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cs.surface,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _cs.surface,
        foregroundColor: _cs.onSurface,
        title: Text(
          _tr('Хочу с тобой', 'Want with you'),
          style: AppFonts.unbounded(size: 17, weight: 600, color: _cs.onSurface),
        ),
      ),
      body: StableStreamBuilder<List<Wish>>(
        create: () => _repo.watch(widget.groupId),
        keys: [widget.groupId],
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Wish>[];
          final dreaming = Wish.dreaming(all);
          final fulfilled = Wish.fulfilled(all);
          final shown = _fulfilledTab ? fulfilled : dreaming;

          return SafeArea(
            child: Column(
              children: [
                if (all.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: _Tabs(
                      scheme: _cs,
                      dreaming:
                          '${_tr('Мечтаем', 'Dreaming')} · ${dreaming.length}',
                      fulfilled:
                          '${_tr('Сбылось', 'Came true')} · ${fulfilled.length}',
                      fulfilledSelected: _fulfilledTab,
                      onChanged: (v) => setState(() => _fulfilledTab = v),
                    ),
                  ),
                Expanded(
                  child: all.isEmpty
                      ? _empty()
                      : shown.isEmpty
                          ? _emptyTab()
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                              itemCount: shown.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final wish = shown[i];
                                final mine = wish.authorUid == widget.myUid;
                                return _WishTile(
                                  wish: wish,
                                  scheme: _cs,
                                  ru: _ru,
                                  authorName: _nameOf(wish.authorUid),
                                  authorAvatarUrl: _avatarOf(wish.authorUid),
                                  onToggle: () => _toggle(wish),
                                  onTap: wish.done
                                      ? () => _editDoneNote(wish)
                                      : mine
                                          ? () => _edit(wish)
                                          : null,
                                  onLongPress:
                                      mine ? () => _remove(wish) : null,
                                  onReserve: mine
                                      ? null
                                      : () => _toggleReserve(wish),
                                  reserved: _reserved.contains(wish.id),
                                );
                              },
                            ),
                ),
                _addButton(),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Кнопка во всю ширину вместо расширенного FAB: действие тут одно, и оно
  /// главное — прятать его в угол незачем.
  Widget _addButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add_rounded, size: 22),
          label: Text(_tr('Добавить', 'Add')),
          style: FilledButton.styleFrom(
            backgroundColor: _cs.primaryContainer,
            foregroundColor: _cs.onPrimaryContainer,
            shape: const StadiumBorder(),
            textStyle: AppFonts.onest(size: 16, weight: 700),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cs.primaryContainer,
              ),
              alignment: Alignment.center,
              child: SymbolIcon('auto_awesome',
                  size: 40, color: _cs.onPrimaryContainer),
            ),
            const SizedBox(height: 14),
            Text(
              _tr('Пока пусто', 'Nothing yet'),
              style: AppFonts.unbounded(
                  size: 20, weight: 700, color: _cs.onSurface),
            ),
            const SizedBox(height: 10),
            Text(
              _tr(
                'Добавьте первое желание: фильм, который ждёте, место, куда '
                    'хотите, или что-то своё. Второй половине оно появится сразу.',
                'Add your first wish: a film you are waiting for, a place you '
                    'want to go, or anything of your own. Your partner will see '
                    'it right away.',
              ),
              textAlign: TextAlign.center,
              style: AppFonts.onest(
                  size: 14, height: 1.5, color: _cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          _fulfilledTab
              ? _tr('Сбывшегося пока нет. Отметьте желание галочкой, когда оно '
                  'случится.', 'Nothing has come true yet. Tick a wish off when '
                  'it happens.')
              : _tr('Все желания сбылись. Самое время придумать новое.',
                  'Every wish came true. Time to think of a new one.'),
          textAlign: TextAlign.center,
          style: AppFonts.onest(
              size: 14, height: 1.5, color: _cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Переключатель списков — связанная пара кнопок M3.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.scheme,
    required this.dreaming,
    required this.fulfilled,
    required this.fulfilledSelected,
    required this.onChanged,
  });

  final ColorScheme scheme;
  final String dreaming;
  final String fulfilled;
  final bool fulfilledSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // ClipRRect снаружи, а не clipBehavior у Container: заливка выбранной
    // половины рисуется дочерним Material и вылезала за скруглённые углы —
    // угол выглядел откушенным.
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 44,
        color: scheme.surfaceContainerHigh,
        child: Row(
          children: [
            _half(dreaming, !fulfilledSelected, () => onChanged(false)),
            _half(fulfilled, fulfilledSelected, () => onChanged(true)),
          ],
        ),
      ),
    );
  }

  Widget _half(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.onest(
                size: 13.5,
                weight: 600,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка желания: чекбокс, значок категории, название и подпись автора.
class _WishTile extends StatelessWidget {
  const _WishTile({
    required this.wish,
    required this.scheme,
    required this.ru,
    required this.authorName,
    required this.onToggle,
    this.authorAvatarUrl,
    this.onTap,
    this.onLongPress,
    this.onReserve,
    this.reserved = false,
  });

  final Wish wish;
  final ColorScheme scheme;
  final bool ru;
  final String authorName;
  final String? authorAvatarUrl;
  final VoidCallback onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Взять вещь на себя. Null у автора желания — ему этой кнопки не видно.
  final VoidCallback? onReserve;

  /// Уже взял. Знают об этом только даритель и сервер.
  final bool reserved;

  @override
  Widget build(BuildContext context) {
    final done = wish.done;
    final s = LocaleService.current;

    // Сбывшееся садится на контейнер ниже — тем же приёмом гаснут выполненные
    // шаги онбординга.
    final background =
        done ? scheme.surfaceContainerLow : scheme.surfaceContainerHigh;
    final leadBackground =
        done ? scheme.surfaceContainerHighest : scheme.primaryContainer;
    final leadColor =
        done ? scheme.onSurfaceVariant : scheme.onPrimaryContainer;

    final subtitle = <String>[
      if (authorName.isNotEmpty) authorName,
      if (wish.note.isNotEmpty) wish.note,
    ].join(' · ');

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Check(checked: done, scheme: scheme, onTap: onToggle),
              const SizedBox(width: 12),
              // У вещи вместо значка категории — её фотография: список
              // желаний-товаров читается картинками, а не одинаковыми
              // кружками. Картинки нет — возвращаемся к значку.
              wish.isItem && wish.image.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      // StorageImage, а не Image.network: своё фото уходит в
                      // хранилище и приходит ссылкой `pb://`, которую обычная
                      // картинка не понимает — на её месте был бы значок.
                      child: StorageImage(
                        imageUrl: wish.image,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Container(
                          width: 56,
                          height: 56,
                          color: leadBackground,
                          alignment: Alignment.center,
                          child: SymbolIcon(wish.iconName,
                              size: 24, color: leadColor),
                        ),
                      ),
                    )
                  : Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: leadBackground,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child:
                          SymbolIcon(wish.iconName, size: 24, color: leadColor),
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wish.title,
                      style: AppFonts.unbounded(
                        size: 17,
                        weight: done ? 500 : 600,
                        color: done ? scheme.onSurfaceVariant : scheme.onSurface,
                      ),
                    ),
                    if (wish.hasPrice || wish.shop.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            if (wish.hasPrice)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: done
                                      ? scheme.surfaceContainerHighest
                                      : scheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  wish.priceLabel,
                                  style: AppFonts.onest(
                                    size: 12.5,
                                    weight: 700,
                                    color: done
                                        ? scheme.onSurfaceVariant
                                        : scheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            if (wish.shop.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  wish.shop,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.onest(
                                      size: 12,
                                      color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (done) ...[
                      if (wish.doneAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            s.dayLogDate(wish.doneAt!),
                            style: AppFonts.onest(
                                size: 12.5, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      if (wish.doneNote.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            wish.doneNote,
                            style: AppFonts.onest(
                                size: 12.5,
                                height: 1.45,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ] else if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            if (authorName.isNotEmpty) ...[
                              // AvatarWidget сам разбирается с форматом ссылки
                              // и кэшем; свой NetworkImage на аватарах из
                              // группы показывал пустой круг.
                              AvatarWidget(
                                uid: wish.authorUid,
                                liveUrl: authorAvatarUrl,
                                name: authorName,
                                size: 18,
                                primary: scheme.primary,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppFonts.onest(
                                    size: 12.5,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // «Дарю» — только на чужой вещи и только пока она не сбылась.
              // Кнопки нет у автора вовсе: он и записи такой не получает,
              // а пустая кнопка выдала бы, что подарок кто-то готовит.
              if (onReserve != null && wish.isItem && !done)
                IconButton(
                  tooltip: reserved
                      ? (ru ? 'Я дарю' : "I'm gifting")
                      : (ru ? 'Дарю' : 'Gift it'),
                  onPressed: onReserve,
                  icon: Icon(
                    reserved
                        ? Icons.card_giftcard_rounded
                        : Icons.redeem_outlined,
                    size: 20,
                    color: reserved ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              // Ссылка на магазин: без неё карточка товара — просто картинка,
              // а желание обычно и приходит ссылкой.
              if (wish.url.isNotEmpty)
                IconButton(
                  tooltip: ru ? 'Открыть' : 'Open',
                  onPressed: () async {
                    final uri = Uri.tryParse(wish.url);
                    if (uri == null) return;
                    await safeLaunchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: Icon(Icons.open_in_new_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Чекбокс M3 со своей зоной нажатия: он и есть отметка «сбылось», поэтому
/// живёт отдельно от тапа по карточке.
class _Check extends StatelessWidget {
  const _Check({
    required this.checked,
    required this.scheme,
    required this.onTap,
  });

  final bool checked;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Padding(
          // Палец получает 48 точек, сам квадрат остаётся 20 — как в макете.
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: const Cubic(.2, 0, 0, 1),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: checked ? scheme.primary : Colors.transparent,
              border: Border.all(
                color: checked ? scheme.primary : scheme.outline,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: checked
                ? Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary)
                : null,
          ),
        ),
      ),
    );
  }
}
