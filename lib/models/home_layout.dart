/// Раскладка главного экрана с Togetherly+: какие вкладки нижней панели,
/// какие кнопки ряда под таймером и какие блоки главной показывать, и в каком
/// порядке идут блоки (просьба из отзыва 02.10.2026: «ненужный функционал
/// скрывать… кто-то минимализм любит»).
///
/// Двигаются и прячутся блоки ниже ряда быстрых действий. Календарь
/// настроений и таймер остаются всегда: ради них приложение открывают, а
/// вёрстку таймера трогать нельзя (см. «Карточку таймера не трогать» в
/// CLAUDE.md проекта). В самом ряду кнопки можно только спрятать, их порядок
/// задан дугой.
///
/// Без Плюса раскладка хранится, но не действует: [effective] отдаёт порядок
/// по умолчанию. Кончился Плюс — главная возвращается целиком, купил снова —
/// прежняя раскладка на месте.
enum HomeBlock { chest, mascot, map, tasks, wishes, lane }

/// Вкладки нижней панели. Переставлять можно все, убрать — только «Виджеты»
/// и «Смотрим»: без главной, «Связи» и профиля не попасть ни в пару, ни в
/// настройки.
enum HomeTab {
  home(0),
  widgets(1),
  watch(4),
  connect(2),
  profile(3);

  const HomeTab(this.navIndex);

  /// Номер вкладки в `HomeScreen._selectedNavIndex`.
  final int navIndex;

  bool get canHide => this == widgets || this == watch;
}

/// Кнопки ряда под таймером, слева направо по дуге.
enum HomeAction { draw, mood, wallet, calendar, post }

class HomeLayout {
  const HomeLayout({
    this.order = defaultOrder,
    this.hiddenBlocks = const {},
    this.hiddenTabs = const {},
    this.hiddenActions = const {},
    this.tabOrder = HomeTab.values,
  });

  /// Порядок, в котором блоки стояли до раскладки.
  static const List<HomeBlock> defaultOrder = [
    HomeBlock.chest,
    HomeBlock.mascot,
    HomeBlock.map,
    HomeBlock.tasks,
    HomeBlock.wishes,
    HomeBlock.lane,
  ];

  final List<HomeBlock> order;
  final Set<HomeBlock> hiddenBlocks;
  final Set<HomeTab> hiddenTabs;
  final Set<HomeAction> hiddenActions;

  /// Вкладки нижней панели слева направо, вместе со спрятанными.
  final List<HomeTab> tabOrder;

  /// Номера видимых вкладок по порядку — для `HomeBottomNav.order`.
  List<int> get navOrder => [
        for (final t in tabOrder)
          if (showsTab(t)) t.navIndex,
      ];

  HomeLayout _copy({
    List<HomeBlock>? order,
    Set<HomeBlock>? hiddenBlocks,
    Set<HomeTab>? hiddenTabs,
    Set<HomeAction>? hiddenActions,
    List<HomeTab>? tabOrder,
  }) =>
      HomeLayout(
        order: order ?? this.order,
        hiddenBlocks: hiddenBlocks ?? this.hiddenBlocks,
        hiddenTabs: hiddenTabs ?? this.hiddenTabs,
        hiddenActions: hiddenActions ?? this.hiddenActions,
        tabOrder: tabOrder ?? this.tabOrder,
      );

  /// Переставляет вкладку, индексы как у `onReorder` (то есть [to] ещё до
  /// удаления перетаскиваемой).
  HomeLayout tabMoved(int from, int to) {
    if (from < 0 || from >= tabOrder.length) return this;
    final target = to > from ? to - 1 : to;
    final list = [...tabOrder];
    final t = list.removeAt(from);
    list.insert(target.clamp(0, list.length), t);
    return _copy(tabOrder: list);
  }

  /// Раскладка, которая действует сейчас: без Плюса — по умолчанию.
  HomeLayout effective({required bool plus}) =>
      plus ? this : const HomeLayout();

  /// Видимые блоки по порядку.
  List<HomeBlock> get visibleBlocks =>
      [for (final b in order) if (!hiddenBlocks.contains(b)) b];

  bool showsBlock(HomeBlock b) => !hiddenBlocks.contains(b);
  bool showsTab(HomeTab t) => !hiddenTabs.contains(t);
  bool showsAction(HomeAction a) => !hiddenActions.contains(a);

  HomeLayout withBlock(HomeBlock b, {required bool shown}) => _copy(
        hiddenBlocks:
            shown ? ({...hiddenBlocks}..remove(b)) : {...hiddenBlocks, b},
      );

