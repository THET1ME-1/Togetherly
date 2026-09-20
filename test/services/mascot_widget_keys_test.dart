import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot_widget_data.dart';
import 'package:love_app/services/mascot/mascot_frame_render.dart';
import 'package:love_app/services/mascot/mascot_widget_keys.dart';

void main() {
  const data = MascotWidgetData(
    mascotId: 'pudya',
    name: 'Пудя',
    streakDays: 12,
    sad: false,
    sleep: MascotSleepWindow(from: 23 * 60, to: 7 * 60),
    recordStreak: 64,
  );

  const labels = MascotWidgetLabels(
    stage: 'подросток',
    streak: 'дней серии',
    next: 'до взрослого 18 дней',
    sleepDay: 'не спит до 23:00',
    sleepNight: 'спит до 07:00',
    record: 'рекорд',
  );

  const paths = {
    MascotWidgetFrame.day: '/data/mascot_widget/day.png',
    MascotWidgetFrame.night: '/data/mascot_widget/night.png',
    MascotWidgetFrame.sad: '/data/mascot_widget/sad.png',
  };

  test('ключи живут под своей группой', () {
    final keys = mascotWidgetKeys(
      groupId: 'grp1',
      data: data,
      labels: labels,
      framePaths: paths,
      framePx: 48,
    );

    expect(keys['mascot_grp1_name'], 'Пудя');
    expect(keys['mascot_grp1_streak'], '12');
    expect(keys['mascot_grp1_progress'], '22');
    expect(keys['mascot_grp1_frame_px'], '48');
    expect(keys['mascot_grp1_frame_day'], '/data/mascot_widget/day.png');
    expect(keys['mascot_grp1_frame_night'], '/data/mascot_widget/night.png');
    expect(keys['mascot_grp1_frame_sad'], '/data/mascot_widget/sad.png');
    expect(keys['mascot_grp1_record'], '64');
    expect(keys['mascot_grp1_pixel'], '1');
    expect(keys['mascot_latest_group'], 'grp1');
  });

  test('подписи кладёт приложение, натив их не сочиняет', () {
    final keys = mascotWidgetKeys(
      groupId: 'grp1',
      data: data,
      labels: labels,
      framePaths: paths,
      framePx: 48,
    );

    expect(keys['mascot_grp1_stage_label'], 'подросток');
    expect(keys['mascot_grp1_streak_label'], 'дней серии');
    expect(keys['mascot_grp1_next_label'], 'до взрослого 18 дней');
    expect(keys['mascot_grp1_record_label'], 'рекорд');
  });

  test('подпись сна уезжает обеими половинами: ночь придёт без приложения', () {
    final keys = mascotWidgetKeys(
      groupId: 'grp1',
      data: data,
      labels: labels,
      framePaths: paths,
      framePx: 48,
    );

    expect(keys['mascot_grp1_sleep_label_day'], 'не спит до 23:00');
    expect(keys['mascot_grp1_sleep_label_night'], 'спит до 07:00');
  });

  test('окно сна уезжает минутами, а «не спит» — минус единицей', () {
    final sleeps = mascotWidgetKeys(
      groupId: 'g',
      data: data,
      labels: labels,
      framePaths: paths,
      framePx: 48,
    );
    expect(sleeps['mascot_g_sleep_from'], '1380');
    expect(sleeps['mascot_g_sleep_to'], '420');

    final awake = mascotWidgetKeys(
      groupId: 'g',
      data: const MascotWidgetData(
        mascotId: 'zheleyka',
        name: 'Желейка',
        streakDays: 3,
        sad: false,
        sleep: MascotSleepWindow.none,
      ),
      labels: labels,
      framePaths: {MascotWidgetFrame.day: '/day.png'},
      framePx: 48,
    );
    expect(awake['mascot_g_sleep_from'], '-1');
    expect(awake['mascot_g_sleep_to'], '-1');
  });

  test('оборванная серия просит грустный кадр флагом', () {
    final keys = mascotWidgetKeys(
      groupId: 'g',
      data: const MascotWidgetData(
        mascotId: 'pudya',
        name: 'Пудя',
        streakDays: 0,
        sad: true,
        sleep: MascotSleepWindow(from: 23 * 60, to: 7 * 60),
      ),
      labels: labels,
      framePaths: paths,
      framePx: 48,
    );

    expect(keys['mascot_g_sad'], '1');
  });

  test('ненайденный кадр уезжает пустой строкой, а не пропадает', () {
    final keys = mascotWidgetKeys(
      groupId: 'g',
      data: data,
      labels: labels,
      framePaths: const {MascotWidgetFrame.day: '/day.png'},
      framePx: 48,
    );

    // Пустая строка значащая: прежний путь на нативе надо ПЕРЕБИТЬ, иначе
    // виджет продолжит показывать кадр снятого персонажа.
    expect(keys['mascot_g_frame_night'], '');
    expect(keys['mascot_g_frame_sad'], '');
  });

  test('рисованный маскот помечен как непиксельный', () {
    final keys = mascotWidgetKeys(
      groupId: 'g',
      data: data,
      labels: labels,
      framePaths: const {MascotWidgetFrame.day: '/drawn.png'},
      framePx: 0,
      pixel: false,
    );

    expect(keys['mascot_g_pixel'], '0');
    expect(keys['mascot_g_frame_px'], '0');
  });

  test('без группы ключи уходят под solo', () {
    final keys = mascotWidgetKeys(
      groupId: '',
      data: data,
      labels: labels,
      framePaths: paths,
      framePx: 48,
    );

    expect(keys['mascot_solo_name'], 'Пудя');
    expect(keys['mascot_latest_group'], 'solo');
  });

  test('провайдеры перечислены все четыре', () {
    expect(
      kMascotWidgetProviders,
      containsAll(const [
        'MascotWidget4x1Provider',
        'MascotWidget2x2Provider',
        'MascotWidget4x2Provider',
        'MascotWidget4x4Provider',
      ]),
    );
    expect(kMascotWidgetProviders.length, 4);
  });
}
