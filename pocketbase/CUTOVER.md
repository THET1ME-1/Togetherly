# Миграция Firebase → PocketBase — что осталось (cutover)

Ветка `feature/pocketbase`. Бэкенд-слои PB **готовы и проверены на проде**
(см. ниже). Осталось перевести приложение на них и выпилить Firebase. Firebase
убираем **РАЗОМ** (не частями) — в окне миграции не должно быть смешанных пар
Firebase/PB, иначе партнёры не видят друг друга.

## ✅ Уже сделано (готово + проверено на проде)

- **Схема:** 17 коллекций + `users` (id-override) + `media`. `pocketbase/gen_schema.py`, `apply_schema.py`, `collections_schema.json`.
- **Фундамент:** `lib/services/pocketbase_service.dart` (клиент на VPS, сессия в SharedPreferences).
- **Auth:** `lib/services/pb_auth_service.dart` — email/Google/Apple. Провайдеры заведены в PB, серверно проверены. Apple-секрет авто-обновляется кроном на VPS.
- **Данные:** `lib/services/pb_data_service.dart` — CRUD всех таблиц.
- **Realtime:** `lib/services/pb_realtime_service.dart` — SSE-подписки без лимитов.
- **Медиа:** `lib/services/pb_media_service.dart` + коллекция `media` (схема `pb://`).
- **Пуш:** `lib/services/pb_push_service.dart` — SSE-событие партнёра → локальное уведомление (без FCM). Конвейер проверен; on-device показ + фоновый сервис — ниже.

## ⏳ Осталось — CUTOVER

### 1. Точка входа `main.dart`
- [ ] `PocketBaseService().init()` + `PbAuthService().signInSilently()` на старте.
- [ ] Убрать `Firebase.initializeApp`, `FirebaseCrashlytics`, `FirebaseMessaging` (+ `_firebaseMessagingBackgroundHandler`), `Supabase.initialize`.
- [ ] Force-update порог: уже читается из Firebase RTDB — перевести на PB (`app_config.min_build`) или оставить как отдельный мелкий вызов (решить).

### 2. Auth UI
- [ ] `login_screen.dart`, `setup_screen.dart` → вызовы `PbAuthService` вместо `FirebaseService.signInWithGoogle/Email`.
- [ ] Добавить кнопку «Войти через Apple» (провайдер готов).

### 3. Данные/Realtime (главный объём — ~45 файлов)
- [ ] Перевести все вызовы `FirebaseService().*` на `PbDataService`/`PbRealtimeService`.
- [ ] Listeners Firestore + RTDB → стримы `PbRealtimeService`.
- [ ] **Убрать кнопки «обновить» и лимиты/пагинацию** (Лента воспоминаний и пр.) — всё live, чтения бесплатны (memory `togetherly_pb_realtime_no_limits`).
- [ ] Модели `Memory/MoodEntry/ChatMsg/Mascot/...`: `fromFirestore` завязаны на `Timestamp` (cloud_firestore). Добавить `fromPb`-конструкторы (даты — ISO/DateTime) или адаптеры; убрать зависимость от Timestamp.
- [ ] RTDB-фичи без аналога onDisconnect — эмулировать heartbeat+TTL: presence (онлайн), live-локация «Где мы», co-watch (together-sessions). Перевести на PB realtime/записи.

### 4. Медиа
- [ ] Загрузки (фото/видео/музыка/аватары) → `PbMediaService.uploadBytes`.
- [ ] Распознавание/резолв `pb://` во ВСЕХ виджетах (зеркалить прежний фикс `sb://`): `StorageImage`, `widget_service`, `home_widget_service` (+карусель/сетка/соло), `widget_screen`, `photo_day_carousel_editor`, `timer_service`. Резолвер — `PbMediaService.resolveUrl`.

### 5. Пуш — фон
- [ ] Интегрировать Android **foreground-сервис** (напр. `flutter_foreground_task`), держащий SSE-подписку `PbPushService` при закрытом приложении.
- [ ] Запускать `PbPushService.start(groupId, myUid, partnerUid)` после входа/привязки пары.
- [ ] Проверить показ баннера на реальном устройстве (на хосте недоступно).

### 6. Серверная логика «коинов»/RPC (НЕ покрыто слоями выше!)
Cloud Functions callable, которые надо заменить (pb_hooks JS или серверная логика PB; деньги нельзя считать на клиенте без валидации):
- [ ] `purchaseTheme`/`purchaseIcon`/`purchaseFeature`, `spendCoins`, `grantDailyBonus`, `grantMemoryReward`, `grantAdReward`, `grantPartnerInviteReward`, `grantMoodStreakReward`, `grantCoinsPurchase`, `mergeDuplicateGroups`.
- [ ] AdMob SSV callback (`adSsvCallback`) — серверная верификация наград за рекламу.
- [ ] IAP-валидация (RuStore/Play) — серверная проверка покупок.

### 7. Зачистка Firebase/Supabase
- [ ] Удалить `lib/services/supabase_service.dart`, `lib/config/migration_config.dart`, `lib/services/firebase_service.dart` (после перевязки).
- [ ] Из `pubspec.yaml` убрать: `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `firebase_messaging`, `firebase_analytics`, `firebase_database`, `firebase_crashlytics`, `supabase_flutter`.
- [ ] Удалить `google-services.json`, `GoogleService-Info.plist`, firebase-инициализацию в Android/iOS.
- [ ] Замена Crashlytics (Sentry/самохост) и Analytics — решить (drop или альтернатива).
- [ ] Android-манифест: убрать FCM-сервис, добавить разрешения/декларацию foreground-сервиса.

### 8. Этап 5 — перенос ДАННЫХ (отдельно от кода)
- [ ] Экспорт Firebase → JSON (Auth `firebase auth:export`; Firestore; RTDB).
- [ ] Импорт в PB через `/api/batch` (включить, чанки ~1000); `users.id` = прежний uid; медиа-блобы перезалить в коллекцию `media`.
- [ ] Реверс медиа-ссылок gs://→pb://.

### 9. Релиз/выкат
- [ ] Обязательное обновление (как 1.14.7) — чтобы не было смешанных пар Firebase/PB.
- [ ] Правила доступа PB (listRule/viewRule/createRule) на коллекциях: сейчас null (только superuser) — открыть по аутентифицированному участнику группы перед публикой.
- [ ] Защита медиа (приватность пары): protected files + file-token PB вместо публичных URL.
- [ ] Firebase-проект НЕ удалять сразу — держать пару недель как откат.

### 10. Безопасность (до публики)
- [ ] PB rules на всех коллекциях (участник группы видит только свою группу).
- [ ] Сменить дефолтный пароль суперюзера PB; рассмотреть отключение password-auth для админки по IP.
