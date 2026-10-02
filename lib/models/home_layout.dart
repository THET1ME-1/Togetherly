/// Раскладка главного экрана с Togetherly+: какие вкладки нижней панели и
/// какие блоки главной показывать и в каком порядке идут блоки (просьба из
/// отзыва 02.10.2026: «ненужный функционал скрывать… кто-то минимализм любит»).
///
/// Двигаются и прячутся только блоки ниже ряда быстрых действий. Календарь
/// настроений, таймер и сам ряд остаются на месте: ради них приложение
/// открывают, а вёрстку таймера трогать нельзя (см. «Карточку таймера не
/// трогать» в CLAUDE.md проекта).
///
/// Без Плюса раскладка хранится, но не действует: [effective] отдаёт порядок
/// по умолчанию. Кончился Плюс — главная возвращается целиком, купил снова —
/// прежняя раскладка на месте.
enum HomeBlock { chest, mascot, map, tasks, wishes, lane }

/// Вкладки, которые можно убрать из нижней панели. Главная, «Связь» и
/// профиль остаются всегда: без них не попасть ни в пару, ни в настройки.
enum HomeTab { widgets, watch }

class HomeLayout {
  const HomeLayout({
    this.order = defaultOrder,
    this.hiddenBlocks = const {},
    this.hiddenTabs = const {},
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

  /// Раскладка, которая действует сейчас: без Плюса — по умолчанию.
  HomeLayout effective({required bool plus}) =>
      plus ? this : const HomeLayout();

  /// Видимые блоки по порядку.
  List<HomeBlock> get visibleBlocks =>
      [for (final b in order) if (!hiddenBlocks.contains(b)) b];

  bool showsBlock(HomeBlock b) => !hiddenBlocks.contains(b);
  bool showsTab(HomeTab t) => !hiddenTabs.contains(t);

  HomeLayout withBlock(HomeBlock b, {required bool shown}) => HomeLayout(
        order: order,
        hiddenBlocks: shown
            ? ({...hiddenBlocks}..remove(b))
            : {...hiddenBlocks, b},
        hiddenTabs: hiddenTabs,
      );

  HomeLayout withTab(HomeTab t, {required bool shown}) => HomeLayout(
        order: order,
        hiddenBlocks: hiddenBlocks,
        hiddenTabs: shown ? ({...hiddenTabs}..remove(t)) : {...hiddenTabs, t},
      );

  /// Переставляет блок с места [from] на место [to] (индексы в [order], как
  /// после удаления элемента — то есть уже поправленные под ReorderableList).
  HomeLayout moved(int from, int to) {
    if (from < 0 || from >= order.length) return this;
    final list = [...order];
    final b = list.removeAt(from);
    list.insert(to.clamp(0, list.length), b);
    return HomeLayout(order: list, hiddenBlocks: hiddenBlocks, hiddenTabs: hiddenTabs);
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
    return HomeLayout(order: list, hiddenBlocks: hiddenBlocks, hiddenTabs: hiddenTabs);
  }

  /// Сдвиг блока на шаг вверх ([delta] = -1) или вниз (+1) среди ВИДИМЫХ:
  /// спрятанные соседи не должны съедать нажатие «Выше».
  HomeLayout shifted(HomeBlock b, int delta) {
    final visible = visibleBlocks;
    final i = visible.indexOf(b);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= visible.length) return this;
    final other = visible[j];
    final list = [...order];
    final ib = list.indexOf(b), io = list.indexOf(other);
    list[ib] = other;
    list[io] = b;
    return HomeLayout(order: list, hiddenBlocks: hiddenBlocks, hiddenTabs: hiddenTabs);
  }

  bool get isDefault =>
      hiddenBlocks.isEmpty &&
      hiddenTabs.isEmpty &&
      _sameOrder(order, defaultOrder);

  static bool _sameOrder(List<HomeBlock> a, List<HomeBlock> b) {
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
      };

  /// Разбор сохранённого. Незнакомые имена (блок убрали из приложения)
  /// пропускаются, новые блоки встают на своё место по умолчанию: сразу за
  /// тем, за кем стоят в [defaultOrder].
  static HomeLayout fromJson(Object? raw) {
    if (raw is! Map) return const HomeLayout();
    List<T> names<T extends Enum>(Object? v, List<T> values) {
      if (v is! List) return const [];
      final out = <T>[];
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
    return HomeLayout(
      order: order,
      hiddenBlocks: names(raw['hiddenBlocks'], HomeBlock.values).toSet(),
      hiddenTabs: names(raw['hiddenTabs'], HomeTab.values).toSet(),
    );
  }
}
