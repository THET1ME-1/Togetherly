// Плашка Togetherly+ на главной: раз в семь часов тем, кто не купил.

const Map<String, Map<String, String>> plusPromoStrings = {
  'plusPromoTitle': {
    'ru': 'Togetherly+',
    'en': 'Togetherly+',
    'pt': 'Togetherly+',
    'it': 'Togetherly+',
    'es': 'Togetherly+',
    'fr': 'Togetherly+',
    'de': 'Togetherly+',
  },
  'plusPromoBody': {
    'ru': 'Свои настроения, календарь цикла, статистика пары, все виджеты и '
        'фоны — и никакой рекламы.',
    'en': 'Custom moods, the cycle calendar, couple stats, every widget and '
        'background — and no ads.',
    'pt': 'Humores próprios, calendário do ciclo, estatísticas do casal, todos '
        'os widgets e fundos — e sem anúncios.',
    'it': 'Umori personali, calendario del ciclo, statistiche di coppia, tutti '
        'i widget e gli sfondi — e niente pubblicità.',
    'es': 'Ánimos propios, calendario del ciclo, estadísticas de pareja, todos '
        'los widgets y fondos — y sin anuncios.',
    'fr': 'Humeurs personnalisées, calendrier du cycle, statistiques du couple, '
        'tous les widgets et fonds — et zéro publicité.',
    'de': 'Eigene Stimmungen, Zykluskalender, Paar-Statistik, alle Widgets und '
        'Hintergründe — und keine Werbung.',
  },
  // Пять строк витрины: то же, что в plusPromoBody, но по одной вещи в строку —
  // сплошным абзацем это читалось как реклама, и человек закрывал не глядя.
  'plusPromoPerkMoods': {
    'ru': 'Свои настроения',
    'en': 'Your own moods',
    'pt': 'Humores próprios',
    'it': 'Umori personali',
    'es': 'Ánimos propios',
    'fr': 'Tes propres humeurs',
    'de': 'Eigene Stimmungen',
  },
  'plusPromoPerkCycle': {
    'ru': 'Календарь цикла',
    'en': 'Cycle calendar',
    'pt': 'Calendário do ciclo',
    'it': 'Calendario del ciclo',
    'es': 'Calendario del ciclo',
    'fr': 'Calendrier du cycle',
    'de': 'Zykluskalender',
  },
  'plusPromoPerkStats': {
    'ru': 'Статистика пары',
    'en': 'Couple stats',
    'pt': 'Estatísticas do casal',
    'it': 'Statistiche di coppia',
    'es': 'Estadísticas de pareja',
    'fr': 'Statistiques du couple',
    'de': 'Paar-Statistik',
  },
  'plusPromoPerkWidgets': {
    'ru': 'Все виджеты и фоны',
    'en': 'Every widget and background',
    'pt': 'Todos os widgets e fundos',
    'it': 'Tutti i widget e gli sfondi',
    'es': 'Todos los widgets y fondos',
    'fr': 'Tous les widgets et fonds',
    'de': 'Alle Widgets und Hintergründe',
  },
  'plusPromoPerkNoAds': {
    'ru': 'Никакой рекламы',
    'en': 'No ads at all',
    'pt': 'Nada de anúncios',
    'it': 'Niente pubblicità',
    'es': 'Nada de anuncios',
    'fr': 'Zéro publicité',
    'de': 'Keine Werbung',
  },
  'plusPromoOpen': {
    'ru': 'Посмотреть',
    'en': 'Take a look',
    'pt': 'Ver',
    'it': 'Dai un’occhiata',
    'es': 'Ver',
    'fr': 'Voir',
    'de': 'Ansehen',
  },
  'plusPromoLater': {
    'ru': 'Не сейчас',
    'en': 'Not now',
    'pt': 'Agora não',
    'it': 'Non ora',
    'es': 'Ahora no',
    'fr': 'Pas maintenant',
    'de': 'Nicht jetzt',
  },
};
