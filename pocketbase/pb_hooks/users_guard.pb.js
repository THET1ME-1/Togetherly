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
///
/// ВАЖНО (PB JSVM): обработчик хука сериализуется и исполняется в изолированном
/// пуле — он НЕ видит функции/переменные уровня файла. Поэтому хелпер _deepEqual
/// объявлен ВНУТРИ обработчика (иначе ReferenceError на каждом update → весь
/// PATCH users падает 500). См. coins.pb.js и CUTOVER.md «грабли PB JSVM».

onRecordUpdateRequest((e) => {
  // Глубокое сравнение значений (надёжнее JSON.stringify — не зависит от
  // порядка ключей в объектах). Объявлено внутри обработчика — см. шапку файла.
  const _deepEqual = (a, b) => {
    if (a === b) return true;
    if (a == null || b == null) return false;
    if (typeof a !== typeof b) return false;
    if (typeof a !== 'object') return a === b;
    if (Array.isArray(a)) {
      if (!Array.isArray(b) || a.length !== b.length) return false;
      for (let i = 0; i < a.length; i++) {
        if (!_deepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    const ka = Object.keys(a);
    const kb = Object.keys(b);
    if (ka.length !== kb.length) return false;
    for (const k of ka) {
      if (!kb.includes(k) || !_deepEqual(a[k], b[k])) return false;
    }
    return true;
  };
  let isSuper = false;
  try {
    isSuper = !!(e.auth && e.auth.collection() && e.auth.collection().name === "_superusers");
  } catch (_) {
    isSuper = false;
  }
  if (!isSuper) {
    // Ownership check: non-superuser can only update their own record.
    if (e.record.id !== e.auth.id) {
      throw new ForbiddenError("cannot update other user's record");
    }
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
      const origVal = orig.get(f);
      const newVal = e.record.get(f);
      if (!_deepEqual(origVal, newVal)) {
        throw new ForbiddenError("read-only economy field");
      }
    }
  }
  e.next();
}, "users");

onRecordCreateRequest((e) => {
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
    for (let i = 0; i < PROTECTED.length; i++) {
      const f = PROTECTED[i];
      const val = e.record.get(f);
      if (val != null && val !== '' && val !== 0 && val !== false) {
        throw new ForbiddenError("read-only economy field");
      }
    }
  }
  e.next();
}, "users");
