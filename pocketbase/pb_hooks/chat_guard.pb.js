/// Страж чата: чужое сообщение можно только «пореагировать», но не переписать.
///
/// Правила коллекции `chat_messages` пускают на update и delete ЛЮБОГО участника
/// группы. Иначе не поставить реакцию: она лежит полем `reactions` в самой записи
/// сообщения, и ставит её как раз НЕ автор (pb_data_service.setChatReaction
/// патчит чужую запись). Побочный эффект — партнёр или тот, у кого утёк токен,
/// мог голым API переписать чужой текст, подменить цвет/лицо или снести
/// сообщение насовсем. Приложение таких кнопок не рисует (правка и удаление
/// показываются только для своих, `chat_screen._showMessageMenu`), но сервер
/// разрешал.
///
/// Источник истины — ТЕЛО запроса, как в users_guard.pb.js: смотрим, какие поля
/// клиент реально прислал. Сравнивать значения полей нельзя — .get() на json-полях
/// в PB JSVM отдаёт БАЙТЫ, не равные сами себе (те же грабли, что в users_guard).
///
/// Разрешено:
///   • автор — что угодно со своим сообщением (правка, мягкое удаление, оформление);
///   • не автор — ТОЛЬКО поля `reactions` и `voice_heard_at` (отметка «послушал»);
///   • суперюзер — всё (админка).
///
/// Жёсткое удаление записи не делает никто: клиент удаляет мягко (deleted=true),
/// поэтому DELETE оставляем только автору и суперюзеру.
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
      author = $app.findRecordById("chat_messages", e.record.id).getString("user_uid");
    } catch (_) {
      author = ""; // записи ещё нет (upsert по id) — пусть решают правила коллекции
    }

    if (author && author !== uid) {
      // `voice_heard_at` ставит СЛУШАТЕЛЬ, а не автор: иначе отправитель никогда
      // не узнает, дошло ли его голосовое до ушей. Поле числовое (epoch-ms) и
      // ничего, кроме отметки, не несёт — переписать им чужой текст нельзя.
      const body = (e.requestInfo().body || {});
      const keys = Object.keys(body);
      for (let i = 0; i < keys.length; i++) {
        const f = keys[i];
        if (f === "reactions" || f === "voice_heard_at" || f === "id") continue;
        throw new ForbiddenError("only the author can edit this message");
      }
    }
  }

  e.next();
}, "chat_messages");

onRecordDeleteRequest((e) => {
  let isSuper = false;
  try {
    isSuper = !!(e.auth && e.auth.collection() && e.auth.collection().name === "_superusers");
  } catch (_) {
    isSuper = false;
  }

  if (!isSuper) {
    const uid = e.auth ? e.auth.id : "";
    const author = e.record.getString("user_uid");
    if (author && author !== uid) {
      throw new ForbiddenError("only the author can delete this message");
    }
  }

  e.next();
}, "chat_messages");
