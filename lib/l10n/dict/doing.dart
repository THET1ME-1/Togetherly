// Виджет «Чем заняты» (11.11.2026): карточка в галерее виджетов, лист выбора
// занятия и названия самих занятий. Украинский и китайский — в
// `../uk/doing.dart` и `../zh/doing.dart`. Каждый ключ — одной строкой: так
// полноту переводов сверяет test/widgets/doing_strings_test.dart.
//
// Название занятия стоит в плашке виджета шириной около двенадцати знаков.
// Длиннее тринадцати оно обрежется многоточием, поэтому переводы короткие.

const Map<String, Map<String, String>> doingStrings = {
  // Карточка в галерее виджетов
  'doing.title': {'ru': 'Чем заняты', 'en': 'What we’re up to', 'pt': 'O que estamos fazendo', 'it': 'Cosa stiamo facendo', 'es': 'Qué estamos haciendo', 'fr': 'Ce qu’on fait', 'de': 'Was wir gerade machen'},
  'doing.subtitle': {'ru': 'Ту показывает, чем сейчас занят каждый из вас', 'en': 'Tu shows what each of you is doing right now', 'pt': 'O Tu mostra o que cada um está fazendo agora', 'it': 'Tu mostra cosa sta facendo ognuno di voi', 'es': 'Tu muestra qué está haciendo cada uno ahora', 'fr': 'Tu montre ce que chacun fait en ce moment', 'de': 'Tu zeigt, was jeder von euch gerade macht'},
  'doing.pick': {'ru': 'Чем я занят', 'en': 'What I’m doing', 'pt': 'O que estou fazendo', 'it': 'Cosa sto facendo', 'es': 'Qué estoy haciendo', 'fr': 'Ce que je fais', 'de': 'Was ich gerade mache'},

  // Лист выбора занятия
  'doing.sheetTitle': {'ru': 'Чем ты занят?', 'en': 'What are you up to?', 'pt': 'O que você está fazendo?', 'it': 'Cosa stai facendo?', 'es': '¿Qué estás haciendo?', 'fr': 'Tu fais quoi ?', 'de': 'Was machst du gerade?'},
  'doing.ownHint': {'ru': 'Своё, например «на паре»', 'en': 'Your own, like “in class”', 'pt': 'O seu, por exemplo «na aula»', 'it': 'Il tuo, ad esempio «a lezione»', 'es': 'Lo tuyo, por ejemplo «en clase»', 'fr': 'Le tien, par exemple « en cours »', 'de': 'Dein eigenes, etwa „im Unterricht“'},
  'doing.done': {'ru': 'Готово', 'en': 'Done', 'pt': 'Pronto', 'it': 'Fatto', 'es': 'Listo', 'fr': 'OK', 'de': 'Fertig'},
  'doing.clear': {'ru': 'Убрать занятие', 'en': 'Clear', 'pt': 'Limpar', 'it': 'Togli', 'es': 'Quitar', 'fr': 'Retirer', 'de': 'Entfernen'},
  'doing.failed': {'ru': 'Не сохранилось. Проверь связь и попробуй ещё раз', 'en': 'Couldn’t save. Check your connection and try again', 'pt': 'Não salvou. Verifique a conexão e tente de novo', 'it': 'Non salvato. Controlla la connessione e riprova', 'es': 'No se guardó. Revisa la conexión e inténtalo de nuevo', 'fr': 'Non enregistré. Vérifie ta connexion et réessaie', 'de': 'Nicht gespeichert. Prüf die Verbindung und versuch es nochmal'},

  // Цвет своей комнатки
  'doing.roomTitle': {'ru': 'Цвет моей комнатки', 'en': 'My room colour', 'pt': 'Cor do meu quartinho', 'it': 'Colore della mia stanzetta', 'es': 'Color de mi cuartito', 'fr': 'Couleur de ma pièce', 'de': 'Farbe meines Zimmers'},
  'doing.roomHint': {'ru': 'Партнёр видит твою комнатку такой же', 'en': 'Your partner sees your room the same way', 'pt': 'Seu par vê o seu quartinho igual', 'it': 'Il partner vede la tua stanzetta così', 'es': 'Tu pareja ve tu cuartito igual', 'fr': 'Ton partenaire voit ta pièce pareil', 'de': 'Dein Partner sieht dein Zimmer genauso'},
  'doing.roomTheme': {'ru': 'Как в теме', 'en': 'Theme colour', 'pt': 'Cor do tema', 'it': 'Colore del tema', 'es': 'Color del tema', 'fr': 'Couleur du thème', 'de': 'Farbe des Designs'},
  'doing.roomAny': {'ru': 'Любой цвет', 'en': 'Any colour', 'pt': 'Qualquer cor', 'it': 'Qualsiasi colore', 'es': 'Cualquier color', 'fr': 'N’importe quelle couleur', 'de': 'Beliebige Farbe'},

  // Занятия
  'doing.study': {'ru': 'Учится', 'en': 'Studying', 'pt': 'Estudando', 'it': 'Studia', 'es': 'Estudiando', 'fr': 'Étudie', 'de': 'Lernt'},
  'doing.sleep': {'ru': 'Спит', 'en': 'Sleeping', 'pt': 'Dormindo', 'it': 'Dorme', 'es': 'Durmiendo', 'fr': 'Dort', 'de': 'Schläft'},
  'doing.rest': {'ru': 'Отдыхает', 'en': 'Resting', 'pt': 'Descansando', 'it': 'Riposa', 'es': 'Descansando', 'fr': 'Se repose', 'de': 'Ruht aus'},
  'doing.shower': {'ru': 'В душе', 'en': 'In the shower', 'pt': 'No banho', 'it': 'Fa la doccia', 'es': 'En la ducha', 'fr': 'Se douche', 'de': 'Duscht'},
  'doing.toilet': {'ru': 'В туалете', 'en': 'Bathroom', 'pt': 'No banheiro', 'it': 'In bagno', 'es': 'En el baño', 'fr': 'Aux WC', 'de': 'Auf dem WC'},
  'doing.work': {'ru': 'Работает', 'en': 'Working', 'pt': 'Trabalhando', 'it': 'Lavora', 'es': 'Trabajando', 'fr': 'Travaille', 'de': 'Arbeitet'},
  'doing.eat': {'ru': 'Ест', 'en': 'Eating', 'pt': 'Comendo', 'it': 'Mangia', 'es': 'Comiendo', 'fr': 'Mange', 'de': 'Isst'},
  'doing.road': {'ru': 'В дороге', 'en': 'On the road', 'pt': 'A caminho', 'it': 'In viaggio', 'es': 'De camino', 'fr': 'En route', 'de': 'Unterwegs'},
  'doing.gym': {'ru': 'Тренируется', 'en': 'Working out', 'pt': 'Treinando', 'it': 'Si allena', 'es': 'Entrenando', 'fr': 'S’entraîne', 'de': 'Trainiert'},
  'doing.game': {'ru': 'Играет', 'en': 'Gaming', 'pt': 'Jogando', 'it': 'Gioca', 'es': 'Jugando', 'fr': 'Joue', 'de': 'Zockt'},
  'doing.cook': {'ru': 'Готовит', 'en': 'Cooking', 'pt': 'Cozinhando', 'it': 'Cucina', 'es': 'Cocinando', 'fr': 'Cuisine', 'de': 'Kocht'},
  'doing.walk': {'ru': 'Гуляет', 'en': 'On a walk', 'pt': 'Passeando', 'it': 'A passeggio', 'es': 'De paseo', 'fr': 'En balade', 'de': 'Spaziert'},
  'doing.movie': {'ru': 'Смотрит кино', 'en': 'Movie time', 'pt': 'Vendo filme', 'it': 'Vede un film', 'es': 'Viendo peli', 'fr': 'Mate un film', 'de': 'Schaut Film'},
  'doing.clean': {'ru': 'Убирается', 'en': 'Cleaning', 'pt': 'Limpando', 'it': 'Fa le pulizie', 'es': 'Limpiando', 'fr': 'Au ménage', 'de': 'Putzt'},
  'doing.shop': {'ru': 'В магазине', 'en': 'Shopping', 'pt': 'Nas compras', 'it': 'Fa la spesa', 'es': 'De compras', 'fr': 'Aux courses', 'de': 'Kauft ein'},
  'doing.friends': {'ru': 'С друзьями', 'en': 'With friends', 'pt': 'Com amigos', 'it': 'Con gli amici', 'es': 'Con amigos', 'fr': 'Avec des amis', 'de': 'Mit Freunden'},
  'doing.sick': {'ru': 'Болеет', 'en': 'Sick', 'pt': 'Doente', 'it': 'Malato', 'es': 'Enfermo', 'fr': 'Malade', 'de': 'Krank'},
  'doing.busy': {'ru': 'Занят', 'en': 'Busy', 'pt': 'Ocupado', 'it': 'Occupato', 'es': 'Ocupado', 'fr': 'Occupé', 'de': 'Beschäftigt'},
};
