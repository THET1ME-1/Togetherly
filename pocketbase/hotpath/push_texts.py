# -*- coding: utf-8 -*-
"""Тексты уведомлений hotpath на языке получателя.

Уведомления пишет сервер, и до 08.11.2026 он писал их только по-русски:
языка, выбранного в приложении, он не знал (отзыв в App Store 19.08.2026:
«The notification and widgets are in Russian though the app I have set to
English»). Теперь приложение кладёт код языка в `users.lang`, а текст
выбирается по нему. Пустой или незнакомый язык — русский, как было: так
пишутся пуши людям на сборках старше поля.

Подписи «Скучаю» совпадают с приложением (`lib/l10n/dict/i_miss_you_vibes.dart`).
Языки — те же девять, что в `AppLanguage`.
"""

ЯЗЫКИ = ("ru", "en", "de", "fr", "es", "it", "pt", "zh", "uk")

ТЕКСТЫ: dict[str, dict[str, str]] = {
    # Имя автора, когда его нет в записи.
    "partner": {
        "ru": "Партнёр", "en": "Partner", "de": "Partner", "fr": "Partenaire",
        "es": "Tu pareja", "it": "Partner", "pt": "Seu par", "zh": "伴侣",
        "uk": "Партнер",
    },
    # Чат: сообщение без текста.
    "voice": {
        "ru": "Голосовое сообщение", "en": "Voice message", "de": "Sprachnachricht",
        "fr": "Message vocal", "es": "Mensaje de voz", "it": "Messaggio vocale",
        "pt": "Mensagem de voz", "zh": "语音消息", "uk": "Голосове повідомлення",
    },
    "figure": {
        "ru": "Фигурка", "en": "Figurine", "de": "Figur", "fr": "Figurine",
        "es": "Figurita", "it": "Statuina", "pt": "Bonequinho", "zh": "小人偶",
        "uk": "Фігурка",
    },
    "message": {
        "ru": "Сообщение", "en": "Message", "de": "Nachricht", "fr": "Message",
        "es": "Mensaje", "it": "Messaggio", "pt": "Mensagem", "zh": "消息",
        "uk": "Повідомлення",
    },
    # Новое воспоминание: заголовок — имя автора.
    "memory_added": {
        "ru": "Добавил воспоминание", "en": "Added a memory",
        "de": "Hat eine Erinnerung hinzugefügt", "fr": "A ajouté un souvenir",
        "es": "Añadió un recuerdo", "it": "Ha aggiunto un ricordo",
        "pt": "Adicionou uma lembrança", "zh": "添加了一段回忆",
        "uk": "Додав спогад",
    },
    # Настроение.
    "mood_title": {
        "ru": "Настроение партнёра", "en": "Your partner’s mood",
        "de": "Stimmung deines Partners", "fr": "Humeur de votre partenaire",
        "es": "Ánimo de tu pareja", "it": "Umore del partner",
        "pt": "Humor do seu par", "zh": "伴侣的心情", "uk": "Настрій партнера",
    },
    "mood_today": {
        "ru": "Сегодня: {label}", "en": "Today: {label}", "de": "Heute: {label}",
        "fr": "Aujourd’hui : {label}", "es": "Hoy: {label}", "it": "Oggi: {label}",
        "pt": "Hoje: {label}", "zh": "今天：{label}", "uk": "Сьогодні: {label}",
    },
    "mood_marked": {
        "ru": "Партнёр отметил настроение", "en": "Your partner logged their mood",
        "de": "Dein Partner hat die Stimmung eingetragen",
        "fr": "Votre partenaire a noté son humeur",
        "es": "Tu pareja marcó su ánimo", "it": "Il partner ha segnato l’umore",
        "pt": "Seu par marcou o humor", "zh": "伴侣记录了心情",
        "uk": "Партнер відмітив настрій",
    },
    # «Скучаю».
    "miss_title": {
        "ru": "Скучает по тебе", "en": "Misses you", "de": "Vermisst dich",
        "fr": "Pense à toi", "es": "Te echa de menos", "it": "Sente la tua mancanza",
        "pt": "Está com saudade de você", "zh": "想你了", "uk": "Сумує за тобою",
    },
    "miss_hug": {
        "ru": "Обними в ответ", "en": "Hug back", "de": "Umarme zurück",
        "fr": "Fais-lui un câlin en retour", "es": "Devuélvele el abrazo",
        "it": "Ricambia l’abbraccio", "pt": "Abrace de volta", "zh": "回抱一下",
        "uk": "Обійми у відповідь",
    },
    "miss_reply": {
        "ru": "В ответ на «{text}»", "en": "In reply to “{text}”",
        "de": "Als Antwort auf „{text}“", "fr": "En réponse à « {text} »",
        "es": "En respuesta a «{text}»", "it": "In risposta a «{text}»",
        "pt": "Em resposta a “{text}”", "zh": "回应「{text}」",
        "uk": "У відповідь на «{text}»",
    },
    "vibe_miss_you": {
        "ru": "Я скучаю", "en": "I miss you", "de": "Ich vermisse dich",
        "fr": "Tu me manques", "es": "Te echo de menos", "it": "Mi manchi",
        "pt": "Estou com saudade", "zh": "我想你", "uk": "Я сумую",
    },
    "vibe_thinking_of_you": {
        "ru": "Думаю о тебе", "en": "Thinking of you", "de": "Ich denke an dich",
        "fr": "Je pense à toi", "es": "Pienso en ti", "it": "Penso a te",
        "pt": "Penso em você", "zh": "在想你", "uk": "Думаю про тебе",
    },
    "vibe_want_hug": {
        "ru": "Хочу обнять", "en": "Want a hug", "de": "Ich will dich umarmen",
        "fr": "J’ai envie de te serrer", "es": "Quiero abrazarte",
        "it": "Voglio abbracciarti", "pt": "Quero te abraçar", "zh": "想抱抱",
        "uk": "Хочу обійняти",
    },
    # Снежок темы «Новый год» (27.11.2026): партнёр не в приложении.
    "snow_title": {
        "ru": "В тебя прилетел снежок", "en": "A snowball hit you", "de": "Ein Schneeball hat dich getroffen",
        "fr": "Une boule de neige t’a touché", "es": "Te dieron con una bola de nieve",
        "it": "Ti è arrivata una palla di neve", "pt": "Uma bola de neve te acertou", "zh": "你被雪球砸中了",
        "uk": "У тебе влучила сніжка",
    },
    "snow_body": {
        "ru": "Открой и кинь в ответ", "en": "Open the app and throw one back", "de": "Öffne die App und wirf zurück",
        "fr": "Ouvre l’app et renvoie-la", "es": "Abre la app y devuélvela", "it": "Apri l’app e rilanciala",
        "pt": "Abra o app e jogue de volta", "zh": "打开应用扔回去", "uk": "Відкрий і кинь у відповідь",
    },
    # Наши даты (TOG-61, 28.11.2026). Новая дата от партнёра: заголовок — имя.
    "date_added": {
        "ru": "Новая дата: {title}", "en": "New date: {title}", "de": "Neues Datum: {title}",
        "fr": "Nouvelle date : {title}", "es": "Nueva fecha: {title}", "it": "Nuova data: {title}",
        "pt": "Nova data: {title}", "zh": "新的日子：{title}", "uk": "Нова дата: {title}",
    },
    # Напоминание: заголовок — название даты, без него — это.
    "date_untitled": {
        "ru": "Наша дата", "en": "Our date", "de": "Unser Datum", "fr": "Notre date",
        "es": "Nuestra fecha", "it": "La nostra data", "pt": "Nossa data", "zh": "我们的日子",
        "uk": "Наша дата",
    },
    "date_today": {
        "ru": "Сегодня", "en": "Today", "de": "Heute", "fr": "Aujourd’hui", "es": "Hoy",
        "it": "Oggi", "pt": "Hoje", "zh": "就是今天", "uk": "Сьогодні",
    },
    "date_tomorrow": {
        "ru": "Завтра", "en": "Tomorrow", "de": "Morgen", "fr": "Demain", "es": "Mañana",
        "it": "Domani", "pt": "Amanhã", "zh": "明天", "uk": "Завтра",
    },
    "date_now": {
        "ru": "Начинается сейчас", "en": "Starting now", "de": "Beginnt jetzt",
        "fr": "Ça commence maintenant", "es": "Empieza ahora", "it": "Inizia ora",
        "pt": "Começa agora", "zh": "现在开始", "uk": "Починається зараз",
    },
    "date_today_at": {
        "ru": "Сегодня в {time}", "en": "Today at {time}", "de": "Heute um {time}",
        "fr": "Aujourd’hui à {time}", "es": "Hoy a las {time}", "it": "Oggi alle {time}",
        "pt": "Hoje às {time}", "zh": "今天 {time}", "uk": "Сьогодні о {time}",
    },
    "date_tomorrow_at": {
        "ru": "Завтра в {time}", "en": "Tomorrow at {time}", "de": "Morgen um {time}",
        "fr": "Demain à {time}", "es": "Mañana a las {time}", "it": "Domani alle {time}",
        "pt": "Amanhã às {time}", "zh": "明天 {time}", "uk": "Завтра о {time}",
    },
    # «Через 3 дня, в 19:00»: {days} — готовая строка «Через 3 дня».
    "date_in_days_at": {
        "ru": "{days}, в {time}", "en": "{days}, at {time}", "de": "{days}, um {time}",
        "fr": "{days}, à {time}", "es": "{days}, a las {time}", "it": "{days}, alle {time}",
        "pt": "{days}, às {time}", "zh": "{days}，{time}", "uk": "{days}, о {time}",
    },
    # Формы числа: one, few (только ru и uk), many.
    "date_in_days_one": {
        "ru": "Через {n} день", "en": "In {n} day", "de": "In {n} Tag", "fr": "Dans {n} jour",
        "es": "Dentro de {n} día", "it": "Tra {n} giorno", "pt": "Daqui a {n} dia",
        "zh": "还有 {n} 天", "uk": "Через {n} день",
    },
    "date_in_days_few": {"ru": "Через {n} дня", "uk": "Через {n} дні"},
    "date_in_days_many": {
        "ru": "Через {n} дней", "en": "In {n} days", "de": "In {n} Tagen", "fr": "Dans {n} jours",
        "es": "Dentro de {n} días", "it": "Tra {n} giorni", "pt": "Daqui a {n} dias",
        "zh": "还有 {n} 天", "uk": "Через {n} днів",
    },
    "date_in_minutes_one": {
        "ru": "Через {n} минуту", "en": "In {n} minute", "de": "In {n} Minute",
        "fr": "Dans {n} minute", "es": "Dentro de {n} minuto", "it": "Tra {n} minuto",
        "pt": "Daqui a {n} minuto", "zh": "还有 {n} 分钟", "uk": "Через {n} хвилину",
    },
    "date_in_minutes_few": {"ru": "Через {n} минуты", "uk": "Через {n} хвилини"},
    "date_in_minutes_many": {
        "ru": "Через {n} минут", "en": "In {n} minutes", "de": "In {n} Minuten",
        "fr": "Dans {n} minutes", "es": "Dentro de {n} minutos", "it": "Tra {n} minuti",
        "pt": "Daqui a {n} minutos", "zh": "还有 {n} 分钟", "uk": "Через {n} хвилин",
    },
    "date_in_hours_one": {
        "ru": "Через {n} час", "en": "In {n} hour", "de": "In {n} Stunde", "fr": "Dans {n} heure",
        "es": "Dentro de {n} hora", "it": "Tra {n} ora", "pt": "Daqui a {n} hora",
        "zh": "还有 {n} 小时", "uk": "Через {n} годину",
    },
    "date_in_hours_few": {"ru": "Через {n} часа", "uk": "Через {n} години"},
    "date_in_hours_many": {
        "ru": "Через {n} часов", "en": "In {n} hours", "de": "In {n} Stunden",
        "fr": "Dans {n} heures", "es": "Dentro de {n} horas", "it": "Tra {n} ore",
        "pt": "Daqui a {n} horas", "zh": "还有 {n} 小时", "uk": "Через {n} годин",
    },
}


def язык(код: str | None) -> str:
    """Код из профиля → язык текста. Пусто или незнакомо — русский."""
    код = (код or "").strip().lower()[:2]
    return код if код in ЯЗЫКИ else "ru"


def пуш(ключ: str, код: str | None = None, **подстановки: str) -> str:
    """Текст уведомления [ключ] на языке [код] с подстановками `{имя}`."""
    варианты = ТЕКСТЫ[ключ]
    текст = варианты.get(язык(код)) or варианты["ru"]
    for имя, значение in подстановки.items():
        текст = текст.replace("{" + имя + "}", значение)
    return текст
