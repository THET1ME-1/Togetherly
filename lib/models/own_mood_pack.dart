import '../services/plus_access.dart';
import 'custom_mood.dart';
import 'mood_band.dart';
import 'mood_pack.dart';

/// Набор «Свои» в ряду наборов настроений.
///
/// До 14.10.2026 свои настроения жили разделом над эмоциями ЛЮБОГО выбранного
/// набора: открыл «Классические» — сверху «Свои», открыл «Моти» — снова они.
/// Теперь это отдельная таблетка в ряду, и выбор её запоминается так же, как
/// выбор «Розовых». Идентификатор лежит в том же ключе настроек, что и паки.
const String kOwnMoodPackId = 'own';

/// Сколько своих настроений держит пара. Предел не про место на сервере, а про
/// сетку выбора: дальше третьего десятка её перестаёт быть видно целиком.
const int kOwnMoodLimit = 24;

/// Что показывает набор «Свои».
enum OwnPackState {
  /// Таблетки нет: одиночка без пары или iPhone, где Плюса нет вовсе.
  hidden,

  /// Набор ещё грузится.
  loading,

  /// Без Плюса и без своих настроений: пример и вход в Плюс.
  teaser,

  /// С Плюсом, но своих настроений пока нет: зовём завести первое.
  empty,

  /// Есть что выбрать.
  list,
}

/// Состояние набора «Свои» по паре, гейту Плюса и загрузке.
///
/// Настроения партнёра выбираются и без своего Плюса: заводит тот, у кого он
/// есть, а пользуются оба. Поэтому [PlusGate.locked] с настроениями — это
/// обычный список, а не пример.
OwnPackState ownPackState({
  required bool hasGroup,
  required PlusGate gate,
  required bool loaded,
  required int count,
}) {
  if (!hasGroup || gate == PlusGate.hidden) return OwnPackState.hidden;
  if (!loaded) return OwnPackState.loading;
  if (count > 0) return OwnPackState.list;
  return gate == PlusGate.open ? OwnPackState.empty : OwnPackState.teaser;
}

/// Можно ли выбрать «Свои» набором, то есть запомнить выбор.
///
/// Пример без Плюса только показывается, как закрытый платный набор: запомни
/// мы его, человек открывал бы лист и видел картинку, где выбрать нечего.
bool ownPackSelectable(OwnPackState state) =>
    state == OwnPackState.loading ||
    state == OwnPackState.empty ||
    state == OwnPackState.list;

/// Какую таблетку в ряду подсветить.
///
/// [resolvedId] — набор, который реально показан сеткой: незнакомый id (пак из
/// каталога, который ещё не приехал) превращается в классический, и подсвечен
/// должен быть он, а не ничего.
String shownMoodPackId({
  required String selectedId,
  required String resolvedId,
  required OwnPackState own,
  String? previewId,
  bool previewOwn = false,
}) {
  if (previewId != null) return previewId;
  if (previewOwn) return kOwnMoodPackId;
  if (selectedId == kOwnMoodPackId) {
    return ownPackSelectable(own) ? kOwnMoodPackId : MoodPack.classic.id;
  }
  return resolvedId;
}

/// Раздел своих настроений по шкале.
class OwnBandSection {
  final MoodBand band;
  final List<CustomMood> moods;

  const OwnBandSection(this.band, this.moods);
}

/// Свои настроения по разделам, как у остальных наборов: от светлого к
/// тяжёлому, внутри раздела — порядок заведения. Пустые разделы не нужны.
List<OwnBandSection> groupOwnByBand(List<CustomMood> moods) {
  final buckets = <MoodBand, List<CustomMood>>{
    for (final b in MoodBand.values) b: <CustomMood>[],
  };
  for (final m in moods) {
    buckets[bandOfScore(m.score)]!.add(m);
  }
  return [
    for (final b in MoodBand.values)
      if (buckets[b]!.isNotEmpty) OwnBandSection(b, buckets[b]!),
  ];
}

/// Набор полон: новое настроение завести нельзя, пока не убрано старое.
bool ownPackFull(int count) => count >= kOwnMoodLimit;
