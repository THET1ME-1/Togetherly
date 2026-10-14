import 'dart:async';
import 'package:flutter/material.dart';
import '../../../widgets/common/ailment_icon.dart';
import '../../../theme/profile_theme.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/mood_image.dart';
import 'package:flutter/services.dart';
import '../../../models/ailment.dart';
import '../../../models/custom_mood.dart';
import '../../../models/mood_band.dart';
import '../../../models/mood_entry.dart';
import '../../../models/own_mood_pack.dart';
import '../../../models/user_data.dart';
import '../../../models/mood_pack.dart';
import '../../../models/pair_data.dart';
import '../../../dict_strings.dart';
import '../../../services/catalog_service.dart';
import '../../../services/locale_service.dart';
import '../../../services/custom_mood_service.dart';
import '../../../services/mood_pack_service.dart';
import '../../../services/mood_service.dart';
import '../../../services/plus_access.dart';
import '../../../services/plus_service.dart';
import '../../../services/pocketbase_service.dart';
import '../../../services/widget_service.dart';
import '../../../screens/plus_screen.dart';
import '../../../widgets/common/m3_loading.dart';
import '../../../widgets/memory_save/floating_note.dart';
import '../../../widgets/mood/custom_mood_sheet.dart';
import '../../../widgets/mood/mood_form_parts.dart';
import '../../../widgets/mood/own_mood_actions_sheet.dart';
import '../../../widgets/mood/own_mood_pack_view.dart';
import '../../../widgets/mood_pack_selector.dart';
import '../../../widgets/mood_tile_shapes.dart';
import '../../../models/catalog_price.dart';
import '../../../models/level.dart';
import '../../../services/coin_store.dart';

/// Shows mood picker bottom sheet for today's mood.
///
/// Все апдейты идут через [MoodService.setMoodForToday] — единая точка входа,
/// которая атомарно обновляет календарь + group memberMoods + widgetData.
/// Параметры pairData/widgetService оставлены ради обратной совместимости;
/// MoodService уже связан с ними через bindServices в home_screen.initState.
void showMoodPicker({
  required BuildContext context,
  required PairData pairData,
  required MoodService moodService,
  required WidgetService widgetService,
  required Color primary,
  required Color navActiveIcon,
  UserData? user,
  Set<String> pairOwned = const {},
}) {
  final mood = moodService.myMoodToday;
  final currentEmoji = mood?.imagePath ?? '';

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (ctx, scrollController) => MoodPickerSheet(
        scrollController: scrollController,
        currentEmoji: currentEmoji,
        primary: primary,
        user: user,
        pairOwned: pairOwned,
        groupId: moodService.groupId,
        partnerName: pairData.partnerName,
        title: LocaleService.current.howAreYouFeeling,
        subtitle: LocaleService.current.partnerWillSeeMood,
        onSelect: (mood) {
          Navigator.pop(ctx);
          moodService.setMoodForToday(
            moodId: mood.id,
            imagePath: mood.imagePath,
            label: mood.myLabel,
          );
        },
        onClear: currentEmoji.isNotEmpty
            ? () async {
                Navigator.pop(ctx);
                await moodService.clearMoodForToday();
              }
            : null,
        // ── Вкладка «Самочувствие» (болячки) ──
        showAilmentTab: true,
        currentAilmentId: pairData.myAilment.id,
        onSelectAilment: (a) {
          Navigator.pop(ctx);
          pairData.setAilment(a.id, a.localizedLabel, a.emoji);
        },
        onClearAilment: pairData.myAilment.isNotEmpty
            ? () async {
                Navigator.pop(ctx);
                await pairData.clearAilment();
              }
            : null,
      ),
    ),
  );
}

