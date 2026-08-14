// Кастомная сборка PocketBase 0.39.11 с НАТИВНЫМ SQLite (CGO, mattn) вместо
// транспилированного modernc.
//
// Зачем: под дневной нагрузкой Togetherly глобальный мьютекс аллокатора
// modernc/libc становится общей точкой сериализации — записи стоят десятками
// секунд при свободном замке самой базы (дамп горутин 14.08.2026: писатель
// заблокирован в modernc.org/libc.Xfree). Нативный C-SQLite этого слоя не
// имеет вовсе.
//
// Состав повторяет examples/base: JSVM (pb_hooks работают как раньше),
// migratecmd, gh-update отключён. Драйвер подключается через Config.DBConnect —
// официальный путь PocketBase для альтернативных драйверов SQLite.
package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	_ "net/http/pprof" // профилировщик на локальном порту, см. ниже
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"strings"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/jsvm"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"
	"github.com/pocketbase/pocketbase/tools/hook"

	"github.com/mattn/go-sqlite3"
)

// ── Рассылка изменений в Centrifugo ──────────────────────────────────────────
//
// Раньше это делал JS-хук `centrifugo.pb.js`, и профиль 14.08.2026 показал, что
// на исполнение JavaScript уходит четверть процессора PocketBase: каждое
// событие поднимало виртуальную машину goja, собирало тело и слало HTTP.
// Здесь то же самое нативно — на порядок дешевле. Каналы и форма тела
// повторены один в один, чтобы клиент не заметил разницы:
//   user:<uid>      — присутствие и изменения групп пользователя
//   loc:<channel>   — геопозиция
//   pair:<groupId>  — всё остальное
//
// Отправка асинхронная: событие уходит в фон, ответ клиенту не ждёт сети.

var rtCollections = map[string]bool{
	"chat_messages": true, "mood_entries": true, "memories": true,
	"memory_comments": true, "mascots": true, "miss_you": true, "gifts": true,
	"user_presence": true, "live_sessions": true, "live_session_presence": true,
	"live_session_chat": true, "live_location": true, "canvas_strokes": true,
	"canvas_meta": true, "canvas_live": true, "canvas_catalogue": true,
	"widget_data": true, "chat_typing": true, "chat_reads": true, "groups": true,
	"watch_history": true, "cycle_entries": true, "wishes": true,
	"wish_categories": true, "custom_moods": true,
}

var centClient = &http.Client{Timeout: 5 * time.Second}

