/// Подпись заметки на двоих из записи `widget_data`: текст и время.
///
/// Заметка лежит в json-поле `data` каждого из пары (`data.note`). По подписи
/// видно, что партнёр её поменял, и только тогда стоит тянуть текст заново
/// (TOG-13). Нет заметки или поле кривое — пустая строка.
String noteSignatureOf(Map<String, dynamic> record) {
  final data = record['data'];
  if (data is! Map) return '';
  final note = data['note'];
  if (note is! Map) return '';
  final text = (note['text'] ?? '').toString();
  if (text.isEmpty) return '';
  return '$text|${note['at'] ?? ''}';
}
