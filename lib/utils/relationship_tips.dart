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
library;

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
      tips.add(const RelationshipTip(
        id: 'mood_low',
        title: 'День у неё так себе',
        body: 'Спросите, как она, и просто выслушайте. Совет не обязателен — '
            'иногда хватает того, что кто-то рядом.',
        weight: 100,
        action: 'chat',
      ));
    } else if (mood == null) {
      tips.add(const RelationshipTip(
        id: 'mood_unknown',
        title: 'Как она сегодня — неизвестно',
        body: 'Спросите сами: живой вопрос лучше отметки в календаре.',
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
          tips.add(const RelationshipTip(
            id: 'cycle_period',
            title: 'Эти дни бывают тяжёлыми',
            body: 'Возьмите на себя что-нибудь бытовое, принесите чай, '
                'предложите вечер без планов. Спросите, чего ей хочется.',
            weight: 90,
            action: 'chat',
          ));
        case CyclePhaseHint.soon:
          tips.add(const RelationshipTip(
            id: 'cycle_soon',
            title: 'Скоро те самые дни',
            body: 'Хороший момент сделать что-то заранее: заказать её любимое '
                'или освободить вечер.',
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
        title: silence >= 5 ? 'Тишина затянулась' : 'Давно не переписывались',
        body: 'Напишите первым — необязательно по делу. Достаточно «думаю о '
            'тебе».',
        weight: 70,
        action: 'chat',
      ));
    }

    final miss = c.daysSinceMiss;
    if (miss != null && miss >= 7) {
      tips.add(const RelationshipTip(
        id: 'miss_gap',
        title: 'Давно не отправляли «скучаю»',
        body: 'Одно касание — и она узнает. Мелочь, а работает.',
        weight: 50,
        action: 'miss',
      ));
    }

    final memory = c.daysSinceMemory;
    if (memory != null && memory >= 10) {
      tips.add(const RelationshipTip(
        id: 'memory_gap',
        title: 'Воспоминаний давно не прибавлялось',
        body: 'Добавьте фото или пару строк о том, что было на неделе. Через '
            'год это будет дороже, чем кажется сейчас.',
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
            ? 'Годовщина сегодня'
            : 'До годовщины $toAnniversary дн.',
        body: toAnniversary == 0
            ? 'Скажите об этом первым.'
            : 'Успеваете придумать что-то, кроме цветов в последний час.',
        weight: 60,
        action: 'gift',
      ));
    }

    final days = c.daysTogether;
    if (days != null && days > 0 && (days % 100 == 0 || days % 365 == 0)) {
      tips.add(RelationshipTip(
        id: 'round_date',
        title: 'Сегодня $days дней вместе',
        body: 'Круглая дата — хороший повод сказать это вслух.',
        weight: 65,
        action: 'chat',
      ));
    }

    tips.sort((a, b) => b.weight.compareTo(a.weight));
    return tips.take(maxTips).toList();
  }
}
