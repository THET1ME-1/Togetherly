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
	"encoding/json"
	"log"
	"net/http"
	_ "net/http/pprof" // профилировщик на локальном порту, см. ниже
	"os"
	"path/filepath"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/jsvm"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"

	_ "github.com/mattn/go-sqlite3"
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

func main() {
	app := pocketbase.NewWithConfig(pocketbase.Config{
		DBConnect: func(dbPath string) (*dbx.DB, error) {
			// Те же прагмы, что ставит сам PocketBase для modernc.
			const params = "?_busy_timeout=10000&_journal_mode=WAL&_journal_size_limit=200000000&_synchronous=NORMAL&_foreign_keys=1&_cache_size=-16000"
			return dbx.Open("sqlite3", dbPath+params)
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
		return e.Next()
	})
	app.OnRecordAfterDeleteSuccess().BindFunc(func(e *core.RecordEvent) error {
		centPublish("delete", e.Record)
		return e.Next()
	})

	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
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
