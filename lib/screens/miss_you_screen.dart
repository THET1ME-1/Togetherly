import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dict_strings.dart' show trKey;
import '../models/miss_you_event.dart';
import '../models/miss_you_state.dart';
import '../models/optimistic_count.dart';
import '../models/tile_columns.dart';
import '../services/custom_wishes_store.dart';
import '../services/locale_service.dart';
import '../services/miss_you_repository.dart';
import '../services/presence_service.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../theme/profile_theme.dart';
import '../widgets/common/stable_stream_builder.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/miss_you/custom_vibe_sheet.dart';
import '../widgets/miss_you/heart_field.dart';
import '../widgets/settings_scaffold.dart';

/// Экран «Скучаю» — вместо панельки под кнопкой в шапке.
///
/// Панель показывала три строки и два числа без подписи: на экран этого не
/// хватало, а на попап хватало ровно потому, что смотреть там было не на что.
/// Экран собран на данных, которые сервер копит и так: счётчики обоих,
/// последний импульс партнёра с его временем (`last_vibe` + `updated_at`) и
/// карта «день недели → сколько раз» (`by_weekday`, её ведёт роут
/// `/api/group/miss-you`). Отдельной коллекции истории пока нет, поэтому лента
/// событий здесь не рисуется — только последнее, и это честно.
///
/// Сердце в шапке главного экрана осталось мгновенной отправкой: экран
/// открывает тап по счётчику.
class MissYouScreen extends StatefulWidget {
  const MissYouScreen({
    super.key,
    required this.theme,
    required this.groupId,
    required this.myUid,
    this.myName = '',
    this.myAvatarUrl,
    required this.partnerUid,
    required this.partnerName,
    this.partnerAvatarUrl,
    this.debugEvents,
  });

  /// История для тестов и превью: без сервера экран её не получит.
  @visibleForTesting
  final List<MissYouEvent>? debugEvents;

  final AppTheme theme;
  final String groupId;
  final String myUid;

  /// Своё имя и снимок — только для кружка в левой пилюле. Подпись под числом
  /// остаётся словом «Ты»: человек ищет там себя, а не своё имя.
  final String myName;
  final String? myAvatarUrl;

  final String partnerUid;
  final String partnerName;
  final String? partnerAvatarUrl;

  @override
  State<MissYouScreen> createState() => _MissYouScreenState();
}

