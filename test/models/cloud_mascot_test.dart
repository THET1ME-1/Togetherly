import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/cloud_mascot.dart';
import 'package:love_app/models/mascot_anim.dart';

/// Облачко на главной живёт в цвете настроения партнёра, а что оно делает,
/// решают руки человека, серия, время суток и годовщина. Анимации лежат в
/// каталоге по ключу `cloud_<сцена>_<цвет>`, поэтому ключ обязан совпадать с
/// тем, что запекает мастерская (`bake_cloud.py`).
void main() {
  group('цвет по настроению', () {
    test('радостные — жёлтое, любовь — розовое, смущение — своё', () {
      expect(cloudTintForMood('happy'), 'joy');
      expect(cloudTintForMood('laugh'), 'joy');
      expect(cloudTintForMood('love'), 'love');
      expect(cloudTintForMood('kiss'), 'love');
      expect(cloudTintForMood('embarrassed'), 'shy');
    });

    test('грусть, злость, усталость и спокойствие', () {
      expect(cloudTintForMood('sad'), 'sad');
      expect(cloudTintForMood('very_sad'), 'sad');
      expect(cloudTintForMood('anger'), 'angry');
      expect(cloudTintForMood('tired'), 'tired');
      expect(cloudTintForMood('sleepy'), 'tired');
      expect(cloudTintForMood('no_emotion'), 'calm');
    });

    test('нет настроения или оно незнакомое — обычное коралловое', () {
      expect(cloudTintForMood(null), 'base');
      expect(cloudTintForMood(''), 'base');
      expect(cloudTintForMood('mood_from_new_pack'), 'base');
    });
  });

  group('какая сцена играет', () {
    test('в покое — цвет настроения', () {
      expect(cloudArt(anim: MascotAnimState.live, tint: 'love'), 'cloud_idle_love');
      expect(cloudArt(anim: MascotAnimState.live, tint: 'base'), 'cloud_idle_base');
    });

    test('руки: тащат — полёт за пальцем, отпустили — касание', () {
      expect(cloudArt(anim: MascotAnimState.grab, tint: 'joy'), 'cloud_drag_joy');
      expect(cloudArt(anim: MascotAnimState.drag, tint: 'joy'), 'cloud_drag_joy');
      expect(cloudArt(anim: MascotAnimState.resize, tint: 'joy'), 'cloud_drag_joy');
      expect(cloudArt(anim: MascotAnimState.drop, tint: 'calm'), 'cloud_tap_calm');
    });

    test('серия: выросла — радость или кувырок, оборвалась — грустный цвет', () {
      expect(cloudArt(anim: MascotAnimState.happy, tint: 'calm'), 'cloud_joy_calm');
      expect(cloudArt(anim: MascotAnimState.grow, tint: 'calm'), 'cloud_flip_calm');
      expect(cloudArt(anim: MascotAnimState.sad, tint: 'joy'), 'cloud_idle_sad');
    });

    test('ночью спит, в годовщину весь день празднует — у них своё лицо', () {
      expect(cloudArt(anim: MascotAnimState.live, tint: 'love', night: true), 'cloud_sleep_base');
      expect(cloudArt(anim: MascotAnimState.live, tint: 'love', anniversary: true), 'cloud_party_base');
      // Руки важнее ночи: потащили спящего — он летит за пальцем.
      expect(cloudArt(anim: MascotAnimState.drag, tint: 'love', night: true), 'cloud_drag_love');
    });

    test('партнёр приболел — облачко с градусником, но спит всё равно ночью', () {
      expect(cloudArt(anim: MascotAnimState.live, tint: 'tired', sick: true), 'cloud_sick_base');
      expect(cloudArt(anim: MascotAnimState.live, tint: 'tired', sick: true, night: true), 'cloud_sleep_base');
      expect(cloudArt(anim: MascotAnimState.drop, tint: 'tired', sick: true), 'cloud_tap_tired');
    });

    test('«Скучаю» и встряска перекрывают всё', () {
      expect(cloudArt(anim: MascotAnimState.live, tint: 'sad', event: CloudEvent.missSend), 'cloud_miss_send_sad');
      expect(cloudArt(anim: MascotAnimState.live, tint: 'sad', event: CloudEvent.missGet), 'cloud_miss_get_sad');
      expect(cloudArt(anim: MascotAnimState.drag, tint: 'sad', night: true, event: CloudEvent.shake), 'cloud_shake_base');
    });
  });

  test('разовые сцены знают свою длину, петли — нет', () {
    expect(cloudOneShot('cloud_tap_joy'), const Duration(milliseconds: 2400));
    expect(cloudOneShot('cloud_miss_get_base'), const Duration(milliseconds: 3600));
    expect(cloudOneShot('cloud_flip_love'), const Duration(milliseconds: 2800));
    expect(cloudOneShot('cloud_idle_love'), isNull);
    expect(cloudOneShot('cloud_drag_love'), isNull);
  });
}
