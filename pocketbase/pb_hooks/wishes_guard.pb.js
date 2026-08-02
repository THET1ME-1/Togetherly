/// Страж желаний: чужое желание можно только отметить сбывшимся, но не переписать.
///
/// Правило update у коллекции `wishes` пускает ЛЮБОГО участника группы, и иначе
/// нельзя: отметку «сбылось» ставит как раз не автор — в этом весь смысл общего
/// списка на двоих. Побочный эффект тот же, что был у чата: партнёр (или тот, у
/// кого утёк токен) мог голым API переписать чужое название и заметку.
/// Приложение таких кнопок не рисует — правка и удаление показываются только
/// автору, — но сервер разрешал.
///
/// Источник истины — ТЕЛО запроса, как в chat_guard.pb.js и users_guard.pb.js:
/// смотрим, какие поля клиент реально прислал.
///
/// Разрешено:
///   • автор — что угодно со своим желанием;
///   • не автор — только поля отметки: `done`, `done_at`, `done_by`, `done_note`;
///   • суперюзер — всё (админка).
///
/// Удаление оставлено автору самим правилом коллекции; здесь оно продублировано
/// на случай, если правило когда-нибудь ослабят.
///
/// ВАЖНО (PB JSVM): обработчик исполняется в изолированном пуле и НЕ видит
/// функций уровня файла — всё нужное объявлено внутри обработчика.

onRecordUpdateRequest((e) => {
  let isSuper = false;
  try {
    isSuper = !!(e.auth && e.auth.collection() && e.auth.collection().name === "_superusers");
  } catch (_) {
    isSuper = false;
  }

  if (!isSuper) {
    const uid = e.auth ? e.auth.id : "";
    let author = "";
    try {
      author = $app.findRecordById("wishes", e.record.id).getString("author_uid");
    } catch (_) {
      author = ""; // записи ещё нет (upsert по id) — пусть решают правила коллекции
    }

    if (author && author !== uid) {
      // Клиент при отметке чужого желания шлёт РОВНО эти поля
      // (`PbDataService.markWish`), а не всю запись — иначе страж отклонил бы
      // обычную галочку вместе с попыткой переписать название.
      const allowed = { done: 1, done_at: 1, done_by: 1, done_note: 1, id: 1 };
      const body = (e.requestInfo().body || {});
      const keys = Object.keys(body);
      for (let i = 0; i < keys.length; i++) {
        if (!allowed[keys[i]]) {
          throw new ForbiddenError("only the author can edit this wish");
        }
      }
    }
  }

  e.next();
}, "wishes");

onRecordDeleteRequest((e) => {
  let isSuper = false;
  try {
    isSuper = !!(e.auth && e.auth.collection() && e.auth.collection().name === "_superusers");
  } catch (_) {
    isSuper = false;
  }

  if (!isSuper) {
    const uid = e.auth ? e.auth.id : "";
    const author = e.record.getString("author_uid");
    if (author && author !== uid) {
      throw new ForbiddenError("only the author can delete this wish");
    }
  }

  e.next();
}, "wishes");