class _MissYouScreenState extends State<MissYouScreen>
    with TickerProviderStateMixin {
  final MissYouRepository _repo = MissYouRepository();

  MissYouState _state = MissYouState.empty;
  StreamSubscription<MissYouState>? _sub;

  /// Свои нажатия, ещё не подтверждённые сервером: счётчик обязан отзываться
  /// сразу, иначе кнопка кажется мёртвой на плохой сети. Правило снятия
  /// надбавки держит [OptimisticCount] — то же, что у кнопки в шапке.
  OptimisticCount _mine = const OptimisticCount();
  Timer? _staleTimer;

  List<String> _wishes = const [];

  /// История импульсов за сегодня и вчера. null — ещё не пришла или сервер
  /// её не знает: тогда внизу прежняя карточка «последнее от партнёра».
  List<MissYouEvent>? _events;

  /// Фон карточки с сердцем: нажатие пускает по нему волну.
  final GlobalKey<HeartFieldState> _field = GlobalKey();

  /// Ответы, ушедшие с этого экрана, пока история не перечиталась.
  final Set<String> _justReplied = {};
  bool _showAll = false;
  Timer? _historyDebounce;
  static const int _collapsed = 5;

  late final AnimationController _pulse;
  late final Animation<double> _pulseScale;

  /// Появление экрана: блоки въезжают по очереди, а не возникают пачкой.
  /// Один контроллер на все четыре — интервалы дешевле четырёх таймеров.
  late final AnimationController _intro;

  final List<_Heart> _hearts = [];
  final Random _random = Random();

  ColorScheme get _cs => ProfileTheme.schemeFor(widget.theme);

  /// Заливка темы и чернила по ней.
  ///
  /// Не `primaryContainer`: у тем, нарисованных руками, он берётся из
  /// «чуть тонированного фона» (`primaryLight`), и на светлой теме залитое
  /// пропадало со страницы — контраст к фону 1,00–1,07 по всем светлым
  /// палитрам. Заливка видна везде, худший случай 2,05.
  Color get _fill => widget.theme.fillColor;
  Color get _onFill =>
      AppThemes.onColor(widget.theme.fillColor, mode: widget.theme.brightness);
  AppStrings get _s => LocaleService.current;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.92)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 82,
      ),
    ]).animate(_pulse);

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..forward();

    _events = widget.debugEvents;
    _loadWishes();
    if (widget.groupId.isNotEmpty) {
      _sub = _repo.watchState(widget.groupId).listen((s) {
        if (!mounted) return;
        _mine = _mine.confirm(s.myCount, now: DateTime.now());
        setState(() => _state = s);
        _scheduleStaleSweep();
        // Запись счётчика двинулась — значит, в истории новый импульс.
        _historyDebounce?.cancel();
        _historyDebounce = Timer(const Duration(milliseconds: 500), _loadHistory);
      });
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    if (widget.groupId.isEmpty) return;
    final list = await _repo.history(widget.groupId);
    if (!mounted || list == null) return;
    setState(() => _events = list);
  }

  /// Протухшие ожидания уходят сами: без этого последняя надбавка висела бы до
  /// следующего импульса, а он может не случиться до завтра.
  void _scheduleStaleSweep() {
    _staleTimer?.cancel();
    if (_mine.pending == 0) return;
    _staleTimer = Timer(OptimisticCount.ttl, () {
      if (!mounted) return;
      setState(() {
        _mine = _mine.confirm(_mine.confirmed, now: DateTime.now());
      });
      _scheduleStaleSweep();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _staleTimer?.cancel();
    _historyDebounce?.cancel();
    _pulse.dispose();
    _intro.dispose();
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadWishes() async {
    // Сперва телефонный список — он под рукой и рисуется сразу. Следом
    // спрашиваем аккаунт: после переустановки или на втором устройстве список
    // приедет оттуда (см. CustomWishesStore.pull).
    final saved = await CustomWishesStore.load();
    if (mounted) setState(() => _wishes = saved);
    final merged = await CustomWishesStore.pull(saved);
    if (mounted && !listEquals(merged, saved)) {
      setState(() => _wishes = merged);
    }
  }

  // ── Отправка ────────────────────────────────────────────────────────────────

  Future<void> _sendMissYou({String? replyTo}) async {
    if (widget.groupId.isEmpty) return;
    HapticFeedback.mediumImpact();
    _pulse.forward(from: 0);
    _field.currentState?.pulse();
    _spawnHearts();
    setState(() => _mine = _mine.tap(DateTime.now()));
    _scheduleStaleSweep();
    var ok = false;
    try {
      ok = await _repo.sendMissYou(widget.groupId, replyTo: replyTo);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) setState(() => _mine = _mine.failed());
  }

  Future<void> _sendVibe(String type, {String? text, String? replyTo}) async {
    if (widget.groupId.isEmpty) return;
    HapticFeedback.mediumImpact();
    _spawnHearts(icon: vibeIcon(type));
    try {
      await _repo.sendVibe(
        groupId: widget.groupId,
        vibeType: type,
        customText: text,
        replyTo: replyTo,
      );
      if (text != null && text.isNotEmpty) {
        final next = await CustomWishesStore.add(_wishes, text);
        if (mounted) setState(() => _wishes = next);
      }
    } catch (_) {
      // Отправка молча не удалась — счётчик просто не вырастет, врать
      // подтверждением нельзя.
    }
  }

  Future<void> _addWish() async {
    final text = await showCustomVibeSheet(context, theme: widget.theme);
    if (text == null || text.trim().isEmpty) return;
    await _sendVibe('custom', text: text.trim());
  }

  Future<void> _removeWish(String text) async {
    final next = await CustomWishesStore.remove(_wishes, text);
    if (!mounted) return;
    setState(() => _wishes = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_s.missYouWishRemoved),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Чем отвечаем на последний импульс партнёра. Своё пожелание не
  /// возвращается эхом — оно про него, а не про меня, — поэтому на `custom`
  /// уходит «скучаю».
  String get _replyVibe {
    final vibe = _state.partner?.lastVibe ?? '';
    return (vibe == 'thinking_of_you' || vibe == 'want_hug')
        ? vibe
        : 'miss_you';
  }

  /// Ответ тем же импульсом, каким прислал партнёр. Отдельной коллекции
  /// ответов нет, но повторить его вайб — ровно то, чего ждут от кнопки.
  Future<void> _replyBack() async {
    if (_replyVibe == 'miss_you') {
      await _sendMissYou();
      return;
    }
    await _sendVibe(_replyVibe);
  }

  /// Ответ на конкретный импульс из истории дня тем же импульсом.
  Future<void> _replyTo(MissYouEvent e) async {
    setState(() => _justReplied.add(e.id));
    final vibe = missYouReplyVibe(e.vibe);
    if (vibe == 'miss_you') {
      await _sendMissYou(replyTo: e.id);
    } else {
      await _sendVibe(vibe, replyTo: e.id);
    }
  }

  void _spawnHearts({IconData icon = Icons.favorite_rounded}) {
    const extra = [
      Icons.favorite_border_rounded,
      Icons.auto_awesome_rounded,
    ];
    for (var i = 0; i < 5; i++) {
      final heart = _Heart(
        icon: i == 0 ? icon : extra[_random.nextInt(extra.length)],
        controller: AnimationController(
          vsync: this,
          duration: Duration(milliseconds: 900 + _random.nextInt(500)),
        ),
        dx: (_random.nextDouble() - 0.5) * 150,
        rise: 130 + _random.nextDouble() * 90,
        size: 14 + _random.nextDouble() * 14,
      );
      heart.controller.forward().then((_) {
        heart.controller.dispose();
        if (mounted) setState(() => _hearts.remove(heart));
      });
      setState(() => _hearts.add(heart));
    }
  }

  // ── Сборка ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          titleSpacing: 0,
          title: _title(cs),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            children: [
              _appear(0, _hero(cs)),
              const SizedBox(height: 12),
              // История дня сразу под сердцем (макет, вариант А): первое, что
              // ищут, открыв экран, — что прислали, пока тебя не было.
              if (_events != null) ...[
                _appear(1, _history(cs)),
                const SizedBox(height: 12),
              ],
              _appear(
                1,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(cs, _s.missYouMore),
                    const SizedBox(height: 8),
                    _chips(cs),
                  ],
                ),
              ),
              if (_events == null && (_state.partner?.lastVibe.isNotEmpty ?? false)) ...[
                const SizedBox(height: 12),
                _appear(2, _latest(cs)),
              ],
              const SizedBox(height: 12),
              _appear(3, _week(cs)),
            ],
          ),
        ),
      ),
    );
  }

  /// Блок [index] въезжает со сдвигом по времени. Кривая emphasized decelerate
  /// из M3: вход быстро набирает и мягко останавливается.
  Widget _appear(int index, Widget child) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    final start = (index * 0.12).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, (start + 0.55).clamp(0.0, 1.0),
          curve: const Cubic(0.05, 0.7, 0.1, 1)),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, inner) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - anim.value)),
          child: inner,
        ),
      ),
      child: child,
    );
  }

  Widget _title(ColorScheme cs) {
    return Row(
      children: [
        AvatarWidget(
          uid: widget.partnerUid,
          fallbackUrl: widget.partnerAvatarUrl,
          name: widget.partnerName,
          size: 36,
          primary: cs.primary,
          tapToView: true,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _s.missYouTitle,
                style: AppFonts.unbounded(
                    size: 17, weight: 700, color: cs.onSurface),
              ),
              _presence(cs),
            ],
          ),
        ),
      ],
    );
  }

  /// «В сети» или время последнего визита. Пусто, если отметки нет вовсе:
  /// придумывать «был давно» не из чего.
  Widget _presence(ColorScheme cs) {
    if (widget.partnerUid.isEmpty) return const SizedBox.shrink();
    return StableStreamBuilder<bool>(
      create: () => PresenceService().watchOnline(widget.partnerUid),
      keys: [widget.partnerUid],
      builder: (context, onlineSnap) {
        if (onlineSnap.data == true) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(_s.chatOnline, style: _caption(cs)),
            ],
          );
        }
        return StableStreamBuilder<int?>(
          create: () => PresenceService().watchLastSeen(widget.partnerUid),
          keys: [widget.partnerUid],
          builder: (context, seenSnap) {
            final label = lastSeenLabel(seenSnap.data, _s.yesterday);
            if (label.isEmpty) return const SizedBox.shrink();
            // Одна дата без подписи («23.09») не читалась как последний визит.
            return Text(trKey('missYouSeenAt').replaceAll('{t}', label), style: _caption(cs));
          },
        );
      },
    );
  }

  TextStyle _caption(ColorScheme cs) => TextStyle(
        fontFamily: ProfileTheme.bodyFont,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant,
      );

  // ── Герой: круг с сердцем и оба счёта ───────────────────────────────────────

  Widget _hero(ColorScheme cs) {
    final myCount = _mine.display;
    // Живой фон — поле сердечек (макет «Фон сердца «Скучаю»», вариант Б):
    // лежит под содержимым карточки, волна идёт от центра большого сердца.
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: ColoredBox(
        color: cs.surfaceContainer,
        child: Stack(
          children: [
            Positioned.fill(
              child: HeartField(
                key: _field,
                color: _fill,
                center: (size) => Offset(size.width / 2, _heroTop + _heartBox / 2),
              ),
            ),
            _heroBody(cs, myCount),
          ],
        ),
      ),
    );
  }

  /// Верхний отступ карточки и высота места под сердцем — от них считается
  /// центр волны фона.
  static const double _heroTop = 22;
  static const double _heartBox = 152;

  Widget _heroBody(ColorScheme cs, int myCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, _heroTop, 16, 16),
      child: Column(
        children: [
          SizedBox(
            height: _heartBox,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                ..._hearts.map(
                  (h) => AnimatedBuilder(
                    animation: h.controller,
                    builder: (context, _) {
                      final p = h.controller.value;
                      final eased = Curves.easeOut.transform(p);
                      return Transform.translate(
                        offset: Offset(h.dx * eased, -h.rise * eased),
                        child: Opacity(
                          opacity: (1 - p).clamp(0.0, 1.0),
                          child: Icon(h.icon, size: h.size, color: _fill),
                        ),
                      );
                    },
                  ),
                ),
                ScaleTransition(
                  scale: _pulseScale,
                  child: _HeartButton(
                    fill: _fill,
                    onFill: _onFill,
                    onTap: _sendMissYou,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _s.iMissYou,
            style:
                AppFonts.unbounded(size: 18, weight: 700, color: cs.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            _s.missYouSendHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 12.5,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Tally(
                  scheme: cs,
                  fill: _fill,
                  onFill: _onFill,
                  uid: widget.myUid,
                  name: _s.missYouYou,
                  avatarName: widget.myName,
                  avatarUrl: widget.myAvatarUrl,
                  count: myCount,
                  filled: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Tally(
                  scheme: cs,
                  fill: _fill,
                  onFill: _onFill,
                  uid: widget.partnerUid,
                  avatarUrl: widget.partnerAvatarUrl,
                  name: widget.partnerName.isEmpty
                      ? _s.missYouPartner
                      : widget.partnerName,
                  count: _state.partnerCount,
                  filled: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Сколько раз этот импульс отправляли. Своё пожелание считается одной
  /// строкой `custom` — на чипах его не показываем: их у человека несколько, а
  /// число на сервере одно на все.
  int _vibeCount(String type, {required bool mine}) {
    final e = mine ? _state.mine : _state.partner;
    return e?.byVibe[type] ?? 0;
  }

  // ── Чипы: вайбы и свои пожелания ────────────────────────────────────────────

  /// Минимальная ширина чипа: короче него подписи вроде «Думаю о тебе 27 · 200»
  /// начинают рваться на многоточие.
  static const double _chipMinWidth = 190;
  static const double _chipGap = 7;

  Widget _chips(ColorScheme cs) {
    // Ширина экрана у людей разная: 320 dp на старых Android, 393 на iPhone 15,
    // за 700 на планшете. Чипы держали свою ширину и на узком экране вставали
    // по одному, оставляя пустоту справа (жалоба 17.08.2026). Теперь колонки
    // считаются, а плитки делят строку ровно — см. tile_columns.dart.
    return LayoutBuilder(
      builder: (context, box) {
        final columns = tileColumns(
          width: box.maxWidth,
          minTileWidth: _chipMinWidth,
        );
        final width = tileWidth(
          width: box.maxWidth,
          columns: columns,
          spacing: _chipGap,
        );
        return Wrap(
          spacing: _chipGap,
          runSpacing: _chipGap,
          children: [
            for (final chip in _chipList(cs))
              SizedBox(width: width, child: chip),
          ],
        );
      },
    );
  }

  List<Widget> _chipList(ColorScheme cs) {
    return [
        _VibeChip(
          scheme: cs,
          icon: Icons.cloud_rounded,
          label: _s.thinkingOfYou,
          mine: _vibeCount('thinking_of_you', mine: true),
          partner: _vibeCount('thinking_of_you', mine: false),
          onTap: () => _sendVibe('thinking_of_you'),
        ),
        _VibeChip(
          scheme: cs,
          icon: Icons.volunteer_activism_rounded,
          label: _s.wantHug,
          mine: _vibeCount('want_hug', mine: true),
          partner: _vibeCount('want_hug', mine: false),
          onTap: () => _sendVibe('want_hug'),
        ),
        for (final w in _wishes)
          _VibeChip(
            scheme: cs,
            icon: Icons.edit_rounded,
            label: w,
            onTap: () => _sendVibe('custom', text: w),
            onRemove: () => _removeWish(w),
          ),
        _VibeChip(
          scheme: cs,
          icon: Icons.add_rounded,
          label: _s.customVibe,
          accent: true,
          accentFill: _fill,
          accentInk: _onFill,
          onTap: _addWish,
        ),
    ];
  }

  // ── Последнее от партнёра ───────────────────────────────────────────────────

  Widget _latest(ColorScheme cs) {
    final e = _state.partner!;
    final name =
        widget.partnerName.isEmpty ? _s.missYouPartner : widget.partnerName;
    final when = lastSeenLabel(
      e.updatedAt?.millisecondsSinceEpoch,
      _s.yesterday,
    );
    final label = e.lastVibe == 'custom' && e.lastVibeText.isNotEmpty
        ? e.lastVibeText
        : vibeLabel(e.lastVibe, _s);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(vibeIcon(e.lastVibe),
                size: 21, color: cs.onSecondaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  when.isEmpty ? '$name · ${_s.missYouLatest}' : '$name · $when',
                  style: _caption(cs),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: _replyBack,
            icon: Icon(vibeIcon(_replyVibe), size: 17),
            label: Text(_s.missYouReplyBack),
            style: FilledButton.styleFrom(
              backgroundColor: _fill,
              foregroundColor: _onFill,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── История дня ─────────────────────────────────────────────────────────────

  String _eventLabel(MissYouEvent e) =>
      e.vibe == 'custom' && e.text.isNotEmpty ? e.text : vibeLabel(e.vibe, _s);

  /// Импульсы сегодня (или вчера, если сегодня тихо) блоками, как строки
  /// настроек: у каждого свой, крайние скруглены сильнее, линий нет. На
  /// импульс партнёра — кнопка ответа тем же; ответил — галочка.
  Widget _history(ColorScheme cs) {
    final all = _events!;
    final day = missYouDay(all, DateTime.now());
    final replied = {...missYouReplied(all, widget.myUid), ..._justReplied};
    final byId = {for (final e in all) e.id: e};
    final events = day.events;
    final shown = _showAll || events.length <= _collapsed + 1 ? events : events.sublist(0, _collapsed);
    final title = day.yesterday ? trKey('missYouYesterdayTitle') : trKey('missYouToday');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(cs, events.isEmpty ? title : '$title · ${events.length}'),
        const SizedBox(height: 8),
        _blocks(cs, [
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Text(trKey('missYouEmptyDay'), style: _caption(cs).copyWith(fontSize: 13, height: 1.35)),
            ),
          for (final e in shown)
            _eventRow(cs, e, replied: replied.contains(e.id), original: e.replyTo == null ? null : byId[e.replyTo]),
          if (shown.length < events.length)
            InkWell(
              onTap: () => setState(() => _showAll = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Center(
                  child: Text(
                    trKey('missYouShowMore').replaceAll('{n}', '${events.length - shown.length}'),
                    style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: cs.primary),
                  ),
                ),
              ),
            ),
        ]),
      ],
    );
  }

  /// Блоки формы [SettingsGroup] — свой у каждой строки, крайние углы 28,
  /// внутренние 8, зазор 4, линий нет. Без `AppearOnScroll` группы: экран и
  /// так въезжает целиком, а строки, ждущие прокрутки, на коротком экране не
  /// появлялись вовсе.
  Widget _blocks(ColorScheme cs, List<Widget> rows) {
    const outer = Radius.circular(SettingsGroup.outerRadius);
    const inner = Radius.circular(SettingsGroup.innerRadius);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: SettingsGroup.gap),
          Material(
            color: cs.surfaceContainerHigh,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.vertical(
              top: i == 0 ? outer : inner,
              bottom: i == rows.length - 1 ? outer : inner,
            ),
            child: rows[i],
          ),
        ],
      ],
    );
  }

  Widget _eventRow(ColorScheme cs, MissYouEvent e, {required bool replied, MissYouEvent? original}) {
    final mine = e.uid == widget.myUid;
    final name = mine
        ? _s.missYouYou
        : (widget.partnerName.isEmpty ? _s.missYouPartner : widget.partnerName);
    final sub = original != null
        ? trKey('missYouInReplyTo').replaceAll('{x}', _eventLabel(original))
        : name;
    final hh = '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              hh,
              style: _caption(cs).copyWith(fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          AvatarWidget(
            uid: mine ? widget.myUid : widget.partnerUid,
            fallbackUrl: mine ? widget.myAvatarUrl : widget.partnerAvatarUrl,
            name: mine ? widget.myName : widget.partnerName,
            size: 28,
            primary: cs.primary,
            showFrame: false,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.count > 1 ? '${_eventLabel(e)} ×${e.count}' : _eventLabel(e),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _caption(cs)),
              ],
            ),
          ),
          if (!mine) ...[
            const SizedBox(width: 8),
            replied
                ? Tooltip(
                    message: trKey('missYouReplied'),
                    child: SizedBox.square(
                      dimension: 40,
                      child: Icon(Icons.check_rounded, size: 20, color: cs.primary),
                    ),
                  )
                : IconButton.filled(
                    tooltip: trKey('missYouReplyTip'),
                    onPressed: () => _replyTo(e),
                    style: IconButton.styleFrom(backgroundColor: _fill, foregroundColor: _onFill),
                    icon: const Icon(Icons.reply_rounded, size: 20),
                  ),
          ],
        ],
      ),
    );
  }

  // ── Дни недели ──────────────────────────────────────────────────────────────

  Widget _week(ColorScheme cs) {
    final bars = weekBars(
      _state.mine?.byWeekday ?? const {},
      _state.partner?.byWeekday ?? const {},
    );
    final empty = weekBarsAreEmpty(bars);
    final today = DateTime.now().weekday;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _s.missYouWeekTitle,
            style:
                AppFonts.unbounded(size: 14, weight: 700, color: cs.onSurface),
          ),
          const SizedBox(height: 12),
          if (empty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_s.missYouWeekEmpty, style: _caption(cs)),
            )
          else
            SizedBox(
              height: 92,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final b in bars)
                    Expanded(
                      child: _WeekColumn(
                        scheme: cs,
                        fill: _fill,
                        bar: b,
                        label: _s.shortWeekdays[b.weekday - 1],
                        isToday: b.weekday == today,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(
          text.toUpperCase(),
          style: ProfileTheme.sectionLabel(cs),
        ),
      );
}

