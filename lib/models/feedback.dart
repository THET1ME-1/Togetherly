/// Обращение из приложения: виды, правила формы и итог отправки.
///
/// Google Play отклонил 1.42 (11.11.2026) по правилам о безопасности детей:
/// человек обязан иметь возможность сообщить о проблеме, не выходя из
/// приложения. Форма — `lib/screens/feedback_screen.dart`, сервер —
/// `pocketbase/pb_hooks/feedback.pb.js`.
library;

/// Вид обращения. [wire] — как он называется в запросе; те же ключи ждёт
/// `feedback_mail.js`, совпадение стережёт тест.
enum FeedbackKind {
  bug('bug'),
  idea('idea'),
  payment('payment'),
  abuse('abuse'),
  childSafety('child_safety'),
  other('other');

  const FeedbackKind(this.wire);
  final String wire;
}

/// Короче сервер не примет: это случайное нажатие, а не обращение.
const int kFeedbackMin = 10;

/// Потолок текста — тот же, что на сервере.
const int kFeedbackMax = 4000;

/// Можно ли отправлять такой текст.
bool feedbackReady(String text) {
  final length = text.trim().length;
  return length >= kFeedbackMin && length <= kFeedbackMax;
}

/// Чем кончилась отправка.
enum FeedbackSent {
  ok,

  /// Дневной предел обращений с одного аккаунта.
  tooMany,

  /// Нет связи или сервер не принял: текст остаётся в форме.
  failed,
}

/// Итог по коду ответа; null — ответа не было.
FeedbackSent feedbackSentOf(int? statusCode) => switch (statusCode) {
  200 => FeedbackSent.ok,
  429 => FeedbackSent.tooMany,
  _ => FeedbackSent.failed,
};
