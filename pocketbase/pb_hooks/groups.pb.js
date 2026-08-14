/// Серверные АТОМАРНЫЕ операции над группой (миграция §6, закрытие гонок
/// group-RMW DATA-5/6/7/8/9). Клиентский read-modify-write по json-полям группы
/// (member_*, счётчики, стрик, miss_you) терял обновления при одновременной
/// записи с двух устройств: конкурентная запись проходит успешно, ретрай ловит
/// только throw. Здесь RMW выполняется в $app.runInTransaction — PB исполняет
/// транзакции на единственном неконкурентном write-коннекте → параллельные
/// вызовы сериализуются, второй читает уже обновлённое значение. Lost-update
/// исключён.
///
/// ВАЖНО (PB JSVM грабли, см. coins.pb.js / CUTOVER.md):
///  1) обработчик сериализуется и НЕ видит функции уровня файла → все хелперы
///     ИНЛАЙН внутри обработчика;
///  2) json-поле читаем через getString()+JSON.parse (get() = байты); незаданное
///     json → getString даёт "null"/"" → коэрсим в fallback;
///  3) внутри tx — ТОЛЬКО txApp (txApp.findRecordById/save), иначе вне транзакции;
///  4) e.json вызываем ПОСЛЕ коммита (out перехватываем в замыкании).
///
/// Безопасность: $app/txApp обходят API-правила, поэтому КАЖДЫЙ роут сам
/// проверяет членство (e.auth.id ∈ group.members) перед мутацией.
/// Клиент (PbDataService) дёргает эти роуты, при их недоступности откатывается
/// на старый локальный RMW — так что версия-скью клиент/сервер безопасна.

