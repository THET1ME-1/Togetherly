#!/bin/bash
# Снимок нагрузки раз в минуту: чтобы после сбоя было видно, кто упёрся.
# Крон: * * * * * /opt/pocketbase/tools/load_snapshot.sh
# Журнал: /var/log/load_snapshot.log
state=/var/lib/load_snapshot.prev
overflows=$(nstat -az TcpExtListenOverflows | awk '/Overflows/{print $2}')
previous=$(cat "$state" 2>/dev/null || echo "$overflows")
echo "$overflows" > "$state"

# Процессор рабочих hotpath и PocketBase за последнюю секунду
hotpath_pids=$(pgrep -d, -P "$(systemctl show hotpath -p MainPID --value)")
pb_pid=$(systemctl show pocketbase -p MainPID --value)
# Второй кадр top — нагрузка за эту секунду, первый — за всё время процесса
cpu=$(top -b -n 2 -d 1 -p "$hotpath_pids,$pb_pid" | awk -v pb="$pb_pid" '
  /^top -/ {frame++; hot=0; base=0}
  frame == 2 && $1 ~ /^[0-9]+$/ {if ($1 == pb) base=$9; else hot+=$9}
  END {printf "%.0f %.0f", hot, base}')
hotpath_cpu=${cpu% *}
pb_cpu=${cpu#* }

queue_8120=$(ss -tn state syn-recv "( sport = :8120 )" | tail -n +2 | wc -l)
established_8120=$(ss -tn state established "( sport = :8120 )" | tail -n +2 | wc -l)

echo "$(date '+%F %T') load=$(cut -d' ' -f1 /proc/loadavg) overflow=$((overflows - previous)) hotpath_cpu=$hotpath_cpu pb_cpu=$pb_cpu conn_8120=$established_8120 synq_8120=$queue_8120"
