// Строки раздела. Одна запись — все языки сразу: так новый язык это
// колонка в словаре, а не ещё один класс на полторы тысячи членов.
//
// Правится руками. Ключ без перевода на выбранный язык откатывается на
// английский (см. `trDict` в ../dict_strings.dart), поэтому пустых мест
// на экране не бывает.

const Map<String, Map<String, String>> loginStrings = {
  'welcomeBack': {
    'ru': 'С возвращением!',
    'en': 'Welcome back!',
    'pt': 'Que bom te ver de novo!',
    'it': 'Bentornato!',
    'es': '¡Qué bien verte otra vez!',
    'fr': 'Content de te revoir !',
    'de': 'Willkommen zurück!',
  },
  'loginToAccount': {
    'ru': 'Войдите в свой аккаунт',
    'en': 'Sign in to your account',
    'pt': 'Entre na sua conta',
    'it': 'Accedi al tuo account',
    'es': 'Inicia sesión en tu cuenta',
    'fr': 'Connecte-toi à ton compte',
    'de': 'Melde dich bei deinem Konto an',
  },
  'signInWithGoogle': {
    'ru': 'Войти через Google',
    'en': 'Sign in with Google',
    'pt': 'Entrar com o Google',
    'it': 'Accedi con Google',
    'es': 'Entrar con Google',
    'fr': 'Se connecter avec Google',
    'de': 'Mit Google anmelden',
  },
  'or': {
    'ru': 'или',
    'en': 'or',
    'pt': 'ou',
    'it': 'o',
    'es': 'o',
    'fr': 'ou',
    'de': 'oder',
  },
  'email': {
    'ru': 'Email',
    'en': 'Email',
    'pt': 'E-mail',
    'it': 'E-mail',
    'es': 'Correo',
    'fr': 'E-mail',
    'de': 'E-Mail',
  },
  'yourEmail': {
    'ru': 'Ваш email',
    'en': 'Your email',
    'pt': 'Seu e-mail',
    'it': 'La tua e-mail',
    'es': 'Tu correo',
    'fr': 'Ton e-mail',
    'de': 'Deine E-Mail',
  },
  'password': {
    'ru': 'Пароль',
    'en': 'Password',
    'pt': 'Senha',
    'it': 'Password',
    'es': 'Contraseña',
    'fr': 'Mot de passe',
    'de': 'Passwort',
  },
  'yourPassword': {
    'ru': 'Ваш пароль',
    'en': 'Your password',
    'pt': 'Sua senha',
    'it': 'La tua password',
    'es': 'Tu contraseña',
    'fr': 'Ton mot de passe',
    'de': 'Dein Passwort',
  },
  'login': {
    'ru': 'Войти',
    'en': 'Sign In',
    'pt': 'Entrar',
    'it': 'Accedi',
    'es': 'Entrar',
    'fr': 'Se connecter',
    'de': 'Anmelden',
  },
  'noAccount': {
    'ru': 'Нет аккаунта? ',
    'en': 'No account? ',
    'pt': 'Ainda não tem conta? ',
    'it': 'Non hai un account? ',
    'es': '¿Aún no tienes cuenta? ',
    'fr': 'Pas encore de compte ? ',
    'de': 'Noch kein Konto? ',
  },
  'create': {
    'ru': 'Создать',
    'en': 'Create',
    'pt': 'Criar',
    'it': 'Crea',
    'es': 'Crear',
    'fr': 'Créer',
    'de': 'Erstellen',
  },
  'invalidEmail': {
    'ru': 'Введите корректный email',
    'en': 'Enter a valid email',
    'pt': 'Digite um e-mail válido',
    'it': 'Inserisci un’e-mail valida',
    'es': 'Escribe un correo válido',
    'fr': 'Saisis une adresse e-mail valide',
    'de': 'Gib eine gültige E-Mail-Adresse ein',
  },
  'enterPassword': {
    'ru': 'Введите пароль',
    'en': 'Enter your password',
    'pt': 'Digite a senha',
    'it': 'Inserisci la password',
    'es': 'Escribe la contraseña',
    'fr': 'Saisis le mot de passe',
    'de': 'Gib das Passwort ein',
  },
  'loginFailed': {
    'ru': 'Не удалось войти. Попробуйте ещё раз.',
    'en': 'Login failed. Please try again.',
    'pt': 'Não deu para entrar. Tente de novo.',
    'it': 'Accesso non riuscito. Prova di nuovo.',
    'es': 'No se pudo entrar. Inténtalo otra vez.',
    'fr': 'Connexion impossible. Essaie encore.',
    'de': 'Anmeldung fehlgeschlagen. Versuche es noch einmal.',
  },
  'profileNotFound': {
    'ru': 'Профиль не найден. Зарегистрируйтесь заново.',
    'en': 'Profile not found. Please register again.',
    'pt': 'Perfil não encontrado. Cadastre-se de novo.',
    'it': 'Profilo non trovato. Registrati di nuovo.',
    'es': 'Perfil no encontrado. Regístrate de nuevo.',
    'fr': 'Profil introuvable. Inscris-toi de nouveau.',
    'de': 'Profil nicht gefunden. Registriere dich erneut.',
  },
  'userNotFound': {
    'ru': 'Пользователь с таким email не найден',
    'en': 'No user found with this email',
    'pt': 'Nenhuma conta com esse e-mail',
    'it': 'Nessun account con questa e-mail',
    'es': 'No hay ninguna cuenta con ese correo',
    'fr': 'Aucun compte avec cet e-mail',
    'de': 'Kein Konto mit dieser E-Mail gefunden',
  },
  // Сервер не дозвонился до Google или Apple. Человеку важно понять, что дело
  // не в пароле и повторять ввод бесполезно — надо просто попробовать снова.
  'providerUnreachable': {
    'ru': 'Не получилось связаться с Google. Пароль тут ни при чём — попробуйте войти ещё раз через минуту.',
    'en': 'Could not reach Google. Your password is fine — try signing in again in a minute.',
    'de': 'Google war nicht erreichbar. Am Passwort liegt es nicht — versuche es in einer Minute noch einmal.',
    'fr': 'Impossible de joindre Google. Ce n’est pas le mot de passe — réessaie dans une minute.',
    'es': 'No se pudo contactar con Google. No es la contraseña — inténtalo de nuevo en un minuto.',
    'it': 'Non siamo riusciti a contattare Google. Non è la password — riprova tra un minuto.',
    'pt': 'Não deu para falar com o Google. Não é a senha — tente entrar de novo em um minuto.',
  },
  'providerPageFailed': {
    'ru': 'Страница входа не открылась. Попробуйте снова или войдите по почте',
    'en': "The sign-in page didn't open. Try again or use your email",
    'pt': 'A página de login não abriu. Tente de novo ou use o e-mail',
    'it': 'La pagina di accesso non si è aperta. Riprova o usa l’e-mail',
    'es': 'La página de acceso no se abrió. Inténtalo otra vez o usa el correo',
    'fr': 'La page de connexion ne s’est pas ouverte. Réessaie ou utilise l’e-mail',
    'de': 'Die Anmeldeseite ging nicht auf. Versuche es erneut oder nimm die E-Mail',
  },
  'wrongPassword': {
    'ru': 'Неверный пароль',
    'en': 'Wrong password',
    'pt': 'Senha incorreta',
    'it': 'Password errata',
    'es': 'Contraseña incorrecta',
    'fr': 'Mot de passe incorrect',
    'de': 'Falsches Passwort',
  },
  'invalidEmailFormat': {
    'ru': 'Некорректный email',
    'en': 'Invalid email format',
    'pt': 'E-mail inválido',
    'it': 'E-mail non valida',
    'es': 'Correo no válido',
    'fr': 'Adresse e-mail invalide',
    'de': 'Ungültige E-Mail-Adresse',
  },
  'tooManyAttempts': {
    'ru': 'Слишком много попыток. Попробуйте позже',
    'en': 'Too many attempts. Try again later',
    'pt': 'Muitas tentativas. Tente mais tarde',
    'it': 'Troppi tentativi. Riprova più tardi',
    'es': 'Demasiados intentos. Prueba más tarde',
    'fr': 'Trop d’essais. Réessaie plus tard',
    'de': 'Zu viele Versuche. Versuche es später',
  },
  'serverNotResponding': {
    'ru': 'Сервер не отвечает. Проверьте интернет.',
    'en': 'Server not responding. Check your internet.',
    'pt': 'O servidor não responde. Confira sua conexão.',
    'it': 'Il server non risponde. Controlla la connessione.',
    'es': 'El servidor no responde. Revisa tu conexión.',
    'fr': 'Le serveur ne répond pas. Vérifie ta connexion.',
    'de': 'Der Server antwortet nicht. Prüfe deine Verbindung.',
  },
  'retry': {
    'ru': 'Ещё раз',
    'en': 'Try again',
    'pt': 'Tentar de novo',
    'it': 'Riprova',
    'es': 'Reintentar',
    'fr': 'Réessayer',
    'de': 'Nochmal',
  },
  'connectionBlocked': {
    'ru':
        'Соединение обрывается по пути. Чаще всего мешает провайдер: попробуйте мобильный интернет, другую сеть или VPN.',
    'en':
        'The connection is being cut on the way. Usually it is the network provider: try mobile data, another network or a VPN.',
    'pt':
        'A conexão está sendo cortada no caminho. Normalmente é a operadora: tente dados móveis, outra rede ou uma VPN.',
    'it':
        'La connessione viene interrotta per strada. Spesso è l’operatore: prova i dati mobili, un’altra rete o una VPN.',
    'es':
        'La conexión se corta por el camino. Suele ser el operador: prueba con datos móviles, otra red o una VPN.',
    'fr':
        'La connexion est coupée en route. C’est souvent l’opérateur : essaie les données mobiles, un autre réseau ou un VPN.',
    'de':
        'Die Verbindung wird unterwegs abgebrochen. Meistens liegt es am Anbieter: probiere mobile Daten, ein anderes Netz oder ein VPN.',
  },
  // TOG-16: интернет у человека есть, а наш сервер в его сети закрыт. Решает
  // проверка сети (ServerReach), текст выбирает networkFailureText.
  'serverBlockedVpn': {
    'ru':
        'Ваша сеть не пускает приложение к нашему серверу. Так делают некоторые провайдеры в Украине и США. Включите VPN или подключитесь к другой сети.',
    'en':
        "Your network won't let the app reach our server. Some providers in Ukraine and the US do this. Turn on a VPN or switch to another network.",
    'pt':
        'Sua rede não deixa o app chegar ao nosso servidor. Algumas operadoras na Ucrânia e nos EUA fazem isso. Ative uma VPN ou troque de rede.',
    'it':
        'La tua rete non lascia arrivare l’app al nostro server. Succede con alcuni operatori in Ucraina e negli Stati Uniti. Attiva una VPN o cambia rete.',
    'es':
        'Tu red no deja que la app llegue a nuestro servidor. Lo hacen algunos operadores de Ucrania y EE. UU. Activa una VPN o cambia de red.',
    'fr':
        'Ton réseau empêche l’app de joindre notre serveur. Certains opérateurs en Ukraine et aux États-Unis le font. Active un VPN ou passe sur un autre réseau.',
    'de':
        'Dein Netz lässt die App nicht zu unserem Server. Das machen manche Anbieter in der Ukraine und den USA. Schalte ein VPN ein oder wechsle das Netz.',
  },
  // Плашка поверх экранов: та же мысль одной строкой.
  'serverBlockedChip': {
    'ru': 'Сеть не пускает к серверу · включите VPN',
    'en': 'Your network blocks our server · try a VPN',
    'pt': 'Sua rede bloqueia nosso servidor · ative uma VPN',
    'it': 'La tua rete blocca il server · attiva una VPN',
    'es': 'Tu red bloquea el servidor · activa una VPN',
    'fr': 'Ton réseau bloque le serveur · active un VPN',
    'de': 'Dein Netz sperrt den Server · VPN einschalten',
  },
  'noInternet': {
    'ru': 'Нет интернета. Проверьте подключение.',
    'en': 'No internet. Check your connection.',
    'pt': 'Sem internet. Confira sua conexão.',
    'it': 'Niente internet. Controlla la connessione.',
    'es': 'Sin internet. Revisa tu conexión.',
    'fr': 'Pas d’internet. Vérifie ta connexion.',
    'de': 'Kein Internet. Prüfe deine Verbindung.',
  },
  'serverSlowRetry': {
    'ru': 'Сервер не успел ответить. Попробуйте ещё раз.',
    'en': "The server didn't answer in time. Try again.",
    'pt': 'O servidor não respondeu a tempo. Tente de novo.',
    'it': 'Il server non ha risposto in tempo. Riprova.',
    'es': 'El servidor no respondió a tiempo. Inténtalo otra vez.',
    'fr': 'Le serveur n’a pas répondu à temps. Réessaie.',
    'de': 'Der Server hat nicht rechtzeitig geantwortet. Versuche es noch einmal.',
  },
  'googleNotResponding': {
    'ru': 'Google не отвечает. Проверьте интернет.',
    'en': 'Google not responding. Check your internet.',
    'pt': 'O Google não responde. Confira sua conexão.',
    'it': 'Google non risponde. Controlla la connessione.',
    'es': 'Google no responde. Revisa tu conexión.',
    'fr': 'Google ne répond pas. Vérifie ta connexion.',
    'de': 'Google antwortet nicht. Prüfe deine Verbindung.',
  },
};
