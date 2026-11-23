/// Советы паре на сегодня.
///
/// Правило письма здесь одно и нарушать его нельзя: **совет говорит, что
/// сделать, и никогда не объясняет, почему партнёр «такой»**. «Спроси, как
/// она» — можно. «У неё ПМС, будь терпелив» — нельзя: это диагноз вместо
/// заботы, он обижает обоих и превращает приложение в инструкцию по
/// обращению с человеком.
///
/// Советы по циклу показываются, только если партнёрша сама включила
/// видимость. Без разрешения фаза не участвует в подборе вовсе — не «скрыта в
/// интерфейсе», а не доходит до движка.
///
/// Когда всё в порядке, советов нет. Пустой совет ради ежедневной карточки
/// («напиши ей что-нибудь приятное») обесценивает те, что появляются по делу.
///
/// Тексты идут через `ruEn`: до 23.11.2026 они были только русскими, и
/// английское приложение показывало советы по-русски.
library;

import '../dict_strings.dart';

/// Фаза цикла в том виде, в каком она доходит до советов.
///
/// Намеренно грубее, чем настоящий расчёт: движку советов не нужны ни даты, ни
/// длина цикла — только повод для заботы.
enum CyclePhaseHint {
  /// Партнёрша не делится циклом или данных мало.
  unknown,

  /// Идут месячные.
  period,

  /// Месячные ожидаются со дня на день.
  soon,

  /// Обычные дни.
  regular,
}

/// Данные, по которым подбираются советы. Любое поле может быть null —
/// значит, сведений нет, и правила на него не срабатывают.
class TipContext {
  const TipContext({
    this.daysSinceMiss,
    this.partnerMoodScore,
    this.myMoodScore,
    this.daysToAnniversary,
    this.daysTogether,
    this.cycle = CyclePhaseHint.unknown,
    this.cycleVisible = false,
    this.daysSinceMemory,
    this.daysSinceChat,
  });

  /// Сколько дней назад отправляли «скучаю».
  final int? daysSinceMiss;

  /// Настроение партнёра сегодня, 1…5. null — не отмечался.
  final int? partnerMoodScore;
  final int? myMoodScore;

  /// Сколько дней до годовщины.
  final int? daysToAnniversary;

  /// Сколько дней вместе — для круглых дат.
  final int? daysTogether;

  final CyclePhaseHint cycle;

  /// Разрешила ли партнёрша показывать цикл.
  final bool cycleVisible;

  /// Сколько дней назад добавляли воспоминание.
  final int? daysSinceMemory;

  /// Сколько дней назад писали в чат.
  final int? daysSinceChat;
}

/// Один совет.
class RelationshipTip {
  const RelationshipTip({
    required this.id,
    required this.title,
    required this.body,
    required this.weight,
    this.action,
  });

  final String id;
  final String title;
  final String body;

  /// Чем больше, тем выше в списке. Настроение важнее круглых дат.
  final int weight;

  /// Куда ведёт совет: `chat`, `memory`, `gift`, `miss`, `mood`.
  final String? action;
}

class RelationshipTips {
  const RelationshipTips._();

  /// Сколько советов показываем за раз. Больше трёх никто не читает, а длинный
  /// список превращает заботу в список дел.
  static const int maxTips = 3;

