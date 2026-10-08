import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';

Map<String, dynamic> _hw() => {
  'key': 'hw',
  'set': '13',
  'until': '2026-11-01',
  'perDay': 3,
  'name': {'ru': 'Хэллоуин', 'en': 'Halloween'},
  'tag': {'ru': 'Хэллоуин · до {date}', 'en': 'Halloween · until {date}'},
  'hint': {'ru': 'Внутри набор «13»'},
  'palette': {
    'page': '#1E1729',
    'surface': '#2C2238',
    'ink': '#F3E9F7',
    'ink2': '#BFAFCC',
    'fill': '#F0924A',
    'onFill': '#2A1A0E',
    'line': '#6E5A86',
  },
  'flash': {'color': '#EDE6FF', 'atMs': 900},
  'cardAspect': 1.1628,
  'track': {
    'frameMs': 60,
    'wonAtMs': 2000,
    'lockAtMs': 900,
    'frames': [null, null, [0.4, 0.4, 0.15], [0.3, 0.2, 0.36]],
  },
  'curtain': {
    'night': {'ms': 1760, 'coverMs': 620},
    'day': {'ms': 1380, 'coverMs': 620},
  },
  'files': {'idle': 'u/idle.webp', 'open': 'u/open.webp', 'music': 'u/music.wav'},
  'glitch': {'mid': '13/13', 'peak': '666', 'peakColor': '#A3101C'},
};

void main() {
  test('сезонный сундук разбирается целиком', () {
    final s = SeasonChest.fromJson(_hw())!;
    expect(s.key, 'hw');
    expect(s.set, '13');
    expect(s.perDay, 3);
    expect(s.palette!.page, const Color(0xFF1E1729));
    expect(s.palette!.fill, const Color(0xFFF0924A));
    expect(s.flashColor, const Color(0xFFEDE6FF));
    expect(s.flashAtMs, 900);
    expect(s.track, hasLength(4));
    expect(s.track[2], [0.4, 0.4, 0.15]);
    expect(s.wonAtMs, 2000);
    expect(s.curtainNightCoverMs, 620);
    expect(s.file('music'), 'u/music.wav');
    expect(s.lastDay, DateTime(2026, 10, 31));
    expect(s.glitch!.peak, '666');
    expect(s.glitch!.peakColor, const Color(0xFFA3101C));
  });

  test('без описания сбоя кнопка честная', () {
    expect(SeasonChest.fromJson({..._hw()}..remove('glitch'))!.glitch, isNull);
    expect(SeasonChest.fromJson({..._hw(), 'glitch': {'mid': '13/13'}})!.glitch, isNull);
  });

  test('язык: свой, иначе английский, иначе русский', () {
    final s = SeasonChest.fromJson(_hw())!;
    expect(s.nameIn('ru'), 'Хэллоуин');
    expect(s.nameIn('de'), 'Halloween');
    expect(s.hintIn('fr'), 'Внутри набор «13»');
    expect(s.tagIn('ru', '1 ноября'), 'Хэллоуин · до 1 ноября');
  });

  test('кривая запись не роняет список', () {
    final bad = {..._hw()}..remove('set');
    final noFiles = {..._hw(), 'files': {'idle': 'x'}};
    final list = SeasonChest.listFromJson([_hw(), bad, noFiles, 'мусор', null]);
    expect(list.map((s) => s.key), ['hw']);
    expect(SeasonChest.listFromJson(null), isEmpty);
  });

  test('без палитры страница остаётся в теме пары', () {
    final s = SeasonChest.fromJson({..._hw(), 'palette': {'page': 'чёрный'}})!;
    expect(s.palette, isNull);
  });

  test('сезоны приезжают в состоянии обычного сундука', () {
    final st = ChestState.fromJson({
      'ok': true,
      'left': 2,
      'perDay': 3,
      'odds': [
        {'key': 'coins5', 'kind': 'coins', 'amount': 5, 'tier': 'common', 'weight': 1000},
      ],
      'seasons': [_hw()],
    });
    expect(st, isNotNull);
    expect(st!.seasons.single.key, 'hw');
    expect(st.afterOpen(left: 1).seasons.single.key, 'hw');
  });
}