/// Shows mood picker for a specific date.
/// Для сегодняшней даты использует [MoodService.setMoodForToday]
/// (атомарный апдейт всех трёх источников). Для прошлых — только календарь.
/// [withAilmentTab] — показывать ли переключатель «Настроение / Самочувствие».
/// Из листа дня он не нужен: разделы там уже разведены отдельными пунктами, и
/// второй ряд вкладок внутри выглядел бы дублем выбора.
void showMoodPickerForDate({
  required BuildContext context,
  required DateTime date,
  required PairData pairData,
  UserData? user,
  Set<String> pairOwned = const {},
  required MoodService moodService,
  required WidgetService widgetService,
  required Color primary,
  required Color navActiveIcon,
  bool withAilmentTab = true,
}) {
  final today = DateTime.now();
  final todayNorm = DateTime(today.year, today.month, today.day);
  if (date.isAfter(todayNorm)) return;

  final isToday = date.year == today.year &&
      date.month == today.month &&
      date.day == today.day;

  final existingEntries = moodService.myEntriesForDay(date);
  final existingPath =
      existingEntries.isNotEmpty ? existingEntries.first.imagePath : '';

  final s = LocaleService.current;
  final months = s.shortMonths;
  final weekdays = s.shortWeekdays;
  final dateLabel = isToday
      ? s.todayDate
      : '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (ctx, scrollController) => MoodPickerSheet(
        scrollController: scrollController,
        currentEmoji: existingPath,
        primary: primary,
        user: user,
        pairOwned: pairOwned,
        groupId: moodService.groupId,
        partnerName: pairData.partnerName,
        title: s.moodDateLabel(dateLabel),
        subtitle: isToday ? s.partnerWillSeeMood : s.indicateMoodForDay,
        onSelect: (mood) {
          Navigator.pop(ctx);
          moodService.setMoodForDate(
            date: date,
            moodId: mood.id,
            imagePath: mood.imagePath,
            label: mood.myLabel,
          );
        },
        onClear: existingPath.isNotEmpty
            ? () async {
                Navigator.pop(ctx);
                await moodService.clearMoodForDate(date);
              }
            : null,
        // Самочувствие — текущий статус, не история: вкладка только для сегодня.
        showAilmentTab: withAilmentTab && isToday,
        currentAilmentId: isToday ? pairData.myAilment.id : '',
        onSelectAilment: isToday
            ? (a) {
                Navigator.pop(ctx);
                pairData.setAilment(a.id, a.localizedLabel, a.emoji);
              }
            : null,
        onClearAilment: (isToday && pairData.myAilment.isNotEmpty)
            ? () async {
                Navigator.pop(ctx);
                await pairData.clearAilment();
              }
            : null,
      ),
    ),
  );
}

