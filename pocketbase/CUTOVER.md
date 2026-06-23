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
- [x] `PocketBaseService().init()` + `PbAuthService().signInSilently()` на старте (additive, рядом с Firebase).
- [x] `Supabase.initialize` + `MigrationConfig` УБРАНЫ из `main.dart` (импорты `supabase_flutter`/`supabase_service`/`migration_config` тоже). Слой Supabase дремлет (`isReady=false` → все вызовы no-op), Firebase-путь работает.
- [x] Force-update порог → PocketBase (`PbDataService.fetchMinSupportedBuild`, коллекция `app_config.min_build`). Supabase-чтение убрано.
- [ ] **`Firebase.initializeApp` / `FirebaseCrashlytics` / `FirebaseMessaging` — НЕЛЬЗЯ убрать сейчас (это §7).** `FirebaseService` биндит `FirebaseAuth.instance`/`FirebaseFirestore.instance` как поля при конструировании (firebase_service.dart:77-78), а `UserData` строит `FirebaseService()` в поле → удаление init = МГНОВЕННЫЙ краш на старте (`No Firebase App`). Гейт: §3 (UserData/данные off Firebase) + §6 (coin-хуки `callGrant*`/`callPurchase*`). Crashlytics/Messaging держим для краш-репортинга/пуша до §5/§7.

### 2. Auth UI ✅
- [x] `login_screen.dart`, `setup_screen.dart` → `PbAuthService` (email/Google), профиль из `currentProfile()` (camelCase), регистрация через `signUpWithEmail` + `PbDataService.updateUserProfile`, аватар через `PbMediaService.uploadBytes` (`pb://`), сброс пароля через `requestPasswordReset`.
- [x] Кнопка «Войти через Apple» (iOS-gated) в обоих экранах + `PbAuthService.signInWithApple` (OAuth2 `apple`).
- Presence (`setOnlineStatus`) из экранов убран — переедет на PB-слой вместе с §3 (TODO в коде).

### 3. Данные/Realtime (главный объём — ~45 файлов)
- [~] Перевести все вызовы `FirebaseService().*` на `PbDataService`/`PbRealtimeService`. **СДЕЛАНО: ВОСПОМИНАНИЯ.** Новый `lib/services/memory_repository.dart` (PB-обёртка над PbData/PbRealtime, отдаёт модели). `memory_lane_screen` (+ части) и `home_screen`-превью переведены: read=live `watch`+`Memory.fromPb`, write add/update/delete/pin, комментарии `watchComments`/add/delete, личность `_myUid`=`PocketBaseService().userId`/`_myAvatar`. Медиа-загрузки (`_fb.uploadFile`) и резолв ОСТАЛИСЬ на Firebase (§4). +PbData: `createMemory`/`loadMemoryById`/`createComment`. analyze=0.
- [~] Остальные сущности — порядок из аудита (multi-agent, 2026-06-23): **miss_you ✅СДЕЛАНО** (`lib/services/miss_you_repository.dart`: watchCounts/sendMissYou/sendVibe; `miss_you_button` снят с `_fb` — личность `PocketBaseService().userId` починена (был баг: `_fb.uid` пуст → весь счётчик уходил «партнёру»); рейт-лимит вайбов сохранён, RateLimitException пробрасывается; **поведение: вайбы теперь инкрементят счётчик** — нужно для повторного пуша, missYouEvents-subcollection не портируется; `senderName` теперь неиспользуемый параметр) → **moods** → **mascots** → **chat** → **canvas** → **widget_data**; затем «забытые»: **solo timers → group timers** (есть колонки `timers`/`solo_timers`, но НЕТ PB-методов/watcher; беречь first-snapshot de-dupe — регресс [timer-first-snapshot]) → **active_session** (co-watch invite, json-колонка groups) → **rel-stats нативный виджет** (getGroup*Count). Группа/пары (ConnectionsManager) — гейт §6.
- [ ] **КРОСС-КАТТИНГ-БАГ (аудит): `_fb.uid`/`currentUser`/`displayName`/`avatarUrl` ПУСТЫ под PB** → латентные баги во ВСЕХ непереведённых сервисах (mood_service:214/361, widget_service:205/289/366/407/523/800, chat_service:61 + chat_screen:110, miss_you_button:143, recordGroupActivity, timer_service:43, together_session_service:134, live_location_service:66, live_map_card:55, watch_together:73, together_launcher:60/218). Чинить КАЖДЫЙ при переводе его сущности → `PocketBaseService().userId` / `PbAuthService().currentProfile()`. Не чинить в изоляции (сервис всё равно мёртв под PB, пока пишет в Firebase).
- [ ] **RTDB-фичи — НЕ переносить на PB, оставить на Firebase RTDB до конца** (аудит): presence, together-плеер+session-chat, live-location, typing — эфемерные/частые, завязаны на onDisconnect, которого в PB нет. Только починить личность (`_fb.uid`→PB), чтоб не молчали. Перенос транспорта — отдельная пост-cutover задача.
- [ ] **МЁРТВЫЙ КОД к удалению (не порт):** daily reflection (`saveReflectionAnswer`/`listenToTodayReflection` — 0 вызовов), emotion_migration (one-time legacy Firestore, станет no-op).
- АУДИТ памяти: 3 бага исправлены (SSE-утечка watchList/watchRecord при отписке-во-время-старта; потерянные XP `LevelService.award(addMemory)` и `logMemoryAdded`; + нит-фиксы: rating 0→null в add, fromPb jsonDecode-fallback, loadMemoryById/loadComments deleted-фильтр, deleteComment без лишнего lookup, мёртвое поле `fb` в _MemoryDetailSheet, self-avatar fast-path в home-превью). analyze=0.
- [~] Listeners Firestore + RTDB → стримы `PbRealtimeService`. Сделано для ленты (home `_startMemoryListener` → `MemoryRepository.watch`).
- [x] **Убрать кнопки «обновить» и лимиты/пагинацию** — В ЛЕНТЕ воспоминаний сделано (live, без `_loadNextPage`/`_refreshMemories`/cache-first; поля-заглушки). Остальные экраны — по мере перевода.
- [~] Модели — `fromPb`-конструкторы (RecordModel→модель, даты ISO/DateTime, пустой text PB `''`→null где nullable). **СДЕЛАНО:** `Memory` (через json-поле `data`+`fromJson`), `MoodEntry`, `MemoryComment`, `Mascot` (id из `mascot_id`), `WidgetData` (uid из `user_uid`). **ОСТАЛОСЬ:** `ChatMsg` (вместе с chat-срезом — семантика edited/deleted колонок), `Connection`/`GroupMember`/`MemberMood` (вместе с group-стримом — адаптер обратный `upsertGroupRaw`). `fromFirestore` НЕ трогаем (Firebase ещё жив).
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
