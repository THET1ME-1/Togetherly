/// Реакции чата (28.09.2026): рисунки той же рукой, что значки, вместо
/// системных эмодзи. В сообщении по-прежнему хранится эмодзи — так реакцию
/// понимают сборки постарше и партнёр на них, а рисунок подставляется при
/// показе. Незнакомый эмодзи рисуется как есть.
class ChatReaction {
  const ChatReaction(this.id, this.emoji);

  /// id рисунка: `assets/images/reactions/<id>.webp`, `reaction_<id>` в каталоге.
  final String id;
  final String emoji;
}

const List<ChatReaction> kChatReactions = [
  ChatReaction('heart', '❤️'),
  ChatReaction('in_love', '🥰'),
  ChatReaction('heart_eyes', '😍'),
  ChatReaction('kiss', '😘'),
  ChatReaction('laugh', '😂'),
  ChatReaction('hug', '🤗'),
  ChatReaction('thumbs_up', '👍'),
  ChatReaction('clap', '👏'),
  ChatReaction('fire', '🔥'),
  ChatReaction('party', '🎉'),
  ChatReaction('wow', '😮'),
  ChatReaction('cry', '😢'),
  ChatReaction('pray', '🙏'),
  ChatReaction('hundred', '💯'),
  ChatReaction('angry', '😡'),
  ChatReaction('thumbs_down', '👎'),
];

/// Реакция двойного касания по умолчанию.
const String kDefaultQuickReaction = '❤️';

/// Рисунок для эмодзи из сообщения; null — рисунка нет, показываем эмодзи.
///
/// Сравнение без вариационного селектора: «❤» и «❤️» — одно сердце, а
/// клавиатуры и старые сборки ставят то одно, то другое.
ChatReaction? chatReactionOf(String emoji) {
  final bare = emoji.replaceAll('️', '');
  for (final r in kChatReactions) {
    if (r.emoji.replaceAll('️', '') == bare) return r;
  }
  return null;
}

/// Что делает двойное касание: ставит выбранную реакцию, а если она уже
/// стоит — снимает. Другую свою реакцию заменяет выбранной.
String? quickReactionToggle({required String? mine, required String quick}) =>
    mine == quick ? null : quick;
