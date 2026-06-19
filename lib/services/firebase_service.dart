import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
// Transaction скрыт: коллизия имён с firebase_database (RTDB-транзакция в
// _seedMissYouCountsIfEmpty). Firestore-транзакции используют выводимый тип
// колбэка `(tx)`, поэтому имя Transaction из cloud_firestore тут не нужно.
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:home_widget/home_widget.dart';
import 'package:video_compress/video_compress.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/mascot.dart';
import '../models/memory.dart';
import '../models/comment.dart';
import '../models/timer_item.dart';
import 'analytics_service.dart';
import 'level_service.dart';
import 'locale_service.dart';
import 'nickname_service.dart';
import 'rate_limiter_service.dart';
import 'supabase_service.dart';
import 'chat_service.dart';
import '../config/migration_config.dart';

/// URL базы Realtime Database (регион europe-west1 — не дефолтный).
/// Presence (онлайн/lastSeen) живёт в RTDB, а не в Firestore: статус меняется
/// при каждом foreground/background, и хранение в users/{uid} стоило сотен
/// тысяч Firestore-чтений в день у партнёрских презенс-листенеров.
const String _kRtdbUrl =
    'https://togetherly-d4856-default-rtdb.europe-west1.firebasedatabase.app';

/// Единый сервис для работы с Firebase.
/// Поддерживает группы от 2 до 10 участников + совместные воспоминания.
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._();
  factory FirebaseService() => _instance;
  FirebaseService._() {
    // Stage 3: подтянуть per-group флаги «читать из Supabase» (поставлены в
    // прошлой сессии). Грузим один раз на старте — набор стабилен в течение
    // сессии, источник чтения не меняется в середине (без ребинда листенеров).
    unawaited(_loadReadSbGroups());
    // Как только появляется авторизованный пользователь (восстановление сессии
    // при старте ИЛИ свежий вход) — гарантируем Supabase-claim role=authenticated.
    // Без него RLS отклоняет все dual-write (см. ensureSupabaseRole).
    _auth.authStateChanges().listen((user) {
      if (user == null) {
        _supabaseRoleEnsured = false;
      } else {
        // Личность восстановлена/вошли → Supabase можно выдавать токен.
        _markAuthReady();
        unawaited(ensureSupabaseRole());
      }
    });
    // Разлогиненный юзер: непустого события не будет — не висим вечно, считаем
    // сессию отсутствующей через короткий грейс (idempotent, один раз).
    Future.delayed(const Duration(seconds: 2), _markAuthReady);
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  /// Realtime Database (presence). Регион europe-west1, см. [_kRtdbUrl].
  FirebaseDatabase get _rtdb =>
      FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: _kRtdbUrl);

  DatabaseReference _presenceRef(String uid) => _rtdb.ref('presence/$uid');

  /// Счётчики «Я скучаю» по группе. Живут в RTDB, а не в Firestore: фича — №1
  /// по нажатиям, и хранение счётчика в живо-слушаемом group-doc заставляло
  /// listenToPair/listenToMissYouCount пере-читать документ на каждый тап у
  /// обоих партнёров. Здесь только per-user счётчики; total = их сумма.
  /// Пуш-уведомления по-прежнему идут через Firestore missYouEvents → функцию.
  DatabaseReference _missYouCountsRef(String groupId) =>
      _rtdb.ref('missYou/$groupId/counts');

  /// Кеш участников группы из последнего [_parseGroupDoc]. Нужен, чтобы класть
  /// recipientUids прямо в missYouEvents и Cloud Function пуша не читала
  /// group-doc на каждый тап. Самовосстанавливается при любом изменении группы.
  final Map<String, List<String>> _groupMembersCache = {};

  /// Получатели пуша = участники группы из кеша минус отправитель.
  /// Пусто, если кеш ещё холодный — тогда функция читает group-doc сама.
  List<String> _cachedRecipients(String groupId, String senderUid) {
    final members = _groupMembersCache[groupId];
    if (members == null) return const [];
    return members.where((m) => m.isNotEmpty && m != senderUid).toList();
  }

  /// Группы, для которых уже выполнен (или запущен) разовый перенос счётчиков
  /// «Я скучаю» из Firestore в RTDB в этой сессии.
  final Set<String> _missYouSeeded = {};

  // SharedPreferences-ключ аддитивной миграции v2 (история: v2 защищалась
  // ТОЛЬКО этим локальным ключом — при переустановке, втором устройстве или
  // смене версии ключа legacy прибавлялся ПОВТОРНО, отсюда жалобы вида
  // «у партнёра счётчик за час вырос на 2к»). Оставлен только для чтения:
  // если ключ стоит, v2 на этом устройстве уже прибавила legacy.
  static const _kMissYouLegacyMigrated = 'miss_you_legacy_additive_v2';
  // Ключ одноразового force-overwrite Supabase из RTDB (Фаза 1).
  static const _kMissYouSbResync = 'miss_you_sb_resync_v2';
  // Ключ одноразовой миграции медиафайлов Firebase Storage → Supabase Storage.
  // v6: после добавления бэкфилла исторических данных в Supabase появляются
  // старые воспоминания/аватары — их медиа тоже нужно перенести, поэтому
  // media-проход обязан повториться один раз (новый ключ сбрасывает «готово»).
  static const _kMediaMigrationDone = 'supabase_media_migration_v6';
  // Ключ одноразового бэкфилла исторических ДАННЫХ (профиль/группа/воспоминания/
  // настроения/чат/комментарии/холсты), созданных ДО установки dual-write сборки.
  // v2: + комментарии; v3: + холсты (штрихи/мета/каталог); v4: + маскоты
  // (галерея + floating/streak group-поля) + статусы прочтения чата
  // (chat_reads) → форс повтора.
  static const _kDataBackfillDone = 'supabase_data_backfill_v4';
  // Числовые версии проходов — для СЕРВЕРНЫХ флагов (migration_flags в
  // Supabase). Должны совпадать с vN в ключах выше; при бампе ключа бампать
  // и константу — иначе серверный флаг подавит повторный проход.
  static const _kDataBackfillVersion = 4;
  static const _kMediaMigrationVersion = 6;
  // Ключ per-group флага Stage 3 «эту группу читаем из Supabase». Ставится в
  // ПРОШЛОЙ сессии _maybeMarkReadFromSupabase, когда оба партнёра на новой
  // сборке И бэкфилл (данные+медиа) завершён. Подхватывается на следующем
  // холодном старте (_readSbGroups) — источник чтения стабилен в течение сессии.
  static const _kReadFromSupabase = 'supabase_read_from_v1';

  /// Группы, для которых уже засеян Supabase-счётчик «Я скучаю» из RTDB в этой
  /// сессии (Фаза 1).
  final Set<String> _sbMissYouSeeded = {};

  /// Копирует RTDB-счётчики «Я скучаю» в Supabase.
  ///
  /// При первом запуске после деплоя (ключ [_kMissYouSbResync] не выставлен)
  /// делает force-overwrite (RTDB — источник истины), восстанавливая рассинхрон
  /// у пользователей, у которых .stream() не обновлял Supabase.
  /// Последующие запуски: max(supabase, rtdb) — не откатываем живые тапы.
  void _seedSupabaseMissYou(String groupId) {
    if (!_mig || groupId.isEmpty || _sbMissYouSeeded.contains(groupId)) return;
    _sbMissYouSeeded.add(groupId);
    SharedPreferences.getInstance().then((prefs) {
      final resyncKey = '$_kMissYouSbResync.$groupId';
      final needsForce = prefs.getBool(resyncKey) != true;
      _missYouCountsRef(groupId).get().then((snap) async {
        final counts = _parseMissYouCounts(snap.value);
        if (counts.isEmpty) return;
        await _sb.mirrorMissYouCountsFull(
          groupId,
          counts,
          forceOverwrite: needsForce,
        );
        if (needsForce) {
          await prefs.setBool(resyncKey, true);
          debugPrint('_seedSupabaseMissYou($groupId): force-resync done');
        }
      }).catchError((Object e) {
        debugPrint('_seedSupabaseMissYou failed: $e');
      });
      // Одновременно запускаем полный миграционный проход (данные + медиа).
      unawaited(_runSupabaseMigration(groupId));
    });
  }

  // ── Оркестратор полной миграции группы в Supabase ─────────────────────────

  /// Группы, по которым в этой сессии уже идёт миграционный проход — частые
  /// обращения к группе (listenToMissYou…) не должны запускать его повторно.
  final Set<String> _migrationInProgress = {};
  // Сколько раз проход повторялся в текущей сессии (защита от бесконечного цикла).
  final Map<String, int> _migrationRetryCount = {};
  // Группы с уже запланированным отложенным повтором (чтобы не плодить таймеры).
  final Set<String> _migrationRetryScheduled = {};
  // Группы с НЕзавершённой миграцией в этой сессии. Обработчики «сеть вернулась»
  // и «приложение на переднем плане» перебирают их, чтобы возобновить проход,
  // прерванный выходом из приложения или потерей сети.
  final Set<String> _migrationGroups = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  AppLifecycleListener? _migrationLifecycleListener;
  bool _migrationWatchersStarted = false;
  // Маркер «я мигрировал» уже записан в свой users-doc в этой сессии.
  bool _sbMigratedFlagWritten = false;
  // В этой сессии уже гарантировали claim role=authenticated (см.
  // ensureSupabaseRole) — повторно не дёргаем Cloud Function.
  bool _supabaseRoleEnsured = false;
  // In-flight операция выдачи claim. Дедупит параллельные вызовы (на старте
  // несколько Supabase-запросов зовут accessToken-колбэк разом).
  Future<void>? _roleEnsureInFlight;
  // Когда последняя попытка выдать claim провалилась. Пока кулдаун не вышел —
  // не дёргаем (возможно недеплоенную/падающую) Cloud Function на КАЖДЫЙ
  // запрос: иначе accessToken-колбэк вешал бы каждый Supabase-вызов на таймаут.
  // Деградация мягкая — запрос уходит как сейчас (фоновым ретраем), без блока.
  DateTime? _roleEnsureFailedAt;
  static const Duration _roleEnsureCooldown = Duration(minutes: 2);

  // Завершается, когда Firebase Auth восстановил сессию на старте (первое
  // непустое событие authStateChanges) ЛИБО истёк короткий грейс (юзер
  // разлогинен). accessToken-колбэк Supabase (main.dart) ждёт его ПЕРЕД выдачей
  // токена — иначе первые запросы холодного старта уходят анонимно (currentUser
  // ещё null) и RLS их отбивает (см. _write / «not a group member»).
  final Completer<void> _authReady = Completer<void>();
  Future<void> get authReady => _authReady.future;
  void _markAuthReady() {
    if (!_authReady.isCompleted) _authReady.complete();
  }

  /// Полный миграционный проход для группы: сначала бэкфилл исторических ДАННЫХ
  /// (профиль/группа/воспоминания/настроения/чат), затем медиафайлы.
  ///
  /// Свойства (цель — 0 риска потери данных):
  ///  • идемпотентность — всё через upsert, повтор безопасен;
  ///  • гонко-безопасность — один проход на группу за раз;
  ///  • самовосстановление — флаги «готово» ставятся ТОЛЬКО при 0 неудач; иначе
  ///    проход повторяется и при следующем обращении к группе, и через
  ///    нарастающую паузу в этой же сессии (без перезапуска приложения);
  ///  • порядок — медиа идёт ПОСЛЕ данных, т.к. media-проход читает воспоминания
  ///    из Supabase (бэкфилл должен сначала их туда положить).
  Future<void> _runSupabaseMigration(String groupId) async {
    if (!_mig || groupId.isEmpty) return;
    // Помечаем группу как «миграция не доведена» и поднимаем наблюдателей сети/
    // жизненного цикла — даже если этот конкретный проход сейчас не стартует.
    _migrationGroups.add(groupId);
    _ensureMigrationWatchers();
    if (_migrationInProgress.contains(groupId)) return;
    _migrationInProgress.add(groupId);
    try {
      final prefs = await SharedPreferences.getInstance();

      // ── 0. Серверные флаги (migration_flags в Supabase) ─────────────────────
      // Локальные prefs стираются при переустановке, а ПОВТОРНЫЙ бэкфилл после
      // Этапа 4 опасен: Firestore-копия устарела (правки/удаления идут только в
      // Supabase) — он затёр бы правки и воскресил удалённое. Если сервер
      // говорит «проход этой версии уже был» — восстанавливаем prefs и выходим.
      final dataKey = '$_kDataBackfillDone.$groupId';
      final mediaKey = '$_kMediaMigrationDone.$groupId';
      var dataDone = prefs.getBool(dataKey) == true;
      var mediaDone = prefs.getBool(mediaKey) == true;
      if (!dataDone || !mediaDone) {
        final server = await _sb.fetchMigrationFlags(groupId);
        if (server != null) {
          if (!dataDone && server.dataVersion >= _kDataBackfillVersion) {
            dataDone = true;
            await prefs.setBool(dataKey, true);
            debugPrint('[MIG] $groupId: data-бэкфилл уже выполнен (сервер)');
          }
          if (!mediaDone && server.mediaVersion >= _kMediaMigrationVersion) {
            mediaDone = true;
            await prefs.setBool(mediaKey, true);
            debugPrint('[MIG] $groupId: media-проход уже выполнен (сервер)');
          }
        }
      }

      // ── 1. Бэкфилл исторических данных ──────────────────────────────────────
      if (!dataDone) {
        final failures = await _backfillDataToSupabase(groupId);
        if (failures == 0) {
          await prefs.setBool(dataKey, true);
          dataDone = true;
          unawaited(_sb.markMigrationFlag(
            groupId,
            dataVersion: _kDataBackfillVersion,
          ));
          debugPrint('[MIG] data backfill($groupId): complete');
        } else {
          debugPrint(
            '[MIG] data backfill($groupId): $failures fail(s) — флаг НЕ ставим, повтор позже',
          );
        }
      }

      // ── 2. Медиа (только когда данные на месте) ─────────────────────────────
      if (dataDone && !mediaDone) {
        await _migrateMediaToSupabase(groupId);
        mediaDone = prefs.getBool(mediaKey) == true;
        if (mediaDone) {
          unawaited(_sb.markMigrationFlag(
            groupId,
            mediaVersion: _kMediaMigrationVersion,
          ));
        }
      }

      // Данные перенесены → помечаем себя «мигрировавшим» в users-doc:
      // по этому флагу сборки партнёров решают, нужен ли мост совместимости.
      if (dataDone) unawaited(_ensureSbMigratedFlag());

      if (dataDone && mediaDone) {
        _migrationRetryCount.remove(groupId);
        _migrationGroups.remove(groupId); // больше не возобновляем
        debugPrint('[MIG] $groupId: миграция полностью завершена');
        // Бэкфилл завершён → если оба партнёра на новой сборке, разрешить чтение
        // группы из Supabase со следующей сессии (Stage 3).
        unawaited(_maybeMarkReadFromSupabase(groupId));
      } else {
        _scheduleMigrationRetry(groupId);
      }
    } catch (e) {
      debugPrint('_runSupabaseMigration($groupId) failed: $e');
      _scheduleMigrationRetry(groupId);
    } finally {
      _migrationInProgress.remove(groupId);
    }
  }

  /// Помечает текущего пользователя «мигрировавшим» — пишет `sbMigrated` в свой
  /// users-doc (users-doc остаётся в Firestore при dual-write). По этому маркеру
  /// сборка партнёра в будущем решает, нужен ли «мост совместимости» (зеркалить
  /// его Firestore-записи в Supabase, пока он на старой сборке). Идемпотентно —
  /// пишем один раз за сессию; при сбое сбрасываем флаг для повтора.
  Future<void> _ensureSbMigratedFlag() async {
    if (_sbMigratedFlagWritten) return;
    final u = _auth.currentUser;
    if (u == null) return;
    _sbMigratedFlagWritten = true;
    try {
      await _db.collection('users').doc(u.uid).set(
        {'sbMigrated': true, 'sbMigratedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e) {
      _sbMigratedFlagWritten = false; // дать шанс повторить в следующий проход
      debugPrint('_ensureSbMigratedFlag failed: $e');
    }
  }

  /// Поднимает наблюдателей, которые ВОЗОБНОВЛЯЮТ прерванную миграцию без
  /// перезапуска приложения: (1) «сеть вернулась» — мгновенный ретрай; (2)
  /// «приложение снова на переднем плане» — добор миграции, которая могла
  /// прерваться выходом из приложения (скачивание оборвалось) или чьи отложенные
  /// таймеры ОС приостановила в фоне. Идемпотентно — стартует один раз за сессию.
  void _ensureMigrationWatchers() {
    if (_migrationWatchersStarted || !_mig) return;
    _migrationWatchersStarted = true;
    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (online) {
          _resumePendingMigrations(freshAttempt: true, reason: 'сеть вернулась');
        }
      });
    } catch (e) {
      debugPrint('[MIG] connectivity watcher failed: $e');
    }
    try {
      _migrationLifecycleListener = AppLifecycleListener(
        onResume: () =>
            _resumePendingMigrations(freshAttempt: true, reason: 'foreground'),
      );
    } catch (e) {
      debugPrint('[MIG] lifecycle watcher failed: $e');
    }
  }

  /// Возобновляет миграцию для всех групп с незавершённым проходом. [freshAttempt]
  /// сбрасывает счётчик сессионных повторов — событие (сеть/возврат в приложение)
  /// даёт «новую надежду», даже если лимит таймер-ретраев уже исчерпан.
  void _resumePendingMigrations({bool freshAttempt = false, String reason = ''}) {
    if (!_mig || _migrationGroups.isEmpty) return;
    debugPrint(
      '[MIG] возобновление ($reason): ${_migrationGroups.length} групп(ы)',
    );
    for (final g in _migrationGroups.toList()) {
      if (freshAttempt) _migrationRetryCount.remove(g);
      unawaited(_runSupabaseMigration(g));
    }
  }

  /// Планирует повтор прохода в этой же сессии с нарастающей паузой (2,4,6,8,10
  /// мин) — самовосстановление при временной потере сети без перезапуска. До 5
  /// повторов за сессию; дальше доберёт следующий холодный старт (флаги «готово»
  /// не выставлены, поэтому проход всё равно повторится при новом запуске).
  void _scheduleMigrationRetry(String groupId) {
    if (_migrationRetryScheduled.contains(groupId)) return;
    final n = _migrationRetryCount[groupId] ?? 0;
    if (n >= 5) return;
    _migrationRetryCount[groupId] = n + 1;
    _migrationRetryScheduled.add(groupId);
    Timer(Duration(minutes: (n + 1) * 2), () {
      _migrationRetryScheduled.remove(groupId);
      unawaited(_runSupabaseMigration(groupId));
    });
  }

  /// Однократный бэкфилл исторических данных группы Firebase → Supabase.
  /// Покрывает данные, созданные ДО установки dual-write сборки (их нет в
  /// зеркале — иначе при переходе на чтение из Supabase они бы «пропали»).
  /// Возвращает число неудачных операций (0 = можно ставить флаг «готово»).
  Future<int> _backfillDataToSupabase(String groupId) async {
    var failures = 0;
    try {
      // ── Группа (вкл. timers/mascots/статусы/даты) ──
      final groupSnap = await _db
          .collection('groups')
          .doc(groupId)
          .get()
          .timeout(const Duration(seconds: 15));
      if (!groupSnap.exists) {
        debugPrint('[MIG] backfill($groupId): group doc отсутствует — пропуск');
        return 0; // нечего переносить — не ошибка
      }
      final groupData = groupSnap.data() ?? <String, dynamic>{};
      // Этап 4: group-поля пишутся ТОЛЬКО в Supabase → Firestore-снимок группы
      // может быть устаревшим. Полный mirrorGroupRaw нужен лишь для
      // исторических групп, которых в Supabase ещё нет; существующую строку
      // не трогаем, чтобы не затереть свежие memberMoods/статус/таймеры.
      final existing = await _sb.fetchGroupColumns(groupId, ['id']);
      if (existing == null) {
        if (!await _sb.mirrorGroupRaw(groupId, groupData)) failures++;
      }

      final members = (groupData['members'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];

      // ── Свой профиль (партнёрский users/{uid} читать нельзя по правилам;
      //    партнёр зеркалит свой сам, а имя/аватар партнёра берутся из group). ──
      final myUid = uid;
      if (myUid != null && members.contains(myUid)) {
        try {
          final us = await _db
              .collection('users')
              .doc(myUid)
              .get()
              .timeout(const Duration(seconds: 10));
          final ud = us.data();
          if (ud != null && !await _sb.mirrorUser(myUid, ud)) failures++;
        } catch (e) {
          debugPrint('[MIG] backfill user $myUid failed: $e');
          failures++;
        }
      }

      // ── Воспоминания (пагинация) ──
      failures += await _backfillMemories(groupId);

      // ── Настроения ОБОИХ участников (months + legacy): Фаза-1 юзер читает
      //    настроения партнёра из Supabase, поэтому переносим всех. ──
      for (final m in members) {
        failures += await _backfillMoods(groupId, m);
      }

      // ── Чат (RTDB → Supabase) ──
      failures += await ChatService.instance.backfillToSupabase(groupId);

      // ── Холсты (штрихи + мета + каталог) ──
      failures += await _backfillCanvas(groupId);

      // ── Маскоты (галерея + floating/streak group-поля) ──
      failures += await _backfillMascots(groupId, groupData);
    } catch (e) {
      debugPrint('_backfillDataToSupabase($groupId) failed: $e');
      failures++;
    }
    return failures;
  }

  /// Переносит галерею маскотов (subcollection groups/{g}/mascots) и floating/
  /// streak-поля group-doc в Supabase. [groupData] — уже прочитанный Firestore
  /// group-doc. Возвращает число неудач.
  Future<int> _backfillMascots(
    String groupId,
    Map<String, dynamic> groupData,
  ) async {
    var failures = 0;
    try {
      // Галерея: subcollection → таблица mascots (docs хранят Mascot.toFirestore).
      final snap =
          await _mascotsRef(groupId).get().timeout(const Duration(seconds: 20));
      final rows = snap.docs
          .map((d) => Map<String, dynamic>.from(d.data())..['id'] = d.id)
          .where((m) => (m['id'] as String).isNotEmpty)
          .toList();
      if (rows.isNotEmpty && !await _sb.mirrorMascotsBatch(groupId, rows)) {
        failures++;
      }
      // Floating-маскот + streak: group-doc → колонки groups. ТОЧЕЧНЫЙ
      // mirrorGroupFields (НЕ mirrorGroupRaw — он затёр бы свежие горячие поля).
      final fields = <String, dynamic>{};
      if (groupData['activeMascotId'] != null) {
        fields['active_mascot_id'] = groupData['activeMascotId'];
      }
      final px = (groupData['mascotPositionX'] as num?)?.toDouble();
      final py = (groupData['mascotPositionY'] as num?)?.toDouble();
      final sc = (groupData['mascotScale'] as num?)?.toDouble();
      if (px != null) fields['mascot_position_x'] = px;
      if (py != null) fields['mascot_position_y'] = py;
      if (sc != null) fields['mascot_scale'] = sc;
      final sd = (groupData['streakDays'] as num?)?.toInt();
      if (sd != null) fields['streak_days'] = sd;
      final slod = groupData['streakLastOpenedDate'] as String?;
      if (slod != null) fields['streak_last_opened_date'] = slod;
      if (fields.isNotEmpty && !await _sb.mirrorGroupFields(groupId, fields)) {
        failures++;
      }
    } catch (e) {
      debugPrint('_backfillMascots($groupId) failed: $e');
      failures++;
    }
    return failures;
  }

  /// Переносит холсты группы (штрихи + мета + каталог) в Supabase. Эфемерные
  /// live-штрихи и presence НЕ переносятся. Возвращает число неудач.
  Future<int> _backfillCanvas(String groupId) async {
    var failures = 0;
    try {
      // Список канвасов: 'main' + каталог.
      final canvasIds = <String>{'main'};
      final cat = await _db
          .collection('groups')
          .doc(groupId)
          .collection('canvasCatalogue')
          .get()
          .timeout(const Duration(seconds: 20));
      for (final doc in cat.docs) {
        canvasIds.add(doc.id);
        final data = Map<String, dynamic>.from(doc.data())..['id'] = doc.id;
        if (!await _sb.mirrorCanvasCatalogue(groupId, doc.id, data)) failures++;
      }
      for (final canvasId in canvasIds) {
        // Штрихи (сам рисунок).
        final strokes = await _strokesRef(groupId, canvasId)
            .get()
            .timeout(const Duration(seconds: 25));
        for (final s in strokes.docs) {
          final sd = Map<String, dynamic>.from(s.data() as Map);
          if (!await _sb.mirrorStroke(groupId, canvasId, s.id, sd)) failures++;
        }
        // Мета (фон/clear/поворот).
        final metaSnap = await _canvasMainRef(groupId, canvasId)
            .get()
            .timeout(const Duration(seconds: 15));
        final md = metaSnap.data();
        if (md != null) {
          final bg = (md['bgColor'] as num?)?.toInt();
          final cv = (md['clearVersion'] as num?)?.toInt();
          final rot = (md['canvasRotation'] as num?)?.toInt();
          if ((bg != null || cv != null || rot != null) &&
              !await _sb.mirrorCanvasMeta(groupId, canvasId,
                  bgColor: bg, rotation: rot, clearVersion: cv)) {
            failures++;
          }
        }
      }
    } catch (e) {
      debugPrint('_backfillCanvas($groupId) failed: $e');
      failures++;
    }
    return failures;
  }

  /// Переносит ВСЕ воспоминания группы в Supabase порциями. Возвращает число
  /// неудачных upsert'ов (уже-перенесённые перезапишутся теми же значениями).
  Future<int> _backfillMemories(String groupId) async {
    var failures = 0;
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    const pageSize = 100;
    try {
      while (true) {
        var q = _db
            .collection('groups')
            .doc(groupId)
            .collection('memories')
            .orderBy('createdAt', descending: true)
            .limit(pageSize);
        if (cursor != null) q = q.startAfterDocument(cursor);
        final snap = await q.get().timeout(const Duration(seconds: 25));
        if (snap.docs.isEmpty) break;
        for (final doc in snap.docs) {
          if (!await _sb.mirrorMemory(groupId, doc.id, doc.data())) failures++;
          // Комментарии воспоминания (сабколлекция) — переносим вместе с ним.
          failures += await _backfillComments(groupId, doc.id);
        }
        cursor = snap.docs.last;
        if (snap.docs.length < pageSize) break;
      }
    } catch (e) {
      debugPrint('_backfillMemories($groupId) failed: $e');
      failures++;
    }
    return failures;
  }

  /// Переносит ВСЕ комментарии воспоминания [memoryId] в Supabase. Возвращает
  /// число неудач (пустая сабколлекция → 0, не ошибка).
  Future<int> _backfillComments(String groupId, String memoryId) async {
    var failures = 0;
    try {
      final snap = await _commentsRef(groupId, memoryId)
          .get()
          .timeout(const Duration(seconds: 15));
      for (final doc in snap.docs) {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        if (!await _sb.mirrorComment(groupId, memoryId, doc.id, data)) {
          failures++;
        }
      }
    } catch (e) {
      debugPrint('_backfillComments($groupId/$memoryId) failed: $e');
      failures++;
    }
    return failures;
  }

  /// Переносит ВСЕ настроения участника [memberUid] (новые month-документы +
  /// legacy-записи) в Supabase. Возвращает число неудач.
  Future<int> _backfillMoods(String groupId, String memberUid) async {
    var failures = 0;
    // Новый формат: groups/{g}/moodCalendar/{uid}/months/{YYYY-MM}.entries{}
    try {
      final months = await _moodMonthsCol(groupId, memberUid)
          .get()
          .timeout(const Duration(seconds: 20));
      for (final doc in months.docs) {
        for (final entry in _entriesFromMonthDoc(doc.data())) {
          if (entry['id'] == null) continue;
          if (!await _sb.mirrorMoodEntry(groupId, memberUid, entry)) failures++;
        }
      }
    } catch (e) {
      debugPrint('_backfillMoods months($groupId/$memberUid) failed: $e');
      failures++;
    }
    // Legacy: groups/{g}/moodCalendar/{uid}/entries/{id}
    try {
      final legacy = await _moodEntriesCol(groupId, memberUid)
          .get()
          .timeout(const Duration(seconds: 20));
      for (final doc in legacy.docs) {
        final e = Map<String, dynamic>.from(doc.data());
        e['id'] ??= doc.id;
        if (!await _sb.mirrorMoodEntry(groupId, memberUid, e)) failures++;
      }
    } catch (e) {
      debugPrint('_backfillMoods legacy($groupId/$memberUid) failed: $e');
      failures++;
    }
    return failures;
  }

  // ── Одноразовая миграция медиафайлов Firebase Storage → Supabase Storage ──

  // Префиксы Firebase Storage путей (для распознавания «голых» путей без схемы).
  static const _fbStoragePrefixes = [
    'memories/',
    'music/',
    'timer_backgrounds/',
    'widget/',
    'groups/',
    'avatars/',
    'wallpapers/',
  ];

  static bool _isFirebaseMediaUrl(String url) {
    if (url.isEmpty) return false;
    if (url.startsWith('sb://')) return false; // уже в Supabase
    return url.startsWith('gs://') ||
        url.contains('firebasestorage.googleapis.com') ||
        // «голый» storage-путь без схемы (старые записи): memories/gId/file.webp
        _fbStoragePrefixes.any(url.startsWith);
  }

  /// Извлекает storage-путь из Firebase URL.
  /// gs://bucket/memories/gId/file.webp → memories/gId/file.webp
  /// https://firebasestorage.../o/memories%2FgId%2Ffile.webp?... → memories/gId/file.webp
  /// memories/gId/file.webp → memories/gId/file.webp (голый путь как есть)
  static String? _fbUrlToStoragePath(String url) {
    if (url.startsWith('gs://')) {
      final parts = url.split('/');
      return parts.length >= 4 ? parts.sublist(3).join('/') : null;
    }
    // Голый путь без схемы
    if (_fbStoragePrefixes.any(url.startsWith)) {
      return url.split('?').first;
    }
    try {
      final uri = Uri.parse(url);
      final encoded = uri.queryParameters['o'];
      return encoded != null ? Uri.decodeComponent(encoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// Скачивает файл из Firebase Storage и загружает в Supabase Storage.
  /// Возвращает 'sb://' (или public https для avatars) ссылку или null.
  ///
  /// Два пути скачивания:
  ///  • https download-URL (с токеном ?alt=media&token=) → качаем по http,
  ///    токен даёт доступ в обход правил Storage (нужно для путей вроде
  ///    canvas/, которых нет в storage.rules → иначе getData = deny);
  ///  • gs:// или «голый» путь → через SDK getData (правила Storage разрешают
  ///    чтение участникам группы).
  /// Переносит один файл Firebase→Supabase. Возвращает запись:
  ///   `ref`  — 'sb://'/https-ссылка при успехе (иначе null);
  ///   `gone` — true, если файл в Firebase Storage отсутствует НАВСЕГДА
  ///            (object-not-found / HTTP 404). Тогда вызывающий ПРОПУСКАЕТ файл,
  ///            а не блокирует флип всей группы вечно. Прочие сбои (таймаут,
  ///            нет доступа, ошибка загрузки в Supabase) → gone=false (ретрай).
  Future<({String? ref, bool gone})> _migrateFbFileToSupabase(
    String fbUrl,
    String storagePath,
  ) async {
    try {
      // download-URL с токеном — самый надёжный путь (минует правила Storage).
      if (fbUrl.startsWith('http')) {
        final res = await _sb.migrateFileFromHttpUrl(fbUrl, storagePath);
        debugPrint(
          '[MIG] $storagePath → ${res.ref ?? (res.gone ? "GONE" : "FAILED")} (http)',
        );
        return res;
      }
      // gs:// или голый путь — через SDK (правила разрешают участникам группы).
      final ref = fbUrl.startsWith('gs://')
          ? _storage.refFromURL(fbUrl)
          : _storage.ref(fbUrl.split('?').first);
      final bytes = await ref
          .getData(100 * 1024 * 1024)
          .timeout(const Duration(minutes: 3));
      if (bytes == null || bytes.isEmpty) {
        debugPrint('[MIG] download empty for $storagePath');
        return (ref: null, gone: false);
      }
      final sbRef = await _sb.uploadStorageFile(bytes, storagePath);
      debugPrint('[MIG] $storagePath → ${sbRef ?? "FAILED"} (sdk)');
      return (ref: sbRef, gone: false);
    } on FirebaseException catch (e) {
      // Файл удалён в Firebase Storage → переносить нечего, не блокируем группу.
      final gone = e.code == 'object-not-found';
      debugPrint(
        '[MIG] _migrateFbFileToSupabase($storagePath) '
        '${gone ? "GONE (object-not-found) — пропуск" : "failed: ${e.code}"}',
      );
      return (ref: null, gone: gone);
    } catch (e) {
      debugPrint('[MIG] _migrateFbFileToSupabase($storagePath) failed: $e');
      return (ref: null, gone: false);
    }
  }

  /// Разовая фоновая миграция всех медиафайлов группы:
  /// Firebase Storage → Supabase Storage, обновление URL в Supabase.
  Future<void> _migrateMediaToSupabase(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final doneKey = '$_kMediaMigrationDone.$groupId';
    if (prefs.getBool(doneKey) == true) return;

    debugPrint('_migrateMediaToSupabase($groupId): started');

    // Считаем файлы, которые НЕ удалось перенести (скачать/загрузить). Флаг
    // «миграция завершена» выставляем только при 0 неудач — иначе повторим при
    // следующем запуске. Повтор дёшев: уже-sb:// пропускаются (_isFirebaseMediaUrl
    // = false), ретраятся только упавшие файлы.
    int failures = 0;

    // ── 1. Воспоминания ──────────────────────────────────────────────────────
    final memories = await _sb.fetchMemoriesForMigration(groupId);
    for (final row in memories) {
      final id = row['id'] as String? ?? '';
      if (id.isEmpty) continue;
      final rawData = row['data'];
      if (rawData is! Map) continue;
      final data = Map<String, dynamic>.from(rawData);
      bool changed = false;

      // Одиночные URL-поля
      for (final field in ['imageUrl', 'videoUrl', 'musicUrl', 'musicCoverUrl']) {
        final url = data[field] as String?;
        if (url == null || !_isFirebaseMediaUrl(url)) continue;
        final storagePath = _fbUrlToStoragePath(url);
        if (storagePath == null) continue;
        final res = await _migrateFbFileToSupabase(url, storagePath);
        if (res.ref != null) {
          data[field] = res.ref;
          changed = true;
        } else if (!res.gone) {
          failures++; // мёртвый файл (gone) пропускаем — не блокируем группу
        }
      }

      // Массив imageUrls
      final rawUrls = data['imageUrls'];
      if (rawUrls is List) {
        final migratedUrls = <dynamic>[];
        for (final item in rawUrls) {
          final url = item as String? ?? '';
          if (!_isFirebaseMediaUrl(url)) {
            migratedUrls.add(url);
            continue;
          }
          final storagePath = _fbUrlToStoragePath(url);
          if (storagePath == null) { migratedUrls.add(url); continue; }
          final res = await _migrateFbFileToSupabase(url, storagePath);
          migratedUrls.add(res.ref ?? url);
          if (res.ref != null) {
            changed = true;
          } else if (!res.gone) {
            failures++;
          }
        }
        if (changed) data['imageUrls'] = migratedUrls;
      }

      // author_avatar (Firebase Storage или Firebase Auth — мигрируем только Storage)
      String? newAuthorAvatar;
      final authorAvatar = row['author_avatar'] as String?;
      if (authorAvatar != null && _isFirebaseMediaUrl(authorAvatar)) {
        final storagePath = _fbUrlToStoragePath(authorAvatar) ??
            'avatars/unknown/avatar_${id.hashCode.abs()}.jpg';
        final res = await _migrateFbFileToSupabase(authorAvatar, storagePath);
        if (res.ref != null) {
          newAuthorAvatar = res.ref;
          changed = true;
        } else if (!res.gone) {
          failures++;
        }
      }

      if (changed) {
        // Если перезапись URL в Supabase не прошла — файл уже в Storage, но
        // строка указывает на мёртвый Firebase-URL: считаем неудачей и повторим.
        if (!await _sb.updateMemoryData(id, data,
            authorAvatar: newAuthorAvatar)) {
          failures++;
        }
      }
    }

    // ── 2. Аватарки участников группы ────────────────────────────────────────
    final group = await _sb.fetchGroupForMigration(groupId);
    if (group != null) {
      final rawAvatars = group['member_avatars'];
      if (rawAvatars is Map) {
        final newAvatars = <String, String>{};
        bool changed = false;
        for (final entry in rawAvatars.entries) {
          final uid = entry.key.toString();
          final url = (entry.value as String?) ?? '';
          if (_isFirebaseMediaUrl(url)) {
            final storagePath = 'avatars/$uid/profile${_extFromUrl(url)}';
            final res = await _migrateFbFileToSupabase(url, storagePath);
            if (res.ref != null) {
              newAvatars[uid] = res.ref!;
              changed = true;
              continue;
            } else if (!res.gone) {
              failures++;
            }
          }
          newAvatars[uid] = url;
        }
        if (changed) {
          if (!await _sb.updateGroupMemberAvatars(groupId, newAvatars)) {
            failures++;
          }
        }
      }

      // ── 2b. Маскоты (group.mascots[].imageUrl) ─────────────────────────────
      final rawMascots = group['mascots'];
      if (rawMascots is List) {
        final newMascots = <dynamic>[];
        bool changed = false;
        for (final item in rawMascots) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            final url = m['imageUrl'] as String?;
            if (url != null && _isFirebaseMediaUrl(url)) {
              final storagePath = _fbUrlToStoragePath(url);
              if (storagePath != null) {
                final res = await _migrateFbFileToSupabase(url, storagePath);
                if (res.ref != null) {
                  m['imageUrl'] = res.ref;
                  changed = true;
                } else if (!res.gone) {
                  failures++;
                }
              }
            }
            newMascots.add(m);
          } else {
            newMascots.add(item);
          }
        }
        if (changed) {
          if (!await _sb.updateGroupMascots(groupId, newMascots)) {
            failures++;
          }
        }
      }
    }

    // ── 3. Widget data ────────────────────────────────────────────────────────
    final widgetRows = await _sb.fetchWidgetDataForMigration(groupId);
    for (final row in widgetRows) {
      final userUid = row['user_uid'] as String? ?? '';
      if (userUid.isEmpty) continue;
      final updates = <String, String>{};

      const urlColumns = ['avatar_url', 'photo_url', 'music_url', 'music_cover_url'];

      for (final col in urlColumns) {
        final url = row[col] as String?;
        if (url == null || !_isFirebaseMediaUrl(url)) continue;
        final storagePath = _fbUrlToStoragePath(url);
        if (storagePath == null) continue;
        final res = await _migrateFbFileToSupabase(url, storagePath);
        if (res.ref != null) {
          updates[col] = res.ref!;
        } else if (!res.gone) {
          failures++; // мёртвый файл (gone) пропускаем — не блокируем группу
        }
      }

      if (updates.isNotEmpty) {
        if (!await _sb.updateWidgetDataUrls(groupId, userUid, updates)) {
          failures++;
        }
      }
    }

    // ── 4. Холсты: image-штрихи (Firestore-сабколлекция, НЕ Supabase) ─────────
    // Штрихи читаются из Firestore, поэтому обновлённый sb://-URL пишем обратно
    // в Firestore-док штриха. Перебираем все холсты группы (main + каталог).
    try {
      final canvasIds = <String>{'main'};
      final catalogue = await _db
          .collection('groups')
          .doc(groupId)
          .collection('canvasCatalogue')
          .get();
      for (final d in catalogue.docs) {
        canvasIds.add(d.id);
      }
      for (final canvasId in canvasIds) {
        final strokes = await _strokesRef(groupId, canvasId).get();
        for (final doc in strokes.docs) {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          final url = data['imageUrl'] as String?;
          if (url == null || !_isFirebaseMediaUrl(url)) continue;
          final storagePath = _fbUrlToStoragePath(url);
          if (storagePath == null) continue;
          final res = await _migrateFbFileToSupabase(url, storagePath);
          if (res.ref != null) {
            await updateDrawingStroke(
              groupId: groupId,
              strokeId: doc.id,
              updates: {'imageUrl': res.ref!},
              canvasId: canvasId,
            );
          } else if (!res.gone) {
            failures++; // мёртвый файл (gone) пропускаем — не блокируем группу
          }
        }
      }
    } catch (e) {
      debugPrint('_migrateMediaToSupabase($groupId): canvas step failed: $e');
      failures++; // не ставим флаг — повторим
    }

    if (failures == 0) {
      await prefs.setBool(doneKey, true);
      debugPrint('_migrateMediaToSupabase($groupId): completed!');
    } else {
      debugPrint(
        '_migrateMediaToSupabase($groupId): $failures файл(ов) не мигрировали '
        '— флаг НЕ ставим, повтор при следующем запуске',
      );
    }
  }

  static String _extFromUrl(String url) {
    final lower = url.toLowerCase().split('?').first;
    for (final ext in [
      '.webp', '.jpg', '.jpeg', '.png',
      '.mp4', '.mov', '.mp3', '.aac', '.m4a', '.wav',
    ]) {
      if (lower.endsWith(ext)) return ext;
    }
    return '.jpg';
  }

  /// Переносит старый Firestore-счётчик «Я скучаю» текущего пользователя в RTDB.
  ///
  /// История проблем:
  /// 1. v1 (seed-if-empty): транзакция прерывалась если RTDB != null —
  ///    legacy-тапы терялись, счётчик «сбрасывался» после обновления.
  /// 2. v2 (аддитивная): RTDB += legacy, но guard — локальный ключ в
  ///    SharedPreferences. Переустановка / второе устройство / новая версия
  ///    ключа → legacy прибавлялся повторно, счётчик раздувался.
  ///
  /// v3: маркер миграции живёт в самой RTDB (missYou/{groupId}/seeded/{uid},
  /// write-once по правилам базы) и пишется ОДНИМ атомарным multi-path update
  /// вместе с инкрементом counts/{uid}. Если маркер уже стоит — правила
  /// отклоняют весь update целиком, т.е. повторное прибавление невозможно ни
  /// при каком сценарии (переустановка, несколько устройств, гонка, будущие
  /// версии). Если на этом устройстве v2 уже прибавила legacy (стоит
  /// prefs-ключ), записываем только маркер — без прибавления.
  Future<void> _seedMissYouCountsIfEmpty(String groupId, Map raw) async {
    final myUid = uid;
    if (myUid == null) return;
    final mine = (raw[myUid] as num?)?.toInt() ?? 0;
    if (mine <= 0) return;
    try {
      // Маркер уже стоит (поставлен любым устройством) — миграция завершена.
      final seededSnap =
          await _rtdb.ref('missYou/$groupId/seeded/$myUid').get();
      if (seededSnap.exists) return;

      final prefs = await SharedPreferences.getInstance();
      final v2AlreadyAdded =
          prefs.getBool('$_kMissYouLegacyMigrated.$groupId.$myUid') == true;

      // Атомарный multi-path update: маркер + инкремент применяются вместе
      // или не применяются вовсе. seeded/{uid} write-once по правилам, поэтому
      // проигравший гонку получит permission-denied на ВЕСЬ update.
      await _rtdb.ref('missYou/$groupId').update({
        'seeded/$myUid': mine,
        if (!v2AlreadyAdded) 'counts/$myUid': ServerValue.increment(mine),
      });
      debugPrint(
        '_seedMissYouCountsIfEmpty($groupId): legacy=$mine for $myUid, '
        'addedNow=${!v2AlreadyAdded}',
      );
    } catch (e) {
      // permission-denied = гонка с другим устройством, уже мигрировано.
      debugPrint('_seedMissYouCountsIfEmpty skipped/failed: $e');
    }
  }

  // In-memory cache — eliminates repeated users/{uid} reads on hot paths.
  String? _cachedDisplayName;
  String? _cachedAvatarUrl;

  // Ref-counted, multiplexed snapshot listeners for hot single-doc paths.
  // Each group doc had 4+ independent snapshot subscriptions
  // (listenToPair / listenToTimers / listenToMissYouCount / listenToMissYouCounts /
  //  listenToCanvasBgColor + ...). Firestore meters each subscription separately,
  // so a single field change was billed 4+ times. The hub keeps ONE underlying
  // snapshot per groupId and fans the data out to every consumer.
  final Map<String, _DocSnapshotHub> _groupDocHubs = {};
  final Map<String, _DocSnapshotHub> _userDocHubs = {};

  Stream<DocumentSnapshot<Map<String, dynamic>>> _groupDocStream(
    String groupId,
  ) {
    return _groupDocHubs
        .putIfAbsent(
          groupId,
          () => _DocSnapshotHub(_db.collection('groups').doc(groupId)),
        )
        .stream;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream(String uid) {
    return _userDocHubs
        .putIfAbsent(
          uid,
          () => _DocSnapshotHub(_db.collection('users').doc(uid)),
        )
        .stream;
  }

  // ══════════════════════════════════════════════
  //  AUTH
  // ══════════════════════════════════════════════

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;

  // ══════════════════════════════════════════════
  //  МИГРАЦИЯ Supabase (Фаза 1)
  // ══════════════════════════════════════════════

  final SupabaseService _sb = SupabaseService();

  /// true — текущий пользователь участвует в Фазе 1 миграции:
  /// его данные зеркалятся в Supabase (dual-write) и читаются оттуда.
  bool get _mig =>
      MigrationConfig.isConfigured &&
      MigrationConfig.isPhase1User(_auth.currentUser?.email);

  // ── Гейты постепенного переезда (Stage 2) ────────────────────────────────
  // Старые версии партнёра продолжают работать. Принцип:
  //   • ЗАПИСЬ — в ОБА склада: Firebase (источник истины) + зеркало в Supabase.
  //     Так старый билд партнёра (читает Firebase) видит данные, а Supabase
  //     копит полную копию без риска потери.
  //   • ЧТЕНИЕ — из Firebase, пока вся группа не на новой сборке. Иначе новый
  //     билд не увидит записи партнёра со старой версии (тот пишет в Firebase).
  // Переключение чтения на Supabase (экономия) — Stage 3, отдельно и после
  // прогона на устройстве, см. _readSb.

  /// Дублировать запись в Supabase (поверх обязательной записи в Firebase).
  bool get _dualWrite => _mig;

  /// Группы, по которым в ПРОШЛОЙ сессии подтверждено: оба партнёра на новой
  /// сборке + бэкфилл (данные+медиа) завершён → читаем из Supabase (Stage 3).
  /// Загружается из prefs на старте ([_loadReadSbGroups]) и НЕ меняется в
  /// течение сессии: источник чтения переключается только на следующей сессии,
  /// без mid-session ребинда листенеров (защита от потери сообщений из рунбука).
  final Set<String> _readSbGroups = {};

  /// Подтягивает per-group флаги Stage 3 из prefs (ключи [_kReadFromSupabase]).
  Future<void> _loadReadSbGroups() async {
    if (!MigrationConfig.stage3ReadFromSupabase) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = '$_kReadFromSupabase.';
      for (final key in prefs.getKeys()) {
        if (key.startsWith(prefix) && prefs.getBool(key) == true) {
          _readSbGroups.add(key.substring(prefix.length));
        }
      }
      if (_readSbGroups.isNotEmpty) {
        debugPrint('[STAGE3] чтение из Supabase: ${_readSbGroups.length} групп(ы)');
      }
    } catch (e) {
      debugPrint('_loadReadSbGroups failed: $e');
    }
  }

  /// Можно ли ЧИТАТЬ эту группу из Supabase (Stage 3). True ТОЛЬКО когда мастер-
  /// флаг включён, юзер мигрирует и группа была помечена в ПРОШЛОЙ сессии
  /// (_readSbGroups — оба партнёра на новой сборке + бэкфилл завершён). Иначе
  /// читаем из Firebase (общий источник, дуал-райт держит его актуальным —
  /// безопасный дефолт; пустой groupId/per-user чтения никогда не флипаются).
  bool _readSb(String groupId) =>
      MigrationConfig.stage3ReadFromSupabase &&
      _mig &&
      groupId.isNotEmpty &&
      _readSbGroups.contains(groupId);

  /// Публичный маршрутизатор чтения для сервисов (ChatService / WidgetService /
  /// HomeWidgetService): читать ли ресурс группы из Supabase. См. [_readSb].
  bool readFromSupabase(String groupId) => _readSb(groupId);

  /// Нужно ли ПИСАТЬ данные группы в Firebase (Stage 4). По умолчанию да. Когда
  /// мастер-флаг включён И группа уже читается из Supabase (полностью мигрирована)
  /// — нет: данные пишутся только в Supabase, Firebase-запись избыточна.
  /// Пустой groupId / не-мигрированная группа → всегда true (безопасный дефолт).
  /// ВАЖНО: НЕ распространяется на членство/события/users-doc/RTDB — те пишутся
  /// в Firebase безусловно (их читают пуш-функции и Auth).
  ///
  /// Доп. гейт `_groupBothRead`: Firebase-запись срезается ТОЛЬКО когда ОБА
  /// партнёра уже читают из Supabase. Пока второй ещё читает Firebase (окно
  /// перехода — телефоны флипают в разные сессии), мы продолжаем писать в
  /// Firebase, иначе он не увидит наши изменения (рисунки/чат/память). Так у
  /// полностью мигрированной пары дуал-райта нет, а на время перехода держится
  /// мост — без потери синхронизации.
  bool _writeFb(String groupId) =>
      !(MigrationConfig.stage4DropFirebaseWrites &&
          _readSb(groupId) &&
          (_groupBothRead[groupId] ?? false));

  /// Публично для сервисов (ChatService): писать ли данные группы в Firebase.
  bool writeToFirebase(String groupId) => _writeFb(groupId);

  /// Извлекает groupId из storage-пути группового медиа. Для ВСЕХ групповых
  /// префиксов (memories/, music/, timer_backgrounds/, widget/, groups/) groupId —
  /// второй сегмент пути. Негрупповые пути (avatars/ — per-user) → null.
  String? _groupIdFromStoragePath(String path) {
    final parts = path.split('/');
    if (parts.length < 2 || parts[1].isEmpty) return null;
    switch (parts[0]) {
      case 'memories':
      case 'music':
      case 'timer_backgrounds':
      case 'widget':
      case 'groups':
        return parts[1];
      default:
        return null; // avatars/ и прочее — не групповое
    }
  }

  /// Куда писать НОВОЕ медиа группы: в Supabase, если группа ПОЛНОСТЬЮ
  /// мигрирована (тот же гейт, что у данных — `!_writeFb`, т.е. Stage 4 активен
  /// и оба партнёра на новой сборке). Медиа флипается синхронно с данными, чтобы
  /// откат оставался согласованным. Негрупповые пути (аватары) и
  /// не-мигрированные/смешанные группы → Firebase (общий источник).
  bool _uploadGroupMediaToSupabase(String storagePath) {
    final gid = _groupIdFromStoragePath(storagePath);
    return gid != null && !_writeFb(gid);
  }

  /// Помечает группу «со следующей сессии читать из Supabase» — ТОЛЬКО когда
  /// compat-резолв подтвердил, что оба партнёра на новой сборке
  /// (`_groupMixed[groupId] == false`, т.е. РАЗРЕШЕНО и не смешанная), И бэкфилл
  /// данных+медиа завершён. Флаг персистится и подхватывается на следующем
  /// холодном старте ([_readSbGroups]) — источник чтения не меняется в середине
  /// сессии. Регресс (партнёр откатился/переустановил → снова смешанная) снимает
  /// флаг, и следующая сессия безопасно вернётся на чтение из Firebase.
  Future<void> _maybeMarkReadFromSupabase(String groupId) async {
    if (!_mig || groupId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kReadFromSupabase.$groupId';
      final eligible = _groupMixed[groupId] == false &&
          prefs.getBool('$_kDataBackfillDone.$groupId') == true &&
          prefs.getBool('$_kMediaMigrationDone.$groupId') == true;
      if (eligible) {
        if (prefs.getBool(key) != true) {
          await prefs.setBool(key, true);
          debugPrint('[STAGE3] $groupId: следующая сессия читает из Supabase');
        }
      } else if (prefs.getBool(key) == true) {
        await prefs.remove(key);
        debugPrint('[STAGE3] $groupId: чтение возвращено на Firebase (регресс)');
      }
    } catch (e) {
      debugPrint('_maybeMarkReadFromSupabase($groupId) failed: $e');
    }
  }

  /// Публичный гейт миграции — нужен другим сервисам (WidgetService /
  /// HomeWidgetService), чтобы маршрутизировать чтения widget_data в Supabase.
  bool get isMigrationUser => _mig;

  // ── Совместимость со старым билдом партнёра (смешанные пары) ──────────────
  // Группа использует Supabase как источник правды ТОЛЬКО когда ОБА партнёра
  // на новой сборке. Пока партнёр на старой версии — группа держится на
  // Firebase (старый билд её там читает/пишет), чтобы пара видела друг друга и
  // ничего не терялось; как только партнёр обновится — на следующей сессии
  // группа докатывается в Supabase и переключается.
  //
  // Маркер новой сборки: group-doc.sbMig[uid] = serverTimestamp, обновляется
  // при каждом listenToPair. Старый билд маркер не пишет → его отсутствие или
  // устаревание = «партнёр на старой версии». Маркер живёт в group-doc, т.к.
  // его читают ОБА участника (users/{uid} партнёра читать нельзя по правилам).
  static const int _kMarkerFreshDays = 21;
  // groupId → партнёр на старом билде (true = смешанная пара, держим Firebase).
  // Безопасный дефолт — отсутствие записи (== не смешанная) равно текущему
  // поведению (_mig), поэтому существующие пары НЕ регрессируют.
  final Map<String, bool> _groupMixed = {};
  final Set<String> _groupCompatResolving = {};

  // groupId → ОБА партнёра уже ЧИТАЮТ из Supabase (по свежести маркеров sbRead
  // в group-doc). Гейтит Stage 4 в [_writeFb]: пока второй партнёр ещё читает
  // Firebase, мы ПРОДОЛЖАЕМ писать туда (иначе он не увидит наши изменения);
  // как только оба на Supabase — Firebase-запись прекращается. Безопасный
  // дефолт — отсутствие записи (== не оба, держим Firebase-запись).
  final Map<String, bool> _groupBothRead = {};

  /// Группа полностью на новой сборке — можно Supabase как источник.
  /// Дефолт безопасный: пока НЕ доказано, что партнёр на старом билде, ведём
  /// себя как раньше (== `_mig`). НЕ используется для маршрутизации, пока не
  /// будет провалидирован флип на запущенном приложении (см. _resolveGroupCompat).
  bool migGroupFull(String groupId) => _mig && !(_groupMixed[groupId] ?? false);

  /// Пишет свой маркер «я на новой сборке» в group-doc и определяет, на новой
  /// ли сборке партнёр (по свежести маркеров всех участников). Раз за сессию на
  /// группу. Когда смешанная пара становится полной (партнёр обновился) —
  /// докатывает миграцию (_runSupabaseMigration) для следующей сессии.
  Future<void> _resolveGroupCompat(String groupId) async {
    if (!_mig || groupId.isEmpty) return;
    if (_groupCompatResolving.contains(groupId)) return;
    _groupCompatResolving.add(groupId);
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      // 1. Помечаем себя «на новой сборке». Если в ЭТОЙ сессии мы уже читаем из
      //    Supabase — дополнительно пишем маркер sbRead, чтобы партнёр узнал и
      //    (когда перейдут оба) безопасно прекратил Firebase-запись (Stage 4).
      final markers = <String, dynamic>{
        'sbMig': {uid: FieldValue.serverTimestamp()},
      };
      if (_readSb(groupId)) {
        markers['sbRead'] = {uid: FieldValue.serverTimestamp()};
      }
      await _db
          .collection('groups')
          .doc(groupId)
          .set(markers, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
      // 2. Читаем маркеры всех участников.
      final doc = await _db
          .collection('groups')
          .doc(groupId)
          .get()
          .timeout(const Duration(seconds: 10));
      final data = doc.data();
      if (data == null) return;
      final members = (data['members'] as List?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList() ??
          const <String>[];
      final sbMig = Map<String, dynamic>.from(data['sbMig'] ?? {});
      final now = DateTime.now();
      var allFresh = members.isNotEmpty;
      for (final m in members) {
        final ts = sbMig[m];
        final dt = ts is Timestamp ? ts.toDate() : null;
        if (dt == null || now.difference(dt).inDays > _kMarkerFreshDays) {
          allFresh = false;
          break;
        }
      }
      final wasMixed = _groupMixed[groupId] ?? false;
      _groupMixed[groupId] = !allFresh;

      // Оба ли партнёра уже ЧИТАЮТ из Supabase (свежесть маркеров sbRead). Пока
      // не оба — Stage 4 не срезает Firebase-запись (см. [_writeFb]): партнёр,
      // ещё читающий Firebase, должен видеть наши изменения.
      final sbRead = Map<String, dynamic>.from(data['sbRead'] ?? {});
      var allRead = members.isNotEmpty;
      for (final m in members) {
        final ts = sbRead[m];
        final dt = ts is Timestamp ? ts.toDate() : null;
        if (dt == null || now.difference(dt).inDays > _kMarkerFreshDays) {
          allRead = false;
          break;
        }
      }
      _groupBothRead[groupId] = allRead;
      // Compat подтверждён → пере-оценить право группы читать из Supabase
      // (применится со следующей сессии). Снимет флаг, если пара снова смешанная.
      unawaited(_maybeMarkReadFromSupabase(groupId));
      if (allFresh && wasMixed) {
        // Партнёр обновился → докатываем его данные в Supabase, переключение
        // источника применится на следующей сессии (без mid-session ребинда).
        debugPrint('[COMPAT] $groupId: партнёр обновился → докат миграции');
        unawaited(_runSupabaseMigration(groupId));
      }
      debugPrint(
        '[COMPAT] $groupId: ${allFresh ? "оба на новой сборке" : "партнёр на старой → bridge"}',
      );
    } catch (e) {
      debugPrint('_resolveGroupCompat($groupId) failed: $e');
    } finally {
      _groupCompatResolving.remove(groupId);
    }
  }

  /// Cached display name — use this instead of reading users/{uid} from Firestore.
  String get displayName =>
      _cachedDisplayName ?? _auth.currentUser?.displayName ?? '';

  /// Cached avatar URL — always reflects the latest save, even before Firestore syncs.
  String get avatarUrl => _cachedAvatarUrl ?? _auth.currentUser?.photoURL ?? '';

  Future<User?> signInWithGoogle() async {
    try {
      final googleAccount = await _googleSignIn.signIn().timeout(
        const Duration(seconds: 30),
      );
      if (googleAccount == null) return null;

      final googleAuth = await googleAccount.authentication.timeout(
        const Duration(seconds: 15),
      );
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      debugPrint('Firebase Auth: signing in...');
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      debugPrint('Firebase Auth success: ${user.uid}');

      try {
        await _db
            .collection('users')
            .doc(user.uid)
            .set({
              'displayName': user.displayName ?? '',
              'email': user.email ?? '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Firestore save failed: $e');
      }

      return user;
    } catch (e) {
      debugPrint('signInWithGoogle failed: $e');
      rethrow;
    }
  }

  /// Создание аккаунта через email/пароль.
  ///
  /// Устойчиво к медленным/нестабильным соединениям (частый кейс из России —
  /// VPN, троттлинг, потери пакетов):
  ///  • увеличенный таймаут;
  ///  • повтор при временных сетевых сбоях (`network-request-failed` и т.п.);
  ///  • если таймаут случился ПОСЛЕ фактического создания аккаунта на сервере —
  ///    подхватываем уже залогиненного пользователя вместо падения;
  ///  • если прошлая попытка успела создать аккаунт (`email-already-in-use`),
  ///    а пользователь ввёл тот же пароль — молча входим в этот аккаунт,
  ///    завершая «зависшую» регистрацию (раньше человек оставался заблокирован).
  Future<User?> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    const transientCodes = {
      'network-request-failed',
      'internal-error',
      'timeout',
    };
    FirebaseAuthException? lastTransient;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
      try {
        debugPrint('Firebase Auth: creating account with email...');
        User? user;
        try {
          final userCredential = await _auth
              .createUserWithEmailAndPassword(email: email, password: password)
              .timeout(const Duration(seconds: 30));
          user = userCredential.user;
        } on TimeoutException {
          // Ответ сервера не успел прийти за таймаут, но аккаунт мог уже
          // создаться, и SDK нередко уже обновил currentUser. Если это так —
          // считаем регистрацию успешной, иначе пробуем ещё раз.
          final current = _auth.currentUser;
          if (current != null && current.email == email) {
            user = current;
          } else {
            lastTransient = FirebaseAuthException(code: 'timeout');
            continue;
          }
        }

        user ??= _auth.currentUser;
        if (user == null) return null;

        await _finishEmailSignUp(user, email: email, displayName: displayName);
        debugPrint('Firebase Auth success: ${user.uid}');
        return _auth.currentUser;
      } on FirebaseAuthException catch (e) {
        // Прошлая (возможно недозавершённая из-за обрыва) попытка уже создала
        // аккаунт. Пользователь ввёл пароль — пробуем войти им же: успех = это
        // его аккаунт, восстанавливаемся; неудача = чужой email, отдаём ошибку.
        if (e.code == 'email-already-in-use') {
          try {
            final cred = await _auth
                .signInWithEmailAndPassword(email: email, password: password)
                .timeout(const Duration(seconds: 30));
            final user = cred.user;
            if (user != null) {
              await _finishEmailSignUp(
                user,
                email: email,
                displayName: displayName,
              );
              debugPrint('signUp recovered via sign-in: ${user.uid}');
              return _auth.currentUser;
            }
          } catch (_) {
            // Пароль не подошёл — это чужой аккаунт. Пробрасываем исходную
            // ошибку, чтобы UI показал диалог «аккаунт уже существует».
          }
          rethrow;
        }
        if (transientCodes.contains(e.code)) {
          lastTransient = e;
          debugPrint('signUp transient error ${e.code}, retrying...');
          continue;
        }
        debugPrint('signUpWithEmailPassword failed: $e');
        rethrow;
      } catch (e) {
        debugPrint('signUpWithEmailPassword failed: $e');
        rethrow;
      }
    }

    // Все попытки исчерпаны на временных сетевых сбоях.
    throw lastTransient ??
        FirebaseAuthException(code: 'network-request-failed');
  }

  /// Дописывает профиль после успешного создания/входа email-аккаунта:
  /// displayName в Firebase Auth + базовый user-документ. Ошибки записи в
  /// Firestore не считаем фатальными — аккаунт уже создан.
  Future<void> _finishEmailSignUp(
    User user, {
    required String email,
    required String displayName,
  }) async {
    try {
      if ((user.displayName ?? '') != displayName) {
        await user.updateDisplayName(displayName);
        await user.reload();
      }
    } catch (e) {
      debugPrint('updateDisplayName failed: $e');
    }
    try {
      await _db
          .collection('users')
          .doc(user.uid)
          .set({
            'displayName': displayName,
            'email': email,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Firestore save failed: $e');
    }
  }

  /// Вход через email/пароль
  Future<User?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('Firebase Auth: signing in with email...');
      final userCredential = await _auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));
      return userCredential.user;
    } catch (e) {
      debugPrint('signInWithEmailPassword failed: $e');
      rethrow;
    }
  }

  /// Отправляет письмо для сброса пароля на указанный email.
  /// Бросает исключение при ошибке (вызывающий показывает текст пользователю).
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth
        .sendPasswordResetEmail(email: email)
        .timeout(const Duration(seconds: 15));
  }

  Future<void> signOut() async {
    try {
      await setOnlineStatus(false);
    } catch (_) {}
    _disposePresenceWatcher();
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (_) {}
    await _auth.signOut();
    // Следующий пользователь должен заново гарантировать свой claim role.
    _supabaseRoleEnsured = false;
  }

  /// Тихий вход без показа диалога Google.
  /// Восстанавливает сессию при перезапуске приложения:
  /// сначала проверяет кэш Firebase Auth, затем пробует GoogleSignIn.signInSilently().
  Future<User?> signInSilently() async {
    try {
      // Firebase Auth уже авторизован — возвращаем текущего пользователя
      final current = _auth.currentUser;
      if (current != null) return current;

      // Пробуем восстановить Google-аккаунт без диалога
      final googleAccount = await _googleSignIn.signInSilently();
      if (googleAccount == null) return null;

      final googleAuth = await googleAccount.authentication.timeout(
        const Duration(seconds: 15),
      );
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      debugPrint('signInSilently success: ${userCredential.user?.uid}');
      return userCredential.user;
    } catch (e) {
      debugPrint('signInSilently failed: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // Local notifications plugin (for foreground FCM)
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localNotificationsInitialized = false;
  static const String _kChannelId = 'miss_you';
  static const String _kChannelName = 'Скучаю';

  /// groupId чата, открытого прямо сейчас на экране (или null). Пока пользователь
  /// смотрит этот чат, foreground-уведомление о новом сообщении не показываем —
  /// он его и так видит. В фоновом изолите это поле всегда null, поэтому
  /// фоновые пуши не подавляются.
  static String? activeChatGroupId;
  // ─────────────────────────────────────────────

  /// Инициализация FCM: запрашиваем разрешение и сохраняем токен.
  Future<void> initFCM() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Настраиваем локальные уведомления и канал Android
      await _initLocalNotifications();

      final token = await messaging.getToken();
      if (token != null) await _saveFcmToken(token);

      // Обновляем токен при ротации
      messaging.onTokenRefresh.listen(_saveFcmToken);

      // Сохраняем токен после входа (для новых пользователей, у которых токен ещё не сохранён)
      _auth.authStateChanges().listen((user) async {
        if (user != null) {
          final t = await messaging.getToken();
          if (t != null) await _saveFcmToken(t);
        }
      });

      // Обрабатываем сообщения пока приложение открыто (foreground)
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    } catch (e) {
      debugPrint('initFCM failed: $e');
    }
  }

  static Future<void> _initLocalNotifications() async {
    if (_localNotificationsInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(settings: initSettings);

    // Создаём канал уведомлений для Android 8+
    const channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: 'Уведомления от партнёра',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    _localNotificationsInitialized = true;
  }

  /// Ключи SharedPreferences для настроек уведомлений (совпадают с ProfileScreen)
  static const _kNotifMissYou = 'notif_miss_you';
  static const _kNotifNewMemory = 'notif_new_memory';
  static const _kNotifMood = 'notif_mood';
  static const _kNotifChat = 'notif_chat';

  /// Сохраняет настройку уведомлений в Firestore, чтобы Cloud Functions
  /// могли проверять её перед отправкой push-уведомлений.
  Future<void> updateNotifPrefs({
    bool? missYou,
    bool? newMemory,
    bool? mood,
    bool? chat,
  }) async {
    final u = currentUser;
    if (u == null) return;
    final updates = <String, dynamic>{};
    if (missYou != null) updates['notifMissYou'] = missYou;
    if (newMemory != null) updates['notifNewMemory'] = newMemory;
    if (mood != null) updates['notifMood'] = mood;
    if (chat != null) updates['notifChat'] = chat;
    if (updates.isEmpty) return;
    try {
      await _db
          .collection('users')
          .doc(u.uid)
          .set(updates, SetOptions(merge: true));
      // Зеркалим настройку «Я скучаю» в RTDB — функция пуша читает её оттуда
      // вместе с токенами, без Firestore-чтения.
      if (missYou != null) {
        try {
          await _rtdb.ref('push/${u.uid}/notifMissYou').set(missYou);
        } catch (e) {
          debugPrint('updateNotifPrefs RTDB mirror failed: $e');
        }
      }
    } catch (e) {
      debugPrint('updateNotifPrefs failed: \$e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) async {
    final shouldShow = await _shouldShowNotification(message);
    if (!shouldShow) return;

    final content = await _buildLocalNotificationContent(message);
    if (content == null) return;

    await _showLocalNotification(
      id: _notificationIdFor(message),
      title: content.title,
      body: content.body,
      channelId: _channelIdFor(message),
    );
  }

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    if (message.data['type'] == 'widget_update') {
      await _handleWidgetUpdateMessage(message);
      return;
    }

    final shouldShow = await _shouldShowNotification(message);
    if (!shouldShow) return;

    final content = await _buildLocalNotificationContent(message);
    if (content == null) return;

    await _showLocalNotification(
      id: _notificationIdFor(message),
      title: content.title,
      body: content.body,
      channelId: _channelIdFor(message),
    );
  }

  static Future<void> _handleWidgetUpdateMessage(RemoteMessage message) async {
    try {
      final d = message.data;
      // Обновляем ТОЛЬКО присутствующие в сообщении поля. Отсутствующий ключ
      // означает «это поле не менялось» — его нельзя затирать пустой строкой,
      // иначе, например, смена настроения обнуляла статус/сообщение/музыку
      // партнёра на виджете (сервер шлёт лишь изменившиеся поля).
      const keyMap = {
        'status': 'partner_status',
        'moodLabel': 'partner_mood',
        'message': 'partner_message',
        'musicTitle': 'partner_music_title',
        'musicArtist': 'partner_music_artist',
      };
      final updates = <Future<void>>[];
      keyMap.forEach((dataKey, widgetKey) {
        if (d.containsKey(dataKey)) {
          updates.add(
            HomeWidget.saveWidgetData<String>(
              widgetKey,
              (d[dataKey] ?? '').toString(),
            ),
          );
        }
      });
      if (updates.isEmpty) return;
      await Future.wait(updates);
      await HomeWidget.updateWidget(
        name: 'LoveWidgetProvider',
        androidName: 'LoveWidgetProvider',
      );
    } catch (e) {
      debugPrint('_handleWidgetUpdateMessage failed: $e');
    }
  }

  static Future<bool> _shouldShowNotification(RemoteMessage message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final type = message.data['type'] ?? '';
      if (type == 'miss_you' && !(prefs.getBool(_kNotifMissYou) ?? true)) {
        debugPrint(
          'FCM foreground: miss_you notification suppressed by user prefs',
        );
        return false;
      }
      if (type == 'new_memory' && !(prefs.getBool(_kNotifNewMemory) ?? true)) {
        debugPrint(
          'FCM foreground: new_memory notification suppressed by user prefs',
        );
        return false;
      }
      if (type == 'mood' && !(prefs.getBool(_kNotifMood) ?? true)) {
        debugPrint(
          'FCM foreground: mood notification suppressed by user prefs',
        );
        return false;
      }
      if (type == 'chat') {
        // Пользователь уже открыл именно этот чат — не дублируем уведомление.
        if (activeChatGroupId != null &&
            message.data['groupId'] == activeChatGroupId) {
          debugPrint('FCM foreground: chat open, notification suppressed');
          return false;
        }
        if (!(prefs.getBool(_kNotifChat) ?? true)) {
          debugPrint(
            'FCM foreground: chat notification suppressed by user prefs',
          );
          return false;
        }
      }
    } catch (e) {
      debugPrint('FCM foreground pref check failed: \$e');
    }

    return true;
  }

  static Future<_LocalNotificationContent?> _buildLocalNotificationContent(
    RemoteMessage message,
  ) async {
    final type = message.data['type'] ?? '';

    const _vibeTypes = {'miss_you', 'thinking_of_you', 'want_hug', 'custom'};
    if (_vibeTypes.contains(type)) {
      await NicknameService.instance.init();
      await LocaleService.instance.init();

      final senderUid = message.data['senderUid'] ?? '';
      final fallbackSenderName = message.data['senderName'] ?? 'Partner';
      final senderName = NicknameService.instance.resolve(
        senderUid,
        fallbackSenderName,
      );
      final strings = LocaleService.current;
      final body = (message.data['body'] ?? '').toString().trim();

      switch (type) {
        case 'miss_you':
          return _LocalNotificationContent(
            title: strings.missYouNotifTitle(senderName),
            body: body.isNotEmpty ? body : strings.missYouNotifBody,
          );
        case 'thinking_of_you':
          return _LocalNotificationContent(
            title: strings.thinkingOfYouNotifTitle(senderName),
            body: body,
          );
        case 'want_hug':
          return _LocalNotificationContent(
            title: strings.wantHugNotifTitle(senderName),
            body: body,
          );
        case 'custom':
          return _LocalNotificationContent(
            title: strings.customVibeNotifTitle(senderName),
            body: body.isNotEmpty ? body : '✉️',
          );
      }
    }

    if (type == 'chat') {
      await NicknameService.instance.init();
      await LocaleService.instance.init();
      final senderUid = message.data['senderUid'] ?? '';
      final fallbackSenderName = message.data['senderName'] ?? 'Partner';
      final senderName = NicknameService.instance.resolve(
        senderUid,
        fallbackSenderName,
      );
      final body = (message.data['body'] ?? '').toString().trim();
      return _LocalNotificationContent(
        title: LocaleService.current.chatNotifTitle(senderName),
        body: body.isNotEmpty ? body : '✉️',
      );
    }

    if (type == 'mood') {
      await NicknameService.instance.init();
      await LocaleService.instance.init();
      final senderUid = message.data['senderUid'] ?? '';
      final fallbackSenderName = message.data['senderName'] ?? 'Partner';
      final senderName = NicknameService.instance.resolve(
        senderUid,
        fallbackSenderName,
      );
      final moodLabel = (message.data['moodLabel'] ?? '').toString().trim();
      // moodLabel хранится на языке отправителя; локализуем только заголовок.
      return _LocalNotificationContent(
        title: LocaleService.current.moodNotifTitle(senderName),
        body: moodLabel.isNotEmpty
            ? moodLabel
            : (message.data['body'] ?? '').toString().trim(),
      );
    }

    final notification = message.notification;
    final title = (notification?.title ?? message.data['title'] ?? '')
        .toString()
        .trim();
    final body = (notification?.body ?? message.data['body'] ?? '')
        .toString()
        .trim();

    if (title.isEmpty && body.isEmpty) return null;

    return _LocalNotificationContent(title: title, body: body);
  }

  /// Публичная обёртка для разовых локальных уведомлений (например, выдача
  /// бейджа спонсора/помощника). Использует общий канал с FCM-уведомлениями.
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) => _showLocalNotification(
    id: id,
    title: title,
    body: body,
    channelId: _kChannelId,
  );

  static Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
  }) async {
    await _initLocalNotifications();

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _kChannelName,
          channelDescription: 'Уведомления от партнёра',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  static int _notificationIdFor(RemoteMessage message) {
    final messageId = message.messageId;
    if (messageId != null && messageId.isNotEmpty) return messageId.hashCode;
    return Object.hashAll([
      message.data['type'],
      message.data['groupId'],
      message.data['senderUid'],
      message.sentTime?.millisecondsSinceEpoch,
    ]);
  }

  static String _channelIdFor(RemoteMessage message) {
    return message.notification?.android?.channelId ?? _kChannelId;
  }

  Future<void> _saveFcmToken(String token) async {
    final u = currentUser;
    if (u == null) return;
    try {
      // Пишем в Firestore только если токен изменился — иначе каждый запуск
      // делает лишний write в users/{uid}, который тригерит listener у партнёра.
      final prefs = await SharedPreferences.getInstance();
      final key = 'fcmToken_${u.uid}';
      final saved = prefs.getString(key);
      if (saved == token) return;

      await _db.collection('users').doc(u.uid).set({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

      // Зеркалим токен в RTDB, чтобы Cloud Function пуша читала токены оттуда
      // (даром), а не из users/{uid} (Firestore-чтение на каждый пуш).
      try {
        await _rtdb.ref('push/${u.uid}/tokens').child(token).set(true);
      } catch (e) {
        debugPrint('_saveFcmToken RTDB mirror failed: $e');
      }

      await prefs.setString(key, token);
    } catch (e) {
      debugPrint('_saveFcmToken failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  EMAIL LINK AUTHENTICATION (Passwordless)
  // ══════════════════════════════════════════════

  /// Отправить ссылку для входа на электронную почту
  Future<bool> sendSignInLinkToEmail(String email) async {
    try {
      debugPrint('Firebase Auth: sending sign-in link to $email');

      final actionCodeSettings = ActionCodeSettings(
        // URL для перенаправления - используем web.app домен
        url: 'https://togetherly-d4856.web.app/',
        handleCodeInApp: true,
        androidPackageName: 'com.togetherly.love',
        androidInstallApp: true,
        androidMinimumVersion: '21',
      );

      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );

      debugPrint('Sign-in link sent successfully');
      return true;
    } catch (e) {
      debugPrint('sendSignInLinkToEmail failed: $e');
      return false;
    }
  }

  /// Проверить, является ли ссылка ссылкой для входа
  bool isSignInWithEmailLink(String emailLink) {
    return _auth.isSignInWithEmailLink(emailLink);
  }

  /// Войти используя ссылку из email
  Future<User?> signInWithEmailLink({
    required String email,
    required String emailLink,
  }) async {
    try {
      debugPrint('Firebase Auth: signing in with email link...');

      final userCredential = await _auth.signInWithEmailLink(
        email: email,
        emailLink: emailLink,
      );

      final user = userCredential.user;
      if (user == null) return null;

      debugPrint('Firebase Auth success: ${user.uid}');

      // Сохранить профиль в Firestore
      try {
        await _db
            .collection('users')
            .doc(user.uid)
            .set({
              'displayName': user.displayName ?? '',
              'email': user.email ?? '',
              'avatarUrl': user.photoURL ?? '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Firestore save failed: $e');
      }

      return user;
    } catch (e) {
      debugPrint('signInWithEmailLink failed: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════
  //  USER PROFILE
  // ══════════════════════════════════════════════

  Future<void> saveUserProfile({
    required String displayName,
    required String email,
    required String gender,
    String avatarUrl = '',
    bool clearPairData = false,
  }) async {
    final u = currentUser;
    if (u == null) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final data = <String, dynamic>{
        'displayName': displayName,
        'email': email,
        'gender': gender,
        'appVersion': '${info.version}+${info.buildNumber}',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Only write avatarUrl if non-empty — never overwrite a real avatar with ''
      if (avatarUrl.isNotEmpty) {
        data['avatarUrl'] = avatarUrl;
      }

      // Clear pair data if this is a new registration
      if (clearPairData) {
        data['pairId'] = '';
        data['pairIds'] = [];
      }

      await _db
          .collection('users')
          .doc(u.uid)
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
      _cachedDisplayName = displayName;
      if (avatarUrl.isNotEmpty) _cachedAvatarUrl = avatarUrl;
      // Двойная запись профиля в Supabase (serverTimestamp заменяем на now).
      if (_mig) {
        final mirror = Map<String, dynamic>.from(data)
          ..remove('updatedAt')
          ..remove('appVersion');
        unawaited(_sb.mirrorUser(u.uid, mirror));
      }
    } catch (e) {
      debugPrint('saveUserProfile failed: $e');
    }
  }

  // ── Коины: серверная логика ─────────────────────────────────────────────
  // Клиент НЕ может писать coins/ownedThemes/devCoinsGranted/lastDailyBonusAt/
  // adRewardsDate напрямую. Начисления/списания идут только через сервер:
  //   • _mig-юзеры → Supabase Postgres RPC (supabase/coins.sql), Cloud Functions
  //     для них не нужны;
  //   • остальные → Firebase Cloud Functions (functions/index.js).

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Гарантирует, что Firebase ID-токен несёт claim `role: authenticated`.
  ///
  /// Без него Supabase (Third-Party Auth) даёт запросу роль `anon`, а все RLS-
  /// политики выданы `TO authenticated` → ЛЮБОЙ dual-write в Supabase отклоняется
  /// (42501), причём `_write` глотает ошибку → зеркало молча пустеет. Идемпотентно
  /// и дёшево: если claim уже в токене — выходим сразу (без сети). Иначе один раз
  /// зовём callable `ensureSupabaseRole` и форс-рефрешим токен, чтобы claim попал
  /// в активную сессию (и в accessToken-колбэк Supabase в main.dart).
  ///
  /// Вызывается из accessToken-колбэка Supabase (main.dart) ПЕРЕД выдачей
  /// токена на каждый запрос: первый запрос сессии дожидается выдачи claim, и
  /// только потом уходит в Supabase — поэтому dual-write больше не отлетает
  /// гонкой со стартом (42501 на users/widget_data + "not a group member").
  /// Также зовётся на authStateChanges как прогрев. Идемпотентно и дёшево:
  /// после первого успеха возвращает управление мгновенно.
  Future<void> ensureSupabaseRole() {
    if (!_mig || _supabaseRoleEnsured) return Future.value();
    // Кулдаун после провала: пока он не вышел, не пытаемся снова — запрос уйдёт
    // как сейчас (фоновым ретраем), а не повиснет повторным таймаутом callable.
    // Само-восстановление: после деплоя функции следующая попытка пройдёт.
    final failedAt = _roleEnsureFailedAt;
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _roleEnsureCooldown) {
      return Future.value();
    }
    // Один in-flight Future на всех параллельных вызывающих (см.
    // _roleEnsureInFlight): не дёргаем Cloud Function и не форс-рефрешим токен
    // пачкой, когда на старте несколько запросов зовут колбэк разом.
    return _roleEnsureInFlight ??=
        _ensureSupabaseRoleImpl().whenComplete(() => _roleEnsureInFlight = null);
  }

  Future<void> _ensureSupabaseRoleImpl() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final res = await user.getIdTokenResult();
      if (res.claims?['role'] == 'authenticated') {
        _supabaseRoleEnsured = true;
        _roleEnsureFailedAt = null;
        return;
      }
      await _functions
          .httpsCallable('ensureSupabaseRole')
          .call()
          .timeout(const Duration(seconds: 15));
      // Форс-рефреш: новый claim попадает в токен (иначе ждать до ~1ч/истечения).
      await user.getIdToken(true);
      _supabaseRoleEnsured = true;
      _roleEnsureFailedAt = null;
      debugPrint('[SB] role=authenticated выдан, токен обновлён');
    } catch (e) {
      // Запоминаем момент провала → кулдаун в ensureSupabaseRole() не даст
      // дёргать (возможно сломанную) функцию на каждый Supabase-запрос.
      _roleEnsureFailedAt = DateTime.now();
      debugPrint('ensureSupabaseRole failed: $e');
    }
  }

  Future<Map<String, dynamic>?> _callCoinFn(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    final u = currentUser;
    if (u == null) return null;
    // Stage 2: коины через Firebase Cloud Functions (баланс — Firebase, как у
    // старой версии). Stage 3 (_readSb) — через Supabase RPC.
    if (_readSb('')) {
      return _sb.callCoinRpc(name, u.uid, data ?? const {});
    }
    try {
      final res = await _functions
          .httpsCallable(name)
          .call<Map<dynamic, dynamic>>(data ?? const {})
          .timeout(const Duration(seconds: 15));
      return Map<String, dynamic>.from(res.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('$name failed: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('$name failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> callPurchaseTheme(int themeId) =>
      _callCoinFn('purchaseTheme', {'themeId': themeId});

  Future<Map<String, dynamic>?> callPurchaseIcon(String iconId) =>
      _callCoinFn('purchaseIcon', {'iconId': iconId});

  Future<Map<String, dynamic>?> callPurchaseFeature(String featureId) =>
      _callCoinFn('purchaseFeature', {'featureId': featureId});

  Future<Map<String, dynamic>?> callSpendCoins(String actionId) =>
      _callCoinFn('spendCoins', {'actionId': actionId});

  Future<Map<String, dynamic>?> callGrantDailyBonus() =>
      _callCoinFn('grantDailyBonus');

  Future<Map<String, dynamic>?> callGrantCoinsPurchase({
    required String productId,
    required String purchaseToken,
  }) => _callCoinFn('grantCoinsPurchase', {
    'productId': productId,
    'purchaseToken': purchaseToken,
  });

  Future<Map<String, dynamic>?> callGrantDevCoins() =>
      _callCoinFn('grantDevCoins');

  Future<Map<String, dynamic>?> callGrantMemoryReward() =>
      _callCoinFn('grantMemoryReward');

  /// Начисляет награду за rewarded-видео Яндекса (у которого нет Google-SSV).
  /// Сервер enforce'ит дневной лимит; счётчик общий с AdMob-SSV.
  Future<Map<String, dynamic>?> callGrantAdReward() =>
      _callCoinFn('grantAdReward');

  /// Награда за подключение партнёра — по 50 🪙 каждому, один раз на уникальную
  /// пару людей. [partnerUid] — uid второго участника (дедуп по его email/uid).
  Future<Map<String, dynamic>?> callGrantPartnerInviteReward(String partnerUid) =>
      _callCoinFn('grantPartnerInviteReward', {'partnerUid': partnerUid});

  Future<Map<String, dynamic>?> callGrantMoodStreakReward(String groupId) =>
      _callCoinFn('grantMoodStreakReward', {'groupId': groupId});

  /// Устанавливает закреплённую иконку-бейдж пользователя.
  /// Пустая строка снимает иконку (записывает пустое значение).
  Future<void> setBadge(String badge) async {
    final u = currentUser;
    if (u == null) return;
    try {
      await _db
          .collection('users')
          .doc(u.uid)
          .set({'badge': badge}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
      // Профиль под `_mig` читается из Supabase — без зеркала смена бейджа
      // была бы невидимой (откатывалась при следующем loadUserProfile).
      if (_mig) unawaited(_sb.mirrorUser(u.uid, {'badge': badge}));
    } catch (e) {
      debugPrint('setBadge failed: $e');
    }
  }

  /// Сохраняет список выданных иконок-наград (Sponsor/Helper) и, опционально,
  /// текущий закреплённый бейдж за одну запись.
  Future<void> saveGrantedBadges(
    List<String> grantedBadges, {
    String? badge,
  }) async {
    final u = currentUser;
    if (u == null) return;
    try {
      final data = <String, dynamic>{'grantedBadges': grantedBadges};
      if (badge != null) data['badge'] = badge;
      await _db
          .collection('users')
          .doc(u.uid)
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
      // См. setBadge: профиль под `_mig` читается из Supabase.
      if (_mig) unawaited(_sb.mirrorUser(u.uid, data));
    } catch (e) {
      debugPrint('saveGrantedBadges failed: $e');
    }
  }

  /// Updates the user's avatar URL in all groups they belong to.
  /// This ensures that partner devices receive the new avatar via the group listener.
  Future<void> updateNameInGroups(String displayName) async {
    final u = currentUser;
    if (u == null) return;
    try {
      final userDoc = await _db.collection('users').doc(u.uid).get();
      if (!userDoc.exists) return;
      final userData = userDoc.data()!;

      final pairIds = <String>{};
      final legacyPairId = userData['pairId'] as String?;
      if (legacyPairId != null && legacyPairId.isNotEmpty) {
        pairIds.add(legacyPairId);
      }
      final pairIdsList = userData['pairIds'] as List<dynamic>?;
      if (pairIdsList != null) {
        pairIds.addAll(
          pairIdsList.whereType<String>().where((s) => s.isNotEmpty),
        );
      }

      // Firestore-запись остаётся и под `_mig`: memberNames читает Cloud
      // Function пуша настроения (имя отправителя). Но партнёр видит группу из
      // Supabase, поэтому БЕЗ зеркала смена имени до него не доезжала — это
      // был баг dual-write; чиним атомарным jsonb_set.
      final nameBatch = _db.batch();
      for (final groupId in pairIds) {
        nameBatch.update(_db.collection('groups').doc(groupId), {
          'memberNames.${u.uid}': displayName,
        });
        if (_mig) unawaited(_sb.setMemberName(groupId, u.uid, displayName));
      }
      await nameBatch.commit().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('updateNameInGroups failed: $e');
    }
  }

  Future<void> updateAvatarInGroups(String avatarUrl) async {
    final u = currentUser;
    if (u == null) return;
    try {
      final userDoc = await _db.collection('users').doc(u.uid).get();
      if (!userDoc.exists) return;
      final userData = userDoc.data()!;

      final pairIds = <String>{};
      final legacyPairId = userData['pairId'] as String?;
      if (legacyPairId != null && legacyPairId.isNotEmpty) {
        pairIds.add(legacyPairId);
      }
      final pairIdsList = userData['pairIds'] as List<dynamic>?;
      if (pairIdsList != null) {
        pairIds.addAll(
          pairIdsList.whereType<String>().where((s) => s.isNotEmpty),
        );
      }

      // Как в updateNameInGroups: Firestore — для пуш-функций, Supabase —
      // источник чтения партнёра (без зеркала аватар не обновлялся у него).
      final avatarBatch = _db.batch();
      for (final groupId in pairIds) {
        avatarBatch.update(_db.collection('groups').doc(groupId), {
          'memberAvatars.${u.uid}': avatarUrl,
        });
        if (_mig) unawaited(_sb.setMemberAvatar(groupId, u.uid, avatarUrl));
      }
      await avatarBatch.commit().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('updateAvatarInGroups failed: $e');
    }
  }

  Future<Map<String, dynamic>?> loadUserProfile({
    bool fromServer = false,
  }) async {
    final u = currentUser;
    if (u == null) return null;

    // Stage 2: профиль (включая coins/owned*) читаем из Firebase (источник, как
    // у старой версии). Stage 3 (_readSb) — из Supabase.
    if (_readSb('')) {
      final sb = await _sb.loadUserProfile(u.uid);
      if (sb != null) {
        _cachedDisplayName = sb['displayName'] as String?;
        _cachedAvatarUrl = sb['avatarUrl'] as String?;
        return sb;
      }
    }

    try {
      final doc = await _db
          .collection('users')
          .doc(u.uid)
          .get(fromServer ? const GetOptions(source: Source.server) : null)
          .timeout(const Duration(seconds: 10));
      final data = doc.data();
      if (data != null) {
        _cachedDisplayName = data['displayName'] as String?;
        _cachedAvatarUrl = data['avatarUrl'] as String?;
        // Фолбэк-сидирование Supabase из Firebase (только пока Supabase пуст).
        if (_mig) unawaited(_sb.mirrorUser(u.uid, data));
      }
      return data;
    } catch (e) {
      debugPrint('loadUserProfile failed: $e');
      // On network error fall back to cache
      if (fromServer) {
        try {
          final cached = await _db
              .collection('users')
              .doc(u.uid)
              .get(const GetOptions(source: Source.cache));
          final cachedData = cached.data();
          if (cachedData != null) {
            _cachedDisplayName = cachedData['displayName'] as String?;
            _cachedAvatarUrl = cachedData['avatarUrl'] as String?;
          }
          return cachedData;
        } catch (_) {}
      }
      return null;
    }
  }

  // ══════════════════════════════════════════════
  //  INVITE CODES
  // ══════════════════════════════════════════════

  Future<String> generateInviteCode() async {
    final u = currentUser;
    if (u == null) return '';

    try {
      final userDoc = await _db
          .collection('users')
          .doc(u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      final existingCode = userDoc.data()?['inviteCode'] as String?;
      if (existingCode != null && existingCode.isNotEmpty) {
        return existingCode;
      }

      String code;
      bool exists;
      do {
        code = _generateCode();
        final codeDoc = await _db
            .collection('inviteCodes')
            .doc(code)
            .get()
            .timeout(const Duration(seconds: 5));
        exists = codeDoc.exists;
      } while (exists);

      final batch = _db.batch();
      batch.set(_db.collection('inviteCodes').doc(code), {
        'ownerUid': u.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(_db.collection('users').doc(u.uid), {'inviteCode': code});
      await batch.commit().timeout(const Duration(seconds: 10));

      return code;
    } catch (e) {
      debugPrint('generateInviteCode failed: $e');
      return '';
    }
  }

  Future<String> generateNewInviteCode({String? oldCode}) async {
    final u = currentUser;
    if (u == null) return '';

    // Force-refresh the ID token so Firestore always sees a valid auth claim.
    // This is critical for freshly-created email accounts where the token may
    // not have propagated to Firestore's security backend yet.
    try {
      await u.getIdToken(true);
    } catch (_) {}

    Future<String> attempt() async {
      if (oldCode != null && oldCode.isNotEmpty) {
        try {
          await _db.collection('inviteCodes').doc(oldCode).delete();
        } catch (_) {}
      }

      String code;
      bool exists;
      do {
        code = _generateCode();
        final codeDoc = await _db
            .collection('inviteCodes')
            .doc(code)
            .get()
            .timeout(const Duration(seconds: 5));
        exists = codeDoc.exists;
      } while (exists);

      await _db
          .collection('inviteCodes')
          .doc(code)
          .set({'ownerUid': u.uid, 'createdAt': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 10));

      return code;
    }

    try {
      return await attempt();
    } catch (e) {
      debugPrint('generateNewInviteCode first attempt failed: $e — retrying…');
      // Retry once after a short pause + token refresh (email sign-up timing fix)
      try {
        await Future.delayed(const Duration(milliseconds: 800));
        await u.getIdToken(true);
        return await attempt();
      } catch (e2) {
        debugPrint('generateNewInviteCode retry failed: $e2');
        return '';
      }
    }
  }

  /// Returns true if [code] exists in Firestore and belongs to the current user.
  /// Returns true (don't invalidate) on network errors.
  Future<bool> isOwnedInviteCodeValid(String code) async {
    if (code.isEmpty) return false;
    final u = currentUser;
    if (u == null) return false;
    try {
      final doc = await _db
          .collection('inviteCodes')
          .doc(code)
          .get()
          .timeout(const Duration(seconds: 5));
      return doc.exists && doc.data()?['ownerUid'] == u.uid;
    } catch (_) {
      return true; // network error — assume valid, don't wipe it
    }
  }

  /// Checks whether [code] exists on the Firestore SERVER (bypasses local cache).
  /// Returns true  → code is confirmed on server and owned by current user.
  /// Returns false → code is not on server (was never written or write failed).
  /// Returns null  → offline / unreachable, cannot determine.
  Future<bool?> isInviteCodeOnServer(String code) async {
    if (code.isEmpty) return false;
    final u = currentUser;
    if (u == null) return false;
    try {
      final doc = await _db
          .collection('inviteCodes')
          .doc(code)
          .get(GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      return doc.exists && doc.data()?['ownerUid'] == u.uid;
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'failed-precondition') {
        return null; // offline
      }
      return false;
    } catch (_) {
      return null; // timeout or other error — treat as offline
    }
  }

  /// Create invite code tied to a specific group (for adding more members)
  Future<String> generateGroupInviteCode(
    String groupId, {
    String? oldCode,
  }) async {
    final u = currentUser;
    if (u == null) return '';

    try {
      if (oldCode != null && oldCode.isNotEmpty) {
        await _db.collection('inviteCodes').doc(oldCode).delete();
      }

      String code;
      bool exists;
      do {
        code = _generateCode();
        final codeDoc = await _db
            .collection('inviteCodes')
            .doc(code)
            .get()
            .timeout(const Duration(seconds: 5));
        exists = codeDoc.exists;
      } while (exists);

      await _db
          .collection('inviteCodes')
          .doc(code)
          .set({
            'ownerUid': u.uid,
            'groupId': groupId,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));

      return code;
    } catch (e) {
      debugPrint('generateGroupInviteCode failed: $e');
      return '';
    }
  }

  Future<String> regenerateInviteCode({String? oldCode}) async {
    return generateNewInviteCode(oldCode: oldCode);
  }

  // ══════════════════════════════════════════════
  //  GROUPS (replaces old PAIRING)
  //
  //  Firestore structure:
  //    groups/{groupId}:
  //      members: [uid1, uid2, ...]
  //      memberNames: {uid1: "Alice", uid2: "Bob"}
  //      memberAvatars: {uid1: "url", uid2: "url"}
  //      maxMembers: 2 | 10
  //      startDate: Timestamp
  //      createdAt: Timestamp
  //
  //    users/{uid}:
  //      pairId: "last groupId" (legacy compat)
  //      pairIds: ["groupId1", "groupId2"]
  // ══════════════════════════════════════════════

  /// Accept invite code → join or create a group.
  Future<Map<String, dynamic>> acceptInviteCode(String code) async {
    final u = currentUser;
    if (u == null) return {'success': false, 'message': 'Не авторизован'};

    code = code.toUpperCase().trim();
    debugPrint('acceptInviteCode: looking up code $code');

    try {
      final codeDoc = await _db.collection('inviteCodes').doc(code).get();
      if (!codeDoc.exists) {
        debugPrint('acceptInviteCode: code not found');
        return {'success': false, 'message': 'Код не найден'};
      }

      final ownerUid = codeDoc.data()!['ownerUid'] as String;
      if (ownerUid == u.uid) {
        return {'success': false, 'message': 'Это ваш собственный код!'};
      }

      // Check if there's a groupId tied to this code
      final codeGroupId = codeDoc.data()!['groupId'] as String?;
      debugPrint('acceptInviteCode: owner=$ownerUid, groupId=$codeGroupId');

      final ownerDoc = await _db.collection('users').doc(ownerUid).get();
      if (!ownerDoc.exists) {
        return {'success': false, 'message': 'Пользователь не найден'};
      }
      final ownerData = ownerDoc.data()!;

      final myDoc = await _db.collection('users').doc(u.uid).get();
      final myData = myDoc.data() ?? {};

      // If code has a groupId → join existing group
      if (codeGroupId != null && codeGroupId.isNotEmpty) {
        debugPrint('acceptInviteCode: code has groupId, joining $codeGroupId');
        return _joinExistingGroup(
          groupId: codeGroupId,
          code: code,
          myData: myData,
          ownerUid: ownerUid,
          ownerData: ownerData,
        );
      }

      // Code has no groupId — check if the owner already has a group
      final ownerPairId = ownerData['pairId'] as String?;
      bool canJoinOwnerGroup = false;

      if (ownerPairId != null && ownerPairId.isNotEmpty) {
        debugPrint(
          'acceptInviteCode: owner has pairId=$ownerPairId, trying to join',
        );
        try {
          final groupDoc = await _db
              .collection('groups')
              .doc(ownerPairId)
              .get();
          if (groupDoc.exists) {
            final groupData = groupDoc.data()!;
            final groupMembers = List<String>.from(groupData['members'] ?? []);
            // Already in this group together — no need to do anything
            if (groupMembers.contains(ownerUid) &&
                groupMembers.contains(u.uid)) {
              return {
                'success': false,
                'message': 'Вы уже подключены к этому пользователю',
              };
            }
            if (groupMembers.contains(ownerUid) &&
                !groupMembers.contains(u.uid)) {
              // Check if I already have a different pairId
              final myPairId = myData['pairId'] as String?;
              if (myPairId != null &&
                  myPairId.isNotEmpty &&
                  myPairId != ownerPairId) {
                // I'm already in a different group — don't join, create new group instead
                debugPrint(
                  'acceptInviteCode: I have different group $myPairId, cannot join $ownerPairId',
                );
                canJoinOwnerGroup = false;
              } else {
                canJoinOwnerGroup = true;
                return _joinExistingGroup(
                  groupId: ownerPairId,
                  code: code,
                  myData: myData,
                  ownerUid: ownerUid,
                  ownerData: ownerData,
                );
              }
            }
          }
        } catch (e) {
          debugPrint('acceptInviteCode: reading owner group failed: $e');
          // Can't read group (not a member) — just create a new one
        }
      }

      // Also check owner's pairIds list for any group we can join
      final ownerPairIds = ownerData['pairIds'] as List<dynamic>?;
      if (ownerPairIds != null &&
          ownerPairIds.isNotEmpty &&
          !canJoinOwnerGroup) {
        for (var pid in ownerPairIds) {
          final pidStr = pid.toString();
          if (pidStr.isEmpty) continue;
          try {
            final groupDoc = await _db.collection('groups').doc(pidStr).get();
            if (groupDoc.exists) {
              final groupData = groupDoc.data()!;
              final groupMembers = List<String>.from(
                groupData['members'] ?? [],
              );
              // Already in this group together — no need to do anything
              if (groupMembers.contains(ownerUid) &&
                  groupMembers.contains(u.uid)) {
                return {
                  'success': false,
                  'message': 'Вы уже подключены к этому пользователю',
                };
              }
              if (groupMembers.contains(ownerUid) &&
                  !groupMembers.contains(u.uid)) {
                // Check if I already have a different pairId
                final myPairId = myData['pairId'] as String?;
                if (myPairId != null &&
                    myPairId.isNotEmpty &&
                    myPairId != pidStr) {
                  // I'm already in a different group — skip this one and try next
                  debugPrint(
                    'acceptInviteCode: I have different group $myPairId, cannot join $pidStr',
                  );
                  continue;
                }
                return _joinExistingGroup(
                  groupId: pidStr,
                  code: code,
                  myData: myData,
                  ownerUid: ownerUid,
                  ownerData: ownerData,
                );
              }
            }
          } catch (e) {
            debugPrint('acceptInviteCode: reading group $pidStr failed: $e');
            // Can't read group — skip
          }
        }
      }

      // Check if there's a disbanded group between these two users to restore
      final disbandedId = await _findDisbandedGroup(ownerUid);
      if (disbandedId != null) {
        debugPrint('acceptInviteCode: restoring disbanded group $disbandedId');
        return _restoreGroup(
          groupId: disbandedId,
          code: code,
          ownerUid: ownerUid,
          ownerData: ownerData,
          myData: myData,
        );
      }

      // Owner has no group yet — create a new 2-person group (pair)
      debugPrint(
        'acceptInviteCode: creating new group for $ownerUid + ${u.uid}',
      );
      return _createNewGroup(
        code: code,
        ownerUid: ownerUid,
        ownerData: ownerData,
        myData: myData,
      );
    } catch (e) {
      debugPrint('acceptInviteCode FAILED: $e');
      return {'success': false, 'message': 'Ошибка: $e'};
    }
  }

  /// Зеркалит свежесозданную/восстановленную пару в Supabase сразу после
  /// записи в Firestore. Без этого пара, созданная только в Firestore, не
  /// появлялась в Supabase до первого fallback-чтения, а live-листенер
  /// (listenToPair) фолбэка не делает → партнёр не видел группу/статус/
  /// настроение. Зеркалим КАНОНИЧНЫЙ снимок group-doc + свой профиль (чужой
  /// профиль не трогаем, чтобы не затереть его коины — партнёр сидирует свою
  /// users-строку сам; имя/аватар для UI берутся из memberNames группы).
  Future<void> _mirrorPairToSupabase(
    String groupId,
    Map<String, dynamic> myData,
  ) async {
    if (!_mig || groupId.isEmpty) return;
    await _mirrorGroupDocToSupabase(groupId);
    final myUid = currentUser?.uid;
    if (myUid != null) unawaited(_sb.mirrorUser(myUid, myData));
  }


  /// Полный mirror группы — только если строки в Supabase ещё нет
  /// (сидирование исторической группы; существующую не перезаписываем).
  Future<void> _mirrorGroupRawIfMissing(
    String groupId,
    Map<String, dynamic> data,
  ) async {
    try {
      final existing = await _sb.fetchGroupColumns(groupId, ['id']);
      if (existing == null) await _sb.mirrorGroupRaw(groupId, data);
    } catch (e) {
      debugPrint('_mirrorGroupRawIfMissing($groupId) failed: $e');
    }
  }

  /// Зеркалит группу из Firestore в Supabase ПОСЛЕ membership-операции
  /// (паринг/restore/выход). С Этапа 4 горячие поля (memberMoods, статус,
  /// таймеры, даты…) пишутся ТОЛЬКО в Supabase — полный снимок Firestore-дока
  /// затёр бы их устаревшими значениями. Поэтому: строки нет (новая группа) →
  /// полный mirrorGroupRaw; строка есть → обновляем только membership-поля.
  Future<void> _mirrorGroupDocToSupabase(String groupId) async {
    if (!_mig || groupId.isEmpty) return;
    try {
      final doc = await _db.collection('groups').doc(groupId).get();
      final data = doc.data();
      if (!doc.exists || data == null) return;
      final existing = await _sb.fetchGroupColumns(groupId, ['id']);
      if (existing == null) {
        await _sb.mirrorGroupRaw(groupId, data);
        return;
      }
      final disbanded = data['disbanded'] == true;
      await _sb.mirrorGroupFields(groupId, {
        'members': SupabaseService.jsonSafe(data['members'] ?? []),
        'member_names': SupabaseService.jsonSafe(data['memberNames'] ?? {}),
        'member_avatars': SupabaseService.jsonSafe(data['memberAvatars'] ?? {}),
        'max_members': data['maxMembers'] ?? 2,
        'disbanded': disbanded,
        // null при restore очищает метку роспуска (mirrorGroupFields не
        // выкидывает null-значения — в отличие от mirrorGroupRaw).
        'disbanded_at':
            disbanded ? SupabaseService.jsonSafe(data['disbandedAt']) : null,
      });
    } catch (e) {
      debugPrint('_mirrorGroupDocToSupabase($groupId) failed: $e');
    }
  }

  /// Create a brand new group between owner and current user.
  Future<Map<String, dynamic>> _createNewGroup({
    required String code,
    required String ownerUid,
    required Map<String, dynamic> ownerData,
    required Map<String, dynamic> myData,
  }) async {
    final u = currentUser!;

    // Страховка от гонки взаимного коннекта: оба партнёра принимают коды друг
    // друга почти одновременно, каждый читает user-doc партнёра ДО того, как
    // первая группа записалась → создаются ДВЕ группы одной пары (симптом:
    // пуши ходят, чат/данные «не синхронизируются»). Перед созданием ещё раз
    // ищем живую группу с этой же парой — окно гонки сужается до секунд, а
    // остаток добивает mergeDuplicateGroups при следующем старте.
    try {
      final existing = await _db
          .collection('groups')
          .where('members', arrayContains: u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      for (final doc in existing.docs) {
        final data = doc.data();
        if (data['disbanded'] == true) continue;
        final members = List<String>.from(data['members'] ?? []);
        if (members.contains(ownerUid)) {
          debugPrint(
            '_createNewGroup: live group ${doc.id} with $ownerUid already '
            'exists (mutual-connect race) — joining it instead of creating',
          );
          // Гарантируем группу в своих pairIds (вдруг запись партнёра в наш
          // user-doc не прошла) и гасим использованный код.
          await _db.collection('users').doc(u.uid).set({
            'pairId': doc.id,
            'pairIds': FieldValue.arrayUnion([doc.id]),
          }, SetOptions(merge: true));
          unawaited(
            _db.collection('inviteCodes').doc(code).delete().catchError((e) {
              debugPrint('_createNewGroup: could not delete invite code: $e');
            }),
          );
          return {
            'success': true,
            'message': 'Connected!',
            'partnerName': ownerData['displayName'] ?? 'Partner',
            'partnerAvatar': ownerData['avatarUrl'] ?? '',
            'pairId': doc.id,
            'startDate': (data['startDate'] as Timestamp?)?.toDate() ??
                DateTime.now(),
            'relationshipType': data['relationshipType'] ?? 'couple',
            'customRelationshipLabel': data['customRelationshipLabel'] ?? '',
            'customRelationshipEmoji': data['customRelationshipEmoji'] ?? '',
            'customRelationshipTypes':
                data['customRelationshipTypes'] ?? <Map<String, String>>[],
            'members': [
              {
                'uid': ownerUid,
                'name': ownerData['displayName'] ?? 'Partner',
                'avatar': ownerData['avatarUrl'] ?? '',
              },
              {
                'uid': u.uid,
                'name': myData['displayName'] ?? u.displayName ?? 'You',
                'avatar': myData['avatarUrl'] ?? u.photoURL ?? '',
              },
            ],
          };
        }
      }
    } catch (e) {
      debugPrint('_createNewGroup: pre-create duplicate check failed: $e');
      // Не критично — дубликат добьёт mergeDuplicateGroups на старте.
    }

    final groupRef = _db.collection('groups').doc();
    final now = FieldValue.serverTimestamp();

    // Step 1: Create the group document (allowed by create rule)
    await groupRef.set({
      'members': [ownerUid, u.uid],
      'memberNames': {
        ownerUid: ownerData['displayName'] ?? '',
        u.uid: myData['displayName'] ?? u.displayName ?? '',
      },
      'memberAvatars': {
        ownerUid: ownerData['avatarUrl'] ?? '',
        u.uid: myData['avatarUrl'] ?? u.photoURL ?? '',
      },
      'maxMembers': 2,
      'relationshipType': 'couple',
      'customRelationshipLabel': '',
      'customRelationshipEmoji': '',
      'customRelationshipTypes': <Map<String, String>>[],
      'memoriesCount': 0,
      'drawingsCount': 0,
      'startDate': now,
      'createdAt': now,
    });
    debugPrint('_createNewGroup: group ${groupRef.id} created');

    // Step 2: Update MY user document (allowed — own doc)
    await _db.collection('users').doc(u.uid).update({
      'pairId': groupRef.id,
      'pairIds': FieldValue.arrayUnion([groupRef.id]),
    });
    debugPrint('_createNewGroup: my user doc updated');

    // Step 3: Update OWNER's user document (allowed by new rules — only pairId/pairIds)
    try {
      await _db.collection('users').doc(ownerUid).update({
        'pairId': groupRef.id,
        'pairIds': FieldValue.arrayUnion([groupRef.id]),
      });
      debugPrint('_createNewGroup: owner user doc updated');
    } catch (e) {
      debugPrint(
        '_createNewGroup: owner doc update failed (owner will pick it up via listener): $e',
      );
      // Not critical — owner's real-time listener will detect the group
    }

    // Step 4: Delete invite code (allowed by new rules)
    try {
      await _db.collection('inviteCodes').doc(code).delete();
      debugPrint('_createNewGroup: invite code $code deleted');
    } catch (e) {
      debugPrint('_createNewGroup: could not delete invite code: $e');
    }

    // Зеркалим новую пару в Supabase, чтобы оба партнёра сразу увидели группу.
    // Fire-and-forget: пара уже создана в Firestore, а listenToPair (realtime)
    // подхватит INSERT — не блокируем UX паринга на Supabase.
    unawaited(_mirrorPairToSupabase(groupRef.id, myData));

    return {
      'success': true,
      'message': 'Connected!',
      'partnerName': ownerData['displayName'] ?? 'Partner',
      'partnerAvatar': ownerData['avatarUrl'] ?? '',
      'pairId': groupRef.id,
      'startDate': DateTime.now(),
      'relationshipType': 'couple',
      'customRelationshipLabel': '',
      'customRelationshipEmoji': '',
      'customRelationshipTypes': <Map<String, String>>[],
      'members': [
        {
          'uid': ownerUid,
          'name': ownerData['displayName'] ?? 'Partner',
          'avatar': ownerData['avatarUrl'] ?? '',
        },
        {
          'uid': u.uid,
          'name': myData['displayName'] ?? u.displayName ?? 'You',
          'avatar': myData['avatarUrl'] ?? u.photoURL ?? '',
        },
      ],
    };
  }

  /// Find a disbanded group that contains both the current user and [ownerUid].
  /// Returns the groupId of the most recently disbanded match, or null.
  ///
  /// Queries by membership instead of reading the user's pairIds: a disbanded
  /// group is REMOVED from both members' pairIds at leave time (see
  /// [unpairById]), so it can no longer be found there. The `members` array is
  /// left intact on soft-delete, so an `arrayContains` query still finds it —
  /// and stays scoped to the user's own groups (not the whole collection).
  Future<String?> _findDisbandedGroup(String ownerUid) async {
    final u = currentUser;
    if (u == null) return null;
    try {
      final snap = await _db
          .collection('groups')
          .where('members', arrayContains: u.uid)
          .get();

      String? bestId;
      Timestamp? bestTs;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['disbanded'] != true) continue;
        // Группы, распущенные слиянием дубликатов (mergeDuplicateGroups),
        // воскрешать нельзя — иначе пара раскололась бы заново. Их данные
        // уже живут в канонической группе.
        if (data['mergedInto'] != null) continue;
        final docMembers = List<String>.from(data['members'] ?? []);
        if (!docMembers.contains(ownerUid)) continue;
        final ts = data['disbandedAt'] as Timestamp?;
        if (bestId == null ||
            (ts != null && (bestTs == null || ts.compareTo(bestTs) > 0))) {
          bestId = doc.id;
          bestTs = ts;
        }
      }
      return bestId;
    } catch (e) {
      debugPrint('_findDisbandedGroup error: $e');
      return null;
    }
  }

  /// Restore a disbanded group when the same two users reconnect.
  Future<Map<String, dynamic>> _restoreGroup({
    required String groupId,
    required String code,
    required String ownerUid,
    required Map<String, dynamic> ownerData,
    required Map<String, dynamic> myData,
  }) async {
    final u = currentUser!;
    Map<String, dynamic> groupData;
    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        return _createNewGroup(
          code: code,
          ownerUid: ownerUid,
          ownerData: ownerData,
          myData: myData,
        );
      }
      groupData = groupDoc.data()!;
    } catch (e) {
      debugPrint('_restoreGroup: read failed, creating new: $e');
      return _createNewGroup(
        code: code,
        ownerUid: ownerUid,
        ownerData: ownerData,
        myData: myData,
      );
    }

    // Restore: clear disbanded flag, refresh member display info
    await _db.collection('groups').doc(groupId).update({
      'disbanded': FieldValue.delete(),
      'disbandedAt': FieldValue.delete(),
      'memberNames.$ownerUid': ownerData['displayName'] ?? '',
      'memberAvatars.$ownerUid': ownerData['avatarUrl'] ?? '',
      'memberNames.${u.uid}': myData['displayName'] ?? u.displayName ?? '',
      'memberAvatars.${u.uid}': myData['avatarUrl'] ?? u.photoURL ?? '',
    });
    debugPrint('_restoreGroup: group $groupId restored');

    // Add group back to both users' pairIds
    await _db.collection('users').doc(u.uid).update({
      'pairId': groupId,
      'pairIds': FieldValue.arrayUnion([groupId]),
    });
    try {
      await _db.collection('users').doc(ownerUid).update({
        'pairId': groupId,
        'pairIds': FieldValue.arrayUnion([groupId]),
      });
    } catch (e) {
      debugPrint('_restoreGroup: owner update failed: $e');
    }

    // Delete invite code
    try {
      await _db.collection('inviteCodes').doc(code).delete();
    } catch (e) {
      debugPrint('_restoreGroup: code delete failed: $e');
    }

    final members = List<String>.from(groupData['members'] ?? []);
    final memberNames = Map<String, dynamic>.from(
      groupData['memberNames'] ?? {},
    );
    final memberAvatars = Map<String, dynamic>.from(
      groupData['memberAvatars'] ?? {},
    );
    memberNames[ownerUid] = ownerData['displayName'] ?? 'Partner';
    memberAvatars[ownerUid] = ownerData['avatarUrl'] ?? '';
    memberNames[u.uid] = myData['displayName'] ?? u.displayName ?? 'Partner';
    memberAvatars[u.uid] = myData['avatarUrl'] ?? u.photoURL ?? '';

    // Зеркалим восстановленную пару в Supabase (снимаем disbanded и там тоже).
    unawaited(_mirrorPairToSupabase(groupId, myData));

    return {
      'success': true,
      'message': 'Reconnected!',
      'partnerName': ownerData['displayName'] ?? 'Partner',
      'partnerAvatar': ownerData['avatarUrl'] ?? '',
      'pairId': groupId,
      'startDate':
          (groupData['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      'relationshipType': groupData['relationshipType'] as String? ?? 'couple',
      'customRelationshipLabel':
          groupData['customRelationshipLabel'] as String? ?? '',
      'customRelationshipEmoji':
          groupData['customRelationshipEmoji'] as String? ?? '',
      'customRelationshipTypes':
          groupData['customRelationshipTypes'] as List<dynamic>? ?? <dynamic>[],
      'members': members
          .map(
            (uid) => {
              'uid': uid,
              'name': memberNames[uid] ?? '',
              'avatar': memberAvatars[uid] ?? '',
            },
          )
          .toList(),
      'restored': true,
    };
  }

  /// Join an existing group by groupId.
  Future<Map<String, dynamic>> _joinExistingGroup({
    required String groupId,
    required String code,
    required Map<String, dynamic> myData,
    required String ownerUid,
    required Map<String, dynamic> ownerData,
  }) async {
    final u = currentUser!;
    debugPrint('_joinExistingGroup: trying to join group $groupId');

    // Try to read the group doc directly
    Map<String, dynamic>? groupData;
    List<String> members;
    int maxMembers;

    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        debugPrint('_joinExistingGroup: group $groupId not found');
        return {'success': false, 'message': 'Group not found'};
      }
      groupData = groupDoc.data()!;
      members = List<String>.from(groupData['members'] ?? []);
      maxMembers = (groupData['maxMembers'] as int?) ?? 10;
    } catch (e) {
      // Can't read group (not a member yet) — that's expected
      // We know the group exists because the owner has it, so just proceed
      debugPrint(
        '_joinExistingGroup: cant read group (expected), will add self directly',
      );
      members = [ownerUid]; // We know owner is there
      maxMembers = 2;
      groupData = null;
    }

    if (members.contains(u.uid)) {
      return {'success': false, 'message': 'Вы уже в этой группе'};
    }
    if (members.length >= maxMembers) {
      return {
        'success': false,
        'message': 'Группа заполнена (макс $maxMembers)',
      };
    }

    final myName = myData['displayName'] ?? u.displayName ?? '';
    final myAvatar = myData['avatarUrl'] ?? u.photoURL ?? '';

    // Step 1: Add self to group (allowed by new rules — uid will be in new members)
    try {
      await _db.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayUnion([u.uid]),
        'memberNames.${u.uid}': myName,
        'memberAvatars.${u.uid}': myAvatar,
      });
      debugPrint('_joinExistingGroup: added self to group');
    } catch (e) {
      debugPrint('_joinExistingGroup: failed to update group: $e');
      return {
        'success': false,
        'message': 'Не удалось присоединиться к группе',
      };
    }

    // Step 2: Update MY user document
    try {
      await _db.collection('users').doc(u.uid).update({
        'pairId': groupId,
        'pairIds': FieldValue.arrayUnion([groupId]),
      });
      debugPrint('_joinExistingGroup: my user doc updated');
    } catch (e) {
      debugPrint('_joinExistingGroup: user doc update failed: $e');
    }

    // Step 3: Delete code if group is now full
    if (members.length + 1 >= maxMembers) {
      try {
        await _db.collection('inviteCodes').doc(code).delete();
      } catch (e) {
        debugPrint('_joinExistingGroup: code delete failed: $e');
      }
    }

    // Build response from groupData if available, otherwise from owner data
    final memberNames = groupData != null
        ? Map<String, dynamic>.from(groupData['memberNames'] ?? {})
        : <String, dynamic>{ownerUid: ownerData['displayName'] ?? 'Partner'};
    final memberAvatars = groupData != null
        ? Map<String, dynamic>.from(groupData['memberAvatars'] ?? {})
        : <String, dynamic>{ownerUid: ownerData['avatarUrl'] ?? ''};
    memberNames[u.uid] = myName;
    memberAvatars[u.uid] = myAvatar;

    // Зеркалим обновлённую группу (со мной в members) в Supabase.
    unawaited(_mirrorPairToSupabase(groupId, myData));

    final otherUid = members.isNotEmpty ? members.first : ownerUid;
    return {
      'success': true,
      'message': 'Joined the group!',
      'partnerName': memberNames[otherUid] ?? 'Partner',
      'partnerAvatar': memberAvatars[otherUid] ?? '',
      'pairId': groupId,
      'startDate': groupData != null
          ? ((groupData['startDate'] as Timestamp?)?.toDate() ?? DateTime.now())
          : DateTime.now(),
      'relationshipType': groupData?['relationshipType'] as String? ?? 'couple',
      'customRelationshipLabel':
          groupData?['customRelationshipLabel'] as String? ?? '',
      'customRelationshipEmoji':
          groupData?['customRelationshipEmoji'] as String? ?? '',
      'customRelationshipTypes':
          groupData?['customRelationshipTypes'] as List<dynamic>? ??
          <dynamic>[],
      'members': [...members, u.uid]
          .map(
            (uid) => {
              'uid': uid,
              'name': memberNames[uid] ?? '',
              'avatar': memberAvatars[uid] ?? '',
            },
          )
          .toList(),
    };
  }

  /// Update group maxMembers
  Future<void> updateGroupMaxMembers(String groupId, int maxMembers) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'maxMembers': maxMembers,
      });
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(groupId, {'max_members': maxMembers}));
      }
    } catch (e) {
      debugPrint('updateGroupMaxMembers failed: $e');
    }
  }

  /// Update group relationship type with all fields
  Future<void> updateGroupRelationshipType(
    String groupId, {
    required String type,
    required int maxMembers,
    String customLabel = '',
    String customEmoji = '',
  }) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'relationshipType': type,
        'maxMembers': maxMembers,
        'customRelationshipLabel': customLabel,
        'customRelationshipEmoji': customEmoji,
      });
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(groupId, {
          'relationship_type': type,
          'max_members': maxMembers,
          'custom_relationship_label': customLabel,
          'custom_relationship_emoji': customEmoji,
        }));
      }
    } catch (e) {
      debugPrint('updateGroupRelationshipType failed: $e');
    }
  }

  // ── Celebration dates ──────────────────────────────────────────────────────

  /// Сохраняет дату годовщины для пары (общая для группы).
  Future<void> updateAnniversaryDate(String groupId, DateTime? date) async {
    try {
      await _db.collection('groups').doc(groupId).set({
        'anniversaryDate': date != null ? Timestamp.fromDate(date) : null,
      }, SetOptions(merge: true));
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(
          groupId,
          {'anniversary_date': date?.toIso8601String()},
        ));
      }
    } catch (e) {
      debugPrint('updateAnniversaryDate failed: $e');
    }
  }

  /// Сохраняет дату первого поцелуя для пары (общая для группы).
  Future<void> updateFirstKissDate(String groupId, DateTime? date) async {
    try {
      await _db.collection('groups').doc(groupId).set({
        'firstKissDate': date != null ? Timestamp.fromDate(date) : null,
      }, SetOptions(merge: true));
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(
          groupId,
          {'first_kiss_date': date?.toIso8601String()},
        ));
      }
    } catch (e) {
      debugPrint('updateFirstKissDate failed: $e');
    }
  }

  /// Сохраняет дату рождения текущего пользователя.
  /// Записывает в users/{uid}/birthDate И в groups/{groupId}/memberBirthdays.{uid}.
  Future<void> updateMyBirthDate(DateTime? date) async {
    final u = currentUser;
    if (u == null) return;
    try {
      // users-doc остаётся dual-write (его читают паринг и пуш-функции),
      // поэтому пишем дату и в Firestore, и в Supabase-профиль.
      await _db.collection('users').doc(u.uid).set({
        'birthDate': date != null ? Timestamp.fromDate(date) : null,
      }, SetOptions(merge: true));
      if (_mig) unawaited(_sb.mirrorUser(u.uid, {'birthDate': date}));
      // Обновляем в каждой группе, чтобы партнёр видел дату рождения.
      final groupIds = <String>[];
      // Пробуем прочитать pairIds из users/{uid}
      try {
        final userDoc = await _db.collection('users').doc(u.uid).get();
        final ids = userDoc.data()?['pairIds'] as List?;
        if (ids != null) groupIds.addAll(ids.whereType<String>());
        final legacy = userDoc.data()?['pairId'] as String?;
        if (legacy != null && legacy.isNotEmpty && !groupIds.contains(legacy)) {
          groupIds.add(legacy);
        }
      } catch (_) {}
      for (final gid in groupIds) {
        // Двойная запись: Firebase (источник) + зеркало в Supabase.
        await _db.collection('groups').doc(gid).update({
          'memberBirthdays.${u.uid}': date != null
              ? Timestamp.fromDate(date)
              : FieldValue.delete(),
        });
        if (_dualWrite) unawaited(_sb.setMemberBirthday(gid, u.uid, date));
      }
    } catch (e) {
      debugPrint('updateMyBirthDate failed: $e');
    }
  }

  /// Add a custom relationship type to the group's shared list
  Future<void> addCustomRelationshipType(
    String groupId,
    Map<String, String> entry,
  ) async {
    try {
      final newList = await _db.runTransaction<List<Map<String, dynamic>>>((
        tx,
      ) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final list = List<Map<String, dynamic>>.from(
          (data['customRelationshipTypes'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        if (!list.any((e) => e['id'] == entry['id'])) {
          list.add(Map<String, dynamic>.from(entry));
        }
        tx.set(ref, {'customRelationshipTypes': list}, SetOptions(merge: true));
        return list;
      });
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(groupId, {
          'custom_relationship_types': SupabaseService.jsonSafe(newList),
        }));
      }
    } catch (e) {
      debugPrint('addCustomRelationshipType failed: $e');
    }
  }

  /// Update a custom relationship type in the group's shared list
  Future<void> updateCustomRelationshipType(
    String groupId,
    Map<String, String> entry,
  ) async {
    try {
      final sbUpdates = await _db.runTransaction<Map<String, dynamic>?>((
        tx,
      ) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return null;

        final list = List<Map<String, dynamic>>.from(
          (data['customRelationshipTypes'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        final idx = list.indexWhere((e) => e['id'] == entry['id']);
        if (idx == -1) return null;

        final previous = Map<String, dynamic>.from(list[idx]);
        list[idx] = Map<String, dynamic>.from(entry);

        final updates = <String, dynamic>{'customRelationshipTypes': list};
        final sb = <String, dynamic>{
          'custom_relationship_types': SupabaseService.jsonSafe(list),
        };
        final currentLabel = data['customRelationshipLabel'] as String? ?? '';
        final currentEmoji = data['customRelationshipEmoji'] as String? ?? '';
        final prevLabel = previous['label'] as String? ?? '';
        final prevEmoji = previous['emoji'] as String? ?? '';
        if (currentLabel == prevLabel && currentEmoji == prevEmoji) {
          updates['customRelationshipLabel'] = entry['label'] ?? '';
          updates['customRelationshipEmoji'] = entry['emoji'] ?? '';
          sb['custom_relationship_label'] = entry['label'] ?? '';
          sb['custom_relationship_emoji'] = entry['emoji'] ?? '';
        }

        tx.update(ref, updates);
        return sb;
      });
      if (_dualWrite && sbUpdates != null) {
        unawaited(_sb.mirrorGroupFields(groupId, sbUpdates));
      }
    } catch (e) {
      debugPrint('updateCustomRelationshipType failed: $e');
    }
  }

  /// Delete a custom relationship type from the group's shared list
  Future<void> deleteCustomRelationshipType(String groupId, String id) async {
    try {
      final sbUpdates = await _db.runTransaction<Map<String, dynamic>?>((
        tx,
      ) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return null;

        final list = List<Map<String, dynamic>>.from(
          (data['customRelationshipTypes'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        final removed = list.where((e) => e['id'] == id).toList();
        list.removeWhere((e) => e['id'] == id);

        final updates = <String, dynamic>{'customRelationshipTypes': list};
        final sb = <String, dynamic>{
          'custom_relationship_types': SupabaseService.jsonSafe(list),
        };
        final removedLabel = removed.isNotEmpty
            ? removed.first['label'] as String? ?? ''
            : '';
        final currentType = data['relationshipType'] as String? ?? '';
        final currentLabel = data['customRelationshipLabel'] as String? ?? '';
        if (currentType == 'custom' &&
            removedLabel.isNotEmpty &&
            currentLabel == removedLabel) {
          updates['relationshipType'] = 'couple';
          updates['maxMembers'] = 2;
          updates['customRelationshipLabel'] = '';
          updates['customRelationshipEmoji'] = '';
          sb['relationship_type'] = 'couple';
          sb['max_members'] = 2;
          sb['custom_relationship_label'] = '';
          sb['custom_relationship_emoji'] = '';
        }

        tx.update(ref, updates);
        return sb;
      });
      if (_dualWrite && sbUpdates != null) {
        unawaited(_sb.mirrorGroupFields(groupId, sbUpdates));
      }
    } catch (e) {
      debugPrint('deleteCustomRelationshipType failed: $e');
    }
  }

  /// Load group data by groupId
  Future<Map<String, dynamic>?> loadPairById(String pairId) async {
    final u = currentUser;
    if (u == null || pairId.isEmpty) return null;

    // Stage 2: читаем группу из Firebase (общий источник). Stage 3 — Supabase.
    if (_readSb(pairId)) {
      debugPrint('[SB] loadPairData: reading group $pairId from Supabase');
      final data = await _sb.loadPairById(pairId, u.uid);
      if (data != null) {
        final members = (data['members'] as List)
            .map((m) => (m as Map)['uid'] as String)
            .toList();
        _groupMembersCache[pairId] = members;
        return data;
      }
      // Supabase пуст — падаем на Firebase (он попутно зеркалит в Supabase).
      debugPrint('[FB] loadPairData: Supabase empty, fallback to Firestore');
    }

    try {
      final doc = await _db
          .collection('groups')
          .doc(pairId)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!doc.exists) {
        // Backward compat: try 'pairs' collection
        final pairDoc = await _db
            .collection('pairs')
            .doc(pairId)
            .get()
            .timeout(const Duration(seconds: 10));
        if (!pairDoc.exists) return null;
        return _parseLegacyPairDoc(pairId, pairDoc.data()!);
      }

      final docData = doc.data()!;
      if (docData['disbanded'] == true) return null;
      return _parseGroupDoc(pairId, docData);
    } catch (e) {
      debugPrint('loadPairById($pairId) failed: $e');
      return null;
    }
  }

  Map<String, dynamic> _parseGroupDoc(
    String groupId,
    Map<String, dynamic> data,
  ) {
    final u = currentUser!;
    final rawMembers = List<String>.from(data['members'] ?? []);
    // Deduplicate in case Firestore data has become inconsistent
    final members = rawMembers.toSet().toList();
    // Кешируем участников — sendMissYou/sendVibe кладут recipientUids в event,
    // чтобы функция пуша не читала group-doc.
    _groupMembersCache[groupId] = members;
    // Сидирование: под `_mig` сюда попадаем только на Firestore-фолбэке
    // (Supabase-строки нет). Зеркалим ТОЛЬКО отсутствующую строку — с Этапа 4
    // горячие поля живут в Supabase, и полный снимок затёр бы их устаревшим
    // Firestore-содержимым (например, при временной ошибке сети).
    if (_mig) unawaited(_mirrorGroupRawIfMissing(groupId, data));
    // Миграция: переносим старые Firestore-счётчики «Я скучаю» в RTDB при первом
    // разборе группы после обновления, чтобы у обновившегося не показывало 0/0,
    // пока партнёр на старой версии (которая пишет в group-doc). Только если
    // RTDB ещё пуст — новые тапы не затираем.
    final rawMissYouCounts = data['missYouCounts'];
    if (rawMissYouCounts is Map &&
        rawMissYouCounts.isNotEmpty &&
        !_missYouSeeded.contains(groupId)) {
      _missYouSeeded.add(groupId);
      unawaited(_seedMissYouCountsIfEmpty(groupId, rawMissYouCounts));
    }
    // If duplicates found — silently repair the Firestore document
    if (members.length < rawMembers.length) {
      debugPrint(
        '_parseGroupDoc: duplicates detected in $groupId, repairing...',
      );
      _db
          .collection('groups')
          .doc(groupId)
          .update({'members': members})
          .catchError((e) => debugPrint('auto-repair members failed: $e'));
    }
    final memberNames = Map<String, dynamic>.from(data['memberNames'] ?? {});
    final memberAvatars = Map<String, dynamic>.from(
      data['memberAvatars'] ?? {},
    );

    final otherUids = members.where((m) => m != u.uid).toList();
    final partnerUid = otherUids.isNotEmpty ? otherUids.first : '';

    return {
      'pairId': groupId,
      'partnerName': memberNames[partnerUid] ?? '',
      'partnerAvatar': memberAvatars[partnerUid] ?? '',
      'startDate': (data['startDate'] as Timestamp?)?.toDate(),
      'members': members
          .map(
            (uid) => {
              'uid': uid,
              'name': memberNames[uid] ?? '',
              'avatar': memberAvatars[uid] ?? '',
            },
          )
          .toList(),
      'maxMembers': data['maxMembers'] ?? 2,
      'memberMoods': (data['memberMoods'] as Map<String, dynamic>? ?? {}).map((
        uid,
        moodData,
      ) {
        final moodMap = Map<String, dynamic>.from(moodData as Map);
        final ts = moodMap['updatedAt'];
        if (ts is Timestamp) {
          moodMap['updatedAt'] = ts.toDate();
        }
        return MapEntry(uid, moodMap);
      }),
      'memberAilments':
          (data['memberAilments'] as Map<String, dynamic>? ?? {}).map((
        uid,
        ailData,
      ) {
        final ailMap = Map<String, dynamic>.from(ailData as Map);
        final ts = ailMap['updatedAt'];
        if (ts is Timestamp) {
          ailMap['updatedAt'] = ts.toDate();
        }
        return MapEntry(uid, ailMap);
      }),
      'currentStatus': data['currentStatus'] as Map<String, dynamic>?,
      'customStatuses': data['customStatuses'] as List<dynamic>?,
      'relationshipType': data['relationshipType'] as String?,
      'customRelationshipLabel': data['customRelationshipLabel'] as String?,
      'customRelationshipEmoji': data['customRelationshipEmoji'] as String?,
      'customRelationshipTypes':
          data['customRelationshipTypes'] as List<dynamic>?,
      'anniversaryDate': (data['anniversaryDate'] as Timestamp?)?.toDate(),
      'firstKissDate': (data['firstKissDate'] as Timestamp?)?.toDate(),
      'memberBirthdays': () {
        final raw = data['memberBirthdays'] as Map<String, dynamic>?;
        if (raw == null) return null;
        return raw.map(
          (k, v) => MapEntry(k, v is Timestamp ? v.toDate() : null),
        );
      }(),
      'raw': data,
    };
  }

  Map<String, dynamic> _parseLegacyPairDoc(
    String pairId,
    Map<String, dynamic> data,
  ) {
    final u = currentUser!;
    final isUser1 = data['user1'] == u.uid;
    return {
      'pairId': pairId,
      'partnerName': isUser1 ? data['user2Name'] : data['user1Name'],
      'partnerAvatar': isUser1 ? data['user2Avatar'] : data['user1Avatar'],
      'startDate': (data['startDate'] as Timestamp?)?.toDate(),
      'members': [
        {
          'uid': data['user1'],
          'name': data['user1Name'] ?? '',
          'avatar': data['user1Avatar'] ?? '',
        },
        {
          'uid': data['user2'],
          'name': data['user2Name'] ?? '',
          'avatar': data['user2Avatar'] ?? '',
        },
      ],
      'maxMembers': 2,
      'raw': data,
    };
  }

  Future<Map<String, dynamic>?> loadPairData() async {
    final u = currentUser;
    if (u == null) return null;

    try {
      final userDoc = await _db
          .collection('users')
          .doc(u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      final pairId = userDoc.data()?['pairId'] as String?;
      if (pairId == null || pairId.isEmpty) return null;

      return await loadPairById(pairId);
    } catch (e) {
      debugPrint('loadPairData failed: $e');
      return null;
    }
  }

  /// Самолечение «потерянных» И РАСЩЕПЛЁННЫХ групп при старте.
  ///
  /// Чинит два симптома сразу, опираясь на реальное членство (`members[]`), а
  /// не на `pairIds` (который мог обнулиться или потерять одну из групп):
  ///
  ///  1. «Потеряли группу»: какой-то путь (переустановка / повторный вход)
  ///     обнулил `pairIds`, НЕ распуская группу. Возвращаем живые группы в
  ///     `pairIds` — слушатель user-документа ([listenToUserDoc]) привяжет их.
  ///
  ///  2. «Расщеплённая пара» (симптом из отзывов: видно только свои настроения/
  ///     «скучаю»/фото, данных партнёра нет): на одну и ту же пару оказалось
  ///     ДВЕ живые группы (гонка взаимного коннекта + частично упавшие
  ///     кросс-записи). Партнёр пишет в одну, ты читаешь из другой. Здесь мы
  ///     ДЕТЕРМИНИРОВАННО сливаем такие дубли через сервер
  ///     ([mergeDuplicateGroups]) прямо на старте — не полагаясь на отложенный
  ///     цикл rebuild→cleanup, — и проверяем, что на каждого партнёра осталась
  ///     ровно одна группа. Сервер сам выбирает канон (старейшую группу),
  ///     переносит данные и чинит pairIds ОБОИХ участников; операция
  ///     идемпотентна и безопасна при гонке двух устройств.
  ///
  /// Запрос по `members arrayContains uid` разрешён правилами (как и в
  /// [_findDisbandedGroup]) и остаётся в рамках собственных групп пользователя.
  /// Возвращает id выживших (канонических) групп — по одной на партнёра.
  Future<List<String>> selfHealActiveGroups() async {
    final u = currentUser;
    if (u == null) return const [];
    try {
      // 1) Все живые группы (>=2 участника), где мы реально в members[].
      final snap = await _db
          .collection('groups')
          .where('members', arrayContains: u.uid)
          .get()
          .timeout(const Duration(seconds: 15));

      // groupId -> отсортированный список партнёров (members без меня) и дата
      // создания (для группировки по паре и детерминированного выбора канона).
      final partnersByGroup = <String, List<String>>{};
      final createdAtByGroup = <String, Timestamp?>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['disbanded'] == true) continue;
        if (data['mergedInto'] != null) continue; // дубль, уже слитый ранее
        final members = List<String>.from(data['members'] ?? [])
            .where((m) => m.isNotEmpty)
            .toSet();
        // «Группа из одного» — мусор (остатки тестов/недозавершённых пар).
        if (members.length < 2 || !members.contains(u.uid)) continue;
        final partners = (members.toList()..remove(u.uid))..sort();
        partnersByGroup[doc.id] = partners;
        createdAtByGroup[doc.id] = data['createdAt'] as Timestamp?;
      }
      if (partnersByGroup.isEmpty) return const [];

      // 2) Сгруппировать живые группы по набору партнёров.
      final groupsByPartnerKey = <String, List<String>>{};
      partnersByGroup.forEach((gid, partners) {
        groupsByPartnerKey.putIfAbsent(partners.join(','), () => []).add(gid);
      });

      // 3) На каждого партнёра — ровно одна группа. Дубли сливаем через сервер
      //    в детерминированном порядке (старейшая = канон), используя
      //    возвращённый сервером канон для следующей итерации.
      final survivors = <String>[];
      for (final ids in groupsByPartnerKey.values) {
        if (ids.length == 1) {
          survivors.add(ids.first);
          continue;
        }
        ids.sort((a, b) {
          final ta = createdAtByGroup[a];
          final tb = createdAtByGroup[b];
          if (ta == null && tb == null) return a.compareTo(b);
          if (ta == null) return 1; // без даты создания — в конец
          if (tb == null) return -1;
          return ta.compareTo(tb); // старейшая первой
        });
        debugPrint(
          'selfHealActiveGroups: расщеплённая пара — ${ids.length} живых '
          'групп(ы) на одного партнёра: $ids — сливаю',
        );
        var canonical = ids.first;
        var allMerged = true;
        for (var i = 1; i < ids.length; i++) {
          final merged = await mergeDuplicateGroups(canonical, ids[i]);
          if (merged != null) {
            canonical = merged;
          } else {
            allMerged = false; // не удалось — повторим на следующем старте
          }
        }
        survivors.add(canonical);
        if (!allMerged) {
          debugPrint(
            'selfHealActiveGroups: не все дубли слиты для $ids — повтор позже',
          );
        }
      }

      // 4) Вернуть выжившие (канонические) группы в pairIds, если их там нет.
      //    (Сервер при merge уже чинит pairIds, но недубликатные «потерянные»
      //    группы тоже нужно вернуть — поэтому проверяем все survivors.)
      final userDoc = await _db
          .collection('users')
          .doc(u.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      final known = <String>{};
      final pairIdsList = userDoc.data()?['pairIds'] as List<dynamic>?;
      if (pairIdsList != null) {
        known.addAll(
          pairIdsList.whereType<String>().where((s) => s.isNotEmpty),
        );
      }
      final legacy = userDoc.data()?['pairId'] as String?;
      if (legacy != null && legacy.isNotEmpty) known.add(legacy);

      final missing = survivors.where((id) => !known.contains(id)).toList();
      if (missing.isNotEmpty) {
        await _db
            .collection('users')
            .doc(u.uid)
            .set({
              'pairIds': FieldValue.arrayUnion(missing),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
        debugPrint(
          'selfHealActiveGroups: restored ${missing.length} group(s): $missing',
        );
      }
      return survivors;
    } catch (e) {
      debugPrint('selfHealActiveGroups failed: $e');
      return const [];
    }
  }

  /// Diagnostic + cleanup for the "phantom member" bug.
  ///
  /// Symptom: header shows N+1 avatars / "Group of N+1" while Members list
  /// renders only N. Root cause: `members[]` in Firestore contains an extra
  /// UID that belongs to the same person (current user) but from an older
  /// auth session (different sign-in method or recreated account). Since
  /// `Connection.partners` filters by `uid != myUid`, the phantom-self uid
  /// passes the filter and is counted as a partner.
  ///
  /// This method prints every member's uid + email + displayName, then
  /// removes any uid that:
  ///   - has no users/{uid} document (orphan), OR
  ///   - has the same email as the current user but a different uid
  ///     (phantom-self from an earlier session).
  ///
  /// Returns the list of removed uids. Safe to call repeatedly — does nothing
  /// when no phantoms exist.
  Future<List<String>> cleanupPhantomMembersInGroup(
    String groupId, {
    bool force = false,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return const [];

    // Сначала читаем group doc (1 read) — нужно знать members/maxMembers, чтобы
    // решить, можно ли пропустить дорогой per-user скан по троттлу.
    final Map<String, dynamic> data;
    final List<String> members;
    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return const [];
      data = groupDoc.data()!;
      final rawMembers = List<String>.from(data['members'] ?? []);
      members = rawMembers.toSet().toList();
    } catch (e) {
      debugPrint(
        'cleanupPhantomMembersInGroup($groupId) group read failed: $e',
      );
      return const [];
    }
    if (members.length <= 1) return const [];

    final maxMembers = (data['maxMembers'] as num?)?.toInt() ?? 2;
    final overCapacity = members.length > maxMembers;

    // Throttle: фантомы — редкий баг. Per-user скан (N×user.get) гоняем не чаще
    // раза в сутки. НО при переполнении группы (overCapacity) или явном force
    // лечим немедленно — это и есть видимый баг «Группа из N+1».
    if (!force && !overCapacity) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'phantom_check_last_$groupId';
        final lastMs = prefs.getInt(key) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        const oneDayMs = 24 * 60 * 60 * 1000;
        if (now - lastMs < oneDayMs) return const [];
        await prefs.setInt(key, now);
      } catch (_) {
        // SharedPreferences недоступны — продолжаем без throttle.
      }
    }

    try {
      final memberAvatars = Map<String, dynamic>.from(
        data['memberAvatars'] ?? {},
      );

      // Читаем user doc КАЖДОГО участника (включая себя), различая
      // «документа нет» (orphan) и «ошибка чтения» (не трогаем).
      final docExists = <String, bool>{};
      final docData = <String, Map<String, dynamic>>{};
      for (final uid in members) {
        try {
          final d = await _db.collection('users').doc(uid).get();
          docExists[uid] = d.exists;
          if (d.exists) docData[uid] = d.data() ?? const <String, dynamic>{};
        } catch (e) {
          debugPrint('  [skip] $uid — cant read user doc: $e');
          // null/unknown — не считаем orphan, чтобы не удалить при сбое сети.
        }
      }

      // Мой email — из Auth (свежий), иначе из своего user doc.
      String myEmail = (u.email ?? '').toLowerCase();
      if (myEmail.isEmpty) {
        myEmail = (docData[u.uid]?['email'] as String? ?? '').toLowerCase();
      }

      debugPrint(
        'cleanupPhantomMembersInGroup($groupId): myUid=${u.uid}, '
        'myEmail=$myEmail, members=$members, overCapacity=$overCapacity',
      );

      final phantoms = <String>[];

      // 1) Orphans: участник, у которого ТОЧНО нет user doc (get вернул !exists),
      //    и это не я. Старая логика — оставляем.
      for (final uid in members) {
        if (uid == u.uid) continue;
        if (docExists[uid] == false) {
          debugPrint('  [orphan] $uid — no users/$uid doc, will remove');
          phantoms.add(uid);
        }
      }

      // 2) Self-twins: участники с тем же email, что и у меня (включая меня).
      //    Это разные uid одного человека (Google + email/пароль). Из кластера
      //    оставляем ОДНОГО «настоящего» — детерминированно, по следам
      //    активности, НЕ по тому, кто сейчас залогинен. Тогда оригинал не
      //    удалит ни одно устройство, а планшет-фантом при необходимости
      //    выселит сам себя.
      if (myEmail.isNotEmpty) {
        final twins = <String>[];
        for (final uid in members) {
          if (phantoms.contains(uid)) continue; // уже помечен orphan
          final email = uid == u.uid
              ? myEmail
              : (docData[uid]?['email'] as String? ?? '').toLowerCase();
          if (email == myEmail) twins.add(uid);
        }

        if (twins.length >= 2) {
          // Очки «настоящести» — считаются ТОЛЬКО из Firestore-данных, поэтому
          // одинаковы на всех устройствах (детерминизм → нет гонки/двойного
          // удаления). Текущая сессия НЕ получает бонуса.
          int score(String uid) {
            var s = 0;
            final avatarInGroup =
                (memberAvatars[uid] as String? ?? '').isNotEmpty;
            if (avatarInGroup) s += 4;
            final profileAvatar =
                (docData[uid]?['avatarUrl'] as String? ?? '').isNotEmpty;
            if (profileAvatar) s += 2;
            if ((docData[uid]?['pairId'] as String?) == groupId) s += 1;
            return s;
          }

          // Победитель = max score; тай-брейк — меньший uid (стабильно).
          final winner = twins.reduce((a, b) {
            final sa = score(a), sb = score(b);
            if (sa != sb) return sa > sb ? a : b;
            return a.compareTo(b) <= 0 ? a : b;
          });

          for (final uid in twins) {
            if (uid != winner && !phantoms.contains(uid)) {
              debugPrint(
                '  [phantom-self] $uid — same email, lost to winner=$winner '
                '(score ${score(uid)} vs ${score(winner)}), will remove',
              );
              phantoms.add(uid);
            }
          }
          debugPrint('  [self-twins] keeping winner=$winner of $twins');
        }
      }

      if (phantoms.isEmpty) {
        debugPrint(
          'cleanupPhantomMembersInGroup($groupId): no phantoms detected',
        );
        return const [];
      }

      final updates = <String, dynamic>{
        'members': FieldValue.arrayRemove(phantoms),
      };
      for (final p in phantoms) {
        updates['memberNames.$p'] = FieldValue.delete();
        updates['memberAvatars.$p'] = FieldValue.delete();
        updates['memberMoods.$p'] = FieldValue.delete();
      }

      await _db
          .collection('groups')
          .doc(groupId)
          .update(updates)
          .timeout(const Duration(seconds: 10));
      debugPrint(
        'cleanupPhantomMembersInGroup($groupId): removed ${phantoms.length} phantom(s): $phantoms',
      );
      return phantoms;
    } catch (e) {
      debugPrint('cleanupPhantomMembersInGroup($groupId) failed: $e');
      return const [];
    }
  }

  /// true — группы действительно больше нет (удалена/распущена и в Firestore).
  /// false — группа жива (миграционная гонка: Supabase-строка ещё не создана)
  /// ИЛИ Firestore недоступен — в обоих случаях «группы нет» сообщать нельзя.
  Future<bool> _verifyPairGone(String groupId) async {
    try {
      final doc = await _db.collection('groups').doc(groupId).get();
      final data = doc.data();
      if (!doc.exists || data == null) return true;
      if (data['disbanded'] == true) return true;
      // Жива в Firestore → засеваем Supabase-строку и запускаем полный
      // миграционный проход; realtime-листенер получит INSERT.
      debugPrint(
        '_verifyPairGone($groupId): группа жива в Firestore — засеваем Supabase',
      );
      await _mirrorGroupRawIfMissing(groupId, data);
      unawaited(_runSupabaseMigration(groupId));
      return false;
    } catch (e) {
      // Ошибка чтения (сеть/правила) — не рискуем расспариванием.
      debugPrint('_verifyPairGone($groupId) failed: $e');
      return false;
    }
  }

  /// Слить две группы одной пары (раскол после «потерянной группы»).
  ///
  /// Сервер детерминированно выбирает канон (старейшая группа), переносит в
  /// него данные дубликата (счётчики, воспоминания, чат, настроения, серию),
  /// помечает дубликат disbanded и чинит pairIds обоих участников. Идемпотентно
  /// и защищено от гонки устройств. Возвращает id канонической группы или
  /// null при ошибке (тогда повторим на следующем старте).
  Future<String?> mergeDuplicateGroups(
    String groupIdA,
    String groupIdB,
  ) async {
    try {
      final res = await _functions
          .httpsCallable('mergeDuplicateGroups')
          .call<Map<dynamic, dynamic>>({
            'groupIdA': groupIdA,
            'groupIdB': groupIdB,
          })
          .timeout(const Duration(seconds: 120));
      final data = Map<String, dynamic>.from(res.data);
      final canonicalId = data['canonicalId'] as String?;
      debugPrint(
        'mergeDuplicateGroups($groupIdA, $groupIdB): canonical=$canonicalId, '
        'merged=${data['merged']}',
      );
      return canonicalId;
    } catch (e) {
      debugPrint('mergeDuplicateGroups failed: $e');
      return null;
    }
  }

  /// Remove a stale groupId from the user's pairIds list in Firestore.
  /// Called when a group turns out to have no partners (orphaned after testing).
  Future<void> removeStaleGroupFromUser(String groupId) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db
          .collection('users')
          .doc(u.uid)
          .update({
            'pairIds': FieldValue.arrayRemove([groupId]),
          })
          .timeout(const Duration(seconds: 10));
      debugPrint('removeStaleGroupFromUser: removed $groupId from user doc');
    } catch (e) {
      debugPrint('removeStaleGroupFromUser failed: $e');
    }
  }

  /// Listen to group changes in real-time
  StreamSubscription? listenToPair({
    required String pairId,
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    // Совместимость смешанных пар: пишем свой маркер «я на новой сборке» в
    // group-doc и резолвим, на новой ли сборке партнёр. Fire-and-forget —
    // НЕ влияет на маршрутизацию ниже (источник переключается на следующей
    // сессии), поэтому регрессии нет; цель — наполнить маркеры/_groupMixed.
    if (_mig) unawaited(_resolveGroupCompat(pairId));
    // Stage 2: живая группа читается из Firebase (общий источник — партнёр на
    // старой версии пишет туда). Stage 3 вернёт Supabase-realtime через _readSb.
    if (_readSb(pairId)) {
      final uid = _auth.currentUser?.uid ?? '';
      var verifyingGone = false;
      return _sb.listenPair(pairId, uid, (data) {
        if (data == null) {
          // ПУСТОЙ снимок ≠ «группы нет». У только что обновившегося юзера
          // строки groups в Supabase ещё нет (зеркало/бэкфилл в полёте), а
          // потребитель (Connection._listenToPair) на null СНИМАЕТ паринг и
          // вычищает группу из pairIds — ложный null равен «потерял группу».
          // Поэтому сверяемся с Firestore: группа жива → засеваем строку и
          // молчим (realtime INSERT доставит данные), мертва → пробрасываем.
          if (verifyingGone) return;
          verifyingGone = true;
          _verifyPairGone(pairId).then((gone) {
            verifyingGone = false;
            if (gone) onData(null);
          });
          return;
        }
        // Кеш участников для пушей (как в _parseGroupDoc).
        final members = (data['members'] as List?)
                ?.map((m) => ((m as Map)['uid'] ?? '').toString())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const <String>[];
        if (members.isNotEmpty) _groupMembersCache[pairId] = members;
        onData(data);
      });
    }
    // Shared hub — every listener for this group reuses one underlying
    // Firestore subscription. `includeMetadataChanges` is intentionally OFF:
    // metadata-only updates don't change any field the UI reads, and they
    // would double-charge every consumer downstream.
    return _groupDocStream(pairId).listen((snap) async {
      if (snap.exists) {
        final rawData = snap.data()!;
        if (rawData['disbanded'] == true) {
          debugPrint('listenToPair: group disbanded, treating as deleted');
          onData(null);
          return;
        }
        final parsedData = _parseGroupDoc(pairId, rawData);
        onData(parsedData);
      } else {
        debugPrint('listenToPair: group document deleted or not found');
        try {
          final pairSnap = await _db
              .collection('pairs')
              .doc(pairId)
              .get(const GetOptions(source: Source.server));
          if (pairSnap.exists) {
            onData(_parseLegacyPairDoc(pairId, pairSnap.data()!));
          } else {
            onData(null);
          }
        } catch (_) {
          onData(null);
        }
      }
    }, onError: (e) => debugPrint('listenToPair error: $e'));
  }

  /// Remove me from a group (or delete if ≤2 members)
  Future<void> unpairById(String groupId) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;

    var groupDoc = await _db.collection('groups').doc(groupId).get();

    if (groupDoc.exists) {
      final data = groupDoc.data()!;
      final members = List<String>.from(data['members'] ?? []);

      if (members.length <= 2) {
        // Soft-delete: mark as disbanded so data can be restored on reconnect
        final batch = _db.batch();
        batch.update(_db.collection('groups').doc(groupId), {
          'disbanded': true,
          'disbandedAt': FieldValue.serverTimestamp(),
        });
        for (final member in members) {
          batch.update(_db.collection('users').doc(member), {
            'pairIds': FieldValue.arrayRemove([groupId]),
          });
        }
        await batch.commit();

        // Миграция: зеркалим роспуск в Supabase, иначе партнёр, читающий группу
        // из Supabase (listenPair), не увидел бы disbanded=true и группа осталась
        // бы у него. Точечный update — полный снимок Firestore-дока затёр бы
        // горячие поля, которые с Этапа 4 живут только в Supabase.
        if (_mig) {
          unawaited(_sb.mirrorGroupFields(groupId, {
            'disbanded': true,
            'disbanded_at': DateTime.now().toIso8601String(),
          }));
        }

        for (final member in members) {
          final memberDoc = await _db.collection('users').doc(member).get();
          final remaining =
              (memberDoc.data()?['pairIds'] as List<dynamic>?) ?? [];
          await _db.collection('users').doc(member).update({
            'pairId': remaining.isNotEmpty ? remaining.last : '',
          });
        }
      } else {
        // Just leave the group
        debugPrint(
          'unpairById: leaving group $groupId (${members.length} members)',
        );

        // Update group document first to remove this member
        await _db.collection('groups').doc(groupId).update({
          'members': FieldValue.arrayRemove([u.uid]),
          'memberNames.${u.uid}': FieldValue.delete(),
          'memberAvatars.${u.uid}': FieldValue.delete(),
          'memberMoods.${u.uid}': FieldValue.delete(),
        });
        unawaited(_mirrorGroupDocToSupabase(groupId));

        debugPrint('unpairById: removed from group, updating user doc');

        // Then update user's pairIds
        await _db.collection('users').doc(u.uid).update({
          'pairIds': FieldValue.arrayRemove([groupId]),
        });

        // Update user's active pairId
        final myDoc = await _db.collection('users').doc(u.uid).get();
        final remaining = (myDoc.data()?['pairIds'] as List<dynamic>?) ?? [];
        await _db.collection('users').doc(u.uid).update({
          'pairId': remaining.isNotEmpty ? remaining.last : '',
        });

        debugPrint('unpairById: successfully left group');
      }
      return;
    }

    // Fallback: legacy pairs collection
    final pairDoc = await _db.collection('pairs').doc(groupId).get();
    if (!pairDoc.exists) return;

    final pData = pairDoc.data()!;
    final partnerId = pData['user1'] == u.uid ? pData['user2'] : pData['user1'];

    final batch = _db.batch();
    batch.delete(_db.collection('pairs').doc(groupId));
    batch.update(_db.collection('users').doc(u.uid), {
      'pairId': '',
      'pairIds': FieldValue.arrayRemove([groupId]),
    });
    if (partnerId != null) {
      batch.update(_db.collection('users').doc(partnerId as String), {
        'pairId': '',
        'pairIds': FieldValue.arrayRemove([groupId]),
      });
    }
    await batch.commit();
  }

  Future<void> unpair() async {
    final u = currentUser;
    if (u == null) return;
    final userDoc = await _db.collection('users').doc(u.uid).get();
    final pairId = userDoc.data()?['pairId'] as String?;
    if (pairId == null || pairId.isEmpty) return;
    await unpairById(pairId);
  }

  // ══════════════════════════════════════════════
  //  REAL-TIME LISTENERS
  // ══════════════════════════════════════════════

  StreamSubscription? listenToUserDoc({
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    final u = currentUser;
    if (u == null) return null;

    // Shared hub for users/{uid} — same dedup reasoning as the group hub.
    return _userDocStream(u.uid).listen((snap) {
      if (snap.exists) {
        onData(snap.data());
      } else {
        onData(null);
      }
    }, onError: (e) => debugPrint('listenToUserDoc error: $e'));
  }

  // ══════════════════════════════════════════════
  //  TOGETHER SESSIONS (совместные занятия)
  //  Приглашение хранится в group-doc.activeSession и доставляется через
  //  УЖЕ работающий group-doc hub-листенер → НОЛЬ новых Firestore-чтений.
  //  Сама синхронизация плеера идёт в RTDB (TogetherSessionService).
  // ══════════════════════════════════════════════

  /// Поток активного приглашения для группы. Реюзает hub-подписку group-doc,
  /// поэтому новых чтений не создаёт.
  Stream<Map<String, dynamic>?> activeSessionStream(String pairId) {
    // Stage 2: activeSession читается из Firebase (его пишет и партнёр на старой
    // версии). Stage 3 вернёт Supabase-realtime через _readSb.
    if (_readSb(pairId)) return _sb.watchActiveSession(pairId);
    return _groupDocStream(pairId).map(
      (snap) => snap.exists
          ? (snap.data()?['activeSession'] as Map<String, dynamic>?)
          : null,
    );
  }

  /// Объявить активный совместный сеанс (вызывает хост). Один write —
  /// партнёрский live-листенер ловит его без дополнительного чтения.
  Future<void> setActiveSession({
    required String groupId,
    required String activity,
    required String mediaId,
    required String hostName,
  }) async {
    if (groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).set({
        'activeSession': {
          'activity': activity,
          'mediaId': mediaId,
          'hostUid': uid,
          'hostName': hostName,
          'startedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(groupId, {
          'active_session': {
            'activity': activity,
            'mediaId': mediaId,
            'hostUid': uid,
            'hostName': hostName,
            'startedAt': DateTime.now().toIso8601String(),
          },
        }));
      }
    } catch (e) {
      debugPrint('setActiveSession failed: $e');
    }
  }

  /// Убрать активный сеанс из group-doc.
  Future<void> clearActiveSession(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).update({
        'activeSession': FieldValue.delete(),
      });
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(groupId, {'active_session': null}));
      }
    } catch (e) {
      debugPrint('clearActiveSession failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  MEMORIES — shared timeline for each group
  //  Firestore: groups/{groupId}/memories/{memoryId}
  // ══════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════════════════
  // FILE UPLOAD (Storage)
  // ══════════════════════════════════════════════════════════════════════════════

  // ── Signed URL ──────────────────────────────────────────────────────────────

  // Кэш подписанных URL: gsPath → {url, expiresAt}.
  // TTL 55 мин — облачная функция выдаёт на 60 мин, буфер 5 мин на запрос.
  final Map<String, _SignedUrlEntry> _signedUrlCache = {};

  /// Получить временный Signed URL для gs:// пути ИЛИ sb:// пути.
  /// Результат кэшируется на 55 минут. https:// URL возвращается как есть.
  /// Резолвит медиа-URL в проигрываемый http(s)-URL для видеоплеера / launchUrl.
  /// sb://→signed (Supabase), gs://bucket/path→signed (CF), http/file→как есть.
  /// Картинки делают то же через StorageImage; видео раньше получало сырой
  /// sb://, из-за чего плеер не запускался (показывалось только превью).
  Future<String> resolveMediaUrl(String url) async {
    if (url.isEmpty) return url;
    if (url.startsWith('sb://')) {
      return (await getSignedUrl(url)) ?? url;
    }
    if (url.startsWith('gs://')) {
      final bare = url.replaceFirst(RegExp(r'^gs://[^/]+/'), '');
      return (await getSignedUrl(bare)) ?? url;
    }
    return url; // http(s) или локальный файл — играем как есть
  }

  Future<String?> getSignedUrl(String path) async {
    if (path.isEmpty) return null;
    // Обратная совместимость: старые записи хранят download URL
    if (path.startsWith('http')) return path;
    // Фаза 1: Supabase Storage
    if (path.startsWith('sb://')) {
      debugPrint('[SB] getSignedUrl: resolving $path');
      return _sb.getStorageSignedUrl(path);
    }
    debugPrint('[FB] getSignedUrl: calling Cloud Function for $path');

    final cached = _signedUrlCache[path];
    if (cached != null && cached.isValid) return cached.url;

    try {
      final res = await _functions
          .httpsCallable('getSignedUrl')
          .call<Map<dynamic, dynamic>>({'gsPath': path})
          .timeout(const Duration(seconds: 15));
      final data = Map<String, dynamic>.from(res.data);
      final url = data['url'] as String?;
      final expiresAt = data['expiresAt'] as int?;
      if (url != null && expiresAt != null) {
        _signedUrlCache[path] = _SignedUrlEntry(
          url,
          DateTime.fromMillisecondsSinceEpoch(expiresAt),
        );
        return url;
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('getSignedUrl failed: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('getSignedUrl failed: $e');
    }
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────────

  /// Upload file to Firebase Storage and return download URL
  /// [path] - file path on device
  /// [destination] - storage path (e.g. 'memories/groupId/filename.jpg')
  Future<String?> uploadFile(String path, String destination) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('uploadFile: File does not exist: $path');
        return null;
      }

      final fileSize = await file.length();
      debugPrint(
        'uploadFile: Starting upload of $destination ($fileSize bytes)',
      );
      debugPrint('uploadFile: Storage bucket = ${_storage.bucket}');

      // Determine content type from extension
      final ext = path.split('.').last.toLowerCase();
      String? contentType;
      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        contentType = 'image/$ext';
      } else if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        contentType = 'video/$ext';
      } else if (['mp3', 'aac', 'wav', 'ogg', 'm4a', 'flac'].contains(ext)) {
        contentType = 'audio/$ext';
      }

      // Convert raster images to WebP before upload — typically 30-60% smaller
      // than JPEG at equivalent visual quality. Storage path gets .webp extension.
      File fileToUpload = file;
      var uploadDestination = destination;
      if (['jpg', 'jpeg', 'png'].contains(ext)) {
        try {
          final tempDir = await getTemporaryDirectory();
          final targetPath =
              '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_comp.webp';
          final xFile = await FlutterImageCompress.compressAndGetFile(
            path,
            targetPath,
            quality: 87,
            format: CompressFormat.webp,
            autoCorrectionAngle: true,
            keepExif: false,
          );
          if (xFile != null) {
            final webpFile = File(xFile.path);
            final webpSize = await webpFile.length();
            debugPrint(
              'uploadFile: WebP conversion $fileSize → $webpSize bytes',
            );
            if (webpSize < fileSize) {
              fileToUpload = webpFile;
              contentType = 'image/webp';
              uploadDestination = destination.replaceAll(
                RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false),
                '.webp',
              );
            } else {
              // WebP turned out larger — keep the original
              debugPrint(
                'uploadFile: WebP larger than original, uploading original $ext',
              );
              webpFile.delete().catchError((_) => webpFile);
            }
          }
        } catch (e) {
          debugPrint(
            'uploadFile: WebP conversion failed, uploading original: $e',
          );
        }
      }

      // Compress video before upload — uses device hardware encoder (H.264).
      // HighestQuality keeps original resolution and framerate; typical savings
      // are 60-80% vs camera-recorded files with no perceptible quality loss.
      File? _compressedTempFile;
      if (!kIsWeb && ['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        try {
          final info = await VideoCompress.compressVideo(
            path,
            quality: VideoQuality.HighestQuality,
            deleteOrigin: false,
            includeAudio: true,
          );
          if (info?.file != null) {
            _compressedTempFile = info!.file!;
            fileToUpload = _compressedTempFile;
            contentType = 'video/mp4';
            uploadDestination = destination.replaceAll(
              RegExp(r'\.(mov|avi|mkv)$', caseSensitive: false),
              '.mp4',
            );
            debugPrint(
              'uploadFile: Video compressed $fileSize → ${await fileToUpload.length()} bytes',
            );
          }
        } catch (e) {
          debugPrint(
            'uploadFile: Video compression failed, uploading original: $e',
          );
          // cancelCompression only on error — calling it after success on some
          // Android devices leaves the native codec spinning and freezes the UI.
          VideoCompress.cancelCompression();
        }
      }

      // Медиа полностью мигрированной группы → Supabase Storage (sb://),
      // синхронно с её данными (Stage 4). Не-мигрированные/смешанные группы и
      // негрупповые пути (аватары) → Firebase Storage (https://-URL читают обе
      // версии — безопасно для смешанных пар и отката).
      if (_uploadGroupMediaToSupabase(uploadDestination)) {
        final bytes = await fileToUpload.readAsBytes();
        final sbRef = await _sb.uploadStorageFile(
          bytes,
          uploadDestination,
          contentType: contentType,
        );
        _compressedTempFile?.delete().catchError((_) {});
        debugPrint('[SB] uploadFile → $sbRef');
        return sbRef;
      }
      debugPrint('[FB] uploadFile → Firebase Storage: $uploadDestination');

      final metadata = contentType != null
          ? SettableMetadata(contentType: contentType)
          : null;

      final ref = _storage.ref().child(uploadDestination);
      final uploadTask = ref.putFile(fileToUpload, metadata);

      // Monitor upload progress
      uploadTask.snapshotEvents.listen((event) {
        final progress = event.bytesTransferred / event.totalBytes;
        debugPrint(
          'uploadFile: Progress ${(progress * 100).toStringAsFixed(1)}%',
        );
      });

      final snapshot = await uploadTask;

      // Для групповых путей возвращаем gs:// — доступ только через Signed URL.
      // Для аватарок (avatars/) оставляем download URL: они намеренно доступны
      // любому авторизованному пользователю и не несут private-данных группы.
      const privatePathPrefixes = [
        'memories/',
        'groups/',
        'music/',
        'timer_backgrounds/',
        'widget/',
      ];
      final isPrivatePath = privatePathPrefixes.any(
        uploadDestination.startsWith,
      );

      String resultUrl;
      if (isPrivatePath) {
        resultUrl = 'gs://${snapshot.ref.bucket}/${snapshot.ref.fullPath}';
      } else {
        resultUrl = await snapshot.ref.getDownloadURL();
      }

      debugPrint('uploadFile: Success! result = $resultUrl');
      _compressedTempFile?.delete().catchError((_) {});
      return resultUrl;
    } on FirebaseException catch (e) {
      debugPrint(
        'uploadFile FirebaseException: code=${e.code} message=${e.message}',
      );
      if (e.code == 'object-not-found') {
        debugPrint(
          'uploadFile: Firebase Storage bucket may not be activated. '
          'Go to Firebase Console → Storage → Get Started to enable it.',
        );
      }
      return null;
    } catch (e) {
      debugPrint('uploadFile failed: $e');
      return null;
    }
  }

  /// Удалить файл из Firebase Storage (gs:// / https://) или Supabase (sb://).
  Future<void> deleteFileByUrl(String url) async {
    if (url.startsWith('sb://')) {
      await _sb.deleteStorageFile(url);
      return;
    }
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
      debugPrint('deleteFileByUrl: deleted $url');
    } catch (e) {
      debugPrint('deleteFileByUrl failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // MEMORIES (CRUD)
  // ══════════════════════════════════════════════════════════════════════════════

  Future<Memory?> addMemory({
    required String groupId,
    required MemoryType type,
    String? imageUrl,
    List<String>? imageUrls,
    String? videoUrl,
    String? title,
    String? caption,
    String? locationName,
    double? latitude,
    double? longitude,
    String? musicTitle,
    String? musicArtist,
    String? musicUrl,
    String? musicCoverUrl,
    String? bookAuthor,
    String? bookCoverUrl,
    String? bookYear,
    String? bookPublisher,
    String? bookInfoUrl,
    String? movieOriginalTitle,
    String? moviePosterUrl,
    String? movieYear,
    String? movieKind,
    String? movieGenres,
    String? movieCountry,
    String? movieRatingKp,
    String? movieInfoUrl,
    int? rating,
    bool isAdult = false,
    DateTime? customDate,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return null;

    await RateLimiterService().checkAndRecordMemory();

    try {
      final name = _cachedDisplayName ?? u.displayName ?? '';
      final avatar =
          (_cachedAvatarUrl?.isNotEmpty == true
              ? _cachedAvatarUrl!
              : u.photoURL) ??
          '';

      final ref = _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .doc();
      // Если пользователь выбрал «дату воспоминания» в прошлом —
      // записываем её как createdAt, чтобы пин оказался на ленте
      // в нужной временной точке. По умолчанию — текущий момент.
      final createdAt = customDate ?? DateTime.now();
      final memory = Memory(
        id: ref.id,
        groupId: groupId,
        authorUid: u.uid,
        authorName: name,
        authorAvatar: avatar,
        type: type,
        createdAt: createdAt,
        imageUrl: imageUrl,
        imageUrls: imageUrls,
        videoUrl: videoUrl,
        title: title,
        caption: caption,
        locationName: locationName,
        latitude: latitude,
        longitude: longitude,
        musicTitle: musicTitle,
        musicArtist: musicArtist,
        musicUrl: musicUrl,
        musicCoverUrl: musicCoverUrl,
        bookAuthor: bookAuthor,
        bookCoverUrl: bookCoverUrl,
        bookYear: bookYear,
        bookPublisher: bookPublisher,
        bookInfoUrl: bookInfoUrl,
        movieOriginalTitle: movieOriginalTitle,
        moviePosterUrl: moviePosterUrl,
        movieYear: movieYear,
        movieKind: movieKind,
        movieGenres: movieGenres,
        movieCountry: movieCountry,
        movieRatingKp: movieRatingKp,
        movieInfoUrl: movieInfoUrl,
        rating: rating,
        isAdult: isAdult,
      );

      // Двойная запись: Firebase (источник) + зеркало в Supabase под тем же id.
      // Stage 4: для мигрированной группы Firebase пропускаем (id уже у memory).
      if (_writeFb(groupId)) {
        await ref.set(memory.toFirestore());
        unawaited(
          _db
              .collection('groups')
              .doc(groupId)
              .update({'memoriesCount': FieldValue.increment(1)})
              .catchError((_) {}),
        );
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorMemory(groupId, ref.id, memory.toFirestore()));
        unawaited(_sb.incrementGroupCounters(groupId, memories: 1));
      }
      unawaited(AnalyticsService.instance.logMemoryAdded(type: type.name));
      unawaited(LevelService.instance.award(XpAction.addMemory));
      return memory;
    } catch (e) {
      debugPrint('addMemory failed: $e');
      return null;
    }
  }

  Future<void> updateMemory({
    required String groupId,
    required String memoryId,
    String? title,
    String? caption,
    String? locationName,
    double? latitude,
    double? longitude,
    String? musicTitle,
    String? musicArtist,
    String? bookAuthor,
    int? rating,
    String? imageUrl,
    bool? isPinned,
    bool? isAdult,
    // Если задано — перезаписываем createdAt (используется при редактировании
    // даты воспоминания). null = оставить createdAt как есть.
    DateTime? customDate,
  }) async {
    try {
      final updates = <String, dynamic>{'editedAt': Timestamp.now()};
      if (title != null) updates['title'] = title;
      if (caption != null) updates['caption'] = caption;
      if (locationName != null) updates['locationName'] = locationName;
      if (latitude != null) updates['latitude'] = latitude;
      if (longitude != null) updates['longitude'] = longitude;
      if (musicTitle != null) updates['musicTitle'] = musicTitle;
      if (musicArtist != null) updates['musicArtist'] = musicArtist;
      if (bookAuthor != null) updates['bookAuthor'] = bookAuthor;
      if (rating != null) updates['rating'] = rating == 0 ? null : rating;
      if (imageUrl != null) updates['imageUrl'] = imageUrl;
      if (isPinned != null) updates['isPinned'] = isPinned;
      if (isAdult != null) updates['isAdult'] = isAdult;
      if (customDate != null) {
        updates['createdAt'] = Timestamp.fromDate(customDate);
      }

      // Зеркало в Supabase шлём БЕЗ captionHistory (Firestore arrayUnion —
      // сентинел, в Supabase его нет). memory_patch атомарно делает data||patch
      // + синк edited_at/created_at/is_pinned.
      final sbUpdates = Map<String, dynamic>.from(updates);

      // Offline Conflict Resolution: Keep history of caption edits using arrayUnion
      // This prevents data loss if both partners edit the caption offline simultaneously.
      if (caption != null && uid != null) {
        updates['captionHistory'] = FieldValue.arrayUnion([
          {'caption': caption, 'uid': uid, 'timestamp': Timestamp.now()},
        ]);
      }

      if (_writeFb(groupId)) {
        await _db
            .collection('groups')
            .doc(groupId)
            .collection('memories')
            .doc(memoryId)
            .update(updates);
      }
      if (_dualWrite) unawaited(_sb.patchMemory(memoryId, sbUpdates));
    } catch (e) {
      debugPrint('updateMemory failed: $e');
    }
  }

  Future<void> deleteMemory({
    required String groupId,
    required String memoryId,
    String? imageUrl,
    String? videoUrl,
    String? musicUrl,
    String? musicCoverUrl,
  }) async {
    try {
      // Delete associated files from storage (Firebase https:// или Supabase sb://)
      final urls = [imageUrl, videoUrl, musicUrl, musicCoverUrl];
      for (final url in urls) {
        if (url == null) continue;
        if (url.startsWith('sb://')) {
          await _sb.deleteStorageFile(url);
        } else if (url.contains('firebasestorage')) {
          try {
            await _storage.refFromURL(url).delete();
            debugPrint('Deleted storage file: $url');
          } catch (e) {
            debugPrint('Failed to delete storage file: $e');
          }
        }
      }

      // Delete Firestore document (источник) + зеркало удаления в Supabase.
      // Stage 4: для мигрированной группы Firebase пропускаем.
      if (_writeFb(groupId)) {
        await _db
            .collection('groups')
            .doc(groupId)
            .collection('memories')
            .doc(memoryId)
            .delete();
        unawaited(
          _db
              .collection('groups')
              .doc(groupId)
              .update({'memoriesCount': FieldValue.increment(-1)})
              .catchError((_) {}),
        );
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorMemoryDelete(memoryId, hard: true));
        unawaited(_sb.incrementGroupCounters(groupId, memories: -1));
      }
    } catch (e) {
      debugPrint('deleteMemory failed: $e');
    }
  }

  Future<void> togglePinMemory({
    required String groupId,
    required String memoryId,
    required bool isPinned,
  }) async {
    await updateMemory(
      groupId: groupId,
      memoryId: memoryId,
      isPinned: isPinned,
    );
  }

  /// Пагинация ленты. Курсор — последнее воспоминание предыдущей страницы
  /// [startAfter] (его createdAt), а не Firestore-DocumentSnapshot: единый
  /// механизм для Firebase и Supabase. Возвращает страницу + lastMemory-курсор.
  Future<({List<Memory> memories, Memory? lastMemory})> loadMemories({
    required String groupId,
    int limit = 50,
    Memory? startAfter,
    bool cacheFirst = false,
  }) async {
    // Stage 2: лента читается из Firebase. Stage 3 — Supabase (_readSb).
    if (_readSb(groupId)) {
      final memories = await _sb.loadMemories(
        groupId,
        limit: limit,
        beforeIso: startAfter?.createdAt.toIso8601String(),
      );
      return (
        memories: memories,
        lastMemory: memories.isNotEmpty ? memories.last : null,
      );
    }
    try {
      var query =
          _db
                  .collection('groups')
                  .doc(groupId)
                  .collection('memories')
                  .orderBy('createdAt', descending: true)
                  .limit(limit)
              as Query<Map<String, dynamic>>;
      // Курсор по времени (createdAt последнего) вместо startAfterDocument —
      // единый механизм с Supabase-путём.
      if (startAfter != null) {
        query = query.where(
          'createdAt',
          isLessThan: Timestamp.fromDate(startAfter.createdAt),
        );
      }
      // cacheFirst: для начального открытия экрана сначала читаем из локального
      // persistent-кэша (его уже прогрел live-слушатель listenToMemories на home),
      // что даёт 0 серверных чтений и мгновенную отрисовку. Если кэш пуст
      // (холодный старт до запуска слушателя), падаем на сервер.
      QuerySnapshot<Map<String, dynamic>> snap;
      if (cacheFirst) {
        try {
          snap = await query
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 5));
          if (snap.docs.isEmpty) {
            snap = await query.get().timeout(const Duration(seconds: 10));
          }
        } catch (_) {
          snap = await query.get().timeout(const Duration(seconds: 10));
        }
      } else {
        snap = await query.get().timeout(const Duration(seconds: 10));
      }
      final memories = snap.docs
          .map((d) => Memory.fromFirestore(d.id, d.data()))
          .toList();
      return (
        memories: memories,
        lastMemory: memories.isNotEmpty ? memories.last : null,
      );
    } catch (e) {
      debugPrint('loadMemories failed: $e');
      return (memories: <Memory>[], lastMemory: null);
    }
  }

  /// Точечное чтение одного воспоминания (пин из чата не на первой странице).
  /// Под `_mig` — из Supabase, иначе Firestore.
  Future<Memory?> getMemoryById({
    required String groupId,
    required String memoryId,
  }) async {
    if (groupId.isEmpty || memoryId.isEmpty) return null;
    try {
      if (_readSb(groupId)) return await _sb.loadMemoryById(memoryId);
      final doc = await _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .doc(memoryId)
          .get();
      if (!doc.exists) return null;
      return Memory.fromFirestore(doc.id, doc.data()!);
    } catch (e) {
      debugPrint('getMemoryById($memoryId) failed: $e');
      return null;
    }
  }

  StreamSubscription? listenToMemories({
    required String groupId,
    required void Function(List<Memory> memories) onData,
    int limit = 20,
  }) {
    // Stage 2: лента читается из Firebase (realtime). Stage 3 — Supabase.
    if (_readSb(groupId)) {
      return _sb.watchMemories(groupId, limit: limit).listen(
            onData,
            onError: (e) => debugPrint('listenToMemories(SB) error: $e'),
          );
    }
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('memories')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .listen((snap) {
          final memories = snap.docs
              .map((d) => Memory.fromFirestore(d.id, d.data()))
              .toList();
          onData(memories);
        }, onError: (e) => debugPrint('listenToMemories error: $e'));
  }

  // ══════════════════════════════════════════════
  //  COMMENTS
  // ══════════════════════════════════════════════

  CollectionReference _commentsRef(String groupId, String memoryId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('memories')
        .doc(memoryId)
        .collection('comments');
  }

  Future<void> addComment({
    required String groupId,
    required String memoryId,
    required String text,
  }) async {
    final user = currentUser;
    if (user == null) return;

    await RateLimiterService().checkAndRecordComment();

    final comment = MemoryComment(
      id: '',
      authorUid: user.uid,
      authorName: user.displayName ?? 'User',
      authorAvatar: user.photoURL ?? '',
      text: text,
      createdAt: DateTime.now(),
    );
    try {
      final fb = comment.toFirestore();
      // Двойная запись: Firebase (источник) + зеркало в Supabase под тем же id.
      final id = _commentsRef(groupId, memoryId).doc().id;
      if (_writeFb(groupId)) {
        await _commentsRef(groupId, memoryId).doc(id).set(fb);
      }
      if (_dualWrite) unawaited(_sb.mirrorComment(groupId, memoryId, id, fb));
    } catch (e) {
      debugPrint('addComment failed: $e');
    }
  }

  Future<void> deleteComment({
    required String groupId,
    required String memoryId,
    required String commentId,
  }) async {
    try {
      if (_writeFb(groupId)) {
        await _commentsRef(groupId, memoryId).doc(commentId).delete();
      }
      if (_dualWrite) unawaited(_sb.mirrorCommentDelete(commentId));
    } catch (e) {
      debugPrint('deleteComment failed: $e');
    }
  }

  Stream<List<MemoryComment>> commentsStream({
    required String groupId,
    required String memoryId,
  }) {
    // Stage 2: комментарии читаются из Firebase (realtime). Stage 3 — Supabase.
    if (_readSb(groupId)) return _sb.watchComments(groupId, memoryId);
    return _commentsRef(groupId, memoryId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => MemoryComment.fromFirestore(
                  d.id,
                  d.data() as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  // ══════════════════════════════════════════════
  //  MOOD
  //  Firestore: groups/{groupId} → memberMoods.{uid}: {imagePath, label, updatedAt}
  // ══════════════════════════════════════════════

  /// Save the current user's mood to the group document
  Future<void> setMood({
    required String groupId,
    required String imagePath,
    required String label,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      // Двойная запись: Firebase (источник, его читает партнёр на старой версии)
      // + зеркало в Supabase. Stage 4: для мигрированной группы Firebase пропускаем.
      if (_writeFb(groupId)) {
        await _db.collection('groups').doc(groupId).update({
          'memberMoods.${u.uid}': {
            'imagePath': imagePath,
            'label': label,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        });
      }
      if (_dualWrite) {
        unawaited(_sb.setMemberMood(groupId, u.uid, {
          'imagePath': imagePath,
          'label': label,
          'updatedAt': DateTime.now().toIso8601String(),
        }));
      }
      unawaited(AnalyticsService.instance.logMoodSet(label: label));
    } catch (e) {
      debugPrint('setMood failed: $e');
    }
  }

  /// Clear the current user's mood
  Future<void> clearMood({required String groupId}) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      if (_writeFb(groupId)) {
        await _db.collection('groups').doc(groupId).update({
          'memberMoods.${u.uid}': FieldValue.delete(),
        });
      }
      if (_dualWrite) unawaited(_sb.clearMemberMood(groupId, u.uid));
    } catch (e) {
      debugPrint('clearMood failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  AILMENT («болячки») — самочувствие участника
  //  Firestore: groups/{groupId} → memberAilments.{uid}: {id, label, emoji, updatedAt}
  // ══════════════════════════════════════════════

  /// Save the current user's ailment to the group document
  Future<void> setAilment({
    required String groupId,
    required String id,
    required String label,
    required String emoji,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).update({
        'memberAilments.${u.uid}': {
          'id': id,
          'label': label,
          'emoji': emoji,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });
    } catch (e) {
      debugPrint('setAilment failed: $e');
    }
  }

  /// Clear the current user's ailment («Здоров(а)»)
  Future<void> clearAilment({required String groupId}) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).update({
        'memberAilments.${u.uid}': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('clearAilment failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  RELATIONSHIP STATUS
  //  Firestore: groups/{groupId} → currentStatus: {...}, customStatuses: [...]
  // ══════════════════════════════════════════════

  /// Set the group's current relationship status
  Future<void> setGroupStatus(String groupId, dynamic status) async {
    if (groupId.isEmpty) return;
    try {
      final statusData = status is Map<String, dynamic>
          ? status
          : (status as dynamic).toJson();
      if (_writeFb(groupId)) {
        await _db.collection('groups').doc(groupId).update({
          'currentStatus': statusData,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(
          groupId,
          {'current_status': SupabaseService.jsonSafe(statusData)},
        ));
      }
    } catch (e) {
      debugPrint('setGroupStatus failed: $e');
    }
  }

  /// Clear the group's current relationship status
  Future<void> clearGroupStatus(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      if (_writeFb(groupId)) {
        await _db.collection('groups').doc(groupId).update({
          'currentStatus': FieldValue.delete(),
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(groupId, {'current_status': null}));
      }
    } catch (e) {
      debugPrint('clearGroupStatus failed: $e');
    }
  }

  /// Add a custom status to the group
  Future<void> addCustomStatus(String groupId, dynamic status) async {
    if (groupId.isEmpty) return;
    try {
      final statusData = status is Map<String, dynamic>
          ? status
          : (status as dynamic).toJson();
      // Двойная запись: Firebase-транзакция (источник) считает финальный список,
      // затем зеркалим его в Supabase.
      final newList = await _db.runTransaction<List<Map<String, dynamic>>>((
        tx,
      ) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final customStatuses = List<Map<String, dynamic>>.from(
          (data['customStatuses'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        if (!customStatuses.any((s) => s['id'] == statusData['id'])) {
          customStatuses.add(Map<String, dynamic>.from(statusData));
        }
        tx.set(ref, {
          'customStatuses': customStatuses,
        }, SetOptions(merge: true));
        return customStatuses;
      });
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(groupId, {
          'custom_statuses': SupabaseService.jsonSafe(newList),
        }));
      }
    } catch (e) {
      debugPrint('addCustomStatus failed: $e');
    }
  }

  /// Update a custom status in the group
  Future<void> updateCustomStatus(String groupId, dynamic status) async {
    if (groupId.isEmpty) return;
    try {
      final statusData = status is Map<String, dynamic>
          ? status
          : (status as dynamic).toJson();
      // Двойная запись: Firebase-транзакция (источник) + зеркало snake_case-полей.
      final sbUpdates = await _db.runTransaction<Map<String, dynamic>?>((
        tx,
      ) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return null;

        final customStatuses = List<Map<String, dynamic>>.from(
          (data['customStatuses'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        final index = customStatuses.indexWhere(
          (s) => s['id'] == statusData['id'],
        );
        if (index == -1) return null;

        customStatuses[index] = Map<String, dynamic>.from(statusData);
        final updates = <String, dynamic>{'customStatuses': customStatuses};
        final sb = <String, dynamic>{
          'custom_statuses': SupabaseService.jsonSafe(customStatuses),
        };
        final currentStatus = data['currentStatus'] as Map<String, dynamic>?;
        if (currentStatus != null && currentStatus['id'] == statusData['id']) {
          updates['currentStatus'] = statusData;
          sb['current_status'] = SupabaseService.jsonSafe(statusData);
        }
        tx.update(ref, updates);
        return sb;
      });
      if (_dualWrite && sbUpdates != null) {
        unawaited(_sb.mirrorGroupFields(groupId, sbUpdates));
      }
    } catch (e) {
      debugPrint('updateCustomStatus failed: $e');
    }
  }

  /// Delete a custom status from the group
  Future<void> deleteCustomStatus(String groupId, String statusId) async {
    if (groupId.isEmpty) return;
    try {
      // Двойная запись: Firebase-транзакция (источник) + зеркало snake_case-полей.
      final sbUpdates = await _db.runTransaction<Map<String, dynamic>?>((
        tx,
      ) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return null;

        final customStatuses = List<Map<String, dynamic>>.from(
          (data['customStatuses'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        customStatuses.removeWhere((s) => s['id'] == statusId);

        final updates = <String, dynamic>{'customStatuses': customStatuses};
        final sb = <String, dynamic>{
          'custom_statuses': SupabaseService.jsonSafe(customStatuses),
        };
        final currentStatus = data['currentStatus'] as Map<String, dynamic>?;
        if (currentStatus != null && currentStatus['id'] == statusId) {
          updates['currentStatus'] = FieldValue.delete();
          sb['current_status'] = null;
        }
        tx.update(ref, updates);
        return sb;
      });
      if (_dualWrite && sbUpdates != null) {
        unawaited(_sb.mirrorGroupFields(groupId, sbUpdates));
      }
    } catch (e) {
      debugPrint('deleteCustomStatus failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  TIMERS (synced across group)
  // ══════════════════════════════════════════════

  /// Save full timers list to group document
  Future<void> saveTimers({
    required String groupId,
    required List<Map<String, dynamic>> timers,
  }) async {
    try {
      debugPrint(
        'FirebaseService: сохраняю ${timers.length} таймеров в группу $groupId',
      );
      // Двойная запись: Firebase (источник) + зеркало в Supabase.
      await _db.collection('groups').doc(groupId).update({'timers': timers});
      if (_dualWrite) unawaited(_sb.mirrorTimers(groupId, timers));
      debugPrint('FirebaseService: таймеры успешно сохранены');
    } catch (e) {
      debugPrint('FirebaseService: ошибка сохранения таймеров - $e');
      // Если документ группы не существует или нет поля timers - пробуем set
      try {
        debugPrint('FirebaseService: пробую создать поле timers через set...');
        await _db.collection('groups').doc(groupId).set({
          'timers': timers,
        }, SetOptions(merge: true));
        debugPrint('FirebaseService: таймеры сохранены через set');
        if (_dualWrite) unawaited(_sb.mirrorTimers(groupId, timers));
      } catch (e2) {
        debugPrint(
          'FirebaseService: критическая ошибка сохранения таймеров - $e2',
        );
      }
    }
  }

  // Мутации списка таймеров — общие для Firestore-транзакции и
  // Supabase read-modify-write пути (Этап 4).

  static void _applyTimerUpsert(
    List<Map<String, dynamic>> timers,
    Map<String, dynamic> timer,
  ) {
    timers.removeWhere((t) => t['id'] == timer['id']);
    final isDefault = timer['isDefault'] as bool? ?? false;
    if (isDefault) {
      for (final existing in timers) {
        existing['isDefault'] = false;
      }
    }
    timers.add(Map<String, dynamic>.from(timer));
    _ensureDefaultTimer(timers);
  }

  static void _ensureDefaultTimer(List<Map<String, dynamic>> timers) {
    if (timers.isNotEmpty && !timers.any((t) => t['isDefault'] == true)) {
      timers.first['isDefault'] = true;
    }
  }


  Future<void> upsertGroupTimer({
    required String groupId,
    required Map<String, dynamic> timer,
  }) async {
    try {
      final newTimers = await _db.runTransaction<List<Map<String, dynamic>>>((
        tx,
      ) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final timers = List<Map<String, dynamic>>.from(
          (data['timers'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );

        _applyTimerUpsert(timers, timer);
        tx.set(ref, {'timers': timers}, SetOptions(merge: true));
        return timers;
      });
      if (_dualWrite) unawaited(_sb.mirrorTimers(groupId, newTimers));
    } catch (e) {
      debugPrint('upsertGroupTimer failed: $e');
    }
  }

  Future<void> deleteGroupTimer({
    required String groupId,
    required String timerId,
  }) async {
    try {
      final newTimers = await _db.runTransaction<List<Map<String, dynamic>>>((
        tx,
      ) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final timers = List<Map<String, dynamic>>.from(
          (data['timers'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );

        timers.removeWhere((t) => t['id'] == timerId);
        _ensureDefaultTimer(timers);
        tx.set(ref, {'timers': timers}, SetOptions(merge: true));
        return timers;
      });
      if (_dualWrite) unawaited(_sb.mirrorTimers(groupId, newTimers));
    } catch (e) {
      debugPrint('deleteGroupTimer failed: $e');
    }
  }

  Future<void> setDefaultGroupTimer({
    required String groupId,
    required String timerId,
  }) async {
    try {
      final newTimers = await _db.runTransaction<List<Map<String, dynamic>>>((
        tx,
      ) async {
        final ref = _db.collection('groups').doc(groupId);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final timers = List<Map<String, dynamic>>.from(
          (data['timers'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );

        for (final timer in timers) {
          timer['isDefault'] = timer['id'] == timerId;
        }
        _ensureDefaultTimer(timers);
        tx.set(ref, {'timers': timers}, SetOptions(merge: true));
        return timers;
      });
      if (_dualWrite) unawaited(_sb.mirrorTimers(groupId, newTimers));
    } catch (e) {
      debugPrint('setDefaultGroupTimer failed: $e');
    }
  }

  // ── Solo timers (Firestore backup for reinstall recovery) ──

  /// Сохраняет соло-таймеры в документ пользователя для восстановления после переустановки.
  Future<void> saveSoloTimers(List<Map<String, dynamic>> timers) async {
    final id = uid;
    if (id == null) return;
    try {
      await _db.collection('users').doc(id).set({
        'soloTimers': timers,
      }, SetOptions(merge: true));
      // users-строка в Supabase — источник профиля под `_mig`, держим в синке.
      if (_mig) unawaited(_sb.mirrorUser(id, {'soloTimers': timers}));
    } catch (e) {
      debugPrint('saveSoloTimers failed: $e');
    }
  }

  /// Загружает соло-таймеры из Firestore (вызывается после переустановки).
  Future<List<Map<String, dynamic>>?> loadSoloTimers() async {
    final id = uid;
    if (id == null) return null;
    try {
      final snap = await _db
          .collection('users')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      final raw = snap.data()?['soloTimers'];
      if (raw is! List || (raw).isEmpty) return null;
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('loadSoloTimers failed: $e');
      return null;
    }
  }

  /// Listen to timers changes in real-time.
  /// Skips the callback when only other group fields changed (e.g. memberMoods)
  /// to avoid redundant _mergeRemoteTimers calls on every partner mood update.
  StreamSubscription? listenToTimers({
    required String groupId,
    required void Function(List<TimerItem> timers) onData,
  }) {
    // null = ещё не доставили ни одного снимка. Важно отличать «не доставляли»
    // от «доставили пустой список»: у только что созданной группы поля timers
    // нет, поэтому hash первого снимка == '' и при старте с prevHash='' колбэк
    // проглатывался — _mergeRemoteTimers([]) не вызывался, _hasReceivedRemoteSync
    // оставался false и отложенный системный таймер не создавался.
    // Stage 2: live-таймеры из Firebase (общий источник). Stage 3 — Supabase.
    if (_readSb(groupId)) {
      debugPrint('[SB] listenTimers: subscribing to Supabase timers for $groupId');
      return _sb.listenGroupTimers(groupId, (rawTimers) {
        onData(rawTimers.map(TimerItem.fromJson).toList());
      });
    }
    debugPrint('[FB] listenTimers: subscribing to Firestore timers for $groupId');
    String? prevHash;
    return _groupDocStream(groupId).listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      final timersList = data['timers'] as List<dynamic>?;
      final hash = timersList?.toString() ?? '';
      if (hash == prevHash) return;
      prevHash = hash;
      if (timersList != null) {
        final timers = timersList
            .map((e) => TimerItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        onData(timers);
      } else {
        onData([]);
      }
    }, onError: (e) => debugPrint('listenToTimers error: $e'));
  }

  // ══════════════════════════════════════════════
  //  MOOD CALENDAR
  //  Firestore (v2): groups/{groupId}/moodCalendar/{uid}/months/{YYYY-MM}
  //    { entries: { <entryId>: {...entry...}, ... }, updatedAt }
  //  Все записи месяца лежат в ОДНОМ документе (map по entryId) — чтение
  //  истории = N документов-месяцев вместо сотен/тысяч отдельных записей.
  //  Legacy (v1): .../moodCalendar/{uid}/entries/{entryId} — по одной записи
  //  на документ. Остаётся для чтения у не-мигрированных пользователей
  //  (партнёр на старой версии) и как источник для миграции своих данных.
  // ══════════════════════════════════════════════

  String _moodMonthKey(DateTime ts) =>
      '${ts.year.toString().padLeft(4, '0')}-'
      '${ts.month.toString().padLeft(2, '0')}';

  CollectionReference<Map<String, dynamic>> _moodMonthsCol(
    String groupId,
    String uid,
  ) => _db
      .collection('groups')
      .doc(groupId)
      .collection('moodCalendar')
      .doc(uid)
      .collection('months');

  CollectionReference<Map<String, dynamic>> _moodEntriesCol(
    String groupId,
    String uid,
  ) => _db
      .collection('groups')
      .doc(groupId)
      .collection('moodCalendar')
      .doc(uid)
      .collection('entries');

  List<Map<String, dynamic>> _entriesFromMonthDoc(Map<String, dynamic>? data) {
    final map = data?['entries'];
    if (map is! Map) return const [];
    return map.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Add a mood entry for the current user (пишет в month-документ).
  Future<void> addMoodEntry({
    required String groupId,
    required Map<String, dynamic> entry,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    final id = entry['id'] as String?;
    final ts = (entry['timestamp'] as Timestamp?)?.toDate();
    if (id == null || ts == null) return;
    try {
      // Двойная запись: Firebase month-документ (источник) + зеркало в Supabase.
      // merge:true сохраняет остальные записи месяца — дописываем только свою.
      if (_writeFb(groupId)) {
        await _moodMonthsCol(groupId, u.uid).doc(_moodMonthKey(ts)).set({
          'entries': {id: entry},
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (_dualWrite) unawaited(_sb.mirrorMoodEntry(groupId, u.uid, entry));
    } catch (e) {
      debugPrint('addMoodEntry failed: $e');
    }
  }

  /// Delete a mood entry. [timestamp] нужен для адресации month-документа;
  /// если не передан — выводим месяц из id (`<uid>_<millis>`).
  Future<void> deleteMoodEntry({
    required String groupId,
    required String entryId,
    DateTime? timestamp,
  }) async {
    final u = currentUser;
    if (u == null || groupId.isEmpty) return;
    // Зеркалим удаление в Supabase (адресуется по id); Firebase-удаление ниже.
    if (_dualWrite) unawaited(_sb.mirrorMoodDelete(entryId));
    var ts = timestamp;
    if (ts == null) {
      final ms = int.tryParse(entryId.split('_').last);
      if (ms != null) ts = DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (ts == null) {
      debugPrint('deleteMoodEntry: cannot resolve month for $entryId');
      return;
    }
    try {
      // entryId = `<uid>_<millis>` — без точек/слэшей, безопасно как field-path.
      if (_writeFb(groupId)) {
        await _moodMonthsCol(groupId, u.uid).doc(_moodMonthKey(ts)).update({
          'entries.$entryId': FieldValue.delete(),
        });
      }
    } catch (e) {
      debugPrint('deleteMoodEntry failed: $e');
    }
  }

  /// Live-слушатель ОДНОГО месяца (обычно текущего) — 1 документ.
  /// Срабатывает на каждое изменение настроений месяца → real-time для партнёра.
  StreamSubscription? listenMoodMonth({
    required String groupId,
    required String uid,
    required String monthKey,
    required void Function(List<Map<String, dynamic>> entries) onData,
  }) {
    // Stage 2: записи настроений читаются из Firebase. Stage 3 — Supabase.
    if (_readSb(groupId)) {
      debugPrint('[SB] listenMoodMonth: subscribing to Supabase mood entries');
      return _sb.listenMoodEntries(groupId, uid, onData);
    }
    debugPrint('[FB] listenMoodMonth: subscribing to Firestore mood entries');
    return _moodMonthsCol(groupId, uid)
        .doc(monthKey)
        .snapshots()
        .listen(
          (snap) => onData(_entriesFromMonthDoc(snap.data())),
          onError: (e) => debugPrint('listenMoodMonth error: $e'),
        );
  }

  /// Разовая загрузка истории: последние [months] month-документов.
  /// cacheFirst → сначала из локального кэша persistence (0 серверных чтений);
  /// при пустом кэше падаем на сервер.
  Future<List<Map<String, dynamic>>> loadMoodMonths({
    required String groupId,
    required String uid,
    int months = 14,
    bool cacheFirst = true,
  }) async {
    // Stage 2: вся история настроений — из Firebase. Stage 3 — Supabase.
    if (_readSb(groupId)) {
      debugPrint('[SB] loadMoodMonths: reading from Supabase');
      return _sb.loadMoodEntries(groupId, uid);
    }
    debugPrint('[FB] loadMoodMonths: reading from Firestore');
    // Диапазон по documentId вместо orderBy(__name__, desc)+limit: убывающая
    // сортировка по имени документа требует составного индекса, а инеравенство
    // по __name__ индексируется автоматически. Ключи YYYY-MM лексикографически
    // совпадают с хронологией, поэтому `>= cutoff` = последние [months] месяцев.
    final now = DateTime.now();
    final cutoff = _moodMonthKey(
      DateTime(now.year, now.month - (months - 1), 1),
    );
    final q = _moodMonthsCol(
      groupId,
      uid,
    ).where(FieldPath.documentId, isGreaterThanOrEqualTo: cutoff);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      if (cacheFirst) {
        snap = await q.get(const GetOptions(source: Source.cache));
        if (snap.docs.isEmpty) snap = await q.get();
      } else {
        snap = await q.get();
      }
    } catch (_) {
      try {
        snap = await q.get();
      } catch (e) {
        debugPrint('loadMoodMonths failed: $e');
        return const [];
      }
    }
    final out = <Map<String, dynamic>>[];
    for (final d in snap.docs) {
      out.addAll(_entriesFromMonthDoc(d.data()));
    }
    return out;
  }

  /// Разовая загрузка LEGACY-записей в окне [since] (cache-first). Нужна как
  /// fallback для партнёра, который ещё не мигрировал (его записи в v1).
  Future<List<Map<String, dynamic>>> loadLegacyMoodEntries({
    required String groupId,
    required String uid,
    required DateTime since,
    bool cacheFirst = true,
  }) async {
    // Stage 2: читаем legacy из Firebase (источник). Stage 3 (_readSb) — пропуск.
    if (_readSb(groupId)) return const [];
    final q = _moodEntriesCol(
      groupId,
      uid,
    ).where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      if (cacheFirst) {
        snap = await q.get(const GetOptions(source: Source.cache));
        if (snap.docs.isEmpty) snap = await q.get();
      } else {
        snap = await q.get();
      }
    } catch (_) {
      try {
        snap = await q.get();
      } catch (e) {
        debugPrint('loadLegacyMoodEntries failed: $e');
        return const [];
      }
    }
    return snap.docs.map((d) => d.data()).toList();
  }

  /// Однократная миграция СВОИХ legacy-записей (v1 → month-документы).
  /// Идемпотентна (entryId как ключ map). Окно [since] ограничивает объём
  /// разового чтения. Возвращает true при успехе (в т.ч. если мигрировать
  /// нечего). Партнёрские данные мигрировать нельзя (правила: пишем только своё).
  Future<bool> migrateMoodToMonthly({
    required String groupId,
    required String uid,
    required DateTime since,
  }) async {
    // Stage 2: читаем из Firebase → legacy→month миграция актуальна. Stage 3 — пропуск.
    if (_readSb(groupId)) return true;
    try {
      final snap = await _moodEntriesCol(groupId, uid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      if (snap.docs.isEmpty) return true;
      final byMonth = <String, Map<String, dynamic>>{};
      for (final d in snap.docs) {
        final data = d.data();
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        if (ts == null) continue;
        (byMonth[_moodMonthKey(ts)] ??= {})[d.id] = data;
      }
      final batch = _db.batch();
      byMonth.forEach((monthKey, entries) {
        batch.set(_moodMonthsCol(groupId, uid).doc(monthKey), {
          'entries': entries,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('migrateMoodToMonthly failed: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════
  //  DAILY REFLECTION
  // ══════════════════════════════════════════════

  /// Сохранить / обновить ответ пользователя на вопрос дня.
  /// Путь: groups/{groupId}/reflections/{YYYY-MM-DD}
  Future<void> saveReflectionAnswer({
    required String groupId,
    required String question,
    required String answer,
    required String authorName,
  }) async {
    final uid = this.uid;
    if (uid == null) return;
    final dayKey = _reflectionDayKey(DateTime.now());
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('reflections')
          .doc(dayKey)
          .set({
            'question': question,
            'updatedAt': FieldValue.serverTimestamp(),
            'answers.$uid': {
              'text': answer,
              'authorName': authorName,
              'createdAt': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('saveReflectionAnswer failed: $e');
    }
  }

  /// Слушать рефлексию текущего дня в реальном времени.
  StreamSubscription listenToTodayReflection({
    required String groupId,
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    final dayKey = _reflectionDayKey(DateTime.now());
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('reflections')
        .doc(dayKey)
        .snapshots()
        .listen(
          (snap) => onData(snap.exists ? snap.data() : null),
          onError: (e) => debugPrint('listenToReflection error: $e'),
        );
  }

  static String _reflectionDayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ══════════════════════════════════════════════
  //  I MISS YOU
  // ══════════════════════════════════════════════

  /// Отправить «Я скучаю» — записывает в Firestore.
  /// Cloud Function слушает этот документ и отправляет push-уведомление.
  /// Триггер push-уведомления о новом сообщении чата. Сам чат живёт в RTDB —
  /// здесь пишется только эфемерный документ-событие, который Cloud Function
  /// (onChatMessageEvent) читает, рассылает FCM и тут же удаляет. История
  /// чата в Firestore не хранится → ноль чтений при просмотре.
  Future<void> sendChatPush({
    required String groupId,
    required String senderName,
    required String text,
  }) async {
    final myUid = uid;
    if (myUid == null || groupId.isEmpty) return;
    try {
      await _db.collection('groups').doc(groupId).collection('chatEvents').add({
        'senderUid': myUid,
        'senderName': senderName,
        'text': text.length > 120 ? '${text.substring(0, 120)}…' : text,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('sendChatPush failed: $e');
    }
  }

  Future<void> sendMissYou({
    required String groupId,
    required String senderName,
  }) async {
    final myUid = uid;
    if (myUid == null || groupId.isEmpty) return;
    // «Я скучаю» намеренно без рейт-лимита: счётчик идёт в RTDB (даром), а
    // защита от спама пушами осталась только на прочих вайбах (sendVibe).
    try {
      debugPrint('sendMissYou($groupId): incrementing counter for uid=$myUid');
      // 1. Инкремент per-user счётчика в RTDB (атомарно, серверный increment).
      // Раньше это был set в Firestore group-doc — а его живьём слушают оба
      // партнёра (listenToPair + listenToMissYouCount), поэтому каждый тап
      // стоил чтение на ОБОИХ устройствах. RTDB-счётчик читается даром и не
      // дёргает Firestore-листенеры. total считается как сумма counts.
      await _missYouCountsRef(
        groupId,
      ).child(myUid).set(ServerValue.increment(1));
      if (_mig) unawaited(_sb.mirrorMissYouIncrement(groupId, myUid));
      debugPrint('sendMissYou($groupId): counter incremented successfully');

      // 2. Добавить запись в subcollection для push-триггера.
      // recipientUids кладём из кеша, чтобы функция не читала group-doc.
      final recipients = _cachedRecipients(groupId, myUid);
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('missYouEvents')
          .add({
            'senderUid': myUid,
            'senderName': senderName,
            if (recipients.isNotEmpty) 'recipientUids': recipients,
            'timestamp': FieldValue.serverTimestamp(),
          });
      debugPrint('sendMissYou($groupId): event written for push');
      unawaited(AnalyticsService.instance.logMissYouSent());
    } catch (e) {
      debugPrint('sendMissYou failed: $e');
    }
  }

  /// Отправить вайб-импульс (думаю о тебе, хочу обнять и др.).
  /// Пишет в ту же subcollection missYouEvents с полем vibeType,
  /// чтобы Cloud Function могла обработать новые типы без изменений схемы.
  Future<void> sendVibe({
    required String groupId,
    required String senderName,
    required String vibeType,
    String? customText,
  }) async {
    final myUid = uid;
    if (myUid == null || groupId.isEmpty) return;
    await RateLimiterService().checkVibe();
    try {
      final recipients = _cachedRecipients(groupId, myUid);
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('missYouEvents')
          .add({
            'senderUid': myUid,
            'senderName': senderName,
            'vibeType': vibeType,
            if (customText != null && customText.isNotEmpty)
              'customText': customText,
            if (recipients.isNotEmpty) 'recipientUids': recipients,
            'timestamp': FieldValue.serverTimestamp(),
          });
      unawaited(RateLimiterService().recordVibe());
      unawaited(AnalyticsService.instance.logVibeSent(vibeType: vibeType));
    } catch (e) {
      debugPrint('sendVibe failed: $e');
    }
  }

  /// Разбирает RTDB-узел counts (Map uid → число) в `Map<String,int>`.
  Map<String, int> _parseMissYouCounts(Object? value) {
    final out = <String, int>{};
    if (value is Map) {
      value.forEach((k, v) => out[k.toString()] = (v as num?)?.toInt() ?? 0);
    }
    return out;
  }

  /// Слушать общий счётчик «Я скучаю» (сумма per-user) в реальном времени.
  /// Источник — RTDB, поэтому изменения не стоят Firestore-чтений.
  /// ВАЖНО: Дедупликация по значению здесь ОПАСНА! Если один партнёр сбросил
  /// счётчик до 0, а у другого он уже был 0, то 0→0 игнорируется и слушатель
  /// не срабатывает. Вместо этого используем хеш снимка (timestamp неявный в RTDB)
  /// или полностью убираем дедупликацию для этого узла.
  ///
  /// Решение: убрали дедупликацию. RTDB отправляет только при реальных изменениях
  /// данных, so we rely on RTDB's dedup, не на наш код.
  StreamSubscription listenToMissYouCount({
    required String groupId,
    required void Function(int count) onData,
  }) {
    // Фаза 2: читаем «Я скучаю» из Supabase (таблица miss_you, realtime).
    // Оба партнёра на сборке dual-write'ят в Supabase, поэтому счётчики сходятся.
    // _seedSupabaseMissYou заранее подтягивает исторические RTDB-тапы (max).
    // RTDB-запись остаётся (дешёвый триггер пуша + фолбэк), но НЕ источник чтения.
    if (_readSb(groupId)) {
      _seedSupabaseMissYou(groupId);
      final sub = _sb.listenMissYouCounts(groupId, (counts) {
        final total = counts.values.fold<int>(0, (s, v) => s + v);
        debugPrint('[SB] listenToMissYouCount($groupId): total=$total');
        onData(total);
      });
      if (sub != null) return sub;
      // Supabase-листенер не стартанул — падаем на RTDB.
    }
    return _missYouCountsRef(groupId).onValue.listen((event) {
      final counts = _parseMissYouCounts(event.snapshot.value);
      final total = counts.values.fold<int>(0, (s, v) => s + v);
      debugPrint(
        'listenToMissYouCount($groupId): total=$total from counts=$counts',
      );
      onData(total);
    }, onError: (e) => debugPrint('listenToMissYouCount error: $e'));
  }

  /// Сбросить свои нажатия «Я скучаю» до 0 (только свой узел в RTDB —
  /// чтения чужих счётчиков не требуется).
  Future<void> resetMyMissYouCount({required String groupId}) async {
    final myUid = uid;
    if (myUid == null || groupId.isEmpty) return;
    try {
      debugPrint(
        'resetMyMissYouCount($groupId): resetting counter for uid=$myUid',
      );
      await _missYouCountsRef(groupId).child(myUid).set(0);
      if (_mig) unawaited(_sb.mirrorMissYouReset(groupId, myUid));
      debugPrint('resetMyMissYouCount($groupId): SUCCESS');
    } catch (e) {
      debugPrint('resetMyMissYouCount failed: $e');
    }
  }

  /// Слушать per-user счётчики «Я скучаю» (Map uid → count) из RTDB.
  /// ВАЖНО: убрали дедупликацию. RTDB гарантирует что срабатывает только
  /// при реальных изменениях данных (не при каждом read), поэтому мы можем
  /// полагаться на это и всегда передавать onData() свежие снимки.
  /// Без этого 0→0 переходы (сброс у одного партнёра) не проходят UI.
  StreamSubscription listenToMissYouCounts({
    required String groupId,
    required void Function(Map<String, int> counts) onData,
    void Function(Object error)? onError,
  }) {
    // Stage 2: per-user счётчики из RTDB (общий источник). Stage 3 — Supabase.
    if (_readSb(groupId)) {
      _seedSupabaseMissYou(groupId);
      final sub = _sb.listenMissYouCounts(groupId, (counts) {
        debugPrint('[SB] listenToMissYouCounts($groupId): counts=$counts');
        onData(counts);
      });
      if (sub != null) return sub;
    }
    return _missYouCountsRef(groupId).onValue.listen((event) {
      final counts = _parseMissYouCounts(event.snapshot.value);
      debugPrint('listenToMissYouCounts($groupId): counts=$counts');
      onData(counts);
    }, onError: (e) {
      // permission-denied на холодном старте (auth-токен ещё не доехал до
      // RTDB) НАВСЕГДА отменяет подписку — без ретрая счётчик висит на нулях
      // до перезапуска приложения. Пробрасываем ошибку, чтобы UI переподнялся.
      debugPrint('listenToMissYouCounts error: $e');
      onError?.call(e);
    });
  }

  /// Разовый снимок общего счётчика «Я скучаю» (для фонового апдейта виджета,
  /// где живой listener не нужен). Фаза 2: из Supabase, фолбэк на RTDB.
  Future<int> getMissYouTotal(String groupId) async {
    if (groupId.isEmpty) return 0;
    try {
      if (_readSb(groupId)) {
        final counts = await _sb.getMissYouCounts(groupId);
        if (counts.isNotEmpty) {
          return counts.values.fold<int>(0, (s, v) => s + v);
        }
        // Пусто в Supabase — падаем на RTDB (мог не сработать сид).
      }
      final snap = await _missYouCountsRef(groupId).get();
      final counts = _parseMissYouCounts(snap.value);
      return counts.values.fold<int>(0, (s, v) => s + v);
    } catch (e) {
      debugPrint('getMissYouTotal failed: $e');
      return 0;
    }
  }

  // ══════════════════════════════════════════════
  //  PRESENCE — отслеживание статуса онлайн/офлайн
  //  RTDB: presence/{uid} = { online: bool, lastSeen: ms-since-epoch }
  //  Хранится в Realtime Database, а не в Firestore: статус дёргается на каждом
  //  foreground/background, а партнёры держат на нём листенер — в Firestore это
  //  выливалось в сотни тысяч чтений users/{uid} в день. RTDB к тому же даёт
  //  honest-offline через onDisconnect при жёстком убийстве приложения.
  // ══════════════════════════════════════════════

  bool? _lastOnlineStatus;
  StreamSubscription<DatabaseEvent>? _presenceConnSub;
  // badge почти неизменен (Sponsor/Helper) — кешируем разовый get, чтобы не
  // держать Firestore-листенер на чужом user-doc ради одного поля.
  final Map<String, String?> _badgeCache = {};

  /// Обновляет статус присутствия текущего пользователя.
  /// Вызывается из AppLifecycleListener при переходе foreground/background.
  Future<void> setOnlineStatus(bool isOnline) async {
    final u = currentUser;
    if (u == null) return;
    // AppLifecycleListener fires onPause + onHide + onDetach in quick
    // succession on Android — without this guard every backgrounding paid
    // for redundant presence writes (and reads on the partner side).
    if (_lastOnlineStatus == isOnline) return;
    _lastOnlineStatus = isOnline;
    final ref = _presenceRef(u.uid);
    try {
      if (isOnline) {
        // Re-arm onDisconnect on every (re)connect so a crash/kill flips us
        // offline server-side even after a transient network blip.
        _ensurePresenceConnectionWatcher();
        await ref.onDisconnect().set({
          'online': false,
          'lastSeen': ServerValue.timestamp,
        });
        await ref
            .set({'online': true, 'lastSeen': ServerValue.timestamp})
            .timeout(const Duration(seconds: 8));
      } else {
        // Explicit background/sign-out: cancel the disconnect handler and mark
        // offline now.
        await ref.onDisconnect().cancel();
        await ref
            .set({'online': false, 'lastSeen': ServerValue.timestamp})
            .timeout(const Duration(seconds: 8));
      }
      debugPrint('setOnlineStatus: uid=${u.uid}, isOnline=$isOnline');
    } catch (e) {
      // Restore so a retry attempt can go through.
      _lastOnlineStatus = null;
      debugPrint('setOnlineStatus failed: $e');
    }
  }

  /// Пока мы считаем себя онлайн, при каждом восстановлении RTDB-соединения
  /// заново ставим online:true и перевешиваем onDisconnect (он одноразовый —
  /// после срабатывания на разрыве его нужно вооружить снова).
  void _ensurePresenceConnectionWatcher() {
    _presenceConnSub ??= _rtdb.ref('.info/connected').onValue.listen((
      event,
    ) async {
      if (event.snapshot.value != true) return;
      final u = currentUser;
      if (u == null || _lastOnlineStatus != true) return;
      final ref = _presenceRef(u.uid);
      try {
        await ref.onDisconnect().set({
          'online': false,
          'lastSeen': ServerValue.timestamp,
        });
        await ref.set({'online': true, 'lastSeen': ServerValue.timestamp});
      } catch (_) {}
    });
  }

  /// Снимает watcher соединения (при выходе из аккаунта).
  void _disposePresenceWatcher() {
    _presenceConnSub?.cancel();
    _presenceConnSub = null;
  }

  /// Стрим присутствия пользователя по uid.
  /// Возвращает Map с полями isOnline (bool), lastSeen (DateTime?), badge.
  /// online/lastSeen — из RTDB (ноль Firestore-чтений); badge — разовый
  /// кешируемый Firestore-get.
  Stream<Map<String, dynamic>> streamUserPresence(String uid) {
    return _presenceRef(uid).onValue.asyncMap((event) async {
      final v = event.snapshot.value;
      bool isOnline = false;
      DateTime? lastSeen;
      if (v is Map) {
        isOnline = v['online'] == true;
        final ts = v['lastSeen'];
        if (ts is int) lastSeen = DateTime.fromMillisecondsSinceEpoch(ts);
      }
      final badge = await _badgeFor(uid);
      return {'isOnline': isOnline, 'lastSeen': lastSeen, 'badge': badge};
    });
  }

  /// Бейдж пользователя (Sponsor/Helper) — кешируемый разовый Firestore-get.
  Future<String?> _badgeFor(String uid) async {
    if (_badgeCache.containsKey(uid)) return _badgeCache[uid];
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final badge = doc.data()?['badge'] as String?;
      _badgeCache[uid] = badge;
      return badge;
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════
  //  COLLABORATIVE DRAWING CANVAS
  //  Firestore structure:
  //    groups/{groupId}/canvas/main/strokes/{strokeId}  – completed strokes
  //    groups/{groupId}/canvas/main/live/{userId}        – in-progress stroke
  // ══════════════════════════════════════════════

  CollectionReference _strokesRef(String groupId, [String canvasId = 'main']) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('canvas')
          .doc(canvasId)
          .collection('strokes');

  DocumentReference<Map<String, dynamic>> _canvasMainRef(
    String groupId, [
    String canvasId = 'main',
  ]) =>
      _db.collection('groups').doc(groupId).collection('canvas').doc(canvasId);

  CollectionReference _liveRef(String groupId, [String canvasId = 'main']) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('canvas')
          .doc(canvasId)
          .collection('live');

  /// Stream of all completed strokes ordered by [orderIndex].
  Stream<List<_DrawStrokeRaw>> listenToDrawingStrokes({
    required String groupId,
    String canvasId = 'main',
  }) {
    // Stage 2: штрихи читаются из Firebase (общий источник). Stage 3 включит
    // Supabase-чтение через _readSb, когда вся группа на новой сборке.
    if (_readSb(groupId)) {
      return _sb.watchCanvasStrokes(groupId, canvasId).map(
            (rows) => rows
                .map((r) => _DrawStrokeRaw(
                      id: r['id'] as String,
                      data: Map<String, dynamic>.from(r['data'] as Map),
                    ))
                .toList(),
          );
    }
    return _strokesRef(groupId, canvasId)
        .orderBy('orderIndex')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => _DrawStrokeRaw(
                  id: d.id,
                  data: Map<String, dynamic>.from(d.data() as Map),
                ),
              )
              .toList(),
        );
  }

  /// Persist a completed stroke and return its new Firestore document ID.
  Future<String> addDrawingStroke({
    required String groupId,
    required Map<String, dynamic> strokeData,
    String canvasId = 'main',
  }) async {
    try {
      // Двойная запись: Firebase (источник) + зеркало в Supabase под ОДНИМ id,
      // чтобы при будущем переключении чтения на Supabase ничего не задвоилось.
      final id = _strokesRef(groupId, canvasId).doc().id;
      if (_writeFb(groupId)) {
        await _strokesRef(groupId, canvasId).doc(id).set(strokeData);
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorStroke(groupId, canvasId, id, strokeData));
      }
      return id;
    } catch (e) {
      debugPrint('addDrawingStroke failed: $e');
      return '';
    }
  }

  /// Update specific fields of an existing stroke (used for image repositioning).
  Future<void> updateDrawingStroke({
    required String groupId,
    required String strokeId,
    required Map<String, dynamic> updates,
    String canvasId = 'main',
  }) async {
    try {
      if (_writeFb(groupId)) {
        await _strokesRef(groupId, canvasId).doc(strokeId).update(updates);
      }
      if (_dualWrite) unawaited(_sb.mirrorStrokePatch(strokeId, updates));
    } catch (e) {
      debugPrint('updateDrawingStroke failed: $e');
    }
  }

  /// Delete a single stroke by ID (used for undo).
  Future<void> deleteDrawingStroke({
    required String groupId,
    required String strokeId,
    String canvasId = 'main',
  }) async {
    try {
      if (_writeFb(groupId)) {
        await _strokesRef(groupId, canvasId).doc(strokeId).delete();
      }
      if (_dualWrite) unawaited(_sb.mirrorStrokeDelete(strokeId));
    } catch (e) {
      debugPrint('deleteDrawingStroke failed: $e');
    }
  }

  /// Write the current in-progress stroke of [userId] so partners can see it live.
  Future<void> updateLiveDrawingStroke({
    required String groupId,
    required String userId,
    required Map<String, dynamic> liveData,
    String canvasId = 'main',
  }) async {
    try {
      await _liveRef(groupId, canvasId).doc(userId).set(liveData);
    } catch (e) {
      debugPrint('updateLiveDrawingStroke failed: $e');
    }
  }

  /// Remove the live stroke document when the user lifts their finger.
  Future<void> clearLiveDrawingStroke({
    required String groupId,
    required String userId,
    String canvasId = 'main',
  }) async {
    try {
      await _liveRef(groupId, canvasId).doc(userId).delete();
    } catch (e) {
      debugPrint('clearLiveDrawingStroke failed: $e');
    }
  }

  /// Stream of all partners' live strokes (excludes [myUserId]).
  Stream<Map<String, Map<String, dynamic>>> listenToLiveDrawingStrokes({
    required String groupId,
    required String myUserId,
    String canvasId = 'main',
  }) {
    return _liveRef(groupId, canvasId).snapshots().map((snap) {
      final result = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        if (doc.id != myUserId) {
          result[doc.id] = Map<String, dynamic>.from(doc.data() as Map);
        }
      }
      return result;
    });
  }

  /// Delete all strokes and live cursors for a canvas and publish a clear event.
  Future<void> clearDrawingCanvas({
    required String groupId,
    int? clearVersion,
    int? bgColorValue,
    String canvasId = 'main',
  }) async {
    final version = clearVersion ?? DateTime.now().millisecondsSinceEpoch;
    try {
      // Firebase (источник): чистим штрихи, live-курсоры и пишем clearVersion/bg.
      final strokesSnap = await _strokesRef(groupId, canvasId).get();
      final liveSnap = await _liveRef(groupId, canvasId).get();
      final batch = _db.batch();
      for (final doc in strokesSnap.docs) {
        batch.delete(doc.reference);
      }
      for (final doc in liveSnap.docs) {
        batch.delete(doc.reference);
      }
      final data = <String, dynamic>{'clearVersion': version};
      if (bgColorValue != null) {
        data['bgColor'] = bgColorValue;
      }
      batch.set(
        _canvasMainRef(groupId, canvasId),
        data,
        SetOptions(merge: true),
      );
      await batch.commit();
      // Зеркало в Supabase.
      if (_dualWrite) {
        unawaited(_sb.mirrorCanvasClear(
          groupId,
          canvasId,
          version,
          bgColor: bgColorValue,
        ));
      }
    } catch (e) {
      debugPrint('clearDrawingCanvas failed: $e');
    }
  }

  /// Persist the canvas background colour so both users see the same fill.
  /// Stored as `bgColor` on the `groups/{groupId}/canvas/main` meta-document.
  Future<void> setCanvasBgColor({
    required String groupId,
    required int colorValue,
    String canvasId = 'main',
  }) async {
    try {
      if (_writeFb(groupId)) {
        await _canvasMainRef(
          groupId,
          canvasId,
        ).set({'bgColor': colorValue}, SetOptions(merge: true));
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorCanvasMeta(groupId, canvasId, bgColor: colorValue));
      }
    } catch (e) {
      debugPrint('setCanvasBgColor failed: $e');
    }
  }

  /// Combined stream of canvas meta fields (bgColor, clearVersion, rotation).
  /// Use this instead of subscribing three times to the same document — each
  /// snapshot listener is metered separately by Firestore, so a single
  /// subscription cuts canvas/main reads to ~1/3 of the previous cost.
  Stream<RemoteCanvasMeta> listenToCanvasMeta({
    required String groupId,
    String canvasId = 'main',
  }) {
    // Stage 2: мета холста читается из Firebase. Stage 3 — из Supabase (_readSb).
    if (_readSb(groupId)) {
      return _sb.watchCanvasMeta(groupId, canvasId).map(
            (m) => RemoteCanvasMeta(
              bgColor: m['bgColor'],
              clearVersion: m['clearVersion'],
              rotationMilliRadians: m['rotation'],
            ),
          );
    }
    return _canvasMainRef(groupId, canvasId).snapshots().map((snap) {
      final data = snap.data();
      return RemoteCanvasMeta(
        bgColor: (data?['bgColor'] as num?)?.toInt(),
        clearVersion: (data?['clearVersion'] as num?)?.toInt(),
        rotationMilliRadians: (data?['canvasRotation'] as num?)?.toInt(),
      );
    });
  }

  /// Persist the canvas rotation so both users see the same orientation.
  /// Stored as `canvasRotation` (angle in milli-radians, int) on the canvas/main doc.
  Future<void> setCanvasRotation({
    required String groupId,
    required int rotationQuarterTurns, // actually milli-radians
    String canvasId = 'main',
  }) async {
    try {
      if (_writeFb(groupId)) {
        await _canvasMainRef(
          groupId,
          canvasId,
        ).set({'canvasRotation': rotationQuarterTurns}, SetOptions(merge: true));
      }
      if (_dualWrite) {
        unawaited(_sb.mirrorCanvasMeta(
          groupId,
          canvasId,
          rotation: rotationQuarterTurns,
        ));
      }
    } catch (e) {
      debugPrint('setCanvasRotation failed: $e');
    }
  }

  /// Upload a drawing image to Firebase Storage and return the download URL.
  Future<String?> uploadDrawingImage({
    required String groupId,
    required String localPath,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return uploadFile(localPath, 'groups/$groupId/canvas/img_$ts.jpg');
  }

  // ── Canvas Catalogue ─────────────────────────────────────────────────────
  // Firestore: groups/{groupId}/canvasCatalogue/{canvasId}

  /// Create or update a canvas meta entry in the shared catalogue.
  Future<void> upsertCanvasMeta({
    required String groupId,
    required String canvasId,
    required String name,
    required int createdAt,
    required int updatedAt,
    String? createdBy,
  }) async {
    try {
      final data = <String, dynamic>{
        'id': canvasId,
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
      if (createdBy != null) data['createdBy'] = createdBy;
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('canvasCatalogue')
          .doc(canvasId)
          .set(data, SetOptions(merge: true));
      if (_dualWrite) {
        unawaited(_sb.mirrorCanvasCatalogue(groupId, canvasId, data));
      }
    } catch (e) {
      debugPrint('upsertCanvasMeta failed: $e');
    }
  }

  /// Rename a canvas in the shared catalogue.
  Future<void> renameCanvasMeta({
    required String groupId,
    required String canvasId,
    required String newName,
  }) async {
    try {
      final updates = {
        'name': newName,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('canvasCatalogue')
          .doc(canvasId)
          .update(updates);
      if (_dualWrite) {
        unawaited(_sb.mirrorCanvasCatalogue(groupId, canvasId, updates));
      }
    } catch (e) {
      debugPrint('renameCanvasMeta failed: $e');
    }
  }

  /// Delete a canvas meta entry from the shared catalogue.
  Future<void> deleteCanvasMeta({
    required String groupId,
    required String canvasId,
  }) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('canvasCatalogue')
          .doc(canvasId)
          .delete();
      if (_dualWrite) {
        unawaited(_sb.mirrorCanvasCatalogueDelete(groupId, canvasId));
      }
    } catch (e) {
      debugPrint('deleteCanvasMeta failed: $e');
    }
  }

  /// Stream of all canvas meta entries for a group.
  Stream<List<Map<String, dynamic>>> listenToCanvasCatalogue({
    required String groupId,
  }) {
    // Stage 2: каталог холстов читается из Firebase. Stage 3 — Supabase (_readSb).
    if (_readSb(groupId)) return _sb.watchCanvasCatalogue(groupId);
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('canvasCatalogue')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Map<String, dynamic>.from(d.data()))
              .toList(),
        );
  }

  /// Record / remove the current user's presence on a specific canvas.
  Future<void> setCanvasPresence({
    required String groupId,
    required String canvasId,
    required String userId,
    required bool present,
  }) async {
    try {
      final ref = _db
          .collection('groups')
          .doc(groupId)
          .collection('canvas')
          .doc(canvasId)
          .collection('presence')
          .doc(userId);
      if (present) {
        await ref.set({
          'userId': userId,
          'joinedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await ref.delete();
      }
    } catch (e) {
      debugPrint('setCanvasPresence failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  MASCOTS
  // ══════════════════════════════════════════════

  CollectionReference<Map<String, dynamic>> _mascotsRef(String groupId) =>
      _db.collection('groups').doc(groupId).collection('mascots');

  /// Upload raw PNG bytes to Storage and return a media ref (sb:// под _mig,
  /// иначе download URL). Резолвится через resolveMediaUrl/StorageImage.
  Future<String?> uploadMascotImage({
    required String groupId,
    required List<int> pngBytes,
  }) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'groups/$groupId/mascots/mascot_$ts.png';
      // Медиа полностью мигрированной группы → Supabase (sb://), синхронно с
      // данными (Stage 4). Иначе → Firebase (общий источник / откат).
      if (!_writeFb(groupId)) {
        return _sb.uploadStorageFile(
          Uint8List.fromList(pngBytes),
          path,
          contentType: 'image/png',
        );
      }
      final ref = _storage.ref().child(path);
      final metadata = SettableMetadata(contentType: 'image/png');
      final task = ref.putData(Uint8List.fromList(pngBytes), metadata);
      final snapshot = await task;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('uploadMascotImage failed: $e');
      return null;
    }
  }

  /// Save a new mascot document (or overwrite existing id).
  Future<void> saveMascot({
    required String groupId,
    required Mascot mascot,
  }) async {
    try {
      await _mascotsRef(
        groupId,
      ).doc(mascot.id).set(mascot.toFirestore(), SetOptions(merge: true));
      if (_dualWrite) unawaited(_sb.mirrorMascot(groupId, mascot.toFirestore()));
    } catch (e) {
      debugPrint('saveMascot failed: $e');
    }
  }

  /// Save multiple mascots in one batch (used for seeding defaults).
  Future<void> saveMascotsBatch({
    required String groupId,
    required List<Mascot> mascots,
  }) async {
    try {
      final batch = _db.batch();
      for (final m in mascots) {
        batch.set(
          _mascotsRef(groupId).doc(m.id),
          m.toFirestore(),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      if (_dualWrite) {
        unawaited(_sb.mirrorMascotsBatch(
          groupId,
          mascots.map((m) => m.toFirestore()).toList(),
        ));
      }
    } catch (e) {
      debugPrint('saveMascotsBatch failed: $e');
    }
  }

  /// Delete a mascot and its Storage image (if remote).
  Future<void> deleteMascot({
    required String groupId,
    required String mascotId,
    String? imageUrl,
  }) async {
    try {
      await _mascotsRef(groupId).doc(mascotId).delete();
      if (_dualWrite) unawaited(_sb.deleteMascotRow(groupId, mascotId));
      // Удаляем картинку из её хранилища: deleteFileByUrl роутит sb://→Supabase
      // Storage, иначе → Firebase Storage (historic download URL).
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await deleteFileByUrl(imageUrl);
      }
    } catch (e) {
      debugPrint('deleteMascot failed: $e');
    }
  }

  /// Rename a mascot.
  Future<void> renameMascot({
    required String groupId,
    required String mascotId,
    required String newName,
  }) async {
    try {
      await _mascotsRef(groupId).doc(mascotId).update({'name': newName});
      if (_dualWrite) unawaited(_sb.renameMascot(groupId, mascotId, newName));
    } catch (e) {
      debugPrint('renameMascot failed: $e');
    }
  }

  /// Update record streak for a mascot.
  Future<void> updateMascotRecord({
    required String groupId,
    required String mascotId,
    required int recordStreak,
  }) async {
    try {
      await _mascotsRef(
        groupId,
      ).doc(mascotId).update({'recordStreak': recordStreak});
      if (_dualWrite) {
        unawaited(_sb.updateMascotRecord(groupId, mascotId, recordStreak));
      }
    } catch (e) {
      debugPrint('updateMascotRecord failed: $e');
    }
  }

  /// Set the active mascot for the group (null = no active mascot).
  Future<void> setActiveMascot({
    required String groupId,
    required String? mascotId,
  }) async {
    try {
      await _db.collection('groups').doc(groupId).set({
        'activeMascotId': mascotId,
      }, SetOptions(merge: true));
      if (_dualWrite) {
        // mirrorGroupFields = update (не upsert) и пропускает null → годится и
        // для очистки активного маскота (mascotId == null).
        unawaited(_sb.mirrorGroupFields(groupId, {'active_mascot_id': mascotId}));
      }
    } catch (e) {
      debugPrint('setActiveMascot failed: $e');
    }
  }

  /// Атомарно начислить XP паре (общий счётчик уровня). Растёт как
  /// memoriesCount: Firebase increment (источник) + зеркало в Supabase.
  Future<void> addGroupXp(String groupId, int amount) async {
    if (groupId.isEmpty || amount == 0) return;
    try {
      if (_writeFb(groupId)) {
        unawaited(
          _db
              .collection('groups')
              .doc(groupId)
              .update({'xp': FieldValue.increment(amount)})
              .catchError((_) {}),
        );
      }
      if (_dualWrite) {
        unawaited(_sb.incrementGroupCounters(groupId, xp: amount));
      }
    } catch (e) {
      debugPrint('addGroupXp failed: $e');
    }
  }

  /// Update the floating mascot's position and scale.
  Future<void> updateMascotPosition({
    required String groupId,
    required double x,
    required double y,
    required double scale,
  }) async {
    try {
      await _db.collection('groups').doc(groupId).set({
        'mascotPositionX': x,
        'mascotPositionY': y,
        'mascotScale': scale,
      }, SetOptions(merge: true));
      if (_dualWrite) {
        unawaited(_sb.mirrorGroupFields(groupId, {
          'mascot_position_x': x,
          'mascot_position_y': y,
          'mascot_scale': scale,
        }));
      }
    } catch (e) {
      debugPrint('updateMascotPosition failed: $e');
    }
  }

  /// Record that someone from this group opened the app today.
  /// Updates the group's streak counter.
  Future<void> recordGroupActivity(String groupId) async {
    if (groupId.isEmpty) return;
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Двойная запись: зеркалим активность в Supabase (идемпотентный RPC за
      // день) + ведём streak в Firebase (источник) ниже.
      if (_dualWrite) unawaited(_sb.recordGroupActivity(groupId, today));

      // Огонёк растёт ТОЛЬКО когда за день зашли ОБА партнёра (а не один). Первый
      // зашедший фиксируется в streakPendingUid/Date, второй ОТЛИЧНЫЙ участник —
      // поднимает streakDays. group-doc активно слушается (_listenToPair), кэш
      // обычно свежий — основные решения принимаем по кэшу БЕЗ сетевого
      // round-trip (функция зовётся на каждый resume; серверное чтение на каждый
      // вызов = всплеск Firestore-чтений). Сервер дёргаем лишь в момент роста
      // огонька (≈раз в день): чтобы устаревший кэш не сбросил живую серию и не
      // словить гонку с устройством партнёра, которое могло уже засчитать день.
      Map<String, dynamic>? data;
      try {
        final doc = await _db
            .collection('groups')
            .doc(groupId)
            .get(const GetOptions(source: Source.cache));
        data = doc.data();
      } catch (_) {
        data = null;
      }
      if (data == null) {
        // Кэша нет (первый запуск/переустановка) — одно серверное чтение.
        try {
          final doc = await _db
              .collection('groups')
              .doc(groupId)
              .get(const GetOptions(source: Source.server));
          data = doc.data();
        } catch (_) {
          return; // оффлайн — ничего не пишем
        }
      }
      if (data == null) return;

      bool bothPresent(Map<String, dynamic> d) {
        final pUid = d['streakPendingUid'] as String?;
        return d['streakPendingDate'] == today && pUid != null && pUid != uid;
      }

      // Кэш намекает, что пара «оба зашли» → перед ростом берём авторитетные
      // данные с сервера (раз в день).
      if (data['streakLastOpenedDate'] != today && bothPresent(data)) {
        try {
          final doc = await _db
              .collection('groups')
              .doc(groupId)
              .get(const GetOptions(source: Source.server));
          data = doc.data();
        } catch (_) {
          return;
        }
        if (data == null) return;
      }

      final last = data['streakLastOpenedDate'] as String?;
      if (last == today) return; // уже засчитано сегодня (оба заходили)

      // Второй РАЗНЫЙ участник отметился сегодня → пара «оба зашли» → растим.
      if (bothPresent(data)) {
        final lastDt = last != null ? DateTime.tryParse(last) : null;
        final todayDate = DateTime(now.year, now.month, now.day);
        final diff = lastDt != null
            ? todayDate
                .difference(DateTime(lastDt.year, lastDt.month, lastDt.day))
                .inDays
            : 999;
        final currentStreak = (data['streakDays'] as num?)?.toInt() ?? 0;
        final newStreak = diff == 1 ? currentStreak + 1 : 1;

        await _db.collection('groups').doc(groupId).set({
          'streakDays': newStreak,
          'streakLastOpenedDate': today,
        }, SetOptions(merge: true));

        // Рекорд активного маскота.
        final activeMascotId = data['activeMascotId'] as String?;
        if (activeMascotId != null) {
          final mascotDoc = await _mascotsRef(groupId).doc(activeMascotId).get();
          if (mascotDoc.exists) {
            final record =
                (mascotDoc.data()?['recordStreak'] as num?)?.toInt() ?? 0;
            if (newStreak > record) {
              await _mascotsRef(
                groupId,
              ).doc(activeMascotId).update({'recordStreak': newStreak});
            }
          }
        }
        return;
      }

      // Первый участник за сегодня (или повторный заход того же) — ставим
      // ожидание партнёра. Огонёк пока НЕ растёт.
      final pendingDate = data['streakPendingDate'] as String?;
      final pendingUid = data['streakPendingUid'] as String?;
      if (pendingDate != today || pendingUid == null) {
        await _db.collection('groups').doc(groupId).set({
          'streakPendingDate': today,
          'streakPendingUid': uid,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('recordGroupActivity failed: $e');
    }
  }

  /// Real-time stream of group mascot state (active id, position, scale, streak).
  Stream<GroupMascotState> listenToGroupMascotState({required String groupId}) {
    if (_readSb(groupId)) return _sb.watchGroupMascotState(groupId);
    String? prevSig;
    return _groupDocStream(groupId)
        .map(
          (snap) => snap.exists
              ? GroupMascotState.fromMap(snap.data()!)
              : const GroupMascotState(),
        )
        .where((state) {
          // De-dupe noisy group-doc updates that don't change mascot fields
          // (mood, status, timers, missYouCounts, etc.). Without this filter
          // the mascot widget rebuilds on every unrelated group-doc change.
          final sig =
              '${state.activeMascotId}|${state.positionX}|${state.positionY}|'
              '${state.scale}|${state.streakDays}|${state.streakLastOpenedDate}|'
              '${state.xp}';
          if (sig == prevSig) return false;
          prevSig = sig;
          return true;
        });
  }

  /// Real-time stream of mascots in the group gallery.
  Stream<List<Mascot>> listenToMascots({required String groupId}) {
    if (_readSb(groupId)) return _sb.watchMascots(groupId);
    return _mascotsRef(groupId).snapshots().map(
      (snap) =>
          snap.docs
              .map((d) => Mascot.fromFirestore(d.data()))
              .where((m) => m.id.isNotEmpty)
              .toList()
            ..sort((a, b) {
              // defaults first, then by creation date
              if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
              return a.createdAt.compareTo(b.createdAt);
            }),
    );
  }

  /// Count of mascots in the group.
  Future<int> getMascotCount(String groupId) async {
    try {
      if (_readSb(groupId)) return await _sb.getMascotCount(groupId);
      final snap = await _mascotsRef(groupId).count().get();
      return snap.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Read denormalized memories count from group doc, falling back to count query
  /// for groups that predate the counter field. The result is written back so
  /// subsequent calls are a single doc read instead of a full index scan.
  /// Pass [groupData] to avoid an extra group doc read when the caller already has it.
  Future<int> getGroupMemoriesCount(
    String groupId, {
    Map<String, dynamic>? groupData,
  }) async {
    try {
      // Этап 4: счётчик ведётся в Supabase (group_inc_counters).
      if (_readSb(groupId)) {
        final row = await _sb.fetchGroupColumns(groupId, ['memories_count']);
        return (row?['memories_count'] as num?)?.toInt() ?? 0;
      }
      if (groupData != null) {
        final c = groupData['memoriesCount'];
        if (c != null) return (c as num).toInt();
      } else {
        final groupDoc = await _db.collection('groups').doc(groupId).get();
        if (groupDoc.exists) {
          final c = groupDoc.data()?['memoriesCount'];
          if (c != null) return (c as num).toInt();
        }
      }
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('memories')
          .count()
          .get();
      final count = snap.count ?? 0;
      unawaited(
        _db
            .collection('groups')
            .doc(groupId)
            .update({'memoriesCount': count})
            .catchError((_) {}),
      );
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// Read denormalized drawings count from group doc, with the same fallback.
  /// Pass [groupData] to avoid an extra group doc read when the caller already has it.
  Future<int> getGroupDrawingsCount(
    String groupId, {
    Map<String, dynamic>? groupData,
  }) async {
    try {
      if (_readSb(groupId)) {
        final row = await _sb.fetchGroupColumns(groupId, ['drawings_count']);
        return (row?['drawings_count'] as num?)?.toInt() ?? 0;
      }
      if (groupData != null) {
        final c = groupData['drawingsCount'];
        if (c != null) return (c as num).toInt();
      } else {
        final groupDoc = await _db.collection('groups').doc(groupId).get();
        if (groupDoc.exists) {
          final c = groupDoc.data()?['drawingsCount'];
          if (c != null) return (c as num).toInt();
        }
      }
      final snap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('canvases')
          .count()
          .get();
      final count = snap.count ?? 0;
      unawaited(
        _db
            .collection('groups')
            .doc(groupId)
            .update({'drawingsCount': count})
            .catchError((_) {}),
      );
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// Atomically increment/decrement the denormalized drawings counter.
  Future<void> incrementDrawingsCount(String groupId, int delta) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'drawingsCount': FieldValue.increment(delta),
      });
      if (_dualWrite) {
        unawaited(_sb.incrementGroupCounters(groupId, drawings: delta));
      }
    } catch (e) {
      debugPrint('incrementDrawingsCount failed: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

class _LocalNotificationContent {
  final String title;
  final String body;

  const _LocalNotificationContent({required this.title, required this.body});
}

/// Internal transfer object used by [listenToDrawingStrokes].
class _DrawStrokeRaw {
  final String id;
  final Map<String, dynamic> data;
  const _DrawStrokeRaw({required this.id, required this.data});
}

/// Snapshot of the shared canvas/main meta document — merged so a single
/// Firestore listener can drive bgColor / clearVersion / rotation updates.
/// Named `RemoteCanvasMeta` to avoid collision with the local catalogue
/// entry in models/canvas_meta.dart.
class RemoteCanvasMeta {
  final int? bgColor;
  final int? clearVersion;
  final int? rotationMilliRadians;
  const RemoteCanvasMeta({
    this.bgColor,
    this.clearVersion,
    this.rotationMilliRadians,
  });
}

/// Ref-counted multiplexer around a single Firestore document snapshot listener.
///
/// Each independent `.snapshots()` subscription on the same DocumentReference
/// is billed separately by Firestore. The hub lets multiple consumers share
/// ONE underlying subscription: the first listener opens it, the last cancel
/// closes it, and new listeners immediately receive the most recent snapshot
/// so they don't have to wait for the next server event.
///
/// Re-establishing a `.snapshots()` listener costs a fresh server read (the
/// initial document load is billed). Screen navigation and `StreamBuilder`
/// rebuilds briefly drop the listener count to zero, so an immediate teardown
/// would bill a new read the instant the next consumer subscribes. To avoid
/// that, the underlying subscription is kept warm for [_idleGrace] after the
/// last listener leaves: rapid re-subscription reuses the live listener and the
/// replayed [_latest] snapshot at zero extra read cost. The document changes
/// rarely, so the idle warm window is effectively free.
class _DocSnapshotHub {
  _DocSnapshotHub(this._ref);

  static const Duration _idleGrace = Duration(seconds: 90);

  final DocumentReference<Map<String, dynamic>> _ref;
  final StreamController<DocumentSnapshot<Map<String, dynamic>>> _controller =
      StreamController.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  DocumentSnapshot<Map<String, dynamic>>? _latest;
  Timer? _idleTimer;

  bool get _isActive => _sub != null;

  void _start() {
    // A new consumer arrived — cancel any pending idle teardown so we keep
    // reusing the warm subscription instead of paying for a fresh read.
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_isActive) return;
    _sub = _ref.snapshots().listen(
      (snap) {
        _latest = snap;
        if (!_controller.isClosed) _controller.add(snap);
      },
      onError: (Object e, StackTrace st) {
        if (!_controller.isClosed) _controller.addError(e, st);
      },
    );
  }

  void _stopIfIdle() {
    if (_controller.hasListener) return;
    // Defer the actual teardown: if a consumer re-subscribes within the grace
    // window (navigation transition, StreamBuilder rebuild), _start() cancels
    // this timer and the live subscription is reused — no new read.
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleGrace, () {
      _idleTimer = null;
      if (_controller.hasListener) return;
      _sub?.cancel();
      _sub = null;
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> get stream {
    return Stream.multi((controller) {
      _start();
      // Replay the latest snapshot so consumers that subscribe mid-stream
      // (e.g. opening profile_screen while a partner has been online for a
      // while) see the current state without waiting for the next change.
      final cached = _latest;
      if (cached != null) controller.add(cached);
      final sub = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () async {
        await sub.cancel();
        _stopIfIdle();
      };
    });
  }
}

class _SignedUrlEntry {
  final String url;
  final DateTime expiresAt;
  _SignedUrlEntry(this.url, this.expiresAt);
  // Считаем валидным пока до истечения больше 5 минут
  bool get isValid => expiresAt.difference(DateTime.now()).inMinutes > 5;
}
