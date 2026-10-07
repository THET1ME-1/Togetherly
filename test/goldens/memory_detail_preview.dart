import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/screens/memory_lane_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/theme_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Открытые воспоминания глазами: заметка, видео по ссылке и своё видео без
/// кадра в каркасе «как фото», светлая и тёмная тема, 360 точек.
///
///   flutter test test/goldens/memory_detail_preview.dart → build/memory-detail/*.png
///
/// «place» отчитывается провалом уже ПОСЛЕ снимка: vector_map_tiles при
/// закрытии отменяет свою фоновую нарезку плиток, и тест ловит эту отмену.
/// Кадр при этом записан; на экране приложения это не ошибка.

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

Memory _m(String id, MemoryType type,
        {String? title,
        String? caption,
        String? videoUrl,
        String? artist,
        String? imageUrl}) =>
    Memory(
      imageUrl: imageUrl,
      id: id,
      groupId: '',
      authorUid: 'u1',
      authorName: 'Аня',
      type: type,
      createdAt: DateTime(2026, 10, 7, 21, 40),
      title: title,
      caption: caption,
      videoUrl: videoUrl,
      musicArtist: artist,
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'ru'});
    await LocaleService.instance.init();
    // Экран слушает поток ленты; без клиента он падает на первом кадре.
    await PocketBaseService().init();
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _loadFont('MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT'] ?? '/home/alelx/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  final cases = {
    'note': _m('n1', MemoryType.text,
        caption: 'Возвращаюсь домой, купи мандаринов'),
    'note-long': _m('n2', MemoryType.text,
        title: 'Список на выходные',
        caption: 'Забрать посылку\nКупить подарок маме\nЗаписаться на стрижку\n'
            'Позвонить бабушке\nВыбрать фильм на вечер'),
    'link': _m('l1', MemoryType.videoLink,
        title: 'когда он опять забыл купить хлеб',
        artist: '@mila.k',
        caption: 'Это прямо мы в субботу, смотри до конца',
        videoUrl: 'https://www.tiktok.com/@mila.k/video/1'),
    'video': _m('v1', MemoryType.video,
        title: 'Сплав по озеру',
        caption: 'Первый раз на байдарке',
        videoUrl: 'pb://media/abc/video.mp4'),
    // Фото с роликом: тулбар рядом с кнопкой сохранения — та же теснота.
    'photo': _m('p1', MemoryType.photo,
        title: 'Сплав по озеру',
        imageUrl: 'pb://media/abc/a.jpg',
        videoUrl: 'pb://media/abc/video.mp4'),
    'music': Memory(
      id: 'm1', groupId: '', authorUid: 'u1', authorName: 'Аня',
      type: MemoryType.music, createdAt: DateTime(2026, 10, 7, 21, 40),
      musicTitle: 'Звезда по имени Солнце', musicArtist: 'Кино',
      musicUrl: 'https://music.yandex.ru/track/1',
      caption: 'Играла, когда мы ехали к морю',
    ),
    // Свой файл: печенье «играть» на краю обложки.
    'music-file': Memory(
      id: 'm2', groupId: '', authorUid: 'u1', authorName: 'Аня',
      type: MemoryType.music, createdAt: DateTime(2026, 10, 7, 21, 40),
      musicTitle: 'Наша песня', musicArtist: 'Голосовое с кухни',
      musicUrl: 'pb://media/abc/track.m4a',
    ),
    'book': Memory(
      id: 'b1', groupId: '', authorUid: 'u1', authorName: 'Аня',
      type: MemoryType.book, createdAt: DateTime(2026, 10, 7, 21, 40),
      title: 'Мастер и Маргарита', bookAuthor: 'Михаил Булгаков',
      bookYear: '1967', bookPublisher: 'АСТ', rating: 5,
      caption: 'Читали по главе перед сном',
    ),
    'movie': Memory(
      id: 'f1', groupId: '', authorUid: 'u1', authorName: 'Аня',
      type: MemoryType.movie, createdAt: DateTime(2026, 10, 7, 21, 40),
      title: 'Интерстеллар', movieOriginalTitle: 'Interstellar',
      movieYear: '2014', movieKind: 'movie', movieGenres: 'фантастика, драма',
      movieCountry: 'США', movieRatingKp: '8.6', rating: 4,
      caption: 'Плакали оба',
    ),
    'place': Memory(
      id: 'pl1', groupId: '', authorUid: 'u1', authorName: 'Аня',
      type: MemoryType.location, createdAt: DateTime(2026, 10, 7, 21, 40),
      locationName: 'Парк Валя Морилор', latitude: 47.0105, longitude: 28.8186,
      caption: 'Здесь мы впервые поцеловались',
    ),
  };

  for (final b in Brightness.values) {
    for (final e in cases.entries) {
      testWidgets('${e.key} ${b.name}', (tester) async {
        tester.view.physicalSize = const Size(360 * 2, 780 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: ThemeScope(
            theme: buildAppTheme(kPalettes[0], b),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              // Лист в приложении живёт внутри showAppSheet, у него есть
              // Material сверху; экрану-моменту Scaffold не мешает.
              home: Scaffold(body: memoryDetailForPreview(e.value)),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('build/memory-detail').createSync(recursive: true);
          File('build/memory-detail/${e.key}-${b.name}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        expect(tester.takeException(), isNull, reason: 'переполнение или падение');
        // Векторная карта режет плитки в фоне; закрытие посреди работы
        // роняет прогон отменой, поэтому даём ей доделать.
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 800)));
        await tester.pumpWidget(const SizedBox());
        // Повторы сетевых запросов и анимации доживают свои таймеры.
        await tester.pump(const Duration(minutes: 2));
      });
    }
  }
}
