/// Ссылка из того, чем поделились в приложение.
///
/// Магазины отдают в «Поделиться» не адрес, а подпись целиком: название
/// товара, иногда цену, перенос строки и уже потом ссылку. Форме вещи нужен
/// только адрес, поэтому текст разбирается здесь, а не в приёмнике интента.
///
/// Возвращает первую http(s)-ссылку без хвостовой пунктуации или пустую
/// строку, если её нет. Чужие схемы (`loveapp://`, `mailto:`) не проходят:
/// карточку товара по ним всё равно не собрать.
String extractSharedUrl(String text) {
  if (text.isEmpty) return '';
  final match = RegExp(r'https?://[^\s<>"]+', caseSensitive: false)
      .firstMatch(text);
  if (match == null) return '';
  var url = match.group(0)!;
  // Точка, запятая и скобка в конце — часть предложения, а не адреса.
  const trailing = '.,;:!?)]}\'"»';
  while (url.isNotEmpty && trailing.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}