// ── Мелкие части ──────────────────────────────────────────────────────────────

/// Значок вайба. Тот же смысл, что нёс эмодзи, но красится ролью схемы.
IconData vibeIcon(String vibeType) => switch (vibeType) {
      'thinking_of_you' => Icons.cloud_rounded,
      'want_hug' => Icons.volunteer_activism_rounded,
      'custom' => Icons.edit_rounded,
      _ => Icons.favorite_rounded,
    };

String vibeLabel(String vibeType, AppStrings s) => switch (vibeType) {
      'thinking_of_you' => s.thinkingOfYou,
      'want_hug' => s.wantHug,
      'custom' => s.customVibe,
      _ => s.iMissYou,
    };

/// «12:33» за сегодня, «вчера 22:10» и дата дальше. Пусто, если отметки нет:
/// подпись «был давно» под пустым временем врала бы.
String lastSeenLabel(int? seenAtMs, String yesterdayWord) {
  if (seenAtMs == null || seenAtMs <= 0) return '';
  final seen = DateTime.fromMillisecondsSinceEpoch(seenAtMs);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(seen.year, seen.month, seen.day);
  final hhmm = '${seen.hour.toString().padLeft(2, '0')}:'
      '${seen.minute.toString().padLeft(2, '0')}';
  if (day == today) return hhmm;
  if (day == today.subtract(const Duration(days: 1))) {
    return '${yesterdayWord.toLowerCase()} $hhmm';
  }
  return '${seen.day.toString().padLeft(2, '0')}.'
      '${seen.month.toString().padLeft(2, '0')}';
}

