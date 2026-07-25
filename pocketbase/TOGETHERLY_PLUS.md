# Togetherly+ — что применить на сервере

Разовая покупка через lava.top: [товар](https://app.lava.top/products/ec861b44-a4b7-49e3-aa0e-e4608abdb0f0), 10 $.
Платёжной логики в приложении нет — всё делает вебхук, который уже принимает
покупки монет.

## 1. Поля коллекции `users`

Коллекция системная (auth), её нет в `collections_schema.json`, — поля
добавляются в админке или через API:

| Поле | Тип | Зачем |
|---|---|---|
| `plus` | bool | куплен ли Togetherly+ |
| `last_plus_grant_ms` | number | когда последний раз выдавали ежемесячные монеты |

Флаг серверный намеренно: на устройстве его не подделать, и при смене телефона
восстанавливать нечего — доступ едет вместе с аккаунтом.

## 2. Схема остальных коллекций

```
PB_EMAIL=... PB_PASSWORD=... python3 pocketbase/apply_schema.py
```

Добавилось:

* `redeem_codes.plus` (bool) — код открывает доступ, а не пополняет баланс;
* `groups.chat_background` (text) — общий фон чата пары;
* `media.file` maxSize 50 → 200 МБ, `watch_videos.file` 100 → 300 МБ;
* коллекция `cycle_entries` целиком (календарь цикла).

## 3. Хуки

Скопировать на сервер и перезапустить:

```
scp pocketbase/pb_hooks/{lava,redeem,coins}.pb.js root@77.91.95.34:/opt/pocketbase/pb_hooks/
ssh root@77.91.95.34 systemctl restart pocketbase
```

* `lava.pb.js` — узнаёт товар Togetherly+ и ставит флаг вместо монет;
* `redeem.pb.js` — код с признаком `plus` открывает доступ;
* `coins.pb.js` — роут `/api/coins/plus-monthly`, ежемесячные 150 монет.

Идентификатор товара зашит в `lava.pb.js`; он публичный (тот же, что в ссылке).
Переопределяется переменной окружения `LAVA_PLUS_SKU`, если товар пересоздадут.

## 4. Проверка

```
curl -X POST https://togetherly.duckdns.org/api/lava/webhook \
  -H "X-Api-Key: $LAVA_WEBHOOK_KEY" -H "Content-Type: application/json" \
  -d '{"status":"success","email":"<почта тестового аккаунта>",
       "productId":"ec861b44-a4b7-49e3-aa0e-e4608abdb0f0","contractId":"test-1"}'
```

Ответ `{"ok":true,"plus":true,"direct":true}` — флаг встал. Повтор с тем же
`contractId` должен вернуть `repeated: true` и ничего не менять.
