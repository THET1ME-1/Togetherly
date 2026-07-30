/// widget_plus.pb.js — признак Togetherly+ в карточке `widget_data`.
///
/// Зачем. Правила `users` пускают человека только к своей записи
/// (`id = @request.auth.id`), поэтому чужой флаг `plus` клиенту не виден — а
/// значок Togetherly+ рядом с именем партнёр видеть должен. `widget_data`
/// читают оба участника пары, значит флаг едет туда.
///
/// Проставляет его СЕРВЕР, а не приложение: поле переписывается на каждом
/// сохранении значением из `users`. Пришли клиент `plus: true` сам — оно будет
/// затёрто, дорисовать себе значок нельзя.
///
/// Деплой: положить в /opt/pocketbase/pb_hooks/ и systemctl restart pocketbase.

onRecordCreateRequest((e) => {
  // ГРАБЛИ JSVM: обработчик живёт в изолированном пуле и функций уровня файла
  // не видит, поэтому тело продублировано в обоих хуках.
  try {
    const uid = e.auth ? e.auth.id : "";
    if (uid) {
      const user = $app.findRecordById("users", uid);
      e.record.set("plus", user.getBool("plus") === true);
    }
  } catch (err) {
    // Не нашли пользователя или база занята — сохранение не рушим, значок
    // подтянется при следующем обновлении карточки.
    try {
      $app.logger().warn("widget_plus create: " + String(err));
    } catch (_) {}
  }
  e.next();
}, "widget_data");

onRecordUpdateRequest((e) => {
  try {
    const uid = e.auth ? e.auth.id : "";
    if (uid) {
      const user = $app.findRecordById("users", uid);
      e.record.set("plus", user.getBool("plus") === true);
    }
  } catch (err) {
    try {
      $app.logger().warn("widget_plus update: " + String(err));
    } catch (_) {}
  }
  e.next();
}, "widget_data");
