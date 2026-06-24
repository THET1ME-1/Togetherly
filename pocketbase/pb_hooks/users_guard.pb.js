/// Страж денежных/наградных полей коллекции `users` (миграция §6, закрытие
/// блокера «экономика обходится прямым PATCH»). Поля coins/owned_*/кулдауны/
/// флаги наград ведут ТОЛЬКО серверные коин-роуты (coins.pb.js через $app.save —
/// программный save НЕ проходит через этот request-хук). Любой клиентский
/// PATCH /api/collections/users/records/:id, меняющий защищённое поле, отвергаем.
/// Суперюзер (админка) — пропускается.
///
/// Сравниваем входящее значение с сохранённым в БД: поле, которое клиент НЕ
/// присылает в PATCH, остаётся прежним (== orig) → проходит. Меняется только
/// то, что клиент реально пытается перезаписать.
onRecordUpdateRequest((e) => {
  let isSuper = false;
  try {
    isSuper = !!(e.auth && e.auth.collection() && e.auth.collection().name === "_superusers");
  } catch (_) {
    isSuper = false;
  }
  if (!isSuper) {
    const PROTECTED = [
      "coins", "owned_themes", "owned_icons", "owned_features", "granted_badges",
      "dev_coins_granted", "ad_rewards_date", "ad_rewards_today",
      "last_daily_bonus_ms", "last_memory_reward_ms",
      "last_daily_bonus_at", "last_memory_reward_at",
      "partner_invite_reward_granted", "partner_invite_rewarded_keys",
      "mood_streak_rewards",
    ];
    const orig = $app.findRecordById("users", e.record.id);
    for (let i = 0; i < PROTECTED.length; i++) {
      const f = PROTECTED[i];
      if (JSON.stringify(orig.get(f)) !== JSON.stringify(e.record.get(f))) {
        throw new ForbiddenError("read-only economy field: " + f);
      }
    }
  }
  e.next();
}, "users");
