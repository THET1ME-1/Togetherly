/// Комнаты совместного просмотра (сайт togetherly.day/watch).
///
/// Сервер не хранит ничего: ни комнат, ни ссылок на видео, ни переписки.
/// Комната — это канал `watch:<id>` в Centrifugo, который живёт, пока в нём
/// есть хоть одно соединение. История канала выключена, на диск не пишется.
///
/// В открытую комнату пускают без аккаунта, в комнату пары — только её
/// участников (подробности у `/api/watch/token`). Пропуск выдаётся на шесть
/// часов и привязан к конкретной комнате. Подписаться на `watch:*` без пропуска
/// Centrifugo не даёт: `allow_subscribe_for_client` у пространства снят
/// 16.09.2026, до этого любой подключённый клиент заходил в любую комнату.
///
/// !!! ГРАБЛИ PB JSVM (см. coins.pb.js:5-19): обработчик исполняется в
/// ИЗОЛИРОВАННОМ пуле и НЕ видит функции уровня файла — всё инлайнится.

/// Код комнаты пары. Приложению не нужно ничего вводить: оба устройства
/// спрашивают код у сервера и молча оказываются в одной комнате. Тот же код
/// показывается в интерфейсе, чтобы позвать партнёра в браузер.
///
/// Код выводится из group_id через HMAC с серверным секретом: одинаковый для
/// пары, неугадываемый снаружи и не раскрывающий сам идентификатор группы.
routerAdd("POST", "/api/watch/room", (e) => {
  const auth = e.auth;
  if (!auth) return e.json(401, { ok: false, error: "unauthorized" });

  const body = e.requestInfo().body || {};
  const groupId = String(body.groupId || "");
  if (!groupId) return e.json(400, { ok: false, error: "no_group" });

  // Участие проверяем по users.group_ids — так же, как в правилах коллекций.
  // Читать только getStringSlice: `get()` по relation в этой сборке JSVM врёт.
  let mine = [];
  try { mine = auth.getStringSlice("group_ids") || []; } catch (_) { mine = []; }
  let member = false;
  for (let i = 0; i < mine.length; i++) {
    if (String(mine[i]) === groupId) { member = true; break; }
  }
  // Список пар догоняет состав с задержкой, а состав группы в зеркале —
  // раньше. Тот же запрос, которым приложение получает пропуск подписки.
  if (!member) {
    try {
      const rows = $app.findRecordsByFilter("groups", "id = {:g} && members ~ {:u}", "", 1, 0,
        { g: groupId, u: auth.id });
      member = !!(rows && rows.length > 0);
    } catch (_) {}
  }
  if (!member) return e.json(403, { ok: false, error: "not_member" });

  const secret = $os.getenv("CENTRIFUGO_TOKEN_HMAC");
  if (!secret) return e.json(500, { ok: false, error: "not_configured" });

  // Без похожих на глаз символов: код диктуют голосом и переписывают руками.
  const abc = "abcdefghjkmnpqrstuvwxyz23456789";
  const digest = $security.hs256(groupId, secret);
  let room = "";
  for (let i = 0; i < 8; i++) {
    room += abc[digest.charCodeAt(i) % abc.length];
  }

  return e.json(200, { ok: true, room: room });
});

