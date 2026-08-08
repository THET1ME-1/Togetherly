/// Метаданные трека Яндекс.Музыки: GET /api/music/yandex?track=<номер>
///
/// ЗАЧЕМ: у остальных сервисов есть oEmbed или og-теги, и клиент разбирает их
/// сам. Яндекс.Музыка страницу рисует скриптом: в ответ на обычный GET
/// приходит пустой каркас с заголовком «Яндекс Музыка — собираем музыку для
/// вас» — ни og, ни ld+json, ни для браузерного User-Agent, ни для Googlebot
/// (проверено 8 августа 2026 и с ноутбука, и с этого сервера). Прежний парсер
/// по `<title>` подставлял в поля виджета этот самый заголовок, поэтому
/// название и исполнителя люди вписывали руками.
///
/// Данные лежат в их API — `api.music.yandex.net/tracks/<id>`, без ключа и без
/// авторизации. За пределами России он отвечает 451 (Unavailable For Legal
/// Reasons), поэтому клиент сперва ходит туда напрямую, а при отказе повторяет
/// запрос сюда: сервер стоит в Тамбове и API ему отвечает.
///
/// БЕЗОПАСНОСТЬ: тут нет ничего от SSRF из `link_preview` — адрес не приходит
/// снаружи. Наружу уходит фиксированный хост, а из запроса берётся только
/// номер трека, и тот проверяется на цифры. Ответ отдаётся как есть: клиент
/// разбирает его тем же кодом, что и прямой ответ Яндекса.
///
/// ВАЖНО (PB JSVM): всё внутри обработчика — модульный уровень ему не виден.

routerAdd("GET", "/api/music/yandex", (e) => {
  const raw = String((e.requestInfo().query || {}).track || "").trim();
  if (!raw) return e.json(400, { error: "track required" });
  // Номер трека — только цифры. Всё прочее в адрес не попадёт.
  if (!/^[0-9]{1,20}$/.test(raw)) {
    return e.json(400, { error: "bad track id" });
  }

  try {
    const res = $http.send({
      url: "https://api.music.yandex.net/tracks/" + raw,
      method: "GET",
      headers: {
        "Accept": "application/json",
        // Яндекс отдаёт JSON и без этого, но пусть в их логах будет видно, кто
        // ходит: правило вежливости то же, что у Викисклада в Plein.
        "User-Agent": "TogetherlyBot/1.0 (+https://togetherly.day)",
      },
      timeout: 8,
    });

    if (res.statusCode !== 200) {
      // Причину видно в журнале: свои отказы роут обязан объяснять сам,
      // `e.json` в `_logs` не попадает.
      $app.logger().warn("music yandex upstream", "track", raw, "status", res.statusCode);
      return e.json(502, { error: "upstream " + res.statusCode });
    }

    const body = res.json;
    const list = body && body.result;
    if (!list || !list.length) {
      return e.json(404, { error: "track not found" });
    }
    const track = list[0];

    // Отдаём ровно ту форму, что приходит от Яндекса: на клиенте один парсер
    // на оба пути (прямой и через нас), и расходиться им негде.
    return e.json(200, {
      result: [
        {
          id: String(track.id || raw),
          title: track.title || "",
          artists: (track.artists || []).map((a) => ({ name: a.name || "" })),
          coverUri: track.coverUri || "",
        },
      ],
    });
  } catch (err) {
    $app.logger().warn("music yandex failed", "track", raw, "error", String(err));
    return e.json(502, { error: "fetch failed" });
  }
});
