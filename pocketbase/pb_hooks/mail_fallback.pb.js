/// Запасной путь писем PocketBase, когда Resend отказал (05.11.2026).
///
/// Основной путь — SMTP Resend из настроек PocketBase (`no-reply@togetherly.day`,
/// см. CLAUDE.md, «Почта PocketBase ушла со stgroup.dev@gmail.com»). У
/// бесплатного Resend две квоты: 100 писем в сутки и месячная. 04.11.2026 в
/// 17:02 UTC кончилась месячная, и до нового периода не ушло ни одно письмо
/// сброса пароля: 374 письма, 94 человека, а приложение отвечало «письмо
/// отправлено».
///
/// Теперь письмо сперва идёт штатно (`e.next()`), а отказ отдаётся локальному
/// релею `127.0.0.1:8099` (`pocketbase/mail_relay/gmail_relay.py`). У релея свои
/// каналы: Resend другого аккаунта и Gmail API с суточным потолком. Скрытые
/// адреса Apple (`privaterelay.appleid.com`) письма с gmail.com не принимают, им
/// запасной путь не поможет, но остальным письмо дойдёт.
///
/// Отказ релея бросается дальше: вызывающий (`email_case.pb.js`, «pwreset»)
/// пишет его в журнал и снимает отметку, чтобы человек мог нажать ещё раз.
///
/// Всё инлайн: JSVM не показывает обработчику функции уровня файла.
onMailerSend((e) => {
  let smtpErr = null;
  try {
    e.next();
    return;
  } catch (err) {
    smtpErr = String(err);
  }

  const msg = e.message;
  const to = [];
  try {
    const list = msg.to || [];
    for (let i = 0; i < list.length; i++) {
      const a = list[i];
      if (a && a.address) to.push(String(a.address));
    }
  } catch (_) {
    // пустой список разберём ниже
  }
  if (to.length === 0) throw new Error("mail-fallback: письмо без получателей; smtp: " + smtpErr);

  const resp = $http.send({
    method: "POST",
    url: "http://127.0.0.1:8099/send",
    body: JSON.stringify({
      to: to,
      subject: String(msg.subject || ""),
      html: String(msg.html || ""),
      text: String(msg.text || ""),
    }),
    headers: { "Content-Type": "application/json" },
    timeout: 25,
  });
  if (resp.statusCode === 200) {
    $app.logger().warn("mail-fallback: ушло через релей", "to", to.join(","), "smtp", smtpErr);
    return;
  }
  throw new Error("mail-fallback: релей " + resp.statusCode + " " + String(resp.body) + "; smtp: " + smtpErr);
});
