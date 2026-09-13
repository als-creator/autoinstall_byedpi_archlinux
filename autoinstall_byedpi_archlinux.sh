#!/bin/bash
set -e

# Запрещаем запуск от root
[ "$EUID" -eq 0 ] && { echo "Не запускайте скрипт от root." >&2; exit 1; }

# Проверка наличия sudo
if sudo -l &>/dev/null; then
  echo "Есть права sudo"
else
  echo "Нет прав sudo"
  exit 1
fi

MODE="${1:---socks}"

# Установка yay из AUR вручную, если не найден
command -v yay &>/dev/null \
  || {
    echo "yay не найден — собираю из AUR..."
    cd /tmp
    [ -d yay ] && rm -rf yay
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
  }

# Установка byedpi-bin, если его нет
pacman -Q byedpi-bin &>/dev/null \
  || yay -Sy --noconfirm byedpi-bin

# Зависимость для transparent-режима: ipset
if ! pacman -Q ipset &>/dev/null; then
  sudo pacman -S --noconfirm --needed ipset || true
fi

case "$MODE" in
  --socks)
    echo 'BYEDPI_OPTIONS="-i 127.0.0.1 --port 14228 -Kt,h -s0 -o1 -Ar -o1 -At -f-1 --md5sig -r1+s -As,n -Ku -a5 -An"' \
      | sudo tee /etc/byedpi.conf > /dev/null
    enable_byedpi_socks=1
    ;;
  --transparent)
    # Прозрачный режим: без браузерных расширений, применимо ТОЛЬКО к hostlist.
    # Демон слушает локальный порт и читает настоящий адрес назначения
    # через SO_ORIGINAL_DST. REDIRECT в iptables матчит только IP из ipset
    # BYEDPI_HOSTS (домены из /etc/byedpi-hosts.txt), остальной трафик идёт напрямую.
    echo 'BYEDPI_OPTIONS="-i 127.0.0.1 --port 14228 -E -Kt,h -s0 -o1 -Ar -o1 -At -f-1 --md5sig -r1+s -As,n -Ku -a5 -An"' \
      | sudo tee /etc/byedpi.conf > /dev/null
    enable_byedpi_socks=0
    ;;
  --transparent-off)
    # Вернуть SOCKS-режим и убрать правила перенаправления
    echo 'BYEDPI_OPTIONS="-i 127.0.0.1 --port 14228 -Kt,h -s0 -o1 -Ar -o1 -At -f-1 --md5sig -r1+s -As,n -Ku -a5 -An"' \
      | sudo tee /etc/byedpi.conf > /dev/null
    enable_byedpi_socks=1
    ;;
  *)
    echo "Неизвестный режим: $MODE" >&2
    echo "Доступно: --socks (по умолчанию), --transparent, --transparent-off" >&2
    exit 1
    ;;
esac

# Hostlist для transparent-режима (домены, которые будут обрабатываться)
sudo tee /etc/byedpi-hosts.txt >/dev/null <<'EOF'
# ByeDPI hostlist — домены, к которым применяется desync.
# Формат: один домен на строку, строки с # игнорируются.
# После правки: sudo systemctl restart byedpi-hosts byedpi-redirect
youtube.com
youtube-nocookie.com
youtu.be
ytimg.com
ggpht.com
googlevideo.com
googleusercontent.com
gvt1.com
play.google.com
accounts.google.com
googlevideo.net
facebook.com
fbcdn.net
instagram.com
cdninstagram.com
twitter.com
twimg.com
t.co
x.com
rutracker.org
rutracker.cc
rutor.info
nnmclub.to
discord.com
discord.co
discord.gg
discordapp.com
discordapp.net
discordcdn.com
discordstatus.com
discord.media
dis.gd
habr.com
medium.com
proton.me
archive.org
sourceforge.net
EOF

# Скрипт обновления hostlist -> ipset
cat > /tmp/byedpi-hosts-update.sh <<'UP'
#!/bin/bash
# ByeDPI: применить desync-обработку только к доменам из hostlist (как zapret).
set -e
SET=BYEDPI_HOSTS
LIST=/etc/byedpi-hosts.txt
[ -f "$LIST" ] || { echo "Нет hostlist: $LIST" >&2; exit 0; }
ipset create "$SET" hash:ip 2>/dev/null || true
ipset flush "$SET"
while IFS= read -r domain; do
  [ -z "$domain" ] && continue
  case "$domain" in \#*) continue ;; esac
  getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u | while read -r ip; do
    ipset add "$SET" "$ip" 2>/dev/null || true
  done