  static List<RelationshipTip> forToday(TipContext c) {
    final tips = <RelationshipTip>[];

    // ── Настроение партнёра ────────────────────────────────────────────────
    final mood = c.partnerMoodScore;
    if (mood != null && mood <= 2) {
      tips.add(RelationshipTip(
        id: 'mood_low',
        title: ruEn('День у неё так себе', 'Your partner is having a rough day'),
        body: ruEn(
            'Спросите, как она, и просто выслушайте. Совет не обязателен — '
                'иногда хватает того, что кто-то рядом.',
            'Ask how they are and just listen. No advice needed — '
                'sometimes it is enough to have someone close.'),
        weight: 100,
        action: 'chat',
      ));
    } else if (mood == null) {
      tips.add(RelationshipTip(
        id: 'mood_unknown',
        title: ruEn('Как она сегодня — неизвестно',
            'You don’t know how your partner is today'),
        body: ruEn('Спросите сами: живой вопрос лучше отметки в календаре.',
            'Ask them yourself: a real question beats a mark in the calendar.'),
        weight: 40,
        action: 'chat',
      ));
    }

    // ── Цикл ───────────────────────────────────────────────────────────────
    //
    // Только с её разрешения. Формулировки — про действие, не про состояние:
    // объяснять чужое настроение календарём здесь не будем никогда.
    if (c.cycleVisible) {
      switch (c.cycle) {
        case CyclePhaseHint.period:
          tips.add(RelationshipTip(
            id: 'cycle_period',
            title: ruEn('Эти дни бывают тяжёлыми', 'These days can be hard'),
            body: ruEn(
                'Возьмите на себя что-нибудь бытовое, принесите чай, '
                    'предложите вечер без планов. Спросите, чего ей хочется.',
                'Take on a chore, bring her some tea, suggest an evening '
                    'with no plans. Ask what she would like.'),
            weight: 90,
            action: 'chat',
          ));
        case CyclePhaseHint.soon:
          tips.add(RelationshipTip(
            id: 'cycle_soon',
            title: ruEn('Скоро те самые дни', 'Her period is coming soon'),
            body: ruEn(
                'Хороший момент сделать что-то заранее: заказать её любимое '
                    'или освободить вечер.',
                'A good moment to do something in advance: order her '
                    'favourite treat or keep the evening free.'),
            weight: 55,
            action: 'gift',
          ));
        case CyclePhaseHint.regular:
        case CyclePhaseHint.unknown:
          break;
      }
    }

    // ── Внимание друг к другу ──────────────────────────────────────────────
    final silence = c.daysSinceChat;
    if (silence != null && silence >= 2) {
      tips.add(RelationshipTip(
        id: 'silence',
        title: silence >= 5
            ? ruEn('Тишина затянулась', 'The silence has gone on too long')
            : ruEn('Давно не переписывались', 'You haven’t texted in a while'),
        body: ruEn(
            'Напишите первым — необязательно по делу. Достаточно «думаю о '
                'тебе».',
            'Write first — it doesn’t have to be about anything. '
                '“Thinking of you” is enough.'),
        weight: 70,
        action: 'chat',
      ));
    }

    final miss = c.daysSinceMiss;
    if (miss != null && miss >= 7) {
      tips.add(RelationshipTip(
        id: 'miss_gap',
        title: ruEn('Давно не отправляли «скучаю»',
            'You haven’t sent “miss you” in a while'),
        body: ruEn('Одно касание — и она узнает. Мелочь, а работает.',
            'One tap and they will know. A small thing that works.'),
        weight: 50,
        action: 'miss',
      ));
    }

    final memory = c.daysSinceMemory;
    if (memory != null && memory >= 10) {
      tips.add(RelationshipTip(
        id: 'memory_gap',
        title: ruEn('Воспоминаний давно не прибавлялось',
            'No new memories for a while'),
        body: ruEn(
            'Добавьте фото или пару строк о том, что было на неделе. Через '
                'год это будет дороже, чем кажется сейчас.',
            'Add a photo or a few lines about your week. A year from now '
                'it will mean more than it seems today.'),
        weight: 45,
        action: 'memory',
      ));
    }

    // ── Даты ───────────────────────────────────────────────────────────────
    final toAnniversary = c.daysToAnniversary;
    if (toAnniversary != null && toAnniversary >= 0 && toAnniversary <= 14) {
      tips.add(RelationshipTip(
        id: 'anniversary_soon',
        title: toAnniversary == 0
            ? ruEn('Годовщина сегодня', 'Your anniversary is today')
            : ruEn(
                'До годовщины $toAnniversary дн.',
                toAnniversary == 1
                    ? 'Your anniversary is tomorrow'
                    : '$toAnniversary days until your anniversary'),
        body: toAnniversary == 0
            ? ruEn('Скажите об этом первым.', 'Be the first to say it.')
            : ruEn('Успеваете придумать что-то, кроме цветов в последний час.',
                'There is time to plan something better than last-minute flowers.'),
        weight: 60,
        action: 'gift',
      ));
    }

    final days = c.daysTogether;
    if (days != null && days > 0 && (days % 100 == 0 || days % 365 == 0)) {
      tips.add(RelationshipTip(
        id: 'round_date',
        title: ruEn('Сегодня $days дней вместе', '$days days together today'),
        body: ruEn('Круглая дата — хороший повод сказать это вслух.',
            'A round date is a good reason to say it out loud.'),
        weight: 65,
        action: 'chat',
      ));
    }

    tips.sort((a, b) => b.weight.compareTo(a.weight));
    return tips.take(maxTips).toList();
  }
}
