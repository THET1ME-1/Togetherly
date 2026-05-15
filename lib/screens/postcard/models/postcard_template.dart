enum PostcardTemplateId { together, polaroid, bloom, nightSky }

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

class PostcardTemplate {
  final PostcardTemplateId id;
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
  }) {
    final names =
        myName.isNotEmpty && partnerName.isNotEmpty
            ? '$myName & $partnerName'
            : myName.isNotEmpty
            ? myName
            : 'Мы вместе';

    return switch (templateId) {
      PostcardTemplateId.together => [
        PostcardTextBlock(id: 'names', label: 'Имена', text: names),
        PostcardTextBlock(
          id: 'days_label',
          label: 'Подпись к числу',
          text: 'дней вместе',
        ),
        PostcardTextBlock(
          id: 'message',
          label: 'Послание',
          text: 'Каждый день с тобой — подарок ❤️',
        ),
      ],
      PostcardTemplateId.polaroid => [
        PostcardTextBlock(id: 'names', label: 'Имена', text: names),
        PostcardTextBlock(
          id: 'days_label',
          label: 'Подпись',
          text: 'дней любви',
        ),
        PostcardTextBlock(
          id: 'message',
          label: 'Подпись на полароиде',
          text: 'Наш момент ✨',
        ),
      ],
      PostcardTemplateId.bloom => [
        PostcardTextBlock(id: 'names', label: 'Имена', text: names),
        PostcardTextBlock(
          id: 'days_label',
          label: 'Подпись к числу',
          text: 'дней рядом',
        ),
        PostcardTextBlock(
          id: 'message',
          label: 'Сообщение',
          text: 'Ты моё любимое приключение 🌸',
        ),
      ],
      PostcardTemplateId.nightSky => [
        PostcardTextBlock(id: 'names', label: 'Имена', text: names),
        PostcardTextBlock(
          id: 'days_label',
          label: 'Подпись к числу',
          text: 'ночей под одним небом',
        ),
        PostcardTextBlock(
          id: 'message',
          label: 'Послание',
          text: 'Ты — моя звезда ✨',
        ),
      ],
    };
  }

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
  ];
}
