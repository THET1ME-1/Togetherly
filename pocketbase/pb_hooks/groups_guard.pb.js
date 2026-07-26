/// Страж состава пары: через API участника можно только убрать, но не добавить.
///
/// updateRule коллекции `groups` — `members ?~ @request.auth.id`, то есть любой
/// участник может писать в запись группы, включая само поле `members`. А хук
/// groups_membership.pb.js на каждое изменение пересчитывает скрытое
/// `users.group_ids`, по которому пускают правила чата и всех остальных
/// коллекций. Итог: одним PATCH'ем можно было вписать в пару третий аккаунт,
/// и он получал всю переписку, ленту и карту. Инварианта «в паре двое» на
/// сервере не было.
///
/// Легальные пути добавления участника идут мимо этого хука — они серверные:
/// приём инвайта (`/api/invite/accept`) и роуты groups.pb.js сохраняют запись
/// через $app.save/txApp.save, а программный save request-хуки не проходит.
/// Клиент же членство только СОКРАЩАЕТ: `_leaveGroupLocal` выкидывает из списка
/// себя (запасной путь, когда серверный роут не ответил).
///
/// Отсюда правило: новый список участников обязан быть подмножеством прежнего.
/// Создание группы (сразу с двумя) идёт через create — этот хук его не трогает.
///
/// ВАЖНО (PB JSVM): обработчик исполняется в изолированном пуле и НЕ видит
/// функций уровня файла — разбор списка инлайнится внутрь.

onRecordUpdateRequest((e) => {
  let isSuper = false;
  try {
    isSuper = !!(e.auth && e.auth.collection() && e.auth.collection().name === "_superusers");
  } catch (_) {
    isSuper = false;
  }

  if (!isSuper) {
    const body = (e.requestInfo().body || {});
    if ("members" in body) {
      // ГРАБЛИ JSVM: json-поле в теле запроса приходит МАССИВОМ БАЙТ
      // ([91,34,...] — это utf-8 от `["uid1","uid2"]`), а не списком строк.
      // Array.isArray при этом true, поэтому проверять надо тип элементов.
      // Тот же случай, что с .get() на json-полях в users_guard.pb.js.
      const raw = body.members;
      let next = null;
      if (typeof raw === "string") {
        try { next = JSON.parse(raw || "[]"); } catch (_) { next = null; }
      } else if (Array.isArray(raw)) {
        if (raw.length === 0) {
          next = [];
        } else if (typeof raw[0] === "number") {
          let s = "";
          for (let i = 0; i < raw.length; i++) s += String.fromCharCode(raw[i]);
          try { next = JSON.parse(s || "[]"); } catch (_) { next = null; }
        } else {
          next = raw;
        }
      }
      if (!Array.isArray(next)) {
        throw new ForbiddenError("members must be a list");
      }

      // Текущий состав читаем из БД строкой: .get() на json-поле в JSVM отдаёт байты.
      let current = [];
      try {
        const saved = $app.findRecordById("groups", e.record.id);
        current = JSON.parse(saved.getString("members") || "[]") || [];
      } catch (_) {
        current = [];
      }

      for (let i = 0; i < next.length; i++) {
        if (current.indexOf(String(next[i])) === -1) {
          throw new ForbiddenError("cannot add members directly");
        }
      }
    }
  }

  e.next();
}, "groups");
