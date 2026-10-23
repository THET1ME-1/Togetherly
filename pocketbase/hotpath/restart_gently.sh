#!/bin/bash
# Перезапуск hotpath, которого люди не замечают.
#
# Пока uvicorn гасит рабочих (около двух секунд), его слушающий сокет открыт:
# ядро принимает новые соединения, отвечать на них некому, и при выходе процесса
# они рвутся. Caddy отдаёт на них 502: выкладка TOG-10 22.10.2026 дала 161 ответ
# за одну секунду, 142 из них — «Скучаю». Удержание Caddy (hold) повторяет
# только несостоявшееся соединение, поэтому на время перезапуска новые
# соединения к hotpath отбиваются сразу (RST): Caddy ждёт и повторяет, пока не
# поднимется новый процесс. Начатые запросы старый процесс дорабатывает.
#
# Отбиваются только соединения от Caddy этого сервера и из туннеля точки входа,
# поэтому проверка готовности от root проходит. Правила снимаются при выходе
# скрипта, а страховочный таймер снимет их через минуту, даже если скрипт убьют.
set -u
port=8120
log=/var/log/hotpath_restart.log
rules=(
  "OUTPUT -o lo -p tcp -d 127.0.0.1 --dport $port --syn -m owner --uid-owner caddy -j REJECT --reject-with tcp-reset"
  "INPUT -i wg0 -p tcp --dport $port --syn -j REJECT --reject-with tcp-reset"
)

say() { echo "$(date '+%F %T.%3N') $*" | tee -a "$log"; }

remove_rules() {
  for rule in "${rules[@]}"; do
    while iptables -D $rule 2>/dev/null; do :; done
  done
}
trap remove_rules EXIT

# Страховка на случай, если скрипт убьют между вставкой и снятием правил
safety_unit=hotpath-restart-safety-$$
n=0
for rule in "${rules[@]}"; do
  systemd-run --quiet --unit "$safety_unit-$((++n))" --on-active=60 \
    --timer-property=AccuracySec=1s /usr/sbin/iptables -D $rule
done

old_pid=$(systemctl show -p MainPID --value hotpath)
say "старт, прежний процесс $old_pid"
for rule in "${rules[@]}"; do iptables -I $rule; done
say "новые соединения к $port отбиваются"

systemctl restart hotpath
say "systemctl restart вернулся, новый процесс $(systemctl show -p MainPID --value hotpath)"

# Новый процесс готов, когда отвечает на проверку
ready=no
for _ in $(seq 1 120); do
  if curl -sf -m 2 "http://127.0.0.1:$port/healthz" >/dev/null; then
    ready=yes
    break
  fi
  sleep 0.25
done
remove_rules
say "правила сняты, hotpath готов: $ready"
[ "$ready" = yes ]
