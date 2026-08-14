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
      // Togetherly+ ведут только серверные пути: вебхук lava.top, погашение
      // кода и роут /api/coins/iap-purchase (он же сверяет чек с Google). До
      // 28 июля флага тут не было, и `PATCH /api/collections/users/records/:id`
      // с `{"plus": true}` открывал платное даром — правило коллекции пускает
      // владельца писать в свою запись любое поле. Место покупки и дата выдачи
      // ежемесячных монет закрыты по той же причине.
      "plus", "plus_platform", "last_plus_grant_ms",
    ];
    // Источник истины — ТЕЛО запроса (как в create-guard ниже). Прежнее
    // сравнение orig.get(f) vs e.record.get(f) давало ЛОЖНЫЙ 403: в PB JSVM
    // .get() на json-полях экономики (owned_*/granted_badges/
    // partner_invite_rewarded_keys/mood_streak_rewards) возвращает БАЙТЫ, не
    // равные сами себе → блокировало даже чистые правки профиля (имя/аватар/
    // пол/настройки/fcm) и роняло денормализацию аватара в группы. Клиент НЕ
    // присылает экономику легально (её ведут серверные коин-роуты через
    // $app.save, мимо этого request-хука), поэтому блокируем лишь реальную
    // попытку клиента записать НЕПУСТОЕ защищённое поле.
    const body = (e.requestInfo().body || {});
    for (let i = 0; i < PROTECTED.length; i++) {
      const f = PROTECTED[i];
      if (!(f in body)) continue; // поле не прислано клиентом — ок
      const v = body[f];
      const empty = (v == null || v === '' || v === 0 || v === false ||
        (Array.isArray(v) && v.length === 0) ||
        (typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0));
      if (!empty) {
        throw new ForbiddenError("read-only economy field");
      }
    }
  }

  // ── Денормализация профиля в группы ──────────────────────────────────────
  // При смене аватара/имени синхронизируем member_avatars[uid]/member_names[uid]
  // во ВСЕХ группах юзера. Партнёр читает аватар/имя из group-дока; клиентская
  // правка member_avatars иногда теряется (гонка/проглоченная ошибка), из-за
  // чего партнёр видел СТАРУЮ аватарку. Это серверная гарантия консистентности.
  let prevAvatar = null, prevName = null;
  try {
    const o = $app.findRecordById("users", e.record.id);
    prevAvatar = o.getString("avatar_url");
    prevName = o.getString("display_name");
  } catch (_) { prevAvatar = null; prevName = null; }
  const newAvatar = e.record.getString("avatar_url");
  const newName = e.record.getString("display_name");

  e.next(); // сохраняем users

  if (newAvatar !== prevAvatar || newName !== prevName) {
    try {
      const uid = e.record.id;
      // Подписи участников лежат в записи пары, а пары живут в Postgres.
      // Правим точечно две карты одним запросом на пару — вместо чтения
      // записи и её сохранения через PocketBase.
      const hp = (path, method, payload) => {
        const r = $http.send({
          url: "http://127.0.0.1:8120" + path,
          method: method,
          headers: { "content-type": "application/json" },
          body: payload ? JSON.stringify(payload) : undefined,
          timeout: 10,
        });
        return (r && r.json) || null;
      };
      const мои = hp("/internal/groups-of?uid=" + encodeURIComponent(uid) + "&live=1",
                     "GET", null);
      const items = (мои && мои.items) || [];
      for (let i = 0; i < items.length; i++) {
        const карты = {};
        const av = items[i].member_avatars;
        const nm = items[i].member_names;
        if (newAvatar && (!av || typeof av !== "object" || av[uid] !== newAvatar)) {
          const набор = {}; набор[uid] = newAvatar;
          карты.member_avatars = набор;
        }
        if (newName && (!nm || typeof nm !== "object" || nm[uid] !== newName)) {
          const набор = {}; набор[uid] = newName;
          карты.member_names = набор;
        }
        if (!Object.keys(карты).length) continue;
        hp("/internal/group-write", "POST", { group_id: items[i].id, map_set: карты });
      }
    } catch (err) {
      try { $app.logger().error("member profile sync failed: " + String(err)); } catch (_) {}
    }
  }
}, "users");

