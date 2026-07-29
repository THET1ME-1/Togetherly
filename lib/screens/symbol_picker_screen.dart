import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/symbol_catalog.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../widgets/common/m3_loading.dart';

/// Выбор символа для таймера из полного набора Material Symbols.
///
/// Пять привычных значков лежат прямо в редакторе таймера, сюда заходят за
/// остальными: 4334 штуки с поиском по-русски и по имени символа.
class SymbolPickerScreen extends StatefulWidget {
  const SymbolPickerScreen({
    super.key,
    required this.theme,
    required this.selected,
  });

  final AppTheme theme;

  /// Имя выбранного символа — подсвечивается в сетке.
  final String selected;

  @override
  State<SymbolPickerScreen> createState() => _SymbolPickerScreenState();
}

class _SymbolPickerScreenState extends State<SymbolPickerScreen> {
  final _query = TextEditingController();
  List<String> _results = const [];
  bool _loading = true;

  /// Подборки под наши поводы: за таймером приходят ради годовщины, свадьбы,
  /// ребёнка, переезда, учёбы или дороги.
  static const Map<String, List<String>> _sets = {
    'love': [
      'favorite', 'favorite_border', 'heart_plus', 'volunteer_activism',
      'diamond', 'celebration', 'local_florist', 'spa', 'wine_bar',
      'nightlife', 'photo_camera', 'mail',
    ],
    'holidays': [
      'cake', 'celebration', 'festival', 'card_giftcard', 'redeem',
      'local_activity', 'emoji_events', 'auto_awesome', 'icecream',
      'local_bar', 'stars', 'confirmation_number',
    ],
    'home': [
      'home', 'house', 'cottage', 'apartment', 'key', 'chair', 'bed',
      'kitchen', 'yard', 'pets', 'door_front', 'local_laundry_service',
    ],
    'road': [
      'flight', 'flight_takeoff', 'luggage', 'travel_explore', 'map',
      'directions_car', 'train', 'sailing', 'beach_access', 'hiking',
      'landscape', 'photo_camera',
    ],
    'work': [
      'work', 'school', 'menu_book', 'business_center', 'badge', 'handshake',
      'savings', 'payments', 'fitness_center', 'rocket_launch',
      'track_changes', 'military_tech',
    ],
  };

  String _set = 'love';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await SymbolCatalog.load();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    setState(() => _results = searchSymbols(value));
  }

  List<String> get _visible {
    if (_query.text.trim().isNotEmpty) return _results;
    return (_sets[_set] ?? const []).where(SymbolCatalog.has).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.themeFor(widget.theme).colorScheme;
    final s = LocaleService.current;
    final searching = _query.text.trim().isNotEmpty;
    final items = _visible;

    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            s.symbolPickerTitle,
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        body: _loading
            ? Center(child: M3PageLoading(color: cs.primary))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      controller: _query,
                      onChanged: _onQuery,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: s.symbolSearchHint,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: searching
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _query.clear();
                                  _onQuery('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: cs.surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  if (!searching)
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final entry in _sets.keys)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(_setLabel(entry, s)),
                                selected: _set == entry,
                                onSelected: (_) => setState(() => _set = entry),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                    child: Text(
                      searching
                          ? (items.isEmpty
                              ? s.symbolSearchEmpty
                              : s.symbolSearchFound(items.length))
                          : s.symbolSetHint,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        MediaQuery.of(context).padding.bottom + 24,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                      ),
                      // Список ограничиваем: по запросу «a» подходит половина
                      // каталога, и рисовать её целиком незачем — уточнить
                      // запрос быстрее, чем пролистать тысячу значков.
                      itemCount: items.length > 200 ? 200 : items.length,
                      itemBuilder: (_, i) {
                        final name = items[i];
                        final selected = name == widget.selected;
                        return Material(
                          color: selected
                              ? cs.primary
                              : cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(18),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(context, name);
                            },
                            child: Center(
                              child: SymbolIcon(
                                name,
                                size: 26,
                                color:
                                    selected ? cs.onPrimary : cs.onSurface,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _setLabel(String key, AppStrings s) => switch (key) {
        'love' => s.symbolSetLove,
        'holidays' => s.symbolSetHolidays,
        'home' => s.symbolSetHome,
        'road' => s.symbolSetRoad,
        _ => s.symbolSetWork,
      };
}
