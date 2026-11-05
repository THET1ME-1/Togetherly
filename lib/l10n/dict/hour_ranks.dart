// Звания за часы в приложении (05.11.2026): названия 14 ступеней и строки
// чипа, листа званий и экрана нового звания. Префикс `hrank_` — чтобы не
// путать с рангами пары за опыт (`rank_*` в ranks.dart, lib/models/level.dart).
// Украинский и китайский — в `../uk/hour_ranks.dart` и `../zh/hour_ranks.dart`.

const Map<String, Map<String, String>> hourRanksStrings = {
  'hrank_0': {'ru': 'Искра', 'en': 'Spark', 'pt': 'Faísca', 'it': 'Scintilla', 'es': 'Chispa', 'fr': 'Étincelle', 'de': 'Funke'},
  'hrank_1': {'ru': 'Знакомство', 'en': 'Getting to know', 'pt': 'Conhecendo', 'it': 'Conoscenza', 'es': 'Conociéndonos', 'fr': 'Rencontre', 'de': 'Kennenlernen'},
  'hrank_2': {'ru': 'Симпатия', 'en': 'Crush', 'pt': 'Paixonite', 'it': 'Cotta', 'es': 'Flechazo', 'fr': 'Béguin', 'de': 'Schwärmerei'},
  'hrank_3': {'ru': 'Свидания', 'en': 'Dates', 'pt': 'Encontros', 'it': 'Appuntamenti', 'es': 'Citas', 'fr': 'Rendez-vous', 'de': 'Dates'},
  'hrank_4': {'ru': 'Влюблённость', 'en': 'In love', 'pt': 'Apaixonados', 'it': 'Innamorati', 'es': 'Enamorados', 'fr': 'Amoureux', 'de': 'Verliebt'},
  'hrank_5': {'ru': 'Пара', 'en': 'Couple', 'pt': 'Casal', 'it': 'Coppia', 'es': 'Pareja', 'fr': 'Couple', 'de': 'Paar'},
  'hrank_6': {'ru': 'Неразлучные', 'en': 'Inseparable', 'pt': 'Inseparáveis', 'it': 'Inseparabili', 'es': 'Inseparables', 'fr': 'Inséparables', 'de': 'Unzertrennlich'},
  'hrank_7': {'ru': 'Опора', 'en': 'Rock', 'pt': 'Porto seguro', 'it': 'Roccia', 'es': 'Apoyo', 'fr': 'Pilier', 'de': 'Fels'},
  'hrank_8': {'ru': 'Родные души', 'en': 'Kindred souls', 'pt': 'Almas afins', 'it': 'Anime affini', 'es': 'Almas afines', 'fr': 'Âmes sœurs', 'de': 'Seelenverwandte'},
  'hrank_9': {'ru': 'Серебряная пара', 'en': 'Silver couple', 'pt': 'Casal de prata', 'it': "Coppia d'argento", 'es': 'Pareja de plata', 'fr': "Couple d'argent", 'de': 'Silbernes Paar'},
  'hrank_10': {'ru': 'Золотая пара', 'en': 'Golden couple', 'pt': 'Casal de ouro', 'it': "Coppia d'oro", 'es': 'Pareja de oro', 'fr': "Couple d'or", 'de': 'Goldenes Paar'},
  'hrank_11': {'ru': 'Легенда', 'en': 'Legend', 'pt': 'Lenda', 'it': 'Leggenda', 'es': 'Leyenda', 'fr': 'Légende', 'de': 'Legende'},
  'hrank_12': {'ru': 'Звёздная пара', 'en': 'Star couple', 'pt': 'Casal estrela', 'it': 'Coppia di stelle', 'es': 'Pareja estelar', 'fr': 'Couple étoilé', 'de': 'Sternenpaar'},
  'hrank_13': {'ru': 'Навсегда', 'en': 'Forever', 'pt': 'Para sempre', 'it': 'Per sempre', 'es': 'Para siempre', 'fr': 'Pour toujours', 'de': 'Für immer'},
  // Лист званий
  'hrankYour': {'ru': 'Ваше звание', 'en': 'Your rank', 'pt': 'Seu título', 'it': 'Il tuo titolo', 'es': 'Tu título', 'fr': 'Votre titre', 'de': 'Dein Rang'},
  'hrankPartner': {'ru': 'Звание', 'en': 'Rank', 'pt': 'Título', 'it': 'Titolo', 'es': 'Título', 'fr': 'Titre', 'de': 'Rang'},
  'hrankNow': {'ru': 'Сейчас', 'en': 'Now', 'pt': 'Agora', 'it': 'Ora', 'es': 'Ahora', 'fr': 'Actuel', 'de': 'Jetzt'},
  // {0} — название следующего звания, {1} — сколько осталось («6 ч 40 мин»)
  'hrankTo': {'ru': 'До «{0}» {1}', 'en': '{1} to {0}', 'pt': '{1} até {0}', 'it': '{1} a {0}', 'es': '{1} para {0}', 'fr': '{1} avant {0}', 'de': '{1} bis {0}'},
  'hrankTop': {'ru': 'Это высшее звание', 'en': 'This is the highest rank', 'pt': 'Este é o título mais alto', 'it': 'È il titolo più alto', 'es': 'Es el título más alto', 'fr': "C'est le titre le plus haut", 'de': 'Das ist der höchste Rang'},
  'hrankFromStart': {'ru': 'С первого дня', 'en': 'From day one', 'pt': 'Desde o primeiro dia', 'it': 'Dal primo giorno', 'es': 'Desde el primer día', 'fr': 'Dès le premier jour', 'de': 'Vom ersten Tag an'},
  'hrankHow': {'ru': 'Часы идут, пока Togetherly открыт на экране', 'en': 'Hours count while Togetherly is open on screen', 'pt': 'As horas contam enquanto o Togetherly está aberto na tela', 'it': 'Le ore contano mentre Togetherly è aperto sullo schermo', 'es': 'Las horas cuentan mientras Togetherly está abierto en pantalla', 'fr': "Les heures comptent tant que Togetherly est ouvert à l'écran", 'de': 'Stunden zählen, solange Togetherly auf dem Bildschirm offen ist'},
  // {0} — число; короткие единицы рядом с числом
  'hrankH': {'ru': '{0} ч', 'en': '{0} h', 'pt': '{0} h', 'it': '{0} h', 'es': '{0} h', 'fr': '{0} h', 'de': '{0} Std.'},
  'hrankMin': {'ru': '{0} мин', 'en': '{0} min', 'pt': '{0} min', 'it': '{0} min', 'es': '{0} min', 'fr': '{0} min', 'de': '{0} Min.'},
  // Экран нового звания
  'hrankNewTitle': {'ru': 'Новое звание', 'en': 'New rank', 'pt': 'Novo título', 'it': 'Nuovo titolo', 'es': 'Nuevo título', 'fr': 'Nouveau titre', 'de': 'Neuer Rang'},
  // {0} — часы («15 ч»)
  'hrankNewHours': {'ru': '{0} в Togetherly', 'en': '{0} in Togetherly', 'pt': '{0} no Togetherly', 'it': '{0} su Togetherly', 'es': '{0} en Togetherly', 'fr': '{0} sur Togetherly', 'de': '{0} in Togetherly'},
  'hrankNewOk': {'ru': 'Ура!', 'en': 'Yay!', 'pt': 'Oba!', 'it': 'Evviva!', 'es': '¡Bien!', 'fr': 'Youpi !', 'de': 'Juhu!'},
  // Экран значка «Старожил» (наградной, всем до выхода званий)
  'oldTimerTitle': {'ru': 'Вы с нами с самого начала', 'en': "You've been with us from the start", 'pt': 'Você está com a gente desde o começo', 'it': "Sei con noi dall'inizio", 'es': 'Estás con nosotros desde el principio', 'fr': 'Vous êtes avec nous depuis le début', 'de': 'Du bist von Anfang an dabei'},
  'oldTimerText': {'ru': 'В Togetherly появились звания за часы в приложении. Часы считаются с сегодняшнего дня, а значок «Старожил» останется у вас навсегда. Его нельзя купить или заработать потом.', 'en': 'Togetherly now has ranks for time in the app. Hours count from today, and the Old-timer badge stays with you forever. Nobody can buy or earn it later.', 'pt': 'O Togetherly agora tem títulos pelo tempo no app. As horas contam a partir de hoje, e o selo Veterano fica com você para sempre. Ninguém pode comprá-lo nem ganhá-lo depois.', 'it': "Su Togetherly ora ci sono titoli per il tempo nell'app. Le ore contano da oggi, e il distintivo Veterano resta tuo per sempre: non si può comprare né ottenere dopo.", 'es': 'Togetherly ahora tiene títulos por el tiempo en la app. Las horas cuentan desde hoy, y la insignia Veterano se queda contigo para siempre: no se puede comprar ni ganar después.', 'fr': "Togetherly a maintenant des titres pour le temps passé dans l'appli. Les heures comptent à partir d'aujourd'hui, et le badge Ancien reste à vous pour toujours : impossible de l'acheter ou de l'obtenir plus tard.", 'de': 'In Togetherly gibt es jetzt Ränge für die Zeit in der App. Die Stunden zählen ab heute, und das Abzeichen Urgestein bleibt für immer bei dir. Später kann man es weder kaufen noch verdienen.'},
};
