import 'mascot_anim.dart';
import 'mood_pack.dart';

/// Облачко — главный маскот Togetherly, коралловое, с глазами, как иконка.
///
/// Рисунок не меняется никогда: мастерская значков снимает его кадры из
/// вектора (`bake_cloud.py`) и кладёт каждую сцену в каждом цвете отдельной
/// анимацией в каталог, ключ `cloud_<сцена>_<цвет>`. Здесь только правила:
/// какой цвет у настроения и что облачко делает сейчас.
const String kCloudMascotId = 'cloud';

/// Цвета облачка: обычный и семь настроений дня.
const List<String> kCloudTints = ['base', 'joy', 'love', 'calm', 'sad', 'angry', 'tired', 'shy'];

const Map<String, String> _tintOfMood = {
  'happy': 'joy',
  'laugh': 'joy',
  'pride': 'joy',
  'cool': 'joy',
  'winking': 'joy',
  'bliss': 'joy',
  'drooling': 'joy',
  'love': 'love',
  'kiss': 'love',
  'no_emotion': 'calm',
  'sad': 'sad',
  'very_sad': 'sad',
  'hurt': 'sad',
  'disappointed': 'sad',
  'missing': 'sad',
  'upset': 'sad',
  'anxiety': 'sad',
  'fear': 'sad',
  'anger': 'angry',
  'devil': 'angry',
  'tired': 'tired',
  'sleepy': 'tired',
  'sick': 'tired',
  'embarrassed': 'shy',
};

/// Цвет облачка по id настроения. Нет настроения или оно из пака, которого
/// сборка не знает, — обычное коралловое.
String cloudTintForMood(String? moodId) => _tintOfMood[moodId] ?? 'base';

/// Id пака настроений «Облачко» в каталоге.
const String kCloudMoodPackId = 'cloud';

/// Анимация эмоции [moodId] из пака «Облачко», или null.
///
/// В покое маскот играет саму эмоцию, а не только цвет: «Дьявол» с рожками,
/// «Крутая» в очках. Id настроений общие у всех паков, поэтому эмоция,
/// выбранная из «Пёсика», на облачке тоже своя.
String? cloudEmotionUrl(List<MoodPack> packs, String? moodId) {
  if (moodId == null || moodId.isEmpty) return null;
  for (final pack in packs) {
    if (pack.id != kCloudMoodPackId) continue;
    for (final mood in pack.moods) {
      if (mood.id == moodId) return mood.imagePath;
    }
  }
  return null;
}

/// Картинки всех эмоций пака Ту — их прогревают заранее: иначе новая эмоция
/// начинала качаться только в момент выбора, и Ту менялся с задержкой.
List<String> cloudEmotionWarmUrls(List<MoodPack> packs) => [
      for (final pack in packs)
        if (pack.id == kCloudMoodPackId)
          for (final mood in pack.moods)
            if (mood.imagePath.isNotEmpty) mood.imagePath,
    ];

/// То, что случилось на главной и перекрывает остальную жизнь облачка.
enum CloudEvent { missSend, missGet, shake, pour }

/// Ключ анимации облачка в каталоге.
///
/// Порядок важности: событие («Скучаю», встряска), руки человека, серия,
/// затем покой — ночью сон, в годовщину праздник, у приболевшего партнёра
/// градусник, иначе цвет настроения.
/// Сон, праздник и встряска только обычного цвета: у них своё лицо.
String cloudArt({
  required MascotAnimState anim,
  required String tint,
  bool night = false,
  bool anniversary = false,
  bool sick = false,
  CloudEvent? event,
}) {
  String key(String scene, String t) => 'cloud_${scene}_$t';
  switch (event) {
    case CloudEvent.missSend:
      return key('miss_send', tint);
    case CloudEvent.missGet:
      return key('miss_get', tint);
    case CloudEvent.shake:
      return key('shake', 'base');
    case CloudEvent.pour:
      return key('pour', tint);
    case null:
      break;
  }
  switch (anim) {
    case MascotAnimState.grab:
    case MascotAnimState.drag:
    case MascotAnimState.resize:
      return key('drag', tint);
    case MascotAnimState.drop:
      return key('tap', tint);
    case MascotAnimState.happy:
      return key('joy', tint);
    case MascotAnimState.grow:
      return key('flip', tint);
    case MascotAnimState.sad:
      return key('idle', 'sad');
    case MascotAnimState.live:
    case MascotAnimState.freeze:
      if (night) return key('sleep', 'base');
      if (anniversary) return key('party', 'base');
      if (sick) return key('sick', 'base');
      return key('idle', tint);
  }
}

/// Длина разовой сцены: после неё облачко возвращается к обычной жизни.
/// Петли (покой, полёт за пальцем, сон) — null. Длины те же, что у петель
/// в `mascot.js`.
/// Тряска в цвете выбранной эмоции пака (`cloud_shake_emo_<id>`, мастерская
/// `bake_emotion_shake.py`): испуг тот же, что у обычной, а Ту остаётся
/// цвета эмоции. Без неё встряска перекрашивала Ту в коралловый. Null —
/// обычная тряска: эмоции нет или её тряска ещё не в каталоге.
String? cloudEmotionShakeArt({required String? mood, required bool Function(String key) hasArt}) {
  if (mood == null || mood.isEmpty) return null;
  final key = 'cloud_shake_emo_$mood';
  return hasArt(key) ? key : null;
}

Duration? cloudOneShot(String art) {
  const ms = {
    'tap': 2400,
    'miss_send': 3600,
    'miss_get': 3600,
    'joy': 2600,
    'flip': 2800,
    'shake': 3800,
    'pour': 3400,
  };
  for (final e in ms.entries) {
    if (art.startsWith('cloud_${e.key}_')) return Duration(milliseconds: e.value);
  }
  return null;
}