// Сколько соединений отдаём под запись. Переопределяется переменной окружения
// PB_WRITE_POOL — чтобы менять на живом сервере без пересборки.
var writePoolSize = func() int {
	if v := os.Getenv("PB_WRITE_POOL"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return 4
}()

func centChannels(rec *core.Record) []string {
	col := rec.Collection().Name
	switch col {
	case "user_presence":
		if u := rec.GetString("user_uid"); u != "" {
			return []string{"user:" + u}
		}
	case "live_location":
		if c := rec.GetString("channel"); c != "" {
			return []string{"loc:" + c}
		}
	case "live_sessions":
		return []string{"pair:" + rec.Id}
	case "live_session_presence", "live_session_chat":
		if p := rec.GetString("pair_id"); p != "" {
			return []string{"pair:" + p}
		}
	case "groups":
		// Кроме канала пары — личные каналы участников: иначе приглашающий не
		// увидит появление пары до перезапуска приложения (разбор 02.08.2026).
		out := []string{"pair:" + rec.Id}
		for _, uid := range rec.GetStringSlice("members") {
			if uid != "" {
				out = append(out, "user:"+uid)
			}
		}
		return out
	default:
		if g := rec.GetString("group_id"); g != "" {
			return []string{"pair:" + g}
		}
	}
	return nil
}

func centPublish(event string, rec *core.Record) {
	if rec == nil || !rtCollections[rec.Collection().Name] {
		return
	}
	api, key := os.Getenv("CENTRIFUGO_API"), os.Getenv("CENTRIFUGO_API_KEY")
	if api == "" || key == "" {
		return
	}
	channels := centChannels(rec)
	if len(channels) == 0 {
		return
	}
	payload := map[string]any{
		"event": event, "collection": rec.Collection().Name, "record": rec,
	}
	go func() {
		for _, ch := range channels {
			body, err := json.Marshal(map[string]any{"channel": ch, "data": payload})
			if err != nil {
				return
			}
			req, err := http.NewRequest("POST", api+"/publish", bytes.NewReader(body))
			if err != nil {
				return
			}
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("X-API-Key", key)
			resp, err := centClient.Do(req)
			if err != nil {
				log.Println("centrifugo publish:", err)
				return
			}
			resp.Body.Close()
		}
	}()
}

// ── Кэш авторизации ──────────────────────────────────────────────────────────
//
// PocketBase на КАЖДЫЙ запрос идёт в базу за записью пользователя по токену
// (`loadAuthToken` → `FindAuthRecordByToken`). Профиль вечернего пика
// 14.08.2026: 12,7% всего процессора PocketBase, при 1160 новых соединениях в
// секунду это заметная доля. Держим найденную запись двадцать секунд и отдаём
// обработчику её копию — общий объект трогать нельзя, запрос может его менять.
//
// Подпись токена к этому моменту уже проверена базой при первом попадании.
// Инвалидация обязательна: запись пользователя изменилась или удалена — все его
// токены выкидываем сразу, иначе правила доступа считали бы по старым
// `group_ids` и человек не увидел бы пару (такое уже ломало приложение).
//
// Свой обработчик встаёт ПЕРЕД штатным и заполняет `e.Auth`; штатный видит
// заполненное поле и молча пропускает запрос дальше — отвязывать его не нужно.
const authCacheTTL = 20 * time.Second

type authCacheItem struct {
	rec *core.Record
	uid string
	exp time.Time
}

var (
	authByToken sync.Map // токен → authCacheItem
	authByUID   sync.Map // id пользователя → *sync.Map(токен → struct{})
)

func authCacheGet(token string, now time.Time) *core.Record {
	v, ok := authByToken.Load(token)
	if !ok {
		return nil
	}
	item := v.(authCacheItem)
	if !item.exp.After(now) {
		authCacheForget(token, item.uid)
		return nil
	}
	return item.rec
}

func authCachePut(token string, rec *core.Record, now time.Time) {
	authByToken.Store(token, authCacheItem{rec: rec, uid: rec.Id, exp: now.Add(authCacheTTL)})
	set, _ := authByUID.LoadOrStore(rec.Id, &sync.Map{})
	set.(*sync.Map).Store(token, struct{}{})
}

func authCacheForget(token, uid string) {
	authByToken.Delete(token)
	if v, ok := authByUID.Load(uid); ok {
		v.(*sync.Map).Delete(token)
	}
}

// Пользователь изменился — его прежние токены больше не годятся.
func authCacheDropUser(uid string) {
	v, ok := authByUID.LoadAndDelete(uid)
	if !ok {
		return
	}
	v.(*sync.Map).Range(func(k, _ any) bool {
		authByToken.Delete(k)
		return true
	})
}

// Уборка протухшего: без неё карта растёт на каждый новый токен.
func authCacheSweeper() {
	for range time.Tick(time.Minute) {
		now := time.Now()
		authByToken.Range(func(k, v any) bool {
			item := v.(authCacheItem)
			if !item.exp.After(now) {
				authCacheForget(k.(string), item.uid)
			}
			return true
		})
	}
}

func authTokenFromRequest(e *core.RequestEvent) string {
	token := e.Request.Header.Get("Authorization")
	// Префикс «Bearer» PocketBase не требует, но клиенты его шлют.
	if len(token) > 7 && strings.EqualFold(token[:7], "Bearer ") {
		return token[7:]
	}
	return token
}

// Драйвер с отображением базы в память. Профиль вечернего пика 14.08.2026:
// треть процессора PocketBase уходит внутрь SQLite, и заметная доля там — это
// системные вызовы чтения. При `mmap_size` SQLite читает страницы прямо из
// отображённой памяти, минуя `read()`; страницы общие на весь процесс, поэтому
// память не дублируется по соединениям (в отличие от `cache_size`, который у
// PocketBase множится на сто двадцать соединений чтения).
// `temp_store=MEMORY` убирает временные файлы сортировок с диска.
func init() {
	sql.Register("sqlite3_tuned", &sqlite3.SQLiteDriver{
		ConnectHook: func(c *sqlite3.SQLiteConn) error {
			for _, pragma := range []string{
				"PRAGMA mmap_size = 2147483648;", // 2 ГБ
				"PRAGMA temp_store = MEMORY;",
			} {
				if _, err := c.Exec(pragma, nil); err != nil {
					return err
				}
			}
			return nil
		},
	})
}

func main() {
	// PocketBase зовёт DBConnect для каждой базы ДВАЖДЫ: сперва для пула чтения,
	// затем для пула записи (core/base.go, initDataDB). Второму подключению
	// добавляем `_txlock=immediate`: транзакция сразу берёт замок записи вместо
	// того, чтобы начаться «мягко» и упереться в чужую при первой же вставке —
	// именно такие откаты и повторы обваливали пропускную способность записи с
	// 33 до 2,7 операций в секунду (замер 14.08.2026).
	connSeen := map[string]int{}
	var connMu sync.Mutex

	app := pocketbase.NewWithConfig(pocketbase.Config{
		DBConnect: func(dbPath string) (*dbx.DB, error) {
			const params = "?_busy_timeout=10000&_journal_mode=WAL&_journal_size_limit=200000000&_synchronous=NORMAL&_foreign_keys=1&_cache_size=-16000"
			connMu.Lock()
			connSeen[dbPath]++
			isWriter := connSeen[dbPath] == 2
			connMu.Unlock()
			dsn := dbPath + params
			if isWriter {
				dsn += "&_txlock=immediate"
			}
			return dbx.Open("sqlite3_tuned", dsn)
		},
	})

	// pb_hooks: тот же прелоад, что в examples/base.
	jsvm.MustRegister(app, jsvm.Config{
		HooksWatch: true,
		HooksPoolSize: func() int {
			return 15
		}(),
	})

	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		TemplateLang: migratecmd.TemplateLangJS,
		Automigrate:  false,
	})

	// Профилировщик на 127.0.0.1:6060 — наружу не торчит (Caddy сюда не
	// маршрутизирует). Официальный бинарь его не отдаёт, а нам нужно видеть,
	// куда уходит процессор под живой нагрузкой: именно так 14.08.2026 нашлась
	// причина коллапса у Caddy.
	go func() {
		if err := http.ListenAndServe("127.0.0.1:6060", nil); err != nil {
			log.Println("pprof:", err)
		}
	}()

	app.OnRecordAfterCreateSuccess().BindFunc(func(e *core.RecordEvent) error {
		centPublish("create", e.Record)
		return e.Next()
	})
	app.OnRecordAfterUpdateSuccess().BindFunc(func(e *core.RecordEvent) error {
		centPublish("update", e.Record)
		if e.Record != nil && e.Record.Collection() != nil && e.Record.Collection().Name == "users" {
			authCacheDropUser(e.Record.Id)
		}
		return e.Next()
	})
	app.OnRecordAfterDeleteSuccess().BindFunc(func(e *core.RecordEvent) error {
		centPublish("delete", e.Record)
		if e.Record != nil && e.Record.Collection() != nil && e.Record.Collection().Name == "users" {
			authCacheDropUser(e.Record.Id)
		}
		return e.Next()
	})

	go authCacheSweeper()

	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		// Пул записи: PocketBase даёт ему ОДНО соединение, и на нашей нагрузке
		// этого мало — под вечерним пиком в очереди стояло 3262 запроса при
		// 11 работающих, а перезапуск лишь смывал очередь на несколько минут.
		// SQLite в режиме WAL сериализует писателей сам, а `_txlock=immediate`
		// плюс `busy_timeout` превращают столкновение в ожидание, а не в откат.
		// NonconcurrentDB отдаётся интерфейсом dbx.Builder — приводим к *dbx.DB,
		// чтобы добраться до пула соединений.
		if db, ok := e.App.NonconcurrentDB().(*dbx.DB); ok && db != nil {
			db.DB().SetMaxOpenConns(writePoolSize)
			db.DB().SetMaxIdleConns(writePoolSize)
			log.Println("pocketbase-cgo: соединений записи —", writePoolSize)
		} else {
			log.Println("pocketbase-cgo: пул записи не удалось расширить")
		}

		// Кэш авторизации встаёт перед штатным `pbLoadAuthToken` и заполняет
		// `e.Auth` из памяти. Штатный обработчик тогда ничего не делает —
		// первым делом он проверяет, не загружен ли пользователь до него.
		e.Router.Bind(&hook.Handler[*core.RequestEvent]{
			Id:       "cachedLoadAuthToken",
			Priority: apis.DefaultLoadAuthTokenMiddlewarePriority - 1,
			Func: func(re *core.RequestEvent) error {
				if re.Auth != nil {
					return re.Next()
				}
				token := authTokenFromRequest(re)
				if token == "" {
					return re.Next()
				}
				now := time.Now()
				if rec := authCacheGet(token, now); rec != nil {
					re.Auth = rec.Clone()
					return re.Next()
				}
				rec, err := re.App.FindAuthRecordByToken(token, core.TokenTypeAuth)
				if err != nil {
					re.App.Logger().Debug("cachedLoadAuthToken: токен не принят", "error", err)
				} else if rec != nil {
					authCachePut(token, rec.Clone(), now)
					re.Auth = rec
				}
				return re.Next()
			},
		})

		// Статика из pb_public: лендинг togetherly.day, страница комнаты
		// просмотра, политика, страница админки mod-memories.html. Официальная
		// сборка вешает этот обработчик сама; в своей его надо повторить —
		// иначе всё это отдаёт 404 (поймано живьём 14.08.2026).
		publicDir := filepath.Join(filepath.Dir(os.Args[0]), "pb_public")
		if wd, err := os.Getwd(); err == nil {
			if _, statErr := os.Stat(publicDir); statErr != nil {
				publicDir = filepath.Join(wd, "pb_public")
			}
		}
		e.Router.GET("/{path...}", apis.Static(os.DirFS(publicDir), false))
		log.Println("pocketbase-cgo: нативный SQLite, статика из", publicDir)
		return e.Next()
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
		os.Exit(1)
	}
}
