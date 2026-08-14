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
	"log"
	"os"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/jsvm"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"

	_ "github.com/mattn/go-sqlite3"
)

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

	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		log.Println("pocketbase-cgo: нативный SQLite (mattn) вместо modernc")
		return e.Next()
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
		os.Exit(1)
	}
}
