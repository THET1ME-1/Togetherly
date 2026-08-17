/// Ключи для голосовой связи в комнате совместного просмотра.
///
/// GET /api/watch/rtc  → { iceServers: [...] }
///
/// ЗАЧЕМ: голос между двумя идёт напрямую (WebRTC), но прямая дорога есть не
/// всегда: у российских операторов сплошной CGNAT, и без ретранслятора
/// соединение не встаёт вовсе. Ретранслятор — свой coturn на этом же сервере.
///
/// Учётка TURN одна (`TURN_USER`/`TURN_PASS` в окружении PocketBase, они же в
/// /etc/turnserver.conf). Временные ключи coturn считает по HMAC-SHA1, а в этом
/// JSVM такого хеша нет вовсе — только sha256/512, поэтому пошли простым путём.
/// Пароль отдаём лишь вошедшим, ретранслятор закрыт квотами и запретом на
/// внутренние адреса, так что цена утечки — чужой голосовой трафик, не больше.
///
/// ВАЖНО (PB JSVM): всё внутри обработчика, модульный уровень ему не виден.
routerAdd("GET", "/api/watch/rtc", (e) => {
  const user = $os.getenv("TURN_USER");
  const pass = $os.getenv("TURN_PASS");
  // Запасное имя — именно `rt.`: TURN живёт на первой машине, а `togetherly.day`
  // с 17.08.2026 смотрит на вторую, где его нет.
  const host = $os.getenv("TURN_HOST") || "rt.togetherly.day";

  // Публичные STUN оставляем даже без своего TURN: большинству пар хватает
  // прямого соединения, и ретранслятор им не нужен вовсе.
  const servers = [
    { urls: ["stun:stun.l.google.com:19302", "stun:" + host + ":3478"] },
  ];

  if (user && pass) {
    servers.push({
      urls: [
        "turn:" + host + ":3478?transport=udp",
        "turn:" + host + ":3478?transport=tcp",
      ],
      username: user,
      credential: pass,
    });
  }

  return e.json(200, { success: true, iceServers: servers });
}, $apis.requireAuth());
