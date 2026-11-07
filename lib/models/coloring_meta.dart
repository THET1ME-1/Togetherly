/// Нужно ли дописать на сервер картинку раскраски.
///
/// Картинка уходит одной записью при заведении листа, а «Готово» и смена
/// половин пишут мету через «обновить, а нет — создать». Не дошла первая
/// запись — «Готово» заводило мету без картинки, и телефон партнёра открывал
/// лист обычным холстом, без контура и половин (обращение 344, 19.10.2026).
///
/// [remoteExists] — мета на сервере уже есть: пока её нет, картинку как раз
/// несёт запись заведения листа, и второй раз её слать незачем.
bool coloringMetaNeedsPicture({
  required bool remoteExists,
  required String? remote,
  required String? local,
}) =>
    remoteExists && (local ?? '').isNotEmpty && (remote ?? '').isEmpty;

bool _isOwn(String? id) => (id ?? '').startsWith('own_');

/// Нужно ли забрать контур своей раскраски, которую завёл партнёр.
///
/// Раньше контур скачивался только при смене картинки на холсте: сорвалось
/// скачивание или ссылка приехала следующей записью — и лист оставался пустым
/// до перезахода (TOG-82, 07.11.2026). Теперь — всякий раз, пока его нет.
bool coloringOutlineToAdopt({
  required String? picture,
  required String? outlineRef,
  required bool haveOutline,
}) =>
    _isOwn(picture) && (outlineRef ?? '').isNotEmpty && !haveOutline;

/// Нужно ли дослать на сервер ссылку на контур своей раскраски.
///
/// Контур уходит вместе с заведением листа; не загрузился он тогда — ссылка
/// так и оставалась пустой, и у партнёра лист был пустым навсегда (на
/// 07.11.2026 таких 58). Дослать может тот, у кого контур есть, и только для
/// той же картинки, что на сервере.
bool coloringMetaNeedsOutline({
  required String? remotePicture,
  required String? local,
  required String? remoteOutline,
  required bool haveOutline,
}) =>
    _isOwn(remotePicture) && remotePicture == local && (remoteOutline ?? '').isEmpty && haveOutline;
