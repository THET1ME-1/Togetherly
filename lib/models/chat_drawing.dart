/// Рисунок в чате.
///
/// Своего поля под картинку у сообщения нет, поэтому рисунок едет обычным
/// сообщением с пином: в `pin_thumb` ссылка на снимок холста, в `pin_title`
/// его название, а `pin_id` помечен приставкой, чтобы чат нарисовал крупную
/// карточку вместо значка пина. Старые сборки покажут тот же пин маленьким
/// чипом: сообщение не теряется, просто выглядит скромнее.
library;

const String kChatDrawingPrefix = 'canvas:';

/// Текст сообщения без подписи. Пустой текст сервис не отправляет, а в пуше и
/// в списке чатов значок читается лучше пустоты. В самом пузыре не выводится.
const String kChatDrawingText = '🎨';

String chatDrawingPinId(String canvasId) => '$kChatDrawingPrefix$canvasId';

bool isChatDrawing(String? pinId) =>
    pinId != null && pinId.startsWith(kChatDrawingPrefix);

/// Показывать ли текст сообщения под пином: у рисунка без подписи не надо.
bool showsChatText({required String? pinId, required String text}) =>
    text.isNotEmpty && !(isChatDrawing(pinId) && text == kChatDrawingText);
