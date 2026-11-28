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

    # ── Обложка «А» (push_cover.py, 28.11.2026): подпись над заголовком ──
    "c_miss": {
        "ru": "Скучаю", "en": "Missing you", "de": "Vermisse dich", "fr": "Tu me manques",
        "es": "Te extraño", "it": "Mi manchi", "pt": "Saudade", "zh": "想你", "uk": "Сумую",
    },
    "c_mood": {
        "ru": "Настроение", "en": "Mood", "de": "Stimmung", "fr": "Humeur", "es": "Ánimo",
        "it": "Umore", "pt": "Humor", "zh": "心情", "uk": "Настрій",
    },
    "c_mood_today": {
        "ru": "Настроение на сегодня", "en": "Mood for today", "de": "Stimmung für heute",
        "fr": "Humeur du jour", "es": "Ánimo de hoy", "it": "Umore di oggi",
        "pt": "Humor de hoje", "zh": "今天的心情", "uk": "Настрій на сьогодні",
    },
    "c_memory": {
        "ru": "Воспоминание", "en": "Memory", "de": "Erinnerung", "fr": "Souvenir",
        "es": "Recuerdo", "it": "Ricordo", "pt": "Lembrança", "zh": "回忆", "uk": "Спогад",
    },
    "c_memory_new": {
        "ru": "Новое воспоминание", "en": "New memory", "de": "Neue Erinnerung",
        "fr": "Nouveau souvenir", "es": "Nuevo recuerdo", "it": "Nuovo ricordo",
        "pt": "Nova lembrança", "zh": "新回忆", "uk": "Новий спогад",
    },
    "c_date_new": {
        "ru": "Новая дата", "en": "New date", "de": "Neues Datum", "fr": "Nouvelle date",
        "es": "Nueva fecha", "it": "Nuova data", "pt": "Nova data", "zh": "新日子",
        "uk": "Нова дата",
    },
    "c_date": {
        "ru": "Наша дата", "en": "Our date", "de": "Unser Datum", "fr": "Notre date",
        "es": "Nuestra fecha", "it": "La nostra data", "pt": "Nossa data", "zh": "我们的日子",
        "uk": "Наша дата",
    },
    "c_snow": {
        "ru": "Снежок", "en": "Snowball", "de": "Schneeball", "fr": "Boule de neige",
        "es": "Bola de nieve", "it": "Palla di neve", "pt": "Bola de neve", "zh": "雪球",
        "uk": "Сніжка",
    },
    "c_evening": {
        "ru": "Вечернее напоминание", "en": "Evening reminder", "de": "Abenderinnerung",
        "fr": "Rappel du soir", "es": "Recordatorio de la noche", "it": "Promemoria serale",
        "pt": "Lembrete da noite", "zh": "晚间提醒", "uk": "Вечірнє нагадування",
    },
    "c_chest": {
        "ru": "Сундук", "en": "Chest", "de": "Truhe", "fr": "Coffre", "es": "Cofre",
        "it": "Forziere", "pt": "Baú", "zh": "宝箱", "uk": "Скриня",
    },
    "c_gift": {
        "ru": "Подарок", "en": "Gift", "de": "Geschenk", "fr": "Cadeau", "es": "Regalo",
        "it": "Regalo", "pt": "Presente", "zh": "礼物", "uk": "Подарунок",
    },
    "c_comment": {
        "ru": "Комментарий", "en": "Comment", "de": "Kommentar", "fr": "Commentaire",
        "es": "Comentario", "it": "Commento", "pt": "Comentário", "zh": "评论",
        "uk": "Коментар",
    },
    "c_draw": {
        "ru": "Рисунок", "en": "Drawing", "de": "Zeichnung", "fr": "Dessin", "es": "Dibujo",
        "it": "Disegno", "pt": "Desenho", "zh": "画画", "uk": "Малюнок",
    },
    "c_security": {
        "ru": "Безопасность", "en": "Security", "de": "Sicherheit", "fr": "Sécurité",
        "es": "Seguridad", "it": "Sicurezza", "pt": "Segurança", "zh": "安全", "uk": "Безпека",
    },
    # Кнопки.
    "a_open_gift": {
        "ru": "Открыть подарок", "en": "Open gift", "de": "Geschenk öffnen",
        "fr": "Ouvrir le cadeau", "es": "Abrir el regalo", "it": "Apri il regalo",
        "pt": "Abrir presente", "zh": "打开礼物", "uk": "Відкрити подарунок",
    },
    "a_canvas": {
        "ru": "Открыть холст", "en": "Open canvas", "de": "Leinwand öffnen",
        "fr": "Ouvrir la toile", "es": "Abrir el lienzo", "it": "Apri la tela",
        "pt": "Abrir a tela", "zh": "打开画布", "uk": "Відкрити полотно",
    },
    "a_hug_back": {
        "ru": "Обнять в ответ", "en": "Hug back", "de": "Zurück umarmen",
        "fr": "Câlin en retour", "es": "Devolver el abrazo", "it": "Ricambia l’abbraccio",
        "pt": "Abraçar de volta", "zh": "回抱", "uk": "Обійняти у відповідь",
    },
    "a_hug": {
        "ru": "Обнять", "en": "Hug", "de": "Umarmen", "fr": "Câlin", "es": "Abrazar",
        "it": "Abbraccia", "pt": "Abraçar", "zh": "抱抱", "uk": "Обійняти",
    },
    "a_write": {
        "ru": "Написать", "en": "Write", "de": "Schreiben", "fr": "Écrire", "es": "Escribir",
        "it": "Scrivi", "pt": "Escrever", "zh": "写消息", "uk": "Написати",
    },
    "a_reply": {
        "ru": "Ответить", "en": "Reply", "de": "Antworten", "fr": "Répondre",
        "es": "Responder", "it": "Rispondi", "pt": "Responder", "zh": "回复",
        "uk": "Відповісти",
    },
    "a_read": {
        "ru": "Прочитано", "en": "Mark as read", "de": "Gelesen", "fr": "Lu", "es": "Leído",
        "it": "Letto", "pt": "Lido", "zh": "已读", "uk": "Прочитано",
    },
    "a_open": {
        "ru": "Открыть", "en": "Open", "de": "Öffnen", "fr": "Ouvrir", "es": "Abrir",
        "it": "Apri", "pt": "Abrir", "zh": "打开", "uk": "Відкрити",
    },
    "a_watch": {
        "ru": "Смотреть", "en": "View", "de": "Ansehen", "fr": "Voir", "es": "Ver",
        "it": "Guarda", "pt": "Ver", "zh": "查看", "uk": "Дивитися",
    },
    "a_throw": {
        "ru": "Кинуть в ответ", "en": "Throw back", "de": "Zurückwerfen", "fr": "Renvoyer",
        "es": "Lanzar de vuelta", "it": "Rilancia", "pt": "Jogar de volta", "zh": "扔回去",
        "uk": "Кинути у відповідь",
    },
    "a_mood": {
        "ru": "Отметить настроение", "en": "Log mood", "de": "Stimmung eintragen",
        "fr": "Noter l’humeur", "es": "Marcar ánimo", "it": "Segna l’umore",
        "pt": "Marcar humor", "zh": "记录心情", "uk": "Позначити настрій",
    },
    "a_task": {
        "ru": "Задание дня", "en": "Today’s task", "de": "Aufgabe des Tages",
        "fr": "Mission du jour", "es": "Tarea del día", "it": "Sfida del giorno",
        "pt": "Tarefa do dia", "zh": "今日任务", "uk": "Завдання дня",
    },
    "a_chest": {
        "ru": "Открыть сундук", "en": "Open chest", "de": "Truhe öffnen",
        "fr": "Ouvrir le coffre", "es": "Abrir el cofre", "it": "Apri il forziere",
        "pt": "Abrir o baú", "zh": "打开宝箱", "uk": "Відкрити скриню",
    },
    "a_mood_back": {
        "ru": "Ответить настроением", "en": "Reply with a mood", "de": "Mit Stimmung antworten",
        "fr": "Répondre par une humeur", "es": "Responder con un ánimo",
        "it": "Rispondi con un umore", "pt": "Responder com humor", "zh": "用心情回应",
        "uk": "Відповісти настроєм",
    },
    # Быстрые ответы под полем ответа в чате (только Android).
    "q_hug": {
        "ru": "Обнимаю", "en": "Hugging you", "de": "Umarme dich", "fr": "Je te serre fort",
        "es": "Te abrazo", "it": "Ti abbraccio", "pt": "Te abraço", "zh": "抱抱你",
        "uk": "Обіймаю",
    },
    "q_miss": {
        "ru": "Скучаю тоже", "en": "Miss you too", "de": "Vermisse dich auch",
        "fr": "Tu me manques aussi", "es": "Yo también te extraño", "it": "Mi manchi anche tu",
        "pt": "Também tô com saudade", "zh": "我也想你", "uk": "Теж сумую",
    },
    "q_love": {
        "ru": "Люблю тебя", "en": "Love you", "de": "Hab dich lieb", "fr": "Je t’aime",
        "es": "Te quiero", "it": "Ti amo", "pt": "Te amo", "zh": "爱你", "uk": "Кохаю тебе",
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
