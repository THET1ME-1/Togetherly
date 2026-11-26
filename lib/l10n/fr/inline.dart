// Французский для строк, которые живут прямо в экранах парой «русский /
// английский» (`ruEn` и `trEnglish` в `../../dict_strings.dart`, `_tr` и `_t`
// в нескольких экранах). Устроено как `../pt/inline.dart`: ключ — английская
// строка, где каждое число заменено на `{0}`, `{1}`… по порядку. Набор ключей
// совпадает с португальским, это стережёт `test/services/locale_eu_test.dart`.
// К человеку на «tu», к паре на «vous» — как в словаре `l10n/dict/`.
//
// До 23.11.2026 таблицы не было, и француз видел эти строки по-английски.

const Map<String, String> kFrByEnglish = {
  // Поиск фильмов: вид работы
  'Series': 'Série',
  'Cartoon': 'Dessin animé',
  'Animated series': 'Série animée',
  'Anime': 'Anime',
  'Movie': 'Film',

  // Работа в фоне (Android)
  'Instant notifications & widgets': 'Notifications et widgets instantanés',
  'To get messages, “miss you” and widget updates instantly — even when the app is closed — allow Togetherly to run in the background without battery limits.\n\nOtherwise Android suspends the connection and everything only arrives when you open the app.':
      'Pour recevoir messages, « tu me manques » et mises à jour des widgets tout de suite, même app fermée, autorise Togetherly à fonctionner en arrière-plan sans limite de batterie.\n\nSinon Android coupe la connexion et tout n’arrive qu’à l’ouverture de l’app.',
  'Allow': 'Autoriser',
  'Later': 'Plus tard',

  // Наборы настроений
  'This pack is not for sale yet': 'Ce pack n’est pas encore en vente',
  'This pack is not available yet': 'Ce pack n’est pas encore disponible',
  'Payment is processing — the pack will open by itself':
      'Paiement en cours – le pack se débloquera tout seul',
  'Purchase failed': 'L’achat a échoué',
  'You already own this pack': 'Tu as déjà ce pack',
  'Could not open checkout': 'Impossible d’ouvrir le paiement',
  'Not enough coins: {0} needed, you have {1}':
      'Pas assez de pièces : il en faut {0}, tu en as {1}',
  'Unlock for {0}': 'Débloquer pour {0}',
  'Yours forever, and your partner gets it too':
      'À toi pour toujours, et ton partenaire l’a aussi',

  // Очередь синхронизации
  'Offline': 'Hors ligne',
  'Compressing video…': 'Compression de la vidéo…',
  "Didn't sync — retry": 'Non synchronisé – réessayer',
  'Dismiss': 'Abandonner',
  "These changes won't be saved. Dismiss?":
      'Ces modifications ne seront pas enregistrées. Abandonner ?',
  'Keep': 'Garder',

  // Желания
  'Want with you': 'Envies à deux',
  'All →': 'Tout →',
  '{0} already came true — see them': '{0} déjà réalisés – les voir',
  'What to watch, where to go, where to eat — start a list for two.':
      'Quoi regarder, où aller, où manger – commencez une liste à deux.',
  "The shop didn't share a card — fill it in":
      'La boutique n’a pas fourni de fiche – remplis-la',
  "The photo didn't upload — try later":
      'La photo n’a pas été envoyée – réessaie plus tard',
  'From gallery': 'Depuis la galerie',
  'Take a photo': 'Prendre une photo',
  'Edit wish': 'Modifier l’envie',
  'New wish': 'Nouvelle envie',
  'Custom': 'Personnalisé',
  'What we want': 'Ce qu’on veut',
  '"Dune: Part Three"': '« Dune : Troisième partie »',
  'Note': 'Note',
  'optional': 'facultatif',
  'Save': 'Enregistrer',
  'Add': 'Ajouter',
  'together': 'ensemble',
  'Cancel': 'Annuler',
  'Own photo': 'Ma photo',
  'Replace photo': 'Remplacer la photo',
  'Product link': 'Lien du produit',
  'Price': 'Prix',
  'Open link': 'Ouvrir le lien',
  'Edit category': 'Modifier la catégorie',
  'Your own category': 'Ta catégorie',
  'Name': 'Nom',
  'Concerts': 'Concerts',
  'Pick from {0} icons': 'Choisis parmi {0} icônes',
  'Create': 'Créer',
  "You're gifting it — your partner won't know":
      'C’est toi qui l’offres – ton partenaire ne le saura pas',
  'Came true': 'Réalisé',
  'UNDO': 'ANNULER',
  'When it happened': 'Quand c’est arrivé',
  'How it went': 'Comment c’était',
  'A few words to remember': 'Quelques mots pour s’en souvenir',
  'Delete': 'Supprimer',
  'Dreaming': 'On en rêve',
  'Add your first wish: a film you are waiting for, a place you want to go, or anything of your own. Your partner will see it right away.':
      'Ajoute ta première envie : un film que tu attends, un endroit où tu veux aller ou ce que tu veux. Ton partenaire la verra tout de suite.',
  'Nothing has come true yet. Tick a wish off when it happens.':
      'Rien ne s’est encore réalisé. Coche une envie quand elle se réalise.',
  'Every wish came true. Time to think of a new one.':
      'Toutes les envies se sont réalisées. Place à une nouvelle.',
  "I'm gifting": 'Je l’offre',
  'Gift it': 'L’offrir',
  'Open': 'Ouvrir',
  'in Togetherly+': 'dans Togetherly+',
  'Delete "{0}"? It will disappear for both of you.':
      'Supprimer « {0} » ? Elle disparaîtra pour vous deux.',

  // Кольцо настроений
  'bright': 'lumineuses',
  'Collapse': 'Réduire',
  '{0} more': 'Encore {0}',

  // Типы воспоминаний
  'Photo': 'Photo',
  'Video': 'Vidéo',
  'Video link': 'Lien vidéo',
  'Text': 'Texte',
  'Music': 'Musique',
  'Book': 'Livre',
  'Place': 'Lieu',
  'Audio': 'Audio',
  'Untyped': 'Sans type',
  'Moment': 'Moment',
  'Location': 'Lieu',
  'Untitled': 'Sans titre',

  // Галерея маскотов
  'Pixel': 'Pixel',
  'Our drawings': 'Nos dessins',
  'Built-in': 'Intégrés',
  'Catalog': 'Catalogue',
  'Unlock this character forever for {0} coins?':
      'Débloquer ce personnage pour toujours contre {0} pièces ?',
  'Buy': 'Acheter',
  'Not for sale yet': 'Pas encore en vente',
  'Unlocks at level {0}': 'Se débloque au niveau {0}',
  'On screen now': 'À l’écran',
  'Waiting': 'En attente',
  'Nobody with that name. Try another word.':
      'Personne de ce nom. Essaie un autre mot.',
  'Mascots marked «От нас» drawn by Meller{0}':
      'Les mascottes marquées « De nous » sont dessinées par Meller{0}',
  'Find a mascot': 'Chercher une mascotte',
  'paid': 'payant',
  'Lv {0}': 'Niv. {0}',
  'Streak paused at {0}. Bring it back to keep going':
      'Série en pause à {0}. Récupère-la pour continuer',
  'Streak {0} paused': 'Série de {0} en pause',

  // Статистика пары
  'You': 'Toi',
  'Partner': 'Partenaire',
  'Couple stats': 'Statistiques du couple',
  'Refresh': 'Actualiser',
  'Nothing to show yet — stats appear once you start together.':
      'Rien à afficher pour l’instant – les statistiques apparaissent quand vous commencez ensemble.',
  'Tips for today': 'Conseils du jour',
  'Picked from your numbers': 'Choisis d’après vos chiffres',
  'Days together': 'Jours ensemble',
  'Day streak': 'Série de jours',
  'Couple XP': 'XP du couple',
  'To anniversary': 'Avant l’anniversaire',
  'Memories': 'Souvenirs',
  'Photos': 'Photos',
  'Videos': 'Vidéos',
  'Messages': 'Messages',
  'Mood marks': 'Humeurs notées',
  'Miss-yous': 'Tu me manques',
  'Brush strokes': 'Coups de pinceau',
  'Comments': 'Commentaires',
  'Gifts': 'Cadeaux',
  'Mascots': 'Mascottes',
  'Watch sessions': 'Séances à deux',
  'Canvases': 'Toiles',
  'The year together': 'L’année ensemble',
  'Share of each series best month': 'Part de chaque série au meilleur mois',
  'Moods': 'Humeurs',
  'Side by side': 'Côte à côte',
  'Each partner all-time': 'Chacun, depuis le début',
  'Weekly rhythm': 'Rythme de la semaine',
  'Which days you are busiest': 'Les jours où vous êtes le plus actifs',
  'Hours of the day': 'Heures de la journée',
  'Peak at {0}:{1} · {2}% between {3} and {4}':
      'Pic à {0}:{1} · {2} % entre {3} et {4}',
  'Mood': 'Humeur',
  'Mood not set': 'Humeur non définie',
  'My mood': 'Mon humeur',
  'Mood on the lock screen': 'Humeur sur l’écran verrouillé',
  'Mood over {0} days': 'Humeur sur {0} jours',
  'Daily average, {0} to {1}': 'Moyenne quotidienne, du {0} au {1}',
  'Favourite moods': 'Humeurs préférées',
  'What you mark most often': 'Ce que vous notez le plus souvent',
  'What memories are made of': 'De quoi sont faits vos souvenirs',
  'Under one': 'Moins d’un',
  'Memories per week now': 'Souvenirs par semaine en ce moment',
  'In {0} days': 'Dans {0} jours',
  'To {0} memories': 'Jusqu’à {0} souvenirs',
  'Projected for a year at this pace': 'Projection sur un an à ce rythme',
  'of {0}': 'sur {0}',
  'Active days last month': 'Jours actifs le mois dernier',
  'Mood versus last month': 'Humeur par rapport au mois dernier',
  'What is next': 'La suite',
  'Projection from the last thirty days': 'Projection sur les trente derniers jours',
  'Nothing yet': 'Rien pour l’instant',

  // Донат за монеты
  'Donation → coins': 'Don → pièces',
  'To get coins automatically, put your email in the donation message:':
      'Pour recevoir les pièces automatiquement, indique ton e-mail dans le message du don :',
  'Email copied': 'E-mail copié',
  'Copy the email above': 'Copie l’e-mail ci-dessus',
  'Paste it into the donation message': 'Colle-le dans le message du don',
  'From {0} ₽ — coins arrive on their own in a couple of minutes':
      'À partir de {0} ₽ – les pièces arrivent toutes seules en quelques minutes',
  'Open DonationAlerts': 'Ouvrir DonationAlerts',

  // Профиль
  'dark': 'sombre',
  'light': 'clair',
  'How you love': 'Comment tu aimes',
  'Twenty questions, one shape for two': 'Vingt questions, une forme pour deux',
  'Tests for two': 'Tests à deux',
  'Six tests, from love language to how you argue':
      'Six tests, du langage de l’amour à votre façon de vous disputer',

  // Настройка профиля
  'Prefer not to say': 'Je préfère ne pas le dire',
  'Custom gender': 'Autre genre',
  'Enter your gender': 'Indique ton genre',

  // Календарь настроений
  'Entries': 'Entrées',
  'Days tracked': 'Jours notés',
  'Most often': 'Le plus souvent',

  // Уровень и задания
  'Open the app every day': 'Ouvre l’app chaque jour',
  'Add memories': 'Ajoute des souvenirs',
  'Watch videos together': 'Regardez des vidéos ensemble',
  'Add the home screen widget': 'Ajoute le widget à l’écran d’accueil',
  'Track your mood': 'Note ton humeur',
  'one-time': 'une fois',
  '{0}/day': '{0}/jour',
  'Level & tasks': 'Niveau et missions',
  'Tasks — how to level up': 'Missions – comment monter de niveau',
  'Rewards — mascots': 'Récompenses – mascottes',
  'Level {0}': 'Niveau {0}',
  '{0} XP to level {1}': 'Encore {0} XP avant le niveau {1}',
  'Rewards are loading…': 'Chargement des récompenses…',

  // Живое фото в виджете
  'A live photo needs a video or a GIF': 'Une photo animée a besoin d’une vidéo ou d’un GIF',
  'Live photo is in the widget': 'La photo animée est dans le widget',
  'Live photo is in the widget. The home screen shows its first frame, it moves here': 'La photo animée est dans le widget. L’écran d’accueil montre la première image, elle bouge ici',
  'Failed — please try again': 'Échec – réessaie',
  'Live photo removed': 'Photo animée supprimée',
  'Live photo — a video or a GIF': 'Photo animée – une vidéo ou un GIF',
  'Remove the live photo': 'Supprimer la photo animée',
  'This video is too large — pick a shorter one':
      'Cette vidéo est trop lourde – choisis-en une plus courte',
  'This GIF is too large — pick a lighter one':
      'Ce GIF est trop lourd – choisis-en un plus léger',

  // Наборы и маскоты: имена
  'Classic': 'Classiques',
  'Pink': 'Roses',
  'Bunny': 'Lapinou',
  'Mochi': 'Mochi',
  'Puppy': 'Chiot',
  'Pud': 'Pouding',
  'Prick': 'Piquant',
  'Cristal': 'Cristal',
  'Wick': 'Mèche',
  'Brew': 'Tisane',
  'Bulb': 'Ampoule',
  'Cloud': 'Nuage',
  'Sprout': 'Pousse',
  'Scoop': 'Boule',
  'Pearl': 'Perle',
  'Volt': 'Volt',
  'Moony': 'Lunette',
  'Snaily': 'Escargot',
  'Balloon': 'Ballon',
  'Shroomy': 'Champi',
  'Donut': 'Donut',
  'Beep': 'Bip',
  'Boo': 'Bouh',
  'Tape': 'Cassette',
  'Compass': 'Boussole',
  'Ember': 'Braise',
  'Boxy': 'Boîtou',
  'Blink': 'Clin',
  'Bubbly': 'Bulle',
  'Cuckoo': 'Coucou',
  'Half': 'Moitié',
  'Seasons': 'Saisons',
  'Postie': 'Facteur',
  'Fae': 'Fée',
  'Lantern': 'Lanterne',
  'Jelly': 'Gelée',
  'Spiky': 'Spiky',
  'Lulu': 'Lulu',
  'Iskrik': 'Étincelle',
  'Zhuzha': 'Zouzou',

  // Раскраски: разделы
  'Food': 'Cuisine',
  'Trip': 'Voyage',
  'Other': 'Autres',
  'Cafe': 'Café',
  'Castle': 'Château',
  'Rain': 'Pluie',
  'Ferris wheel': 'Grande roue',
  'Snowman': 'Bonhomme de neige',
  'Metro': 'Métro',
  'Camping': 'Camping',
  'Festival': 'Festival',
  'Baking': 'Pâtisserie',
  'Beach': 'Plage',
  'Gaming': 'Jeux vidéo',

  // Подарки
  'date lost': 'date perdue',
  'from you': 'de ta part',
  'from your partner': 'de ton partenaire',
  'from the chest': 'du coffre',
  'This gift is not on the shelf yet.': 'Ce cadeau n’est pas encore en rayon.',
  'Your reply': 'Ta réponse',
  'Reply': 'Répondre',
  'No note': 'Sans mot',
  'Everyday': 'Au quotidien',
  'Occasions': 'Occasions',
  'Milestones': 'Grandes étapes',
  'from {0}': 'de {0}',
  'last on {0}': 'dernier le {0}',

  // Ту и его гардероб
  'Tu': 'Tu',
  'Whose Tu': 'Quel Tu',
  'Mine': 'Le mien',
  'Wardrobe': 'Garde-robe',
  'Clothes': 'Vêtements',
  'Glasses': 'Lunettes',
  'Face': 'Visage',
  'Scarves': 'Écharpes et plaids',
  'Head': 'Tête',
  'Above': 'Au-dessus',
  'Buddy': 'Petit compagnon',
  'Tu’s wardrobe': 'La garde-robe de Tu',
  'Tu’s items will appear here once the catalog loads.':
      'Les affaires de Tu apparaîtront ici dès que le catalogue sera chargé.',
  'Trying on: ': 'Essayage : ',
  'Stop trying on': 'Arrêter l’essayage',
  'All': 'Tout',
  'For coins': 'Contre des pièces',
  'For ads': 'Contre des pubs',
  'Nothing here yet': 'Rien ici pour l’instant',
  'Wearing': 'Porté',
  'Trying on': 'Essayage',
  'Wear': 'Porter',
  'Ads {0} of {1}': 'Pubs {0} sur {1}',
  '{0} coins': '{0} pièces',
  'Get': 'Obtenir',
  'Watch ad': 'Voir la pub',
  'From chest': 'Du coffre',
  'Buy · {0}': 'Acheter · {0}',
  'Next ad · {0} of {1}': 'Pub suivante · {0} sur {1}',
  'Drops from the “Cozy autumn” chest': 'Sort du coffre « Automne douillet »',
  'Drops from the chest': 'Sort du coffre',
  'Something went wrong, try again': 'Un problème est survenu, réessaie',
  'The ad is still loading, try again in a moment':
      'La pub se charge encore, réessaie dans un instant',
  'Ad counted: {0} of {1}': 'Pub comptée : {0} sur {1}',
  'Wait a few seconds before the next one': 'Attends quelques secondes avant la suivante',
  'For Tu only, wear it in the wardrobe': 'Réservé à Tu, à porter dans la garde-robe',
  'Tu is wearing it now': 'Tu le porte en ce moment',
  '“{0}” is yours and already on': '« {0} » est à toi et déjà porté',
  'Tu’s item “{0}”': 'Article de Tu « {0} »',

  // Вещи Ту: названия из каталога (`name_en` записей вида `wear`)
  'Acorn cap': 'Chapeau de gland',
  'Freckles': 'Taches de rousseur',
  'Maple leaf': 'Feuille d’érable',
  'Little rain cloud': 'Petit nuage de pluie',
  'Knitted snood': 'Snood tricoté',
  'Umbrella': 'Parapluie',
  'Round glasses': 'Lunettes rondes',
  'Blanket cocoon': 'Cocon de plaid',
  'Leaf fall': 'Pluie de feuilles',
  'Scarf': 'Écharpe',
  'Heart balloon': 'Ballon cœur',
  'Little bell': 'Clochette',
  'Bow': 'Nœud',
  'Bow tie': 'Nœud papillon',
  'Daisy': 'Pâquerette',
  'Glitter': 'Paillettes',
  'Heart blush': 'Joues en cœur',
  'Spring antennae': 'Antennes à ressort',
  'Little bee': 'Petite abeille',
  'Heart glasses': 'Lunettes cœur',
  'Firefly': 'Luciole',
  'Monocle': 'Monocle',
  'Halo': 'Auréole',
  'Mustache': 'Moustache',
  'Pearl necklace': 'Collier de perles',
  'Circling hearts': 'Cœurs qui tournent',
  'Heart plaster': 'Pansement cœur',
  'Rainbow': 'Arc-en-ciel',
  'Sunglasses': 'Lunettes de soleil',
  'Tiara': 'Diadème',
  'Star glasses': 'Lunettes étoiles',
  'Tie': 'Cravate',
  'Cat whiskers': 'Moustaches de chat',
  'Check blazer': 'Blazer à carreaux',
  'Linen blazer': 'Blazer en lin',
  'Mint blazer': 'Blazer menthe',
  'Navy blazer': 'Blazer bleu marine',
  'Pink suit': 'Costume rose',
  'Tuxedo': 'Smoking',
  'Velvet blazer': 'Blazer en velours',
  'White suit': 'Costume blanc',
  'Argyle vest': 'Pull sans manches à losanges',
  'Breton top': 'Marinière',
  'Cable-knit sweater': 'Pull torsadé',
  'Denim jacket': 'Veste en jean',
  'Hoodie': 'Sweat à capuche',
  'Biker jacket': 'Blouson de motard',
  'Overalls': 'Salopette',
  'Puffer jacket': 'Doudoune',
  'Raincoat': 'Imperméable',
  'Cardigan': 'Cardigan',
  'Corduroy jacket': 'Veste en velours côtelé',
  'Flannel shirt': 'Chemise en flanelle',
  'Quilted vest': 'Gilet matelassé',
  'Leaf sweater': 'Pull à feuilles',
  'Pumpkin sweatshirt': 'Sweat citrouille',
  'Trench coat': 'Trench',
  'Fish in a bubble': 'Poisson dans sa bulle',
  'Our story book': 'Le livre de notre histoire',
  'Pumpkin lantern': 'Lanterne citrouille',

  // Строки, которые до 23.11.2026 были только русскими
  // Каналы и тексты уведомлений
  'Mascot': 'Mascotte',
  "A reminder when you haven't opened the app for a while":
      'Un rappel quand tu n’as pas ouvert l’app depuis longtemps',
  'Your mascot misses you 🥺': 'Ta mascotte s’ennuie de toi 🥺',
  "It's been a while — come back and cheer up your mascot 🐾":
      'Ça fait longtemps – reviens faire plaisir à ta mascotte 🐾',
  'Invitation': 'Invitation',
  'A reminder to invite your partner while you have no pair':
      'Un rappel pour inviter ton partenaire tant que vous n’êtes pas reliés',
  'Celebrations': 'Fêtes',
  'Reminders about anniversaries and birthdays': 'Rappels d’anniversaires de couple et de naissance',
  'Time capsule': 'Capsule temporelle',
  'A reminder when a time capsule opens': 'Un rappel à l’ouverture d’une capsule temporelle',
  'A permanent counter of the days you have spent together':
      'Un compteur permanent des jours passés ensemble',
  'Server connection': 'Connexion au serveur',
  'Keeps the connection open to deliver messages, moods and “miss you” from your partner while the app is in the background.':
      'Garde la connexion ouverte pour recevoir les messages, humeurs et « tu me manques » de ton partenaire quand l’app est en arrière-plan.',
  'Togetherly is connected': 'Togetherly est connecté',
  'Receiving notifications from your partner': 'Réception des notifications de ton partenaire',

  // Запасные подписи виджетов
  'No data yet': 'Pas encore de données',
  'Rating': 'Note',
  'Photo of the day': 'Photo du jour',
  'My photo': 'Ma photo',
  "Partner's photo": 'Photo du partenaire',
  'Me': 'Moi',
  'Member': 'Membre',

  // Советы паре
  'Your partner is having a rough day': 'Ton partenaire passe une mauvaise journée',
  'Ask how they are and just listen. No advice needed — sometimes it is enough to have someone close.':
      'Demande comment ça va et écoute, simplement. Pas besoin de conseil – parfois, il suffit d’être là.',
  'You don’t know how your partner is today': 'Tu ne sais pas comment va ton partenaire aujourd’hui',
  'Ask them yourself: a real question beats a mark in the calendar.':
      'Demande-lui toi-même : une vraie question vaut mieux qu’une case dans le calendrier.',
  'These days can be hard': 'Ces jours-là peuvent être difficiles',
  'Take on a chore, bring her some tea, suggest an evening with no plans. Ask what she would like.':
      'Prends une tâche en charge, apporte-lui un thé, propose une soirée sans programme. Demande-lui ce qui lui ferait plaisir.',
  'Her period is coming soon': 'Ses règles arrivent bientôt',
  'A good moment to do something in advance: order her favourite treat or keep the evening free.':
      'Le bon moment pour anticiper : commande sa gourmandise préférée ou libère la soirée.',
  'The silence has gone on too long': 'Le silence dure trop',
  'You haven’t texted in a while': 'Vous ne vous êtes pas écrit depuis longtemps',
  'Write first — it doesn’t have to be about anything. “Thinking of you” is enough.':
      'Écris en premier – pas besoin d’un sujet. « Je pense à toi » suffit.',
  'You haven’t sent “miss you” in a while': 'Tu n’as pas envoyé de « tu me manques » depuis longtemps',
  'One tap and they will know. A small thing that works.':
      'Un geste, et ton partenaire le saura. Une petite chose qui marche.',
  'No new memories for a while': 'Pas de nouveaux souvenirs depuis un moment',
  'Add a photo or a few lines about your week. A year from now it will mean more than it seems today.':
      'Ajoute une photo ou quelques lignes sur votre semaine. Dans un an, cela comptera plus qu’il n’y paraît.',
  'Your anniversary is today': 'C’est votre anniversaire aujourd’hui',
  'Your anniversary is tomorrow': 'C’est votre anniversaire demain',
  '{0} days until your anniversary': 'Encore {0} jours avant votre anniversaire',
  'Be the first to say it.': 'Dis-le en premier.',
  'There is time to plan something better than last-minute flowers.':
      'Tu as le temps de prévoir mieux que des fleurs de dernière minute.',
  '{0} days together today': '{0} jours ensemble aujourd’hui',
  'A round date is a good reason to say it out loud.':
      'Une date ronde, c’est une belle raison de le dire à voix haute.',
  'Write': 'Écrire',
  'Send': 'Envoyer',

  // Ограничение комментариев
  'No more than {0} comments an hour — try again in {1} min. 🌸':
      'Pas plus de {0} commentaires par heure – réessaie dans {1} min. 🌸',

  // Отказы сервера при подключении пары (`lib/utils/server_message.dart`)
  'No code entered': 'Aucun code saisi',
  'This code is damaged': 'Ce code est endommagé',
  'This is your own code!': 'C’est ton propre code !',
  'This is your own code': 'C’est ton propre code',
  'Couldn’t accept the code': 'Impossible d’accepter le code',
  'Code not found. Ask your partner to tap “New code” and read it out again':
      'Code introuvable. Demande à ton partenaire d’appuyer sur « Nouveau code » et de te le redonner',
  'Code not found': 'Code introuvable',
  'This pair is already full': 'Ce couple est déjà complet',
  'Enter a name': 'Saisis un nom',
  'There is no request': 'Aucune demande',
  'This place is already taken': 'Cette place est déjà prise',
  'Couldn’t save': 'Non enregistré',
  'Couldn’t create the pair': 'Impossible de créer le couple',
  'Couldn’t issue a code': 'Impossible de générer un code',
  'No pair specified': 'Aucun couple indiqué',
  'Pair not found': 'Couple introuvable',
  'This is not your pair': 'Ce n’est pas ton couple',
  'Couldn’t send the request': 'Impossible d’envoyer la demande',
  'You already have a pair': 'Tu as déjà un couple',
  'You already have a pair — leave it first': 'Tu as déjà un couple – quitte-le d’abord',
  'Enter the code': 'Saisis le code',
  'Your session has expired — please sign in again': 'Ta session a expiré – reconnecte-toi',
  'The server didn’t return the pair': 'Le serveur n’a pas renvoyé le couple',
  'The server didn’t return the pair — please try again':
      'Le serveur n’a pas renvoyé le couple – réessaie',

  // Свои раскраски
  'My colouring page': 'Mon coloriage',
  'The file is lost': 'Le fichier est perdu',
  'This is not a picture, or it couldn’t be read': 'Ce n’est pas une image, ou elle n’a pas pu être lue',
  'The lines aren’t closed: the fill would spread over the whole page':
      'Les traits ne sont pas fermés : la couleur déborderait sur toute la page',
  'Something went wrong': 'Un problème est survenu',

  // Архив воспоминаний
  'Title': 'Titre',
  'File': 'Fichier',
  'MEMORIES': 'SOUVENIRS',
  'TIMERS': 'MINUTEURS',
  'Start': 'Début',
  'Days passed': 'Jours écoulés',
  'Memories archive': 'Archive des souvenirs',

  // Мелочи
  ' & ': ' et ',
  'cell': 'case',
  'm': 'm',
  'km': 'km',
};
