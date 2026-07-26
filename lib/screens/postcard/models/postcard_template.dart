import '../../../services/locale_service.dart';

enum PostcardTemplateId {
  together,
  polaroid,
  bloom,
  nightSky,
  // Бумажные: узнаваемый документ из настоящего мира, подделанный под пару.
  ticket,
  receipt,
  telegram,
  parcel,
}

class PostcardTextBlock {
  final String id;
  final String label;
  final String text;

  const PostcardTextBlock({
    required this.id,
    required this.label,
    required this.text,
  });

  PostcardTextBlock copyWith({String? text}) =>
      PostcardTextBlock(id: id, label: label, text: text ?? this.text);
}

/// Настоящие числа пары для открытки.
///
/// Открытка не заполняется выдуманным текстом: всё, что на ней написано,
/// приложение уже посчитало — воспоминания, рисунки, «я скучаю», серия дней.
/// Пока цифры не доехали с сервера, строки с ними просто не печатаются.
class PostcardStats {
  const PostcardStats({
    this.memories = 0,
    this.drawings = 0,
    this.missYou = 0,
    this.streak = 0,
  });

  final int memories;
  final int drawings;
  final int missYou;
  final int streak;

  bool get isEmpty => memories == 0 && drawings == 0 && missYou == 0 && streak == 0;
}

class PostcardTemplate {
  final PostcardTemplateId id;

  /// Латинские названия старой четвёрки — часть их облика («Polaroid»,
  /// «Night Sky»), поэтому они не переводятся. У бумажных название читается
  /// как подпись к предмету, и оно берётся из локали: в приложении два языка.
  final String name;
  final String emoji;

  const PostcardTemplate({
    required this.id,
    required this.name,
    required this.emoji,
  });

  static List<PostcardTextBlock> defaultBlocks({
    required PostcardTemplateId templateId,
    required int days,
    required String myName,
    required String partnerName,
    PostcardStats stats = const PostcardStats(),
  }) {
    final s = LocaleService.current;
    final names =
        myName.isNotEmpty && partnerName.isNotEmpty
            ? '$myName & $partnerName'
            : myName.isNotEmpty
            ? myName
            : s.pcNamesFallback;

    return switch (templateId) {
      PostcardTemplateId.together => [
        PostcardTextBlock(id: 'names', label: s.pcLabelNames, text: names),
        PostcardTextBlock(
          id: 'days_label',
          label: s.pcLabelDaysCaption,
          text: s.pcDaysTogether,
        ),
        PostcardTextBlock(
          id: 'message',
          label: s.pcLabelMessage,
          text: s.pcMsgTogether,
        ),
      ],
      PostcardTemplateId.polaroid => [
        PostcardTextBlock(id: 'names', label: s.pcLabelNames, text: names),
        PostcardTextBlock(
          id: 'days_label',
          label: s.pcLabelCaption,
          text: s.pcDaysOfLove,
        ),
        PostcardTextBlock(
          id: 'message',
          label: s.pcLabelPolaroidCaption,
          text: s.pcMsgPolaroid,
        ),
      ],
      PostcardTemplateId.bloom => [
        PostcardTextBlock(id: 'names', label: s.pcLabelNames, text: names),
        PostcardTextBlock(
          id: 'days_label',
          label: s.pcLabelDaysCaption,
          text: s.pcDaysNearby,
        ),
        PostcardTextBlock(
          id: 'message',
          label: s.pcLabelMessageAlt,
          text: s.pcMsgBloom,
        ),
      ],
      PostcardTemplateId.ticket => [
        PostcardTextBlock(
          id: 'names',
          label: s.pcLabelNames,
          text: myName.isNotEmpty && partnerName.isNotEmpty
              ? '$myName → $partnerName'
              : names,
        ),
        PostcardTextBlock(
          id: 'days_label',
          label: s.pcLabelDaysCaption,
          text: s.pcDaysTogether,
        ),
        PostcardTextBlock(
          id: 'message',
          label: s.pcLabelMessage,
          text: s.pcMsgTicket,
        ),
      ],
      PostcardTemplateId.receipt => [
        PostcardTextBlock(id: 'names', label: s.pcLabelNames, text: names),
        PostcardTextBlock(
          id: 'days_label',
          label: s.pcLabelDaysCaption,
          text: s.pcDaysTogether,
        ),
        PostcardTextBlock(
          id: 'items',
          label: s.pcLabelReceiptItems,
          text: s.pcReceiptItems(stats),
        ),
        PostcardTextBlock(
          id: 'message',
          label: s.pcLabelMessage,
          text: s.pcMsgReceipt,
        ),
      ],
      PostcardTemplateId.telegram => [
        PostcardTextBlock(
          id: 'names',
          label: s.pcLabelNames,
          text: myName.isNotEmpty ? myName : names,
        ),
        PostcardTextBlock(
          id: 'days_label',
          label: s.pcLabelDaysCaption,
          text: s.pcDaysTogether,
        ),
        PostcardTextBlock(
          id: 'message',
          label: s.pcLabelMessage,
          text: s.pcMsgTelegram,
        ),
      ],
      PostcardTemplateId.parcel => [
        PostcardTextBlock(
          id: 'names',
          label: s.pcLabelNames,
          text: partnerName.isNotEmpty ? partnerName : names,
        ),
        PostcardTextBlock(
          id: 'days_label',
          label: s.pcLabelDaysCaption,
          text: s.pcDaysTogether,
        ),
        PostcardTextBlock(
          id: 'message',
          label: s.pcLabelMessage,
          text: s.pcMsgParcel(myName, days),
        ),
      ],
      PostcardTemplateId.nightSky => [
        PostcardTextBlock(id: 'names', label: s.pcLabelNames, text: names),
        PostcardTextBlock(
          id: 'days_label',
          label: s.pcLabelDaysCaption,
          text: s.pcNightsUnderSky,
        ),
        PostcardTextBlock(
          id: 'message',
          label: s.pcLabelMessage,
          text: s.pcMsgNightSky,
        ),
      ],
    };
  }

  /// Подпись открытки на языке приложения. Пустое имя в каталоге означает
  /// «взять из локали» — так у бумажных, у старой четвёрки имя латинское.
  String get title => name.isNotEmpty
      ? name
      : switch (id) {
          PostcardTemplateId.ticket => LocaleService.current.pcNameTicket,
          PostcardTemplateId.receipt => LocaleService.current.pcNameReceipt,
          PostcardTemplateId.telegram => LocaleService.current.pcNameTelegram,
          PostcardTemplateId.parcel => LocaleService.current.pcNameParcel,
          _ => id.name,
        };

  static const List<PostcardTemplate> all = [
    PostcardTemplate(
      id: PostcardTemplateId.together,
      name: 'Together',
      emoji: '💕',
    ),
    PostcardTemplate(
      id: PostcardTemplateId.polaroid,
      name: 'Polaroid',
      emoji: '📷',
    ),
    PostcardTemplate(
      id: PostcardTemplateId.bloom,
      name: 'Bloom',
      emoji: '🌸',
    ),
    PostcardTemplate(
      id: PostcardTemplateId.nightSky,
      name: 'Night Sky',
      emoji: '🌙',
    ),
    PostcardTemplate(id: PostcardTemplateId.ticket, name: '', emoji: '🎟'),
    PostcardTemplate(id: PostcardTemplateId.receipt, name: '', emoji: '🧾'),
    PostcardTemplate(
      id: PostcardTemplateId.telegram,
      name: '',
      emoji: '📨',
    ),
    PostcardTemplate(id: PostcardTemplateId.parcel, name: '', emoji: '📦'),
  ];
}
