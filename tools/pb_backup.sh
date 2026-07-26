#!/usr/bin/env bash
# Ночная зашифрованная копия базы PocketBase.
#
# Живёт на VPS как /opt/pb_backup.sh, запускается кроном. Снимок снимается через
# `VACUUM INTO` — база при этом остаётся под нагрузкой, останавливать PocketBase
# не нужно.
#
# Шифрование: OpenPGP на ПУБЛИЧНЫЙ ключ `backup@togetherly.local`. Секретной
# части на сервере нет, поэтому взлом VPS не даёт прочитать даже те копии, что
# лежат тут же рядом. Расшифровать можно только с ноутбука:
#
#   gpg --decrypt pb-20260726-0430.db.gpg > data.db
#
# ВАЖНО: секретный ключ (~/keys/togetherly-backup-SECRET.asc) — единственный
# способ вскрыть эти копии. Потеряется он — копии превратятся в мусор.
#
# Файлы пользователей (pb_data/storage) сюда не попадают: это десятки гигабайт,
# им нужен отдельный путь (rsync на холодное хранилище).
set -euo pipefail

DB=/opt/pocketbase/pb_data/data.db
OUT=/opt/pb_backups
RECIPIENT=backup@togetherly.local
KEEP=7
MIN_FREE_GB=20

STAMP=$(date +%Y%m%d-%H%M)
TMP="$OUT/.pb-$STAMP.db"

# Незашифрованный снимок не должен пережить скрипт ни при каком исходе.
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

mkdir -p "$OUT"

FREE=$(df --output=avail -BG "$OUT" | tail -1 | tr -dc '0-9')
if [ "${FREE:-0}" -lt "$MIN_FREE_GB" ]; then
  logger -t pb_backup "мало места (${FREE}G) — копия пропущена"
  exit 1
fi

sqlite3 "$DB" "VACUUM INTO '$TMP'"

gpg --batch --yes --trust-model always \
    --encrypt --recipient "$RECIPIENT" \
    --output "$OUT/pb-$STAMP.db.gpg" "$TMP"
chmod 600 "$OUT/pb-$STAMP.db.gpg"

# Держим только последние $KEEP копий.
ls -1t "$OUT"/pb-*.db.gpg 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f

logger -t pb_backup "готово: pb-$STAMP.db.gpg ($(du -h "$OUT/pb-$STAMP.db.gpg" | cut -f1))"