// ── Точечная правка json-словаря группы (member_moods/names/avatars/ailments) ──
// body { groupId, field, uid, value }  value=null → удалить ключ
routerAdd("POST", "/api/group/patch-map", (e) => {
  const body = (e.requestInfo().body || {});
  const groupId = String(body.groupId || "").trim();
  const field = String(body.field || "").trim();
  const uid = String(body.uid || "").trim();
  const ALLOWED = ["member_moods", "member_names", "member_avatars", "member_ailments"];
  if (!groupId || !uid || ALLOWED.indexOf(field) === -1) {
    return e.json(400, { ok: false, error: "bad params" });
  }
  const hasValue = (body.value !== null && body.value !== undefined);
  const value = body.value;
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const g = txApp.findRecordById("groups", groupId);
      const parse = (k, fb) => {
        try { const v = JSON.parse(g.getString(k) || JSON.stringify(fb)); return v == null ? fb : v; }
        catch (_) { return fb; }
      };
      const members = parse("members", []);
      if (members.indexOf(e.auth.id) === -1) { out = { s: 403, b: { ok: false, error: "not a member" } }; return; }
      const map = parse(field, {});
      if (hasValue) { map[uid] = value; } else { delete map[uid]; }
      g.set(field, map);
      txApp.save(g);
      out = { s: 200, b: { ok: true } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Атомарный инкремент счётчика группы ───────────────────────────────────────
// body { groupId, field, by }
routerAdd("POST", "/api/group/increment", (e) => {
  const body = (e.requestInfo().body || {});
  const groupId = String(body.groupId || "").trim();
  const field = String(body.field || "").trim();
  const by = Number(body.by);
  // drawings_count и memories_count теперь ведёт серверный хук counters.pb.js
  // (по canvas_catalogue и memories create/delete). Старые клиенты всё ещё
  // дёргают increment по этим полям — гасим в NO-OP с ok:true (клиент считает
  // операцию выполненной и НЕ падает в локальный RMW), иначе счётчик задвоился
  // бы с хуком. memories_count вернулся сюда 5 августа 2026: пока цифру вёл
  // клиент отдельной операцией очереди, она расходилась с лентой у каждой
  // четвёртой пары.
  if (field === "drawings_count" || field === "memories_count") {
    return e.json(200, { ok: true, value: 0, noop: true });
  }
  const ALLOWED = ["xp"];
  if (!groupId || ALLOWED.indexOf(field) === -1 || !Number.isFinite(by)) {
    return e.json(400, { ok: false, error: "bad params" });
  }
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const g = txApp.findRecordById("groups", groupId);
      let members = [];
      try { members = JSON.parse(g.getString("members") || "[]") || []; } catch (_) { members = []; }
      if (members.indexOf(e.auth.id) === -1) { out = { s: 403, b: { ok: false, error: "not a member" } }; return; }
      const next = (g.getInt(field) || 0) + by;
      g.set(field, next);
      txApp.save(g);
      out = { s: 200, b: { ok: true, value: next } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Выход участника из группы (members + member_* + disband если пусто) ────────
// body { groupId, uid }
routerAdd("POST", "/api/group/leave", (e) => {
  const body = (e.requestInfo().body || {});
  const groupId = String(body.groupId || "").trim();
  const uid = String(body.uid || "").trim();
  if (!groupId || !uid) return e.json(400, { ok: false, error: "bad params" });
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const g = txApp.findRecordById("groups", groupId);
      const parse = (k, fb) => {
        try { const v = JSON.parse(g.getString(k) || JSON.stringify(fb)); return v == null ? fb : v; }
        catch (_) { return fb; }
      };
      let members = parse("members", []);
      if (members.indexOf(e.auth.id) === -1) { out = { s: 403, b: { ok: false, error: "not a member" } }; return; }
      members = members.filter((m) => m !== uid);
      const names = parse("member_names", {}); delete names[uid];
      const avatars = parse("member_avatars", {}); delete avatars[uid];
      const moods = parse("member_moods", {}); delete moods[uid];
      const ailments = parse("member_ailments", {}); delete ailments[uid];
      g.set("members", members);
      g.set("member_names", names);
      g.set("member_avatars", avatars);
      g.set("member_moods", moods);
      g.set("member_ailments", ailments);
      if (members.length === 0) {
        g.set("disbanded", true);
        g.set("disbanded_at", new Date().toISOString());
      }
      txApp.save(g);
      out = { s: 200, b: { ok: true } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Засчитать дневную активность (стрик растёт когда зашли ОБА) ────────────────
// body { groupId, uid, today }  today = "YYYY-MM-DD" (локальная дата клиента —
// сохраняем семантику старого клиента; атомарность добавляет транзакция).
routerAdd("POST", "/api/group/record-activity", (e) => {
  const body = (e.requestInfo().body || {});
  const groupId = String(body.groupId || "").trim();
  const uid = String(body.uid || "").trim();
  const today = String(body.today || "").trim();
  if (!groupId || !uid || !/^\d{4}-\d{2}-\d{2}$/.test(today)) {
    return e.json(400, { ok: false, error: "bad params" });
  }
  // Клиент отмечается на каждом заходе, а день засчитывается один раз — восемь
  // запросов в секунду вечером 14.08.2026, и почти все впустую открывали
  // транзакцию, занимая соединение записи. Сначала дешёвое чтение: день уже
  // отмечен — отвечаем сразу. Настоящая отметка идёт прежним путём, с
  // перепроверкой внутри транзакции.
  try {
    const peek = $app.findRecordById("groups", groupId);
    let peekMembers = [];
    try { peekMembers = JSON.parse(peek.getString("members") || "[]") || []; } catch (_) { peekMembers = []; }
    if (peekMembers.indexOf(e.auth.id) === -1) {
      return e.json(403, { ok: false, error: "not a member" });
    }
    if (String(peek.getString("streak_last_opened_date") || "") === today) {
      return e.json(200, { ok: true, already: true });
    }
  } catch (_) { /* не прочиталось — идём обычным путём через транзакцию */ }
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const nz = (v) => { const s = v == null ? "" : String(v); return s.length ? s : null; };
      const g = txApp.findRecordById("groups", groupId);
      let members = [];
      try { members = JSON.parse(g.getString("members") || "[]") || []; } catch (_) { members = []; }
      if (members.indexOf(e.auth.id) === -1) { out = { s: 403, b: { ok: false, error: "not a member" } }; return; }
      const last = nz(g.getString("streak_last_opened_date"));
      if (last === today) { out = { s: 200, b: { ok: true, already: true } }; return; }
      const pendUid = nz(g.getString("streak_pending_uid"));
      const pendDate = nz(g.getString("streak_pending_date"));
      const bothPresent = pendDate === today && pendUid != null && pendUid !== uid;
      if (bothPresent) {
        const isConsecutive = (prevDay) => {
          if (!prevDay) return false;
          const a = Date.parse(today + "T00:00:00Z");
          const b = Date.parse(prevDay + "T00:00:00Z");
          return !isNaN(a) && !isNaN(b) && Math.round((a - b) / 86400000) === 1;
        };
        // Парная серия (back-compat): оставляем, но отображение теперь per-mascot.
        const pairStreak = isConsecutive(last) ? (g.getInt("streak_days") || 0) + 1 : 1;
        g.set("streak_days", pairStreak);
        g.set("streak_last_opened_date", today);

        // PER-MASCOT серия: привязана к активному маскоту, считается по ЕГО
        // собственной последней дате общего дня. Пропуск → старт с 1 («умер»).
        const activeMascotId = nz(g.getString("active_mascot_id"));
        let mStreak = 0;
        if (activeMascotId) {
          let map = {};
          try { const v = JSON.parse(g.getString("mascot_streaks") || "{}"); if (v && typeof v === "object") map = v; } catch (_) { map = {}; }
          const prev = (map[activeMascotId] && typeof map[activeMascotId] === "object") ? map[activeMascotId] : {};
          const prevS = Number(prev.s) || 0;
          mStreak = isConsecutive(nz(prev.d)) ? prevS + 1 : 1;
          map[activeMascotId] = { s: mStreak, d: today };
          g.set("mascot_streaks", map);
        }
        txApp.save(g);

        // record_streak (рекорд per-mascot) — только для персистентных маскотов.
        if (activeMascotId) {
          try {
            const mascot = txApp.findFirstRecordByFilter(
              "mascots", "group_id = {:g} && mascot_id = {:m}", { g: groupId, m: activeMascotId });
            if ((mascot.getInt("record_streak") || 0) < mStreak) {
              mascot.set("record_streak", mStreak);
              txApp.save(mascot);
            }
          } catch (_) { /* каталожный/нет записи — ок */ }
        }
        out = { s: 200, b: { ok: true, streak: pairStreak, mascotStreak: mStreak } };
        return;
      }
      if (pendDate !== today || pendUid == null) {
        g.set("streak_pending_date", today);
        g.set("streak_pending_uid", uid);
        txApp.save(g);
      }
      out = { s: 200, b: { ok: true, pending: true } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Атомарный инкремент «Я скучаю» (запись miss_you по group_id+user_uid) ──────
// body { groupId, uid, vibe, text }
routerAdd("POST", "/api/group/miss-you", (e) => {
  const body = (e.requestInfo().body || {});
  const groupId = String(body.groupId || "").trim();
  const uid = String(body.uid || "").trim();
  const vibe = String(body.vibe || "miss_you");
  const text = String(body.text || "");
  // Сколько нажатий приехало разом. Клиент копит частые тапы и шлёт их одним
  // запросом: каждый тап отдельным запросом упирался в ограничитель, и человек
  // видел, что «половина нажатий не регистрируется» (523 отказа 429 за сутки,
  // 13 августа 2026). Потолок двадцать — дальше это зажатый палец.
  let times = parseInt(body.count, 10);
  if (!(times >= 1 && times <= 20)) times = 1;
  if (!groupId || !uid) return e.json(400, { ok: false, error: "bad params" });

  // ── Копилка нажатий ────────────────────────────────────────────────────────
  //
  // Вечером 14.08.2026 «Скучаю» жали 23 раза в СЕКУНДУ с полусотни устройств —
  // у людей это игра «кто больше», один человек накопил 13 681 нажатие. Каждый
  // запрос открывал транзакцию записи, очередь к базе выросла до семи тысяч, и
  // вместе с ней встало всё остальное: регистрация висела по тридцать секунд.
  //
  // Поэтому пишем в базу не чаще раза в десять секунд на человека, а нажатия
  // между записями складываем в память приложения. Первое нажатие серии уходит
  // сразу — партнёр получает своё уведомление без задержки, а хвост зажатого
  // пальца доезжает одной записью. Счёт не теряется: в базу уходит сумма.
  //
  // Store хранит СТРОКУ: значения бегают между разными машинами JSVM, и
  // JS-объект из чужой машины там неживой.
  const bufKey = "missbuf:" + groupId + ":" + uid;
  const nowMs = Date.now();
  let buffered = 0;
  let bufWeek = {};
  let bufVibes = {};
  try {
    const raw = $app.store().get(bufKey);
    if (raw) {
      const parsed = JSON.parse(String(raw));
      if (nowMs - (parsed.at || 0) < 10000) {
        // Окно ещё открыто — добавляем к накопленному и отвечаем сразу.
        parsed.n = (parsed.n || 0) + times;
        const wd = parseInt(body.weekday, 10);
        const wk = wd >= 1 && wd <= 7 ? String(wd) : "0";
        parsed.w = parsed.w || {};
        parsed.w[wk] = (parsed.w[wk] || 0) + times;
        parsed.v = parsed.v || {};
        const vk = ["miss_you", "thinking_of_you", "want_hug", "custom"].indexOf(vibe) === -1
          ? "miss_you" : vibe;
        parsed.v[vk] = (parsed.v[vk] || 0) + times;
        $app.store().set(bufKey, JSON.stringify(parsed));
        return e.json(200, { ok: true, count: (parsed.base || 0) + parsed.n, buffered: true });
      }
      // Окно закрылось — забираем накопленное с собой в эту запись.
      buffered = parsed.n || 0;
      bufWeek = parsed.w || {};
      bufVibes = parsed.v || {};
    }
  } catch (_) { buffered = 0; bufWeek = {}; bufVibes = {}; }

  let out;
  try {
    $app.runInTransaction((txApp) => {
      // членство по группе
      let members = [];
      try {
        const g = txApp.findRecordById("groups", groupId);
        members = JSON.parse(g.getString("members") || "[]") || [];
      } catch (_) { members = []; }
      if (members.indexOf(e.auth.id) === -1) { out = { s: 403, b: { ok: false, error: "not a member" } }; return; }
      const nowIso = new Date().toISOString();
      let rec = null;
      try {
        rec = txApp.findFirstRecordByFilter(
          "miss_you", "group_id = {:g} && user_uid = {:u}", { g: groupId, u: uid });
      } catch (_) { rec = null; }
      // День недели присылает клиент (1=пн … 7=вс): считать на сервере нельзя,
      // он живёт в UTC, и ночные нажатия попадали бы во вчера. Копится карта
      // «день → сколько раз» — этого хватает для статистики и не растит базу.
      let weekday = parseInt(body.weekday, 10);
      if (!(weekday >= 1 && weekday <= 7)) {
        const d = new Date().getUTCDay(); // 0=вс
        weekday = d === 0 ? 7 : d;
      }
      // Своё число у каждого импульса: «Думаю о тебе» и «Хочу обнять» до
      // 13 августа 2026 копились в общий счётчик, и в меню у них не было
      // цифр вовсе. Ключом берём тип импульса; чужие типы отсекаем, чтобы
      // подделанное тело не растило карту без края. Своё пожелание считаем
      // одной строкой `custom` — текстов у людей сотни.
      const VIBES = { miss_you: 1, thinking_of_you: 1, want_hug: 1, custom: 1 };
      const vibeKey = VIBES[vibe] ? vibe : "miss_you";
      if (rec) {
        // times — нажатия этого запроса, buffered — то, что скопилось в памяти
        // за прошедшее окно (см. копилку выше).
        const next = (rec.getInt("count") || 0) + times + buffered;
        let week = {};
        try { week = JSON.parse(rec.getString("by_weekday") || "{}") || {}; } catch (_) { week = {}; }
        week[weekday] = (parseInt(week[weekday], 10) || 0) + times;
        for (const k in bufWeek) {
          const day = k === "0" ? String(weekday) : k;
          week[day] = (parseInt(week[day], 10) || 0) + bufWeek[k];
        }
        let vibes = {};
        try { vibes = JSON.parse(rec.getString("by_vibe") || "{}") || {}; } catch (_) { vibes = {}; }
        // Первая запись карты у старой пары: весь прежний счёт был «скучаю» —
        // ровно так его показывает и клиент, пока карты нет.
        if (!vibes || typeof vibes !== "object" || Array.isArray(vibes) || Object.keys(vibes).length === 0) {
          vibes = {};
          const before = rec.getInt("count") || 0;
          if (before > 0) vibes.miss_you = before;
        }
        vibes[vibeKey] = (parseInt(vibes[vibeKey], 10) || 0) + times;
        for (const k in bufVibes) {
          vibes[k] = (parseInt(vibes[k], 10) || 0) + bufVibes[k];
        }
        rec.set("by_vibe", JSON.stringify(vibes));
        rec.set("by_weekday", JSON.stringify(week));
        rec.set("count", next);
        rec.set("updated_at", nowIso);
        rec.set("last_vibe", vibe);
        rec.set("last_vibe_text", text);
        txApp.save(rec);
        out = { s: 200, b: { ok: true, count: next } };
      } else {
        const col = txApp.findCollectionByNameOrId("miss_you");
        const r = new Record(col);
        r.set("group_id", groupId);
        r.set("user_uid", uid);
        r.set("count", times + buffered);
        r.set("by_weekday", JSON.stringify({ [weekday]: times + buffered }));
        r.set("by_vibe", JSON.stringify({ [vibeKey]: times + buffered }));
        r.set("updated_at", nowIso);
        r.set("last_vibe", vibe);
        r.set("last_vibe_text", text);
        txApp.save(r);
        out = { s: 200, b: { ok: true, count: times + buffered } };
      }
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  // Запись прошла — открываем новое окно: следующие десять секунд нажатия
  // копятся в памяти, а в ответе человек видит их сразу (base + накопленное).
  if (out && out.s === 200 && out.b && out.b.ok) {
    try {
      $app.store().set(bufKey, JSON.stringify({
        at: nowMs, n: 0, w: {}, v: {}, base: out.b.count || 0,
      }));
    } catch (_) { /* копилка не обязательна: без неё просто пишем чаще */ }
  }
  return e.json(out.s, out.b);
}, $apis.requireAuth());
