/// Архив «мои данные»: копия того, что приложение хранит о человеке.
///
/// Право забрать такую копию даёт и закон Республики Молдова № 133/2011, и
/// GDPR, а политика конфиденциальности обещает его прямо: «Настройки → Мои
/// данные → Скачать архив». Собирается архив здесь, чтобы состав было видно с
/// одного экрана и его можно было проверить тестами.
library;

/// Поля, которые в архив не попадают ни при каких условиях.
///
/// Файл уходит в мессенджер одним нажатием, а токен сессии или ключ кэша
/// открывают доступ ко всей переписке пары. Человеку они бесполезны, риск
/// несут настоящий.
const Set<String> kExportSecrets = {
  'token',
  'refresh_token',
  'password',
  'password_hash',
  'passwordHash',
  'cache_key',
  'cacheKey',
  'file_token',
};

/// Поля, по которым видно автора записи.
const List<String> kAuthorFields = [
  'author_uid',
  'authorUid',
  'uid',
  'user_uid',
  'from',
  'sender_uid',
];

Map<String, dynamic> _clean(Map<String, dynamic> row) => {
      for (final e in row.entries)
        if (!kExportSecrets.contains(e.key)) e.key: e.value,
    };

/// Моя ли это запись.
///
/// Право доступа даёт копию СВОИХ данных: профиль партнёра и его сообщения —
/// данные другого человека, и в машиночитаемом архиве им не место, файл уходит
/// куда угодно одним нажатием. Записи без автора — общее имущество пары
/// (таймеры, желания), их оставляем: иначе архив выйдет неполным.
bool _mine(Map<String, dynamic> row, String uid, {required bool byId}) {
  if (uid.isEmpty) return true;
  // Профили: владельца видно по самому идентификатору записи, поля автора там
  // нет вовсе.
  if (byId) return (row['id'] ?? '').toString() == uid;
  for (final field in kAuthorFields) {
    final value = row[field];
    if (value == null) continue;
    return value.toString() == uid;
  }
  return true;
}

/// Собирает архив: когда снят, чем снят, чей и что внутри.
Map<String, dynamic> buildExportBundle({
  required DateTime takenAt,
  required String appVersion,
  required String uid,
  required Map<String, List<Map<String, dynamic>>> sections,
  Set<String> ownedById = const {},
}) {
  final data = <String, dynamic>{};
  final counts = <String, dynamic>{};
  for (final entry in sections.entries) {
    final byId = ownedById.contains(entry.key);
    final mine = entry.value
        .where((row) => _mine(row, uid, byId: byId))
        .map(_clean)
        .toList();
    data[entry.key] = mine;
    counts[entry.key] = mine.length;
  }
  return {
    'taken_at': takenAt.toUtc().toIso8601String(),
    'app_version': appVersion,
    'uid': uid,
    'counts': counts,
    'data': data,
  };
}
