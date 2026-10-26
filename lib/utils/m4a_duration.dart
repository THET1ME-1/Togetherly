import 'dart:typed_data';

/// Длительность звука из заголовка файла m4a (атом `moov/mvhd`).
///
/// Голосовые пишутся в m4a и на Android, и на iPhone, а длина записи в
/// заголовке точнее любых часов: часы считают и ожидание остановки, которое на
/// Android доходит до десятков секунд. `null` — заголовка нет (запись
/// оборвалась) или он не читается.
Duration? m4aDuration(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final moov = _findAtom(data, 0, bytes.length, 'moov');
  if (moov == null) return null;
  final mvhd = _findAtom(data, moov.$1, moov.$2, 'mvhd');
  if (mvhd == null) return null;
  final at = mvhd.$1;
  final end = mvhd.$2;
  if (at + 4 > end) return null;
  final version = data.getUint8(at);
  final int scale;
  final int units;
  if (version == 1) {
    // версия и флаги 4, создание 8, правка 8, масштаб 4, длительность 8
    if (at + 32 > end) return null;
    scale = data.getUint32(at + 20);
    units = data.getUint64(at + 24);
  } else {
    // версия и флаги 4, создание 4, правка 4, масштаб 4, длительность 4
    if (at + 20 > end) return null;
    scale = data.getUint32(at + 12);
    units = data.getUint32(at + 16);
  }
  if (scale <= 0 || units <= 0) return null;
  return Duration(microseconds: (units * 1000000) ~/ scale);
}

/// Ищет атом [name] между [from] и [to]. Отдаёт начало и конец его тела.
(int, int)? _findAtom(ByteData data, int from, int to, String name) {
  var i = from;
  while (i + 8 <= to) {
    var size = data.getUint32(i);
    var header = 8;
    if (size == 1) {
      if (i + 16 > to) return null;
      size = data.getUint64(i + 8);
      header = 16;
    } else if (size == 0) {
      size = to - i;
    }
    if (size < header || i + size > to) return null;
    final type = String.fromCharCodes(
        Uint8List.sublistView(data, i + 4, i + 8));
    if (type == name) return (i + header, i + size);
    i += size;
  }
  return null;
}
