/// Приведение введённого кода приглашения к тому виду, в котором он лежит на
/// сервере.
///
/// В поле ввода приносят не только шесть символов. Вставляют ссылку целиком —
/// так бывает, когда приглашение переслали текстом и оно не кликнулось. Набирают
/// в русской раскладке: кириллические А, В, Е, К, М, Н, О, Р, С, Т, У, Х от
/// латинских не отличить ни на глаз, ни на слух. Приносят кавычку, которую
/// подставила автозамена на iPhone. Всё это раньше упиралось в «Код не найден».
///
/// Та же чистка живёт на сервере (`pocketbase/pb_hooks/invite.pb.js`) — она
/// выручает сборки, которые уже разошлись по телефонам. Здесь она нужна, чтобы
/// человек видел в поле ровно то, что уйдёт на проверку.
library;

const _cyrillicLookalikes = <String, String>{
  'А': 'A',
  'В': 'B',
  'Е': 'E',
  'К': 'K',
  'М': 'M',
  'Н': 'H',
  'О': 'O',
  'Р': 'P',
  'С': 'C',
  'Т': 'T',
  'У': 'Y',
  'Х': 'X',
};

String normalizeInviteCode(String? raw) {
  var s = (raw ?? '').toUpperCase().trim();

  // Ссылка-приглашение: и `https://host/invite/CODE`, и `loveapp://invite/CODE`.
  final marker = s.lastIndexOf('/INVITE/');
  if (marker != -1) s = s.substring(marker + '/INVITE/'.length);
  s = s.split('?').first.split('#').first;

  final out = StringBuffer();
  for (final ch in s.split('')) {
    final c = _cyrillicLookalikes[ch] ?? ch;
    final isLatin = c.compareTo('A') >= 0 && c.compareTo('Z') <= 0;
    final isDigit = c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
    if (isLatin || isDigit) out.write(c);
  }
  return out.toString();
}
