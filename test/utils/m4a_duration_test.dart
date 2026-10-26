import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/m4a_duration.dart';

/// Атом MP4: длина, имя, тело.
Uint8List _atom(String name, List<int> body) {
  final b = BytesBuilder()
    ..add(_u32(8 + body.length))
    ..add(name.codeUnits)
    ..add(body);
  return b.toBytes();
}

List<int> _u32(int v) =>
    [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

List<int> _u64(int v) => [..._u32(v >> 32), ..._u32(v & 0xffffffff)];

void main() {
  test('длина из файла, где заголовок в конце', () {
    final d = m4aDuration(
        File('test/fixtures/voice/tone_11_6s_moov_end.m4a').readAsBytesSync());
    expect(d!.inMilliseconds, closeTo(11600, 50));
  });

  test('длина из файла, где заголовок в начале', () {
    final d = m4aDuration(File('test/fixtures/voice/tone_11_6s_moov_start.m4a')
        .readAsBytesSync());
    expect(d!.inMilliseconds, closeTo(11600, 50));
  });

  test('mdat с 64-битной длиной и mvhd второй версии', () {
    // Так пишет MediaMuxer на Android: mdat с длиной 1 и настоящей длиной
    // следом восемью байтами.
    final mdatBody = List<int>.filled(100, 7);
    final mdat = BytesBuilder()
      ..add(_u32(1))
      ..add('mdat'.codeUnits)
      ..add(_u64(16 + mdatBody.length))
      ..add(mdatBody);
    final mvhd = _atom('mvhd', [
      1, 0, 0, 0, // версия 1 и флаги
      ..._u64(0), ..._u64(0), // создание и правка
      ..._u32(1000), // единиц в секунде
      ..._u64(40588), // длительность
      ...List<int>.filled(80, 0),
    ]);
    final bytes = BytesBuilder()
      ..add(_atom('ftyp', 'M4A '.codeUnits))
      ..add(mdat.toBytes())
      ..add(_atom('moov', mvhd));
    expect(m4aDuration(bytes.toBytes()), const Duration(milliseconds: 40588));
  });

  test('мусор и обрезанный файл дают null, а не падение', () {
    expect(m4aDuration(Uint8List.fromList(List<int>.filled(64, 0xff))), isNull);
    expect(m4aDuration(Uint8List(0)), isNull);
    final full = File('test/fixtures/voice/tone_11_6s_moov_end.m4a')
        .readAsBytesSync();
    // Запись оборвалась до заголовка — длины в файле нет.
    expect(m4aDuration(Uint8List.sublistView(full, 0, full.length - 200)),
        isNull);
  });

  test('нулевой масштаб времени не делит на ноль', () {
    final mvhd = _atom('mvhd', [
      0, 0, 0, 0,
      ..._u32(0), ..._u32(0),
      ..._u32(0), // единиц в секунде — ноль
      ..._u32(5000),
      ...List<int>.filled(80, 0),
    ]);
    final bytes = BytesBuilder()
      ..add(_atom('ftyp', 'M4A '.codeUnits))
      ..add(_atom('moov', mvhd));
    expect(m4aDuration(bytes.toBytes()), isNull);
  });
}
