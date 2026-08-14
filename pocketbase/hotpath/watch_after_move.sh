#!/usr/bin/env bash
# Наблюдение за сервером после переезда пар в Postgres.
# Раз в десять минут пишет строку с показателями, по которым видно, держится
# ли выигрыш и не появился ли писатель, о котором мы не знаем.
#
#   nohup /opt/hotpath/watch_after_move.sh >> /var/log/after_move.log 2>&1 &
#
# Имена переменных латиницей намеренно: bash кириллические имена не принимает.
set -a; . /opt/hotpath/env; set +a

while true; do
  load=$(cut -d' ' -f1 /proc/loadavg)
  gor=$(curl -s --max-time 8 "http://127.0.0.1:6060/debug/pprof/goroutine?debug=1" 2>/dev/null | head -1 | grep -oE '[0-9]+$')
  queue=$(curl -s --max-time 8 "http://127.0.0.1:6060/debug/pprof/goroutine?debug=2" 2>/dev/null | grep -c 'database/sql.(\*DB).conn')
  # Тревога зеркала = кто-то правит пару мимо Postgres.
  alarm=$(journalctl -u hotpath --since "-10 min" --no-pager -o cat 2>/dev/null | grep -c 'ТРЕВОГА')
  fails=$(journalctl -u hotpath --since "-10 min" --no-pager -o cat 2>/dev/null | grep -c 'не обновилось')
  wr=$(tail -1 /var/log/pb_write_watchdog.log 2>/dev/null | grep -oE 'макс [0-9.]+с')
  noacc=$(/opt/hotpath/venv/bin/python /opt/hotpath/check_membership.py 2>/dev/null | sed -n '2p' | grep -oE '[0-9]+$')

  echo "$(date -Is) load=${load} горутин=${gor:-?} очередь=${queue:-?} тревог=${alarm} сбоев_зеркала=${fails} ${wr:-запись=?} без_доступа=${noacc:-?}"
  sleep 600
done
