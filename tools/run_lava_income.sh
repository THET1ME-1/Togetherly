#!/usr/bin/env bash
# Сбор дохода lava по письмам продавца.
#
# Крон зовёт этот файл, а не питон напрямую: раньше вывод уходил в /dev/null, и
# поломка 14.08.2026 (значение с пробелом без кавычек в /etc/gmail-relay.env —
# dash обрывал чтение и питон не запускался) прожила двое суток незамеченной.
# Здесь каждая ошибка попадает в журнал, а bash к тому же не падает целиком на
# кривой строке окружения.
LOG=/var/log/lava_income.log
stamp() { date -Is; }

set -a
if ! . /etc/gmail-relay.env 2>/tmp/.env_err; then
  echo "$(stamp) ОШИБКА окружения: $(cat /tmp/.env_err)" >> "$LOG"
fi
set +a

if [ -z "${GMAIL_READ_REFRESH_TOKEN:-}" ]; then
  echo "$(stamp) ОШИБКА: нет GMAIL_READ_REFRESH_TOKEN — почту не прочитать" >> "$LOG"
  exit 1
fi

out=$(/usr/bin/python3 /opt/income/lava_income.py 2>&1)
code=$?
if [ $code -ne 0 ]; then
  echo "$(stamp) СБОЙ (код $code): ${out:0:400}" >> "$LOG"
  exit $code
fi

# Одна короткая строка на запуск: видно, что сбор живой и сколько продаж
# разобрано. Читаем сводку с диска, а не вывод скрипта: он печатает обрезанный
# JSON, и разобрать его нельзя — журнал годами писал «ответ не разобран».
python3 -c '
import json, datetime
now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
try:
    d = json.load(open("/opt/pocketbase/pb_data/.lava_income.json"))
    print("%s ok продаж=%s новых_писем=%s сегодня=%s"
          % (now, d.get("count"), d.get("new_mails"), d.get("today_net") or {}))
except Exception as e:
    print("%s сводка не прочиталась: %s" % (now, e))
' >> "$LOG"
