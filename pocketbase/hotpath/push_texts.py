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