/// Новая комната из браузера. Код придумывает СЕРВЕР, а не страница.
///
/// До 16.09.2026 лендинг сочинял шесть букв сам, а пропуск сервер выдавал на
/// любой код: набрал что угодно — и комната «создалась». Хуже того, тем же
/// путём открывалась и комната пары, если код попал в чужие руки: вечером
/// 16.09 к паре в `watch:4ejxgjve` пришли двое посторонних, писали в чат и
/// жали паузу (жалоба с записью экрана).
///
/// Теперь у открытой комнаты код из десяти знаков: шесть случайных и четыре
/// подписи от них. Подпись знает только сервер, поэтому набранный руками код
/// честно отвечает «комнаты нет». Хранить ничего не нужно — код проверяется
/// сам по себе и переживает перезапуск. Длина 10 не пересекается с кодом пары
/// (там 8).
routerAdd("POST", "/api/watch/new", (e) => {
  const secret = $os.getenv("CENTRIFUGO_TOKEN_HMAC");
  if (!secret) return e.json(500, { ok: false, error: "not_configured" });

  const abc = "abcdefghjkmnpqrstuvwxyz23456789";
  const seed = $security.hs256($security.randomString(32), secret);
  let head = "";
  for (let i = 0; i < 6; i++) head += abc[parseInt(seed.substr(i * 2, 2), 16) % abc.length];
  const sig = $security.hs256("watch-open:" + head, secret);
  let tail = "";
  for (let i = 0; i < 4; i++) tail += abc[parseInt(sig.substr(i * 2, 2), 16) % abc.length];

  return e.json(200, { ok: true, room: head + tail });
});