/// Лист «Самочувствие» сам по себе — без вкладок и без сетки настроений.
///
/// Самочувствие живёт не в календаре, а в профиле пары и стареет само, поэтому
/// отмечается только на сегодня; лист дня зовёт его лишь для текущей даты.
void showAilmentPicker({
  required BuildContext context,
  required PairData pairData,
  required Color primary,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => MoodPickerSheet(
        scrollController: scrollController,
        currentEmoji: '',
        primary: primary,
        title: LocaleService.current.ailmentTabLabel,
        subtitle: LocaleService.current.ailmentPickerSubtitle,
        onSelect: (_) {},
        onClear: null,
        ailmentOnly: true,
        currentAilmentId: pairData.myAilment.id,
        onSelectAilment: (a) {
          Navigator.pop(ctx);
          pairData.setAilment(a.id, a.localizedLabel, a.emoji);
        },
        onClearAilment: pairData.myAilment.isNotEmpty
            ? () async {
                Navigator.pop(ctx);
                await pairData.clearAilment();
              }
            : null,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared bottom-sheet widget
// ─────────────────────────────────────────────────────────────────────────────

/// Тело листа выбора настроения. Публичный ради golden-тестов раскладки.
class MoodPickerSheet extends StatefulWidget {
  final ScrollController scrollController;
  final String currentEmoji;
  final Color primary;
  final String title;
  final String subtitle;
  final void Function(MoodOption) onSelect;
  final Future<void> Function()? onClear;

  // ── Вкладка «Самочувствие» (опционально) ──
  final bool showAilmentTab;

  /// Лист целиком про самочувствие: ни вкладок, ни сетки настроений.
  final bool ailmentOnly;

  /// Кошелёк и покупки человека: по ним пак настроений закрывается замком.
  /// Без него замков нет — так ведут себя точки вызова без данных о человеке.
  final UserData? user;

  /// Ключи `owned_features` группы: пак общий на пару, платит кто-то один.
  final Set<String> pairOwned;

  /// Пара, чьи свои настроения показываем. Пусто — таблетки «Свои» нет вовсе
  /// (одиночка: настроения без группы никуда не сохраняются).
  final String groupId;

  /// Имя партнёра: удержание чужого своего настроения говорит, кто может его
  /// изменить. Пусто — фраза обходится без имени.
  final String partnerName;
  final String currentAilmentId;
  final void Function(Ailment)? onSelectAilment;
  final Future<void> Function()? onClearAilment;

  /// Набор своих настроений. По умолчанию [CustomMoodService]; тесты кладут
  /// набор в памяти.
  final CustomMoodStore? store;

  /// Гейт Плюса вместо [PlusService.gate] — для тестов.
  final PlusGate? plusGate;

  /// Свой uid вместо сессии PocketBase — для тестов.
  final String? myUid;

  const MoodPickerSheet({
    super.key,
    required this.scrollController,
    required this.currentEmoji,
    required this.primary,
    required this.title,
    required this.subtitle,
    required this.onSelect,
    required this.onClear,
    this.user,
    this.pairOwned = const {},
    this.groupId = '',
    this.partnerName = '',
    this.showAilmentTab = false,
    this.ailmentOnly = false,
    this.currentAilmentId = '',
    this.onSelectAilment,
    this.onClearAilment,
    this.store,
    this.plusGate,
    this.myUid,
  });

  @override
  State<MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends State<MoodPickerSheet> {
  int _tab = 0; // 0 — настроение, 1 — самочувствие

  /// Закрытый набор, который человек сейчас разглядывает. Экран тот же, просто
  /// эмоции показываются от чужого пака, выбрать их нельзя, а кнопка внизу
  /// превращается из «Убрать настроение» в покупку. Пусто — показан свой.
  MoodPack? _preview;

  /// Свои настроения пары.
  List<CustomMood> _custom = const [];

  /// Набор загрузился: до этого «Своих» нет ни пустыми, ни примером.
  bool _customLoaded = false;

  /// «Свои» показаны примером без Плюса. Это просмотр, как у закрытого
  /// платного набора: выбор не запоминается.
  bool _previewOwn = false;

  CustomMoodStore get _store => widget.store ?? CustomMoodService.instance;

  PlusGate get _gate => widget.plusGate ?? PlusService.instance.gate;

  OwnPackState get _ownState => ownPackState(
        hasGroup: widget.groupId.isNotEmpty,
        gate: _gate,
        loaded: _customLoaded,
        count: _custom.length,
      );

  @override
  void initState() {
    super.initState();
    // Загрузить сохранённый выбор пака (идемпотентно); AnimatedBuilder ниже
    // перестроит сетку, когда значение подгрузится/изменится.
    MoodPackService.instance.load();
    _loadCustom();
  }

  Future<void> _loadCustom() async {
    final list = widget.groupId.isEmpty ? const <CustomMood>[] : await _store.load(widget.groupId);
    if (!mounted) return;
    setState(() {
      _custom = list;
      _customLoaded = true;
    });
  }

  void _openPlus() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlusScreen(scheme: ProfileTheme.schemeFor(context.appTheme)),
    ));
  }

  /// «Новое»: заводит своё настроение или ведёт на экран Плюса.
  Future<void> _addCustom() async {
    final s = LocaleService.current;
    switch (_gate) {
      case PlusGate.hidden:
        return; // на iPhone без Плюса набора «Свои» нет вовсе
      case PlusGate.locked:
        _openPlus();
        return;
      case PlusGate.open:
        break;
    }
    if (ownPackFull(_custom.length)) {
      // Снекбар уехал бы под лист: плашка ложится поверх него.
      showFloatingNote(context, s.customMoodLimitReached, icon: Icons.info_outline_rounded, duration: const Duration(milliseconds: 2600));
      return;
    }
    final made = await showCustomMoodSheet(context, widget.groupId, store: widget.store);
    if (made == true) await _loadCustom();
  }

  /// Удержание своего настроения: своё изменить или убрать, про чужое —
  /// объяснить, кто может.
  Future<void> _holdCustom(CustomMood mood) async {
    HapticFeedback.mediumImpact();
    final uid = widget.myUid ?? PocketBaseService().userId ?? '';
    final action = await showOwnMoodActions(
      context,
      mood: mood,
      mine: mood.editableBy(uid),
      partnerName: widget.partnerName,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case OwnMoodAction.edit:
        final saved = await showEditCustomMoodSheet(context, mood, store: widget.store);
        if (saved == true) await _loadCustom();
      case OwnMoodAction.remove:
        final ok = await _store.remove(mood.id);
        if (!mounted) return;
        if (!ok) {
          showFloatingNote(context, trKey('customMoodRemoveFailed'), icon: Icons.error_outline_rounded);
        }
        await _loadCustom();
    }
  }

  /// Нажатие на таблетку «Свои».
  void _tapOwn() {
    final selectable = ownPackSelectable(_ownState);
    setState(() {
      _preview = null;
      _previewOwn = !selectable;
    });
    if (selectable) MoodPackService.instance.setSelectedPack(kOwnMoodPackId);
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = context.appTheme;
    final cs = ProfileTheme.schemeFor(t);
    final onAilment = widget.ailmentOnly || (widget.showAilmentTab && _tab == 1);
    return Container(
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Ручка листа по спецификации M3: 32×4.
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Заголовок держим на обеих вкладках: раньше при двух вкладках он
          // исчезал и наверху оставалась одна серая строка подсказки.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontFamily: ProfileTheme.displayFont,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.2,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  onAilment ? s.ailmentPickerSubtitle : widget.subtitle,
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (widget.showAilmentTab)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _segmented(s, cs),
            ),
          Expanded(child: onAilment ? _ailmentList(cs) : _moodBody(cs)),
          _clearButton(s, cs, onAilment),
        ],
      ),
    );
  }

  /// Связанная группа кнопок M3 Expressive: выбранная вкладка забирает больше
  /// места и округляется в стадион, соседняя остаётся мягким прямоугольником.
  Widget _segmented(AppStrings s, ColorScheme cs) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          _segBtn(s.moodTabLabel, 0, cs, first: true),
          const SizedBox(width: 4),
          _segBtn(s.ailmentTabLabel, 1, cs, first: false),
        ],
      ),
    );
  }

  Widget _segBtn(String label, int idx, ColorScheme cs, {required bool first}) {
    final active = _tab == idx;
    final outer = Radius.circular(active ? 24 : 20);
    final inner = Radius.circular(active ? 24 : 12);
    return Expanded(
      flex: active ? 145 : 100,
      child: GestureDetector(
        onTap: () => setState(() => _tab = idx),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // Невыбранная вкладка на тон темнее листа: у рисованных тем
            // surfaceContainerHigh совпадает с фоном листа, и её не было видно.
            color: active ? widget.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: first ? outer : inner,
              bottomLeft: first ? outer : inner,
              topRight: first ? inner : outer,
              bottomRight: first ? inner : outer,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: active ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _moodBody(ColorScheme cs) {
    return AnimatedBuilder(
      animation: Listenable.merge([MoodPackService.instance, CatalogService.instance]),
      builder: (context, _) {
        final own = _ownState;
        final shown = shownMoodPackId(
          selectedId: MoodPackService.instance.selectedPackId,
          resolvedId: MoodPackService.instance.selectedPack.id,
          own: own,
          previewId: _preview?.id,
          previewOwn: _previewOwn,
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: MoodPackSelector(
                primary: widget.primary,
                user: widget.user,
                pairOwned: widget.pairOwned,
                shownId: shown,
                own: own == OwnPackState.hidden ? null : _ownChip(cs),
                onChanged: (_) => setState(() {
                  _preview = null;
                  _previewOwn = false;
                }),
                onPreview: (p) {
                  setState(() {
                    _preview = p;
                    _previewOwn = false;
                  });
                  // Цену на кнопке называет магазин, а описание товара приезжает
                  // по требованию: спрашиваем его сразу, как человек открыл набор,
                  // иначе кнопка секунду показывала бы цену из манифеста.
                  if (p.unlock.isMoney && kCatalogBuysInStore) {
                    final id = catalogProductId(
                        Unlock.featureKey(kMoodPackFeatureKind, p.id));
                    unawaited(sharedCoinStore.ensureProduct(id).then((known) {
                      if (known && mounted) setState(() {});
                    }));
                  }
                },
              ),
            ),
            Expanded(
              child: shown == kOwnMoodPackId ? _ownList(cs, own) : _packList(cs),
            ),
          ],
        );
      },
    );
  }

  /// Таблетка «Свои»: картинка первого своего настроения или «+».
  OwnPackChip _ownChip(ColorScheme cs) {
    final first = _custom.isEmpty ? null : _custom.first;
    return OwnPackChip(
      preview: first?.imageUrl ?? '',
      previewTint: first != null && first.onTintedTile ? moodScoreTint(first.score, cs, alpha: 0.30) : null,
      locked: _gate == PlusGate.locked,
      onTap: _tapOwn,
    );
  }

  /// Сетка обычного набора: разделы по шкале и подпись художника.
  Widget _packList(ColorScheme cs) {
    final pack = _preview ?? MoodPackService.instance.selectedPack;
    final sections = groupMoodsByBand(pack.moods);
    // Подпись художника идёт последней строкой списка, а не отдельным
    // блоком под ним: иначе она висела бы на экране всё время, пока
    // человек листает эмоции, и спорила бы с кнопкой снизу.
    final signed = pack.author.isNotEmpty;
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      itemCount: sections.length + (signed ? 1 : 0),
      itemBuilder: (_, i) => i < sections.length
          ? _bandSection(sections[i], pack, cs)
          : _authorLine(pack.author, cs),
    );
  }

  /// Набор «Свои»: строка с местом и «Новое», дальше разделы по шкале, как у
  /// остальных наборов (макет 14.10.2026, вариант А «Как все наборы»).
  Widget _ownList(ColorScheme cs, OwnPackState own) {
    const padding = EdgeInsets.fromLTRB(20, 0, 20, 16);
    switch (own) {
      case OwnPackState.hidden:
      case OwnPackState.loading:
        return ListView(
          controller: widget.scrollController,
          padding: padding,
          children: [
            const SizedBox(height: 48),
            Center(child: M3Loading(color: cs.primary)),
          ],
        );
      case OwnPackState.teaser:
        return ListView(
          controller: widget.scrollController,
          padding: padding,
          children: [
            OwnMoodsEmpty(title: trKey('customMoodTeaserTitle'), text: trKey('customMoodTeaserText')),
          ],
        );
      case OwnPackState.empty:
        return ListView(
          controller: widget.scrollController,
          padding: padding,
          children: [
            OwnMoodsEmpty(
              title: trKey('customMoodEmptyTitle'),
              text: trKey('customMoodEmptyText'),
              onCreate: _addCustom,
            ),
          ],
        );
      case OwnPackState.list:
        final s = LocaleService.current;
        final locked = _gate == PlusGate.locked;
        final sections = groupOwnByBand(_custom);
        final meta = locked
            ? trKey('customMoodLockedMeta')
            : trKey('customMoodSetCount')
                .replaceAll('{n}', '${_custom.length}')
                .replaceAll('{max}', '$kOwnMoodLimit');
        return ListView.builder(
          controller: widget.scrollController,
          padding: padding,
          itemCount: 1 + sections.length,
          itemBuilder: (_, i) {
            if (i == 0) {
              return OwnMoodsBar(
                meta: meta,
                locked: locked,
                full: ownPackFull(_custom.length),
                newLabel: s.customMoodNewTile,
                onNew: _addCustom,
              );
            }
            final section = sections[i - 1];
            return _bandBlock(
              section.band,
              cs,
              itemCount: section.moods.length,
              itemBuilder: (i) {
                final mood = section.moods[i];
                final option = mood.toMoodOption();
                return _MoodTile(
                  mood: option,
                  isSelected: widget.currentEmoji == option.imagePath,
                  primary: widget.primary,
                  scheme: cs,
                  sticker: mood.onTintedTile,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onSelect(option);
                  },
                  onLongPress: () => _holdCustom(mood),
                );
              },
            );
          },
        );
    }
  }

  String _bandTitle(MoodBand band) {
    final s = LocaleService.current;
    return switch (band) {
      MoodBand.bright => s.moodBandBright,
      MoodBand.even => s.moodBandEven,
      MoodBand.sad => s.moodBandSad,
      MoodBand.heavy => s.moodBandHeavy,
    };
  }

  /// Раздел сетки: подпись с линией и пять колонок плиток.
  Widget _bandBlock(
    MoodBand band,
    ColorScheme cs, {
    required int itemCount,
    required Widget Function(int) itemBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
          child: Row(
            children: [
              // Длинный раздел («Traurig und unruhig») при крупном шрифте на
              // узком экране не должен выталкивать строку за край.
              Flexible(
                child: Text(
                  _bandTitle(band),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Divider(height: 1, color: cs.outlineVariant)),
            ],
          ),
        ),
        LayoutBuilder(builder: (context, box) {
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 12,
              crossAxisSpacing: 8,
              // Плитка + две строки подписи в 11 пунктов. Высота считается, а не
              // берётся числом: при крупном системном шрифте подпись выше.
              childAspectRatio: moodTileRatio(context, box.maxWidth),
            ),
            itemCount: itemCount,
            itemBuilder: (_, i) => itemBuilder(i),
          );
        }),
      ],
    );
  }

  /// Раздел сетки обычного набора.
  Widget _bandSection(MoodBandSection section, MoodPack pack, ColorScheme cs) {
    return _bandBlock(
      section.band,
      cs,
      itemCount: section.moods.length,
      itemBuilder: (i) {
        final mood = section.moods[i];
        final isSelected = widget.currentEmoji == mood.imagePath;
        return _MoodTile(
          mood: mood,
          // У чужого набора выбранного быть не может: человек его смотрит.
          isSelected: _preview == null && isSelected,
          primary: widget.primary,
          scheme: cs,
          sticker: pack.tileGradient != null,
          onTap: () {
            HapticFeedback.lightImpact();
            // Тап по эмоции закрытого набора ведёт туда же, куда кнопка
            // внизу: отметить ею день пока нельзя.
            if (_preview != null) {
              _buyPreviewed();
              return;
            }
            widget.onSelect(mood);
          },
        );
      },
    );
  }

  /// Кто нарисовал пак. Тихая строка по центру — благодарность художнику,
  /// а не элемент управления, поэтому ни ссылки, ни нажатия.
  Widget _authorLine(String author, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 4),
      child: Center(
        child: Text(
          LocaleService.current.moodPackAuthor(author),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  /// Болячки — это подпись с эмодзи, поэтому чипы-строки, а не сетка квадратов
  /// с обрезанными названиями.
  Widget _ailmentList(ColorScheme cs) {
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in kAilments)
            _AilmentChip(
              ailment: a,
              isSelected: widget.currentAilmentId == a.id,
              scheme: cs,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onSelectAilment?.call(a);
              },
            ),
        ],
      ),
    );
  }

  /// Купить набор, который человек сейчас смотрит.
  Future<void> _buyPreviewed() async {
    final pack = _preview;
    final user = widget.user;
    if (pack == null || user == null) return;
    await buyMoodPack(
      context,
      pack,
      user: user,
      // За монеты набор открывается сразу и становится выбранным — значит
      // просмотр закончился, показываем его уже как свой.
      onBought: () {
        if (mounted) setState(() => _preview = null);
      },
    );
  }

  Widget _clearButton(AppStrings s, ColorScheme cs, bool onAilment) {
    // «Свои» без Плюса показаны примером — внизу вход в Плюс, как у закрытого
    // платного набора.
    if (_previewOwn && !onAilment) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MoodSheetButton(
                key: const Key('own-moods-unlock'),
                label: trKey('customMoodUnlock'),
                icon: Icons.workspace_premium_rounded,
                onPressed: _openPlus,
              ),
              const SizedBox(height: 8),
              Text(
                trKey('customMoodUnlockNote'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    // Смотрим чужой набор — вместо «убрать настроение» тут покупка: другого
    // действия на этом экране сейчас нет.
    final previewed = _preview;
    if (previewed != null && !onAilment) {
      // Цена — от магазина: у Apple и Google свой налог и округление в каждой
      // стране, и число из манифеста рядом с ними читалось бы как вторая цена.
      final price = catalogPriceLabel(
        storePrice: kCatalogBuysInStore
            ? sharedCoinStore.priceLabel(catalogProductId(
                Unlock.featureKey(kMoodPackFeatureKind, previewed.id)))
            : null,
        catalogPrice: previewed.unlock.priceLabel,
      );
      final author = previewed.author;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _buyPreviewed,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(ruEn('Открыть за $price', 'Unlock for $price')),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                author.isEmpty
                    ? ruEn('Набор останется навсегда и появится у партнёра',
                        'Yours forever, and your partner gets it too')
                    : switch (LocaleService.instance.language) {
                        AppLanguage.ru =>
                          'Рисунки — $author · набор появится и у партнёра',
                        AppLanguage.zh => '画师：$author · 另一半也会一起获得',
                        _ => 'Art by $author · your partner gets it too',
                      },
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final onClear = onAilment ? widget.onClearAilment : widget.onClear;
    if (onClear == null) return const SizedBox(height: 16);
    final label = onAilment ? s.clearAilment : s.clearMood;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: onClear,
            style: FilledButton.styleFrom(
              backgroundColor: cs.secondaryContainer,
              foregroundColor: cs.onSecondaryContainer,
              shape: const StadiumBorder(),
              // Стиль кнопки не сливается с темой: без семейства надпись
              // уходила в системный шрифт, а не в Onest.
              textStyle: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// Отношение сторон ячейки настроения с поправкой на системный шрифт.
///
/// Плитка квадратная, под ней две строки подписи в 11 пунктов. Жёсткое 0.62
/// сходилось только при масштабе 1.0: на эмуляторе с `font_scale 1.3` каждая
/// строка сетки рисовала «BOTTOM OVERFLOWED BY 9.6 PIXELS» — подпись длинных
/// эмоций («Embarrassed», «Missing you») не помещалась в отведённую высоту.
/// Теперь высота ячейки складывается из ширины плитки, отступа и настоящей
/// высоты подписи, а та растёт вместе с системным шрифтом.
double moodTileRatio(
  BuildContext context,
  double gridWidth, {
  int columns = 5,
  double spacing = 8,
}) {
  final cell = (gridWidth - spacing * (columns - 1)) / columns;
  if (cell <= 0) return 0.62;
  final label = MediaQuery.textScalerOf(context).scale(11) * 1.2 * 2;
  // Прежнее 0.62 — потолок: при обычном шрифте сетка остаётся ровно такой,
  // какой была, и ниже по высоте ячейка не становится. Крупный шрифт её
  // вытягивает — ровно настолько, сколько занимает подпись.
  final fit = cell / (cell + 6 + label + 2);
  return fit < 0.62 ? fit : 0.62;
}

/// Нижний предел кегля подписи плитки: мельче её уже не прочесть.
const double kMoodLabelMinSize = 8.5;

/// Кегль подписи плитки шириной [width]: самое длинное слово должно влезть в
/// строку целиком.
///
/// Слово шире плитки Flutter рвёт посреди: «Подмигив/аю», «Скуча/ю». Своим
/// настроениям пара сама даёт названия, и они длиннее встроенных, поэтому
/// такое слово набирается мельче, но не ниже [kMoodLabelMinSize].
double moodLabelSize(BuildContext context, String label, double width, {double base = 11}) {
  if (width <= 0) return base;
  final style = DefaultTextStyle.of(context).style.merge(
        TextStyle(fontSize: base, fontWeight: FontWeight.w700, height: 1.2),
      );
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final word in label.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    if (painter.width > widest) widest = painter.width;
    painter.dispose();
  }
  if (widest <= width) return base;
  // Ширина глифов при уменьшении кегля меняется не строго пропорционально
  // (округление на мелком размере), поэтому целимся с запасом в пять процентов.
  final fit = (base * width * 0.95 / widest * 10).floorToDouble() / 10;
  return fit < kMoodLabelMinSize ? kMoodLabelMinSize : fit;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single emoji tile
// ─────────────────────────────────────────────────────────────────────────────

class _MoodTile extends StatelessWidget {
  final MoodOption mood;
  final bool isSelected;
  final Color primary;
  final ColorScheme scheme;

  /// Картинка прозрачная (стикеры «Розовых», эмодзи своего набора) и стоит на
  /// подложке цвета настроения. false — картинка заполняет плитку сама.
  final bool sticker;
  final VoidCallback onTap;

  /// Есть только у своих настроений: удержание открывает их действия.
  final VoidCallback? onLongPress;

  const _MoodTile({
    required this.mood,
    required this.isSelected,
    required this.primary,
    required this.scheme,
    required this.onTap,
    this.sticker = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: LayoutBuilder(
              builder: (context, box) {
                final size = box.maxWidth;
                // Выбор читается формой: мягкий квадрат превращается в
                // волнистую фигуру и чуть подрастает. Цветное свечение прошлой
                // версии выглядело подсветкой, а не отметкой.
                final shape = moodTileShape(selected: isSelected, size: size);
                return AnimatedScale(
                  scale: isSelected ? 1.06 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ClipPath(
                          clipper: ShapeBorderClipper(shape: shape),
                          child: Container(
                            color: sticker
                                ? Color.alphaBlend(
                                    mood.color.withValues(alpha: 0.16),
                                    scheme.surfaceContainerHigh,
                                  )
                                : null,
                            child: mood.imagePath.isEmpty
                                ? Container(color: mood.color)
                                : sticker
                                    ? Padding(
                                        padding: EdgeInsets.all(size * 0.06),
                                        child: MoodImage(
                                          mood.imagePath,
                                          fit: BoxFit.contain,
                                        ),
                                      )
                                    : MoodImage(
                                        mood.imagePath,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                          ),
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 13,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, box) => Text(
              mood.myLabel,
              style: TextStyle(
                fontSize: moodLabelSize(context, mood.myLabel, box.maxWidth),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? primary : scheme.onSurfaceVariant,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single ailment tile — значок той же рукой, что значки профиля
// ─────────────────────────────────────────────────────────────────────────────

class _AilmentChip extends StatelessWidget {
  final Ailment ailment;
  final bool isSelected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _AilmentChip({
    required this.ailment,
    required this.isSelected,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Цвет говорит, насколько плохо: жёлтый — мешает, красный — свалило.
    // Обводка не сообщала ничего, все шестнадцать чипов были на одно лицо.
    // Тон приглушён тем же приёмом, что клетки календаря: цвет ложится на
    // поверхность, а не заливается в полную силу.
    final tone = ailment.severity.color;
    final fill = Color.alphaBlend(
      tone.withValues(alpha: isSelected ? 0.55 : 0.20),
      scheme.surfaceContainerHighest,
    );
    final fg = isSelected ? scheme.onSurface : scheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 44,
        padding: const EdgeInsets.only(left: 4, right: 16),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AilmentIcon(id: ailment.id, emoji: ailment.emoji, size: 38),
            const SizedBox(width: 4),
            Text(
              ailment.localizedLabel,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