class _HeartButton extends StatefulWidget {
  const _HeartButton({
    required this.fill,
    required this.onFill,
    required this.onTap,
  });

  final Color fill;
  final Color onFill;
  final VoidCallback onTap;

  @override
  State<_HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends State<_HeartButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            color: widget.fill,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.favorite_rounded,
            size: 58,
            color: widget.onFill,
          ),
        ),
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({
    required this.scheme,
    required this.fill,
    required this.onFill,
    required this.uid,
    required this.name,
    required this.count,
    required this.filled,
    this.avatarName,
    this.avatarUrl,
  });

  final ColorScheme scheme;
  final Color fill;
  final Color onFill;
  final String uid;
  final String name;

  /// Имя для буквы в кружке, когда снимка нет. Отдельно от [name]: под своим
  /// числом стоит слово «Ты», и заглушка из него давала букву «Т» вместо
  /// первой буквы имени — жалоба со скриншотом от 16.08.2026.
  final String? avatarName;

  final int count;
  final bool filled;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? fill : scheme.surfaceContainerHigh;
    final ink = filled ? onFill : scheme.onSurface;
    final muted =
        filled ? onFill.withValues(alpha: 0.75) : scheme.onSurfaceVariant;

    return Container(
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          AvatarWidget(
            uid: uid,
            fallbackUrl: avatarUrl,
            name: (avatarName?.trim().isNotEmpty == true) ? avatarName : name,
            size: 26,
            primary: ink,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Число набегает, а не перескакивает: рост счётчика — главное
                // подтверждение, что импульс ушёл.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: count.toDouble()),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Text(
                    '${value.round()}',
                    style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 11,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VibeChip extends StatelessWidget {
  const _VibeChip({
    required this.scheme,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onRemove,
    this.accent = false,
    this.accentFill,
    this.accentInk,
    this.mine = 0,
    this.partner = 0,
  });

  final ColorScheme scheme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool accent;
  final Color? accentFill;
  final Color? accentInk;

  /// Сколько раз этот импульс отправляли: свои и партнёрские. Просьба тестера
  /// («было бы классно добавить счёт в остальные пункты») — до этого число
  /// стояло только у «Скучаю», хотя сервер считает каждый импульс.
  final int mine;
  final int partner;

  @override
  Widget build(BuildContext context) {
    final bg = accent
        ? (accentFill ?? scheme.primary)
        : scheme.surfaceContainerHigh;
    final ink =
        accent ? (accentInk ?? scheme.onPrimary) : scheme.onSurface;

    return Material(
      color: bg,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onRemove,
        child: Padding(
          padding: EdgeInsets.fromLTRB(13, 0, onRemove == null ? 14 : 8, 0),
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: accent ? ink : scheme.primary),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                ),
                if (mine > 0 || partner > 0) ...[
                  const SizedBox(width: 8),
                  _VibeTally(
                    mine: mine,
                    partner: partner,
                    ink: ink,
                    muted: accent
                        ? ink.withValues(alpha: 0.62)
                        : scheme.onSurfaceVariant,
                  ),
                ],
                if (onRemove != null) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: scheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints.tightFor(width: 30, height: 30),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Два числа у импульса: свои и партнёрские, тем же порядком, что в шапке
/// («мои / её»). Ноль не рисуется вовсе — пустая пилюля читалась бы поломкой.
class _VibeTally extends StatelessWidget {
  const _VibeTally({
    required this.mine,
    required this.partner,
    required this.ink,
    required this.muted,
  });

  final int mine;
  final int partner;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    TextStyle style(Color color) => TextStyle(
          fontFamily: ProfileTheme.bodyFont,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: color,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$mine', style: style(ink)),
        Text(' · ', style: style(muted)),
        Text('$partner', style: style(muted)),
      ],
    );
  }
}

class _WeekColumn extends StatelessWidget {
  const _WeekColumn({
    required this.scheme,
    required this.fill,
    required this.bar,
    required this.label,
    required this.isToday,
  });

  final ColorScheme scheme;
  final Color fill;
  final WeekBar bar;
  final String label;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    const maxHeight = 62.0;
    // Ненулевой день обязан быть виден: доля 0,01 даёт полоску в полпикселя,
    // и «один раз за всё время» читался бы как ноль.
    double h(double fraction, int value) =>
        value == 0 ? 0 : max(4.0, maxHeight * fraction);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: maxHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _bar(h(bar.mineFraction, bar.mine), fill, top: true),
              const SizedBox(height: 2),
              _bar(h(bar.partnerFraction, bar.partner),
                  scheme.secondaryContainer),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: ProfileTheme.bodyFont,
            fontSize: 10,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
            color: isToday ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Столбик вырастает снизу за 520 мс. Смена данных догоняется той же
  /// анимацией: TweenAnimationBuilder идёт от текущего значения к новому.
  Widget _bar(double height, Color color, {bool top = false}) =>
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: height),
        duration: const Duration(milliseconds: 520),
        curve: const Cubic(0.05, 0.7, 0.1, 1),
        builder: (context, value, _) => Container(
          height: value,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: top
                ? const BorderRadius.vertical(top: Radius.circular(5))
                : const BorderRadius.vertical(bottom: Radius.circular(5)),
          ),
        ),
      );
}

class _Heart {
  _Heart({
    required this.icon,
    required this.controller,
    required this.dx,
    required this.rise,
    required this.size,
  });

  final IconData icon;
  final AnimationController controller;
  final double dx;
  final double rise;
  final double size;
}
