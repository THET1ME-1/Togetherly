// Испанский для строк, которые живут прямо в экранах парой «русский /
// английский» (`ruEn` и `trEnglish` в `../../dict_strings.dart`, `_tr` и `_t`
// в нескольких экранах). Устроено как `../pt/inline.dart`: ключ — английская
// строка, где каждое число заменено на `{0}`, `{1}`… по порядку. Набор ключей
// совпадает с португальским, это стережёт `test/services/locale_eu_test.dart`.
// Обращение на «tú», как в словаре `l10n/dict/`.
//
// До 23.11.2026 таблицы не было, и испанец видел эти строки по-английски.

const Map<String, String> kEsByEnglish = {
  // Поиск фильмов: вид работы
  'Series': 'Serie',
  'Cartoon': 'Dibujos animados',
  'Animated series': 'Serie animada',
  'Anime': 'Anime',
  'Movie': 'Película',

  // Работа в фоне (Android)
  'Instant notifications & widgets': 'Notificaciones y widgets al instante',
  'To get messages, “miss you” and widget updates instantly — even when the app is closed — allow Togetherly to run in the background without battery limits.\n\nOtherwise Android suspends the connection and everything only arrives when you open the app.':
      'Para recibir mensajes, «te echo de menos» y actualizaciones de los widgets al instante, incluso con la app cerrada, permite que Togetherly funcione en segundo plano sin límite de batería.\n\nSi no, Android corta la conexión y todo llega solo al abrir la app.',
  'Allow': 'Permitir',
  'Later': 'Más tarde',

  // Наборы настроений
  'This pack is not for sale yet': 'Este pack aún no está a la venta',
  'This pack is not available yet': 'Este pack aún no está disponible',
  'Payment is processing — the pack will open by itself':
      'El pago se está procesando: el pack se desbloqueará solo',
  'Purchase failed': 'La compra no se completó',
  'You already own this pack': 'Ya tienes este pack',
  'Could not open checkout': 'No se pudo abrir el pago',
  'Not enough coins: {0} needed, you have {1}':
      'No tienes suficientes monedas: necesitas {0}, tienes {1}',
  'Unlock for {0}': 'Desbloquear por {0}',
  'Yours forever, and your partner gets it too':
      'Tuyo para siempre, y tu pareja también lo recibe',

  // Очередь синхронизации
  'Offline': 'Sin conexión',
  'Compressing video…': 'Comprimiendo el vídeo…',
  "Didn't sync — retry": 'No se sincronizó: reintentar',
  'Dismiss': 'Descartar',
  "These changes won't be saved. Dismiss?":
      'Estos cambios no se guardarán. ¿Descartar?',
  'Keep': 'Conservar',

  // Желания
  'Want with you': 'Quiero contigo',
  'All →': 'Todos →',
  '{0} already came true — see them': '{0} ya se cumplieron: verlos',
  'What to watch, where to go, where to eat — start a list for two.':
      'Qué ver, adónde ir, dónde comer: empezad una lista para dos.',
  "The shop didn't share a card — fill it in":
      'La tienda no compartió la ficha: rellénala tú',
  "The photo didn't upload — try later":
      'La foto no se subió: inténtalo más tarde',
  'From gallery': 'De la galería',
  'Take a photo': 'Hacer una foto',
  'Edit wish': 'Editar deseo',
  'New wish': 'Nuevo deseo',
  'Custom': 'Personalizado',
  'What we want': 'Lo que queremos',
  '"Dune: Part Three"': '«Dune: Parte tres»',
  'Note': 'Nota',
  'optional': 'opcional',
  'Save': 'Guardar',
  'Add': 'Añadir',
  'together': 'juntos',
  'Cancel': 'Cancelar',
  'Own photo': 'Foto propia',
  'Replace photo': 'Cambiar foto',
  'Product link': 'Enlace del producto',
  'Price': 'Precio',
  'Open link': 'Abrir enlace',
  'Edit category': 'Editar categoría',
  'Your own category': 'Tu propia categoría',
  'Name': 'Nombre',
  'Concerts': 'Conciertos',
  'Pick from {0} icons': 'Elige entre {0} iconos',
  'Create': 'Crear',
  "You're gifting it — your partner won't know":
      'Lo regalas tú: tu pareja no lo sabrá',
  'Came true': 'Cumplido',
  'UNDO': 'DESHACER',
  'When it happened': 'Cuándo pasó',
  'How it went': 'Cómo fue',
  'A few words to remember': 'Unas palabras para recordarlo',
  'Delete': 'Eliminar',
  'Dreaming': 'Soñamos',
  'Add your first wish: a film you are waiting for, a place you want to go, or anything of your own. Your partner will see it right away.':
      'Añade tu primer deseo: una película que esperas, un lugar al que quieres ir o lo que se te ocurra. Tu pareja lo verá al momento.',
  'Nothing has come true yet. Tick a wish off when it happens.':
      'Todavía no se ha cumplido nada. Marca un deseo cuando se cumpla.',
  'Every wish came true. Time to think of a new one.':
      'Se cumplieron todos los deseos. Hora de pensar uno nuevo.',
  "I'm gifting": 'Lo regalo yo',
  'Gift it': 'Regalarlo',
  'Open': 'Abrir',
  'in Togetherly+': 'en Togetherly+',
  'Delete "{0}"? It will disappear for both of you.':
      '¿Eliminar «{0}»? Desaparecerá para los dos.',

  // Кольцо настроений
  'bright': 'alegres',
  'Collapse': 'Contraer',
  '{0} more': '{0} más',

  // Типы воспоминаний
  'Photo': 'Foto',
  'Video': 'Vídeo',
  'Video link': 'Enlace de vídeo',
  'Text': 'Texto',
  'Music': 'Música',
  'Book': 'Libro',
  'Place': 'Lugar',
  'Audio': 'Audio',
  'Untyped': 'Sin tipo',
  'Moment': 'Momento',
  'Location': 'Ubicación',
  'Untitled': 'Sin título',

  // Галерея маскотов
  'Pixel': 'Píxel',
  'Our drawings': 'Nuestros dibujos',
  'Built-in': 'Incluidos',
  'Catalog': 'Catálogo',
  'Unlock this character forever for {0} coins?':
      '¿Desbloquear este personaje para siempre por {0} monedas?',
  'Buy': 'Comprar',
  'Not for sale yet': 'Aún no está a la venta',
  'Unlocks at level {0}': 'Se desbloquea en el nivel {0}',
  'On screen now': 'En pantalla ahora',
  'Waiting': 'En espera',
  'Nobody with that name. Try another word.':
      'No hay nadie con ese nombre. Prueba otra palabra.',
  'Mascots marked «От нас» drawn by Meller{0}':
      'Las mascotas marcadas con «De nuestra parte» las dibujó Meller{0}',
  'Find a mascot': 'Buscar mascota',
  'paid': 'de pago',
  'Lv {0}': 'Nv. {0}',
  'Streak paused at {0}. Bring it back to keep going':
      'Racha en pausa en {0}. Recupérala para seguir',
  'Streak {0} paused': 'Racha de {0} en pausa',

  // Статистика пары
  'You': 'Tú',
  'Partner': 'Tu pareja',
  'Couple stats': 'Estadísticas de la pareja',
  'Refresh': 'Actualizar',
  'Nothing to show yet — stats appear once you start together.':
      'Aún no hay nada: las estadísticas aparecen cuando empecéis juntos.',
  'Tips for today': 'Consejos para hoy',
  'Picked from your numbers': 'Elegidos según vuestros datos',
  'Days together': 'Días juntos',
  'Day streak': 'Racha de días',
  'Couple XP': 'XP de la pareja',
  'To anniversary': 'Hasta el aniversario',
  'Memories': 'Recuerdos',
  'Photos': 'Fotos',
  'Videos': 'Vídeos',
  'Messages': 'Mensajes',
  'Mood marks': 'Estados de ánimo',
  'Miss-yous': 'Te echo de menos',
  'Brush strokes': 'Pinceladas',
  'Comments': 'Comentarios',
  'Gifts': 'Regalos',
  'Mascots': 'Mascotas',
  'Watch sessions': 'Sesiones viendo juntos',
  'Canvases': 'Lienzos',
  'The year together': 'El año juntos',
  'Share of each series best month': 'Parte de cada serie en el mejor mes',
  'Moods': 'Ánimos',
  'Side by side': 'Lado a lado',
  'Each partner all-time': 'Cada uno, desde el principio',
  'Weekly rhythm': 'Ritmo semanal',
  'Which days you are busiest': 'Qué días estáis más activos',
  'Hours of the day': 'Horas del día',
  'Peak at {0}:{1} · {2}% between {3} and {4}':
      'Pico a las {0}:{1} · {2} % entre {3} y {4}',
  'Mood': 'Ánimo',
  'Mood not set': 'Ánimo sin marcar',
  'My mood': 'Mi ánimo',
  'Mood on the lock screen': 'Ánimo en la pantalla bloqueada',
  'Mood over {0} days': 'Ánimo en {0} días',
  'Daily average, {0} to {1}': 'Media diaria, del {0} al {1}',
  'Favourite moods': 'Ánimos favoritos',
  'What you mark most often': 'Lo que más marcáis',
  'What memories are made of': 'De qué están hechos los recuerdos',
  'Under one': 'Menos de uno',
  'Memories per week now': 'Recuerdos por semana ahora',
  'In {0} days': 'En {0} días',
  'To {0} memories': 'Hasta {0} recuerdos',
  'Projected for a year at this pace': 'Previsión para un año a este ritmo',
  'of {0}': 'de {0}',
  'Active days last month': 'Días activos el mes pasado',
  'Mood versus last month': 'Ánimo frente al mes pasado',
  'What is next': 'Lo que viene',
  'Projection from the last thirty days': 'Previsión según los últimos treinta días',
  'Nothing yet': 'Nada todavía',

  // Донат за монеты
  'Donation → coins': 'Donación → monedas',
  'To get coins automatically, put your email in the donation message:':
      'Para recibir las monedas automáticamente, escribe tu correo en el mensaje de la donación:',
  'Email copied': 'Correo copiado',
  'Copy the email above': 'Copia el correo de arriba',
  'Paste it into the donation message': 'Pégalo en el mensaje de la donación',
  'From {0} ₽ — coins arrive on their own in a couple of minutes':
      'Desde {0} ₽: las monedas llegan solas en un par de minutos',
  'Open DonationAlerts': 'Abrir DonationAlerts',

  // Профиль
  'dark': 'oscuro',
  'light': 'claro',
  'How you love': 'Cómo amas',
  'Twenty questions, one shape for two': 'Veinte preguntas, una forma para dos',
  'Tests for two': 'Tests para dos',
  'Six tests, from love language to how you argue':
      'Seis tests, del lenguaje del amor a cómo discutís',

  // Настройка профиля
  'Prefer not to say': 'Prefiero no decirlo',
  'Custom gender': 'Otro género',
  'Enter your gender': 'Escribe tu género',

  // Календарь настроений
  'Entries': 'Registros',
  'Days tracked': 'Días registrados',
  'Most often': 'Lo más frecuente',

  // Уровень и задания
  'Open the app every day': 'Abre la app cada día',
  'Add memories': 'Añade recuerdos',
  'Watch videos together': 'Ved vídeos juntos',
  'Add the home screen widget': 'Añade el widget a la pantalla de inicio',
  'Track your mood': 'Marca tu ánimo',
  'one-time': 'una vez',
  '{0}/day': '{0}/día',
  'Level & tasks': 'Nivel y tareas',
  'Tasks — how to level up': 'Tareas: cómo subir de nivel',
  'Rewards — mascots': 'Recompensas: mascotas',
  'Level {0}': 'Nivel {0}',
  '{0} XP to level {1}': '{0} XP para el nivel {1}',
  'Rewards are loading…': 'Cargando recompensas…',

  // Живое фото в виджете
  'A live photo needs a video or a GIF': 'Una foto animada necesita un vídeo o un GIF',
  'Live photo is in the widget': 'La foto animada está en el widget',
  'Live photo is in the widget. The home screen shows its first frame, it moves here': 'La foto animada está en el widget. En la pantalla de inicio se ve el primer fotograma, aquí se mueve',
  'Failed — please try again': 'No salió: inténtalo de nuevo',
  'Live photo removed': 'Foto animada eliminada',
  'Live photo — a video or a GIF': 'Foto animada: un vídeo o un GIF',
  'Remove the live photo': 'Quitar la foto animada',
  'This video is too large — pick a shorter one':
      'Este vídeo es demasiado grande: elige uno más corto',
  'This GIF is too large — pick a lighter one':
      'Este GIF es demasiado grande: elige uno más ligero',

  // Наборы и маскоты: имена
  'Classic': 'Clásicos',
  'Pink': 'Rosas',
  'Bunny': 'Conejito',
  'Mochi': 'Mochi',
  'Puppy': 'Cachorro',
  'Pud': 'Flan',
  'Prick': 'Pincho',
  'Cristal': 'Cristal',
  'Wick': 'Mecha',
  'Brew': 'Tecito',
  'Bulb': 'Bombilla',
  'Cloud': 'Nube',
  'Sprout': 'Brote',
  'Scoop': 'Bolita',
  'Pearl': 'Perla',
  'Volt': 'Volt',
  'Moony': 'Lunita',
  'Snaily': 'Caracolito',
  'Balloon': 'Globo',
  'Shroomy': 'Setita',
  'Donut': 'Dónut',
  'Beep': 'Bip',
  'Boo': 'Bu',
  'Tape': 'Casete',
  'Compass': 'Brújula',
  'Ember': 'Brasa',
  'Boxy': 'Cajita',
  'Blink': 'Guiño',
  'Bubbly': 'Burbuja',
  'Cuckoo': 'Cucú',
  'Half': 'Mitad',
  'Seasons': 'Estaciones',
  'Postie': 'Cartero',
  'Fae': 'Hada',
  'Lantern': 'Farolillo',
  'Jelly': 'Gelatina',
  'Spiky': 'Spiky',
  'Lulu': 'Lulu',
  'Iskrik': 'Chispita',
  'Zhuzha': 'Zuzú',

  // Раскраски: разделы
  'Food': 'Comida',
  'Trip': 'Viaje',
  'Other': 'Otros',
  'Cafe': 'Cafetería',
  'Castle': 'Castillo',
  'Rain': 'Lluvia',
  'Ferris wheel': 'Noria',
  'Metro': 'Metro',
  'Camping': 'Acampada',
  'Festival': 'Festival',
  'Baking': 'Repostería',
  'Beach': 'Playa',
  'Gaming': 'Videojuegos',

  // Подарки
  'date lost': 'fecha perdida',
  'from you': 'de tu parte',
  'from your partner': 'de tu pareja',
  'from the chest': 'del cofre',
  'This gift is not on the shelf yet.': 'Este regalo aún no está en la estantería.',
  'Your reply': 'Tu respuesta',
  'Reply': 'Responder',
  'No note': 'Sin nota',
  'Everyday': 'Del día a día',
  'Occasions': 'Ocasiones',
  'Milestones': 'Hitos',
  'from {0}': 'de {0}',
  'last on {0}': 'el último, el {0}',

  // Ту и его гардероб
  'Tu': 'Tu',
  'Whose Tu': 'De quién es Tu',
  'Mine': 'El mío',
  'Wardrobe': 'Armario',
  'Clothes': 'Ropa',
  'Glasses': 'Gafas',
  'Face': 'Cara',
  'Scarves': 'Bufandas y mantas',
  'Head': 'Cabeza',
  'Above': 'Sobre la cabeza',
  'Buddy': 'Amiguito al lado',
  'Tu’s wardrobe': 'Armario de Tu',
  'Tu’s items will appear here once the catalog loads.':
      'Las cosas de Tu aparecerán aquí cuando cargue el catálogo.',
  'Trying on: ': 'Probándose: ',
  'Stop trying on': 'Dejar de probar',
  'All': 'Todo',
  'For coins': 'Por monedas',
  'For ads': 'Por anuncios',
  'Nothing here yet': 'Aquí aún no hay nada',
  'Wearing': 'Lo lleva',
  'Trying on': 'Probándose',
  'Wear': 'Ponerse',
  'Ads {0} of {1}': 'Anuncios {0} de {1}',
  '{0} coins': '{0} monedas',
  'Get': 'Conseguir',
  'Watch ad': 'Ver anuncio',
  'From chest': 'Del cofre',
  'Buy · {0}': 'Comprar · {0}',
  'Next ad · {0} of {1}': 'Siguiente anuncio · {0} de {1}',
  'Drops from the “Cozy autumn” chest': 'Sale del cofre «Otoño acogedor»',
  'Drops from the chest': 'Sale del cofre',
  'Something went wrong, try again': 'Algo salió mal, inténtalo de nuevo',
  'The ad is still loading, try again in a moment':
      'El anuncio aún se está cargando, inténtalo en un momento',
  'Ad counted: {0} of {1}': 'Anuncio contado: {0} de {1}',
  'Wait a few seconds before the next one': 'Espera unos segundos antes del siguiente',
  'For Tu only, wear it in the wardrobe': 'Solo para Tu: póntelo en el armario',
  'Tu is wearing it now': 'Tu lo lleva puesto ahora',
  '“{0}” is yours and already on': '«{0}» es tuyo y ya lo lleva puesto',
  'Tu’s item “{0}”': 'Prenda de Tu «{0}»',

  // Вещи Ту: названия из каталога (`name_en` записей вида `wear`)
  'Acorn cap': 'Gorro de bellota',
  'Freckles': 'Pecas',
  'Maple leaf': 'Hoja de arce',
  'Little rain cloud': 'Nubecita de lluvia',
  'Knitted snood': 'Braga de punto',
  'Umbrella': 'Paraguas',
  'Round glasses': 'Gafas redondas',
  'Blanket cocoon': 'Capullo de manta',
  'Leaf fall': 'Lluvia de hojas',
  'Scarf': 'Bufanda',
  'Heart balloon': 'Globo de corazón',
  'Little bell': 'Campanita',
  'Bow': 'Lazo',
  'Bow tie': 'Pajarita',
  'Daisy': 'Margarita',
  'Glitter': 'Purpurina',
  'Heart blush': 'Mejillas de corazón',
  'Spring antennae': 'Antenas de muelle',
  'Little bee': 'Abejita',
  'Heart glasses': 'Gafas de corazón',
  'Firefly': 'Luciérnaga',
  'Monocle': 'Monóculo',
  'Halo': 'Aureola',
  'Mustache': 'Bigote',
  'Pearl necklace': 'Collar de perlas',
  'Circling hearts': 'Corazones girando',
  'Heart plaster': 'Tirita de corazón',
  'Rainbow': 'Arcoíris',
  'Sunglasses': 'Gafas de sol',
  'Tiara': 'Tiara',
  'Star glasses': 'Gafas de estrella',
  'Tie': 'Corbata',
  'Cat whiskers': 'Bigotes de gato',
  'Check blazer': 'Blazer de cuadros',
  'Linen blazer': 'Blazer de lino',
  'Mint blazer': 'Blazer menta',
  'Navy blazer': 'Blazer azul marino',
  'Pink suit': 'Traje rosa',
  'Tuxedo': 'Esmoquin',
  'Velvet blazer': 'Blazer de terciopelo',
  'White suit': 'Traje blanco',
  'Argyle vest': 'Chaleco de rombos',
  'Breton top': 'Camiseta marinera',
  'Cable-knit sweater': 'Jersey de ochos',
  'Denim jacket': 'Cazadora vaquera',
  'Hoodie': 'Sudadera con capucha',
  'Biker jacket': 'Chaqueta motera',
  'Overalls': 'Peto',
  'Puffer jacket': 'Plumífero',
  'Raincoat': 'Chubasquero',
  'Cardigan': 'Cárdigan',
  'Corduroy jacket': 'Chaqueta de pana',
  'Flannel shirt': 'Camisa de franela',
  'Quilted vest': 'Chaleco acolchado',
  'Leaf sweater': 'Jersey de hojas',
  'Pumpkin sweatshirt': 'Sudadera de calabaza',
  'Trench coat': 'Gabardina',
  'Fish in a bubble': 'Pez en su burbuja',
  'Our story book': 'El libro de nuestra historia',
  'Pumpkin lantern': 'Farol de calabaza',

  // Строки, которые до 23.11.2026 были только русскими
  // Каналы и тексты уведомлений
  'Mascot': 'Mascota',
  "A reminder when you haven't opened the app for a while":
      'Un aviso cuando llevas tiempo sin abrir la app',
  'Your mascot misses you 🥺': 'Tu mascota te echa de menos 🥺',
  "It's been a while — come back and cheer up your mascot 🐾":
      'Hace tiempo que no vienes: vuelve y alegra a tu mascota 🐾',
  'Invitation': 'Invitación',
  'A reminder to invite your partner while you have no pair':
      'Un aviso para invitar a tu pareja mientras no estéis conectados',
  'Celebrations': 'Celebraciones',
  'Reminders about anniversaries and birthdays': 'Avisos de aniversarios y cumpleaños',
  'Time capsule': 'Cápsula del tiempo',
  'A reminder when a time capsule opens': 'Un aviso cuando se abre una cápsula del tiempo',
  'A permanent counter of the days you have spent together':
      'Un contador fijo de los días que lleváis juntos',
  'Server connection': 'Conexión con el servidor',
  'Keeps the connection open to deliver messages, moods and “miss you” from your partner while the app is in the background.':
      'Mantiene la conexión abierta para recibir los mensajes, el ánimo y los «te echo de menos» de tu pareja con la app en segundo plano.',
  'Togetherly is connected': 'Togetherly está conectado',
  'Receiving notifications from your partner': 'Recibiendo notificaciones de tu pareja',

  // Запасные подписи виджетов
  'No data yet': 'Aún no hay datos',
  'Rating': 'Nota',
  'Photo of the day': 'Foto del día',
  'My photo': 'Mi foto',
  "Partner's photo": 'Foto de tu pareja',
  'Me': 'Yo',
  'Member': 'Miembro',

  // Советы паре
  'Your partner is having a rough day': 'Tu pareja está teniendo un mal día',
  'Ask how they are and just listen. No advice needed — sometimes it is enough to have someone close.':
      'Pregúntale cómo está y simplemente escucha. No hace falta dar consejos: a veces basta con tener a alguien cerca.',
  'You don’t know how your partner is today': 'No sabes cómo está tu pareja hoy',
  'Ask them yourself: a real question beats a mark in the calendar.':
      'Pregúntale tú: una pregunta de verdad vale más que una marca en el calendario.',
  'These days can be hard': 'Estos días pueden ser duros',
  'Take on a chore, bring her some tea, suggest an evening with no plans. Ask what she would like.':
      'Encárgate de alguna tarea de casa, llévale un té, propón una tarde sin planes. Pregúntale qué le apetece.',
  'Her period is coming soon': 'Pronto le viene la regla',
  'A good moment to do something in advance: order her favourite treat or keep the evening free.':
      'Buen momento para adelantarte: pide su capricho favorito o deja la tarde libre.',
  'The silence has gone on too long': 'El silencio ya dura demasiado',
  'You haven’t texted in a while': 'Hace tiempo que no os escribís',
  'Write first — it doesn’t have to be about anything. “Thinking of you” is enough.':
      'Escribe tú primero, no hace falta que sea por algo. Con «pienso en ti» basta.',
  'You haven’t sent “miss you” in a while': 'Hace tiempo que no mandas un «te echo de menos»',
  'One tap and they will know. A small thing that works.':
      'Un toque y tu pareja lo sabrá. Un detalle pequeño que funciona.',
  'No new memories for a while': 'Hace tiempo que no hay recuerdos nuevos',
  'Add a photo or a few lines about your week. A year from now it will mean more than it seems today.':
      'Añade una foto o unas líneas sobre la semana. Dentro de un año valdrá más de lo que parece hoy.',
  'Your anniversary is today': 'Hoy es vuestro aniversario',
  'Your anniversary is tomorrow': 'Mañana es vuestro aniversario',
  '{0} days until your anniversary': 'Faltan {0} días para vuestro aniversario',
  'Be the first to say it.': 'Dilo tú primero.',
  'There is time to plan something better than last-minute flowers.':
      'Hay tiempo para preparar algo mejor que flores de última hora.',
  '{0} days together today': 'Hoy hacéis {0} días juntos',
  'A round date is a good reason to say it out loud.':
      'Una fecha redonda es un buen motivo para decirlo en voz alta.',
  'Write': 'Escribir',
  'Send': 'Enviar',

  // Ограничение комментариев
  'No more than {0} comments an hour — try again in {1} min. 🌸':
      'No más de {0} comentarios por hora: vuelve a intentarlo en {1} min. 🌸',

  // Отказы сервера при подключении пары (`lib/utils/server_message.dart`)
  'No code entered': 'No has escrito ningún código',
  'This code is damaged': 'Este código está dañado',
  'This is your own code!': '¡Es tu propio código!',
  'This is your own code': 'Es tu propio código',
  'Couldn’t accept the code': 'No se pudo aceptar el código',
  'Code not found. Ask your partner to tap “New code” and read it out again':
      'Código no encontrado. Pide a tu pareja que pulse «Nuevo código» y te lo diga otra vez',
  'Code not found': 'Código no encontrado',
  'This pair is already full': 'Esta pareja ya está completa',
  'Enter a name': 'Escribe un nombre',
  'There is no request': 'No hay ninguna solicitud',
  'This place is already taken': 'Este sitio ya está ocupado',
  'Couldn’t save': 'No se guardó',
  'Couldn’t create the pair': 'No se pudo crear la pareja',
  'Couldn’t issue a code': 'No se pudo generar un código',
  'No pair specified': 'No se indicó la pareja',
  'Pair not found': 'Pareja no encontrada',
  'This is not your pair': 'Esta no es tu pareja',
  'Couldn’t send the request': 'No se pudo enviar la solicitud',
  'You already have a pair': 'Ya tienes pareja',
  'You already have a pair — leave it first': 'Ya tienes pareja: sal de ella primero',
  'Enter the code': 'Escribe el código',
  'Your session has expired — please sign in again': 'Tu sesión ha caducado: vuelve a iniciar sesión',
  'The server didn’t return the pair': 'El servidor no devolvió la pareja',
  'The server didn’t return the pair — please try again':
      'El servidor no devolvió la pareja: inténtalo de nuevo',

  // Свои раскраски
  'My colouring page': 'Mi dibujo para colorear',
  'The file is lost': 'El archivo se ha perdido',
  'This is not a picture, or it couldn’t be read': 'No es una imagen o no se pudo leer',
  'The lines aren’t closed: the fill would spread over the whole page':
      'Las líneas no están cerradas: el color se saldría por toda la hoja',
  'Something went wrong': 'Algo salió mal',

  // Архив воспоминаний
  'Title': 'Título',
  'File': 'Archivo',
  'MEMORIES': 'RECUERDOS',
  'TIMERS': 'TEMPORIZADORES',
  'Start': 'Inicio',
  'Days passed': 'Días transcurridos',
  'Memories archive': 'Archivo de recuerdos',

  // Мелочи
  ' & ': ' y ',
  'cell': 'celda',
  'm': 'm',
  'km': 'km',
};