  HomeLayout withTab(HomeTab t, {required bool shown}) {
    if (!shown && !t.canHide) return this;
    return _copy(
      hiddenTabs: shown ? ({...hiddenTabs}..remove(t)) : {...hiddenTabs, t},
    );
  }

  HomeLayout withAction(HomeAction a, {required bool shown}) => _copy(
        hiddenActions:
            shown ? ({...hiddenActions}..remove(a)) : {...hiddenActions, a},
      );

  /// Переставляет блок с места [from] на место [to] (индексы в [order], как
  /// после удаления элемента — то есть уже поправленные под ReorderableList).
  HomeLayout moved(int from, int to) {
    if (from < 0 || from >= order.length) return this;
    final list = [...order];
    final b = list.removeAt(from);
    list.insert(to.clamp(0, list.length), b);
    return _copy(order: list);
  }

  /// Перетаскивание на главной: [shown] — блоки, которые сейчас на экране,
  /// [from] и [to] — индексы в нём, как их отдаёт `onReorder` (то есть [to]
  /// ещё до удаления перетаскиваемого). Спрятанные и не показанные сейчас
  /// блоки (желания выключены с сервера, нет пары) остаются на своих местах
  /// относительно соседей: блок встаёт перед тем, кто оказался за ним.
  HomeLayout dragged(List<HomeBlock> shown, int from, int to) {
    if (from < 0 || from >= shown.length) return this;
    final target = to > from ? to - 1 : to;
    if (target == from) return this;
    final b = shown[from];
    final next = [...shown]..removeAt(from);
    next.insert(target.clamp(0, next.length), b);
    final pos = next.indexOf(b);
    final list = [...order]..remove(b);
    if (pos + 1 < next.length) {
      list.insert(list.indexOf(next[pos + 1]), b);
    } else {
      list.insert(list.indexOf(next[pos - 1]) + 1, b);
    }
    return _copy(order: list);
  }

  bool get isDefault =>
      hiddenBlocks.isEmpty &&
      hiddenTabs.isEmpty &&
      hiddenActions.isEmpty &&
      _sameOrder(order, defaultOrder) &&
      _sameOrder(tabOrder, HomeTab.values);

  static bool _sameOrder<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Map<String, Object> toJson() => {
        'order': [for (final b in order) b.name],
        'hiddenBlocks': [for (final b in hiddenBlocks) b.name],
        'hiddenTabs': [for (final t in hiddenTabs) t.name],
        'hiddenActions': [for (final a in hiddenActions) a.name],
        'tabOrder': [for (final t in tabOrder) t.name],
      };

  /// Разбор сохранённого. Незнакомые имена (блок убрали из приложения)
  /// пропускаются, новые блоки встают на своё место по умолчанию: сразу за
  /// тем, за кем стоят в [defaultOrder].
  static HomeLayout fromJson(Object? raw) {
    if (raw is! Map) return const HomeLayout();
    List<T> names<T extends Enum>(Object? v, List<T> values) {
      final out = <T>[];
      if (v is! List) return out;
      for (final x in v) {
        for (final e in values) {
          if (e.name == x && !out.contains(e)) out.add(e);
        }
      }
      return out;
    }

    final order = names(raw['order'], HomeBlock.values);
    for (var i = 0; i < defaultOrder.length; i++) {
      final b = defaultOrder[i];
      if (order.contains(b)) continue;
      final prev = i == 0 ? -1 : order.indexOf(defaultOrder[i - 1]);
      order.insert(prev + 1, b);
    }
    // Вкладки: пропавшие в сохранённом встают на своё место по умолчанию.
    final tabs = names(raw['tabOrder'], HomeTab.values);
    for (var i = 0; i < HomeTab.values.length; i++) {
      final t = HomeTab.values[i];
      if (tabs.contains(t)) continue;
      final prev = i == 0 ? -1 : tabs.indexOf(HomeTab.values[i - 1]);
      tabs.insert(prev + 1, t);
    }
    return HomeLayout(
      order: order,
      hiddenBlocks: names(raw['hiddenBlocks'], HomeBlock.values).toSet(),
      hiddenTabs: {
        for (final t in names(raw['hiddenTabs'], HomeTab.values))
          if (t.canHide) t,
      },
      hiddenActions: names(raw['hiddenActions'], HomeAction.values).toSet(),
      tabOrder: tabs,
    );
  }
}
