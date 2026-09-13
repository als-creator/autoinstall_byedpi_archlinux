#!/bin/bash
# ByeDPI: применить desync-обработку только к доменам из hostlist (как zapret).
# Резолвит домены из /etc/byedpi-hosts.txt в IP и кладёт их в ipset BYEDPI_HOSTS.
# Правила iptables (byedpi-redirect.service) матчат REDIRECT по этому ipset.
set -e

SET=BYEDPI_HOSTS
LIST=/etc/byedpi-hosts.txt
[ -f "$LIST" ] || { echo "Нет hostlist: $LIST" >&2; exit 0; }

ipset create "$SET" hash:ip 2>/dev/null || true
ipset flush "$SET"

count=0
while IFS= read -r domain; do
  [ -z "$domain" ] && continue
  case "$domain" in \#*) continue ;; esac
  # getent ahosts выдаёт и IPv4 и IPv6; берём уникальные, но REDIRECT ipset матчит оба семейства
  getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u | while read -r ip; do
    ipset add "$SET" "$ip" 2>/dev/null || true
  done
  count=$((count + 1))
done < "$LIST"

members=$(ipset list "$SET" 2>/dev/null | grep -cE '^[0-9a-fA-F:\.]+$' || true)
echo "ByeDPI hostlist: обработано доменов $count, IP в ipset $SET: $members"
exit 0