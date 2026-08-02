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

Map<String, dynamic> _clean(Map<String, dynamic> row) => {
      for (final e in row.entries)
        if (!kExportSecrets.contains(e.key)) e.key: e.value,
    };

/// Собирает архив: когда снят, чем снят, чей и что внутри.
Map<String, dynamic> buildExportBundle({
  required DateTime takenAt,
  required String appVersion,
  required String uid,
  required Map<String, List<Map<String, dynamic>>> sections,
}) {
  final data = <String, dynamic>{};
  final counts = <String, dynamic>{};
  for (final entry in sections.entries) {
    data[entry.key] = entry.value.map(_clean).toList();
    counts[entry.key] = entry.value.length;
  }
  return {
    'taken_at': takenAt.toUtc().toIso8601String(),
    'app_version': appVersion,
    'uid': uid,
    'counts': counts,
    'data': data,
  };
}