onRecordCreateRequest((e) => {
  let isSuper = false;
  try {
    isSuper = !!(e.auth && e.auth.collection() && e.auth.collection().name === "_superusers");
  } catch (_) {
    isSuper = false;
  }
  if (!isSuper) {
    // ── Чёрный список email (модерация: бан-эвейдеры) ─────────────────────
    // Список — в файле pb_data/.banned_emails, по одному lowercase-email в
    // строке. Читаем на КАЖДУЮ регистрацию (createRequest редок) → новые баны
    // = просто дописать строку в файл, БЕЗ рестарта PB. $os.readFile отдаёт
    // БАЙТЫ → декодируем fromCharCode. Ошибка чтения/нет файла = fail-open
    // (не мешаем легитимной регистрации). Блокирует только повторный signup на
    // тот же email; смена email/oauth — потолок без device-атестации.
    try {
      const bodyEmail = String(((e.requestInfo().body || {}).email) || "").trim().toLowerCase();
      if (bodyEmail) {
        let raw = "";
        try {
          const bytes = $os.readFile("/opt/pocketbase/pb_data/.banned_emails");
          raw = String.fromCharCode.apply(null, bytes);
        } catch (_) { raw = ""; }
        const banned = raw.split("\n").map(function (s) { return s.trim().toLowerCase(); }).filter(Boolean);
        if (banned.indexOf(bodyEmail) !== -1) {
          throw new ForbiddenError("registration blocked");
        }
      }
    } catch (err) {
      if (err instanceof ForbiddenError) throw err; // реальный бан — пробрасываем
      // прочие ошибки (чтение файла и т.п.) — не блокируем регистрацию
    }

    const PROTECTED = [
      "coins", "owned_themes", "owned_icons", "owned_features", "granted_badges",
      "dev_coins_granted", "ad_rewards_date", "ad_rewards_today",
      "last_daily_bonus_ms", "last_memory_reward_ms",
      "last_daily_bonus_at", "last_memory_reward_at",
      "partner_invite_reward_granted", "partner_invite_rewarded_keys",
      "mood_streak_rewards",
      // Togetherly+ ведут только серверные пути: вебхук lava.top, погашение
      // кода и роут /api/coins/iap-purchase (он же сверяет чек с Google). До
      // 28 июля флага тут не было, и `PATCH /api/collections/users/records/:id`
      // с `{"plus": true}` открывал платное даром — правило коллекции пускает
      // владельца писать в свою запись любое поле. Место покупки и дата выдачи
      // ежемесячных монет закрыты по той же причине.
      "plus", "plus_platform", "last_plus_grant_ms",
    ];
    // Проверяем ТОЛЬКО реально присланные клиентом поля, а не дефолты записи:
    // e.record.get() для json-полей экономики (owned_*/granted_badges/
    // partner_invite_rewarded_keys/mood_streak_rewards) возвращает БАЙТЫ → ложно
    // «непусто» → рубило даже чистую регистрацию (email/пароль/имя). Источник
    // истины — тело запроса; пустые/дефолтные значения разрешаем, блокируем
    // только попытку клиента выставить РЕАЛЬНУЮ экономику.
    const body = (e.requestInfo().body || {});
    for (let i = 0; i < PROTECTED.length; i++) {
      const f = PROTECTED[i];
      if (!(f in body)) continue; // клиент не присылал поле — ок (дефолт схемы)
      const v = body[f];
      const empty = (v == null || v === '' || v === 0 || v === false ||
        (Array.isArray(v) && v.length === 0) ||
        (typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0));
      if (!empty) {
        throw new ForbiddenError("read-only economy field");
      }
    }
  }
  e.next();
}, "users");