/// Пропуск в комнату.
///
/// Комнат два вида, и пускают в них по-разному:
///
/// * **открытая** (код из 10 знаков, выдан `/api/watch/new`) — кто угодно по
///   ссылке, это и есть её смысл: позвать друга в браузер;
/// * **комната пары** (8 знаков, HMAC от group_id) — только участники пары.
///   Вошедший на странице аккаунт сверяется со своими группами; чужому — 403.
///
/// Выпущенные сборки приложения открывают комнату во встроенном браузере БЕЗ
/// сессии, и ломать их нельзя. Для них есть поручительство: экран комнаты в
/// приложении держит своё подключение к каналу (метка `app`, а выдаёт его
/// `centrifugo_tokens.pb.js` только участнику). Каждое такое подключение
/// пускает одну страницу без входа. Когда оба в приложении и обе страницы уже
/// внутри, свободных мест нет — посторонний получает экран входа. Свои
/// страницы помечаются `vouch`, вошедшие — `auth`; счёт ведётся по ним.
/// Новые сборки передают сессию сами и сюда не попадают.
///
/// Всё остальное — «комнаты нет». Коды, которые лендинг сочинял до 16.09,
/// пускаем только пока в комнате кто-то есть и только до 20.09: люди, уже
/// сидящие в такой комнате, должны суметь перезагрузить вкладку.
routerAdd("POST", "/api/watch/token", (e) => {
  const TTL = 6 * 60 * 60; // пропуск на вечер, дольше комнате не нужно
  const LEGACY_UNTIL = Date.parse("2026-09-20T00:00:00Z");
  const abc = "abcdefghjkmnpqrstuvwxyz23456789";

  const body = e.requestInfo().body || {};
  const room = String(body.room || "").toLowerCase().replace(/[^a-z0-9]/g, "");

  // Короткое и только буквы с цифрами: иначе через имя канала можно было бы
  // уехать в чужое пространство имён.
  if (room.length < 4 || room.length > 12) {
    return e.json(400, { ok: false, error: "bad_room" });
  }

  const secret = $os.getenv("CENTRIFUGO_TOKEN_HMAC");
  if (!secret) return e.json(500, { ok: false, error: "not_configured" });

  // Гостю выдаём случайное имя: постоянного идентификатора у него нет и не
  // должно быть — сайт анонимный. Своё прежнее имя браузер присылает обратно,
  // иначе перезагрузка вкладки выглядела бы приходом второго зрителя.
  const asked = String(body.guest || "");
  const guest = /^g[a-z0-9]{14}$/.test(asked)
    ? asked
    : "g" + $security.randomString(14).toLowerCase();
  const channel = "watch:" + room;
  const auth = e.auth;

  /** Кто сейчас в канале. null — Centrifugo не ответил. */
  const presence = () => {
    try {
      const api = $os.getenv("CENTRIFUGO_API") || "http://127.0.0.1:9000/api";
      const res = $http.send({
        url: api + "/presence",
        method: "POST",
        headers: {
          "X-API-Key": $os.getenv("CENTRIFUGO_API_KEY") || "",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ channel: channel }),
        timeout: 4,
      });
      if (res.statusCode !== 200) return null;
      const out = res.json || {};
      if (out.error) return null;
      return (out.result && out.result.presence) || {};
    } catch (_) {
      return null;
    }
  };

  /** Метка подписки: объектом или строкой — смотря как отдал Centrifugo. */
  const infoOf = (c) => {
    let info = c && (c.chan_info || c.chanInfo);
    if (typeof info === "string") {
      try { info = JSON.parse(info); } catch (_) { info = null; }
    }
    return info || null;
  };

  let kind = "";

  // 1. Открытая комната: подпись сходится.
  if (room.length === 10) {
    const sig = $security.hs256("watch-open:" + room.substr(0, 6), secret);
    let tail = "";
    for (let i = 0; i < 4; i++) tail += abc[parseInt(sig.substr(i * 2, 2), 16) % abc.length];
    if (tail === room.substr(6)) kind = "open";
  }

  // 2. Комната пары. Код выводится из hex-строки, поэтому знаков в нём только
  //    шестнадцать — по форме её и узнаём.
  const pairShape = room.length === 8 && /^[efghjkuvwxyz2345]{8}$/.test(room);

  if (!kind && pairShape) {
    if (auth) {
      const codeOf = (gid) => {
        const digest = $security.hs256(String(gid), secret);
        let code = "";
        for (let i = 0; i < 8; i++) code += abc[digest.charCodeAt(i) % abc.length];
        return code;
      };
      let mine = [];
      try { mine = auth.getStringSlice("group_ids") || []; } catch (_) { mine = []; }
      for (let i = 0; i < mine.length && !kind; i++) {
        if (codeOf(mine[i]) === room) kind = "member";
      }
      // `group_ids` догоняет состав с задержкой: свежая пара могла ещё не
      // доехать. Тот же запрос, которым приложение получает пропуск подписки.
      if (!kind) {
        try {
          const rows = $app.findRecordsByFilter("groups", "members ~ {:u}", "", 50, 0, { u: auth.id });
          for (let i = 0; i < rows.length && !kind; i++) {
            if (codeOf(rows[i].id) === room) kind = "member";
          }
        } catch (_) {}
      }
    }

    if (!kind) {
      const clients = presence() || {};
      const apps = {};
      const vouched = {};
      Object.keys(clients).forEach((k) => {
        const c = clients[k] || {};
        const info = infoOf(c);
        if (info && info.app) apps[c.user] = 1;
        // Место занимает любая страница без входа: и пущенная по
        // поручительству, и вошедшая до 16.09 (метки у неё нет, а свой это
        // или посторонний — не узнать). Вошедшие своим аккаунтом не в счёт.
        else if (!(info && info.auth) && c.user !== guest) vouched[c.user] = 1;
      });
      const nApps = Object.keys(apps).length;
      if (nApps > 0 && Object.keys(vouched).length < nApps) kind = "vouch";
    }

    if (!kind) {
      $app.logger().warn("watch: в комнату пары не пустили",
        "room", room, "auth", auth ? auth.id : "", "ip", e.realIP());
      return auth
        ? e.json(403, { ok: false, error: "not_member" })
        : e.json(401, { ok: false, error: "auth_required" });
    }
  }

  // 3. Код от прежнего лендинга: только в живую комнату и только до срока.
  if (!kind && Date.now() < LEGACY_UNTIL) {
    const clients = presence();
    if (clients && Object.keys(clients).length > 0) kind = "legacy";
  }

  if (!kind) {
    $app.logger().warn("watch: комнаты нет", "room", room, "ip", e.realIP());
    return e.json(404, { ok: false, error: "not_found" });
  }

  const claims = { sub: guest, channel: channel };
  if (kind === "member") claims.info = { auth: 1 };
  if (kind === "vouch") claims.info = { vouch: 1 };

  return e.json(200, {
    ok: true,
    kind: kind,
    userId: guest,
    channel: channel,
    // Пропуск на соединение и отдельный — на конкретный канал.
    connectionToken: $security.createJWT({ sub: guest }, secret, TTL),
    subscriptionToken: $security.createJWT(claims, secret, TTL),
  });
});