done < "$LIST"
members=$(ipset list "$SET" 2>/dev/null | grep -cE '^[0-9a-fA-F:\.]+$' || true)
echo "ByeDPI hostlist: IP в ipset $SET: $members"
exit 0
UP
sudo install -m 755 /tmp/byedpi-hosts-update.sh /usr/local/bin/byedpi-hosts-update.sh
rm -f /tmp/byedpi-hosts-update.sh

# Включение и запуск byedpi
sudo systemctl enable --now byedpi

case "$MODE" in
  --transparent)
    # Юнит обновления ipset (oneshot)
    sudo tee /etc/systemd/system/byedpi-hosts.service >/dev/null <<'EOF'
[Unit]
Description=ByeDPI hostlist -> ipset update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/byedpi-hosts-update.sh

[Install]
WantedBy=multi-user.target
EOF

    # Таймер обновления ipset (как у zapret autohostlist)
    sudo tee /etc/systemd/system/byedpi-hosts.timer >/dev/null <<'EOF'
[Unit]
Description=ByeDPI hostlist ipset refresh

[Timer]
OnBootSec=1min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Юнит правил REDIRECT: матч ТОЛЬКО по ipset BYEDPI_HOSTS
    sudo tee /etc/systemd/system/byedpi-redirect.service >/dev/null <<'EOF'
[Unit]
Description=ByeDPI transparent redirect rules (hostlist)
Wants=byedpi.service byedpi-hosts.service
After=byedpi.service byedpi-hosts.service
Before=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '\
iptables -t nat -N BYEDPI 2>/dev/null || true; \
iptables -t nat -F BYEDPI; \
iptables -t nat -A BYEDPI -d 0.0.0.0/8 -j RETURN; \
iptables -t nat -A BYEDPI -d 10.0.0.0/8 -j RETURN; \
iptables -t nat -A BYEDPI -d 172.16.0.0/12 -j RETURN; \
iptables -t nat -A BYEDPI -d 192.168.0.0/16 -j RETURN; \
iptables -t nat -A BYEDPI -d 169.254.0.0/16 -j RETURN; \
iptables -t nat -A BYEDPI -p tcp -m owner ! --uid-owner 0 -m set --match-set BYEDPI_HOSTS dst -m multiport --dports 80,443 -j REDIRECT --to-ports 14228; \
iptables -t nat -A OUTPUT -j BYEDPI'
ExecStop=/bin/sh -c 'iptables -t nat -D OUTPUT -j BYEDPI 2>/dev/null || true; iptables -t nat -F BYEDPI 2>/dev/null || true; iptables -t nat -X BYEDPI 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now byedpi-hosts.timer
    sudo systemctl restart byedpi-hosts.service
    sudo systemctl enable --now byedpi-redirect
    ;;
  *)
    # SOCKS / off: убираем transparent-правила и таймер
    sudo systemctl disable --now byedpi-redirect 2>/dev/null || true
    sudo systemctl disable --now byedpi-hosts.timer 2>/dev/null || true
    sudo systemctl stop byedpi-hosts.service 2>/dev/null || true
    ;;
esac

echo "ByeDPI успешно установлен и запущен на адресе 127.0.0.1:14228"
echo "Правило и порт можно изменить в /etc/byedpi.conf"
if [ "$enable_byedpi_socks" -eq 0 ]; then
  echo "Режим: transparent (без расширений), обрабатываются ТОЛЬКО домены из /etc/byedpi-hosts.txt"
  echo "Список доменов: /etc/byedpi-hosts.txt (правьте и: sudo systemctl restart byedpi-hosts byedpi-redirect)"
  echo "Отключить: sudo $0 --transparent-off"
else
  echo "Режим: SOCKS-прокси. Для настройки прокси браузера можно использовать расширения FoxyProxy, SmartProxy или Proxy SwitchyOmega 3"
  echo "Готовый бэкап настроек Proxy SwitchyOmega 3 для восстановления можно взять в репозитории скрипта"
  echo "Переключиться на работу без расширений (только hostlist): sudo $0 --transparent"
fi
echo "sudo systemctl restart byedpi для перезапуска"
echo "sudo systemctl start byedpi для запуска"
echo "sudo systemctl status byedpi для проверки статуса сервиса"
sudo systemctl status byedpi