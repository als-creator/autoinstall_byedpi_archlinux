#!/bin/sh
#
# ByeDPI installer (ArchLinux/EndeavourOS)
#
# Способы применения:
#
#   Режим системы (--system):
#     конфиг  -> /etc/byedpi.conf, hostlist -> /etc/byedpi-hosts.txt
#     демон   -> systemd system unit byedpi.service
#
#   Режим пользователя (--user):
#     конфиг  -> ~/.config/byedpi.conf, hostlist -> ~/.config/byedpi-hosts.txt
#     демон   -> systemd USER unit byedpi.service (запускается при входе)
#     порт    -> свой на каждого пользователя (14228 + uid - 1000)
#
#   Метод ipset (--ipset):
#     без браузерных расширений. iptables REDIRECT заворачивает ВЕСЬ TCP 80/443
#     в ByeDPI, а демон фильтрует домены по SNI (--hosts) — работает и для CDN
#     (googlevideo), у которых тысячи IP. В режиме пользователя правило
#     привязано к --uid-owner, поэтому затрагивает трафик ТОЛЬКО этого
#     пользователя; сам hostlist и конфиг остаются в ~/.config.
#
#   Метод extension (--extension):
#     SOCKS-прокси 127.0.0.1:PORT, конфигурируется в браузерном расширении
#     (FoxyProxy / SmartProxy / Proxy SwitchyOmega 3). Root не нужен.
#
# Скрипт написан на POSIX sh (работает в bash, dash, ash, zsh).
# Двоичные опции ByeDPI: опции, перечисленные В ПРЕДЕЛАХ одной
# группы --auto, применяются только при срабатывании триггера этой группы.
# Поэтому активная стратегия (fake/disorder/oob) ставится ДО первого --auto.
#
set -u

usage(){
  cat <<EOF
Использование: $0 [--system|--user] [--ipset|--extension] [--off|--status] [--port N]
  --system        установить для всех пользователей (конфиг /etc/byedpi.conf)
  --user          установить только для текущего пользователя
  --ipset         метод ipset: только домены из hostlist, без расширений
  --extension     метод extension: SOCKS-прокси для браузерного расширения
  --off | --remove  отключить, удалить сервисы, правила и конфиги
  --status|--info   показать текущее состояние
  --port N        изменить порт
  --socks         = --system --extension (старая совместимость)
  --transparent   = --system --ipset (старая совместимость)
  --transparent-off = --off
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Логирование (стиль autoinstall_zapret)
# ---------------------------------------------------------------------------
log_ok(){  echo "[OK] $*"; }
log_warn(){ echo "[WARN] $*"; }
log_err(){ echo "[ERROR] $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Парсинг аргументов
# ---------------------------------------------------------------------------
SCOPE=""           # system | user
METHOD=""          # ipset | extension
ACTION="install"   # install | off | status
ARG_PORT=""

for a in "$@"; do
  case "$a" in
    --system)        SCOPE=system ;;
    --user)          SCOPE=user ;;
    --ipset)         METHOD=ipset ;;
    --extension)     METHOD=extension ;;
    --off|--remove)  ACTION=off ;;
    --status|--info) ACTION=status ;;
    --help|-h)       usage ;;
    --port=*)        ARG_PORT="${a#*=}" ;;
    --socks)         SCOPE=system; METHOD=extension ;;
    --transparent)   SCOPE=system; METHOD=ipset ;;
    --transparent-off) ACTION=off ;;
    *) log_err "Неизвестный аргумент: $a (см. $0 --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Проверка окружения
# ---------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  log_err "Не запускайте скрипт от root."
fi
command -v sudo >/dev/null 2>&1 || log_err "sudo не установлен"

if [ "$ACTION" = "install" ]; then
  if [ -z "$SCOPE" ] && [ -t 0 ]; then
    echo "=== Куда установить? ==="
    echo "  1) Система (все пользователи)"
    echo "  2) Только для текущего пользователя"
    printf "Выбор (1/2): "; read -r c
    [ "$c" = "2" ] && SCOPE=user || SCOPE=system
  fi
  [ -z "$SCOPE" ] && SCOPE=system
  if [ -z "$METHOD" ] && [ -t 0 ]; then
    echo "=== Как использовать? ==="
    echo "  1) ipset — без расширений, весь трафик через ByeDPI (фильтр по SNI)"
    echo "  2) extension — расширение в браузере (SOCKS)"
    printf "Выбор (1/2): "; read -r c
    [ "$c" = "1" ] && METHOD=ipset || METHOD=extension
  fi
  [ -z "$METHOD" ] && METHOD=extension
fi

UID_NUM=$(id -u)

# ---------------------------------------------------------------------------
# Пакеты
# ---------------------------------------------------------------------------
install_packages(){
  if ! command -v yay >/dev/null 2>&1; then
    log_warn "yay не найден — собираю из AUR..."
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
    cd "$tmpdir/yay" || log_err "Не удалось зайти в $tmpdir/yay"
    makepkg -si --noconfirm
    cd /tmp
  fi
  if ! pacman -Q byedpi-bin >/dev/null 2>&1; then
    log_ok "Устанавливаю byedpi-bin через yay..."
    yay -Sy --noconfirm byedpi-bin
  fi
}

# ---------------------------------------------------------------------------
# Значения по режиму
# ---------------------------------------------------------------------------
if [ "$SCOPE" = "user" ]; then
  CFG="$HOME/.config/byedpi.conf"
  HOSTS="$HOME/.config/byedpi-hosts.txt"
  IHOSTS="BYEDPI_$UID_NUM"                         # цепочка iptables на пользователя
  PORT=$(( 14228 + UID_NUM - 1000 ))
  [ -n "$ARG_PORT" ] && PORT="$ARG_PORT"
else
  CFG="/etc/byedpi.conf"
  HOSTS="/etc/byedpi-hosts.txt"
  IHOSTS="BYEDPI_HOSTS"
  PORT="${ARG_PORT:-14228}"
fi

# Параметры демона (длинная стратегия desync).
# ВАЖНО: в ByeDPI опция --auto разделяет опции на группы. Опции ДО первого
# --auto применяются ВСЕГДА (активная стратегия), опции ПОСЛЕ --auto — только
# при срабатывании события (torst/ssl_err/...).
DESYNC_ACTIVE="-d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1 -As -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -S -a1"
DESYNC_FALLBACK=""

HOSTLIST_OPTIONS="-i 127.0.0.1 --port $PORT $DESYNC_ACTIVE $DESYNC_FALLBACK"
if [ "$METHOD" = "ipset" ]; then
  # Прозрачный режим: iptables REDIRECT заворачивает весь TCP в ByeDPI,
  # а ciadpi сам решает по SNI (--hosts), какие домены десинхронизировать.
  # Так работают и CDN-домены (googlevideo): фильтр по домену, не по IP.
  HOSTLIST_OPTIONS="-E -H $HOSTS $HOSTLIST_OPTIONS"
fi

# ---------------------------------------------------------------------------
# systemctl-обёртка (POSIX: массив не используем)
# ---------------------------------------------------------------------------
sctl(){
  if [ "$SCOPE" = "user" ]; then
    systemctl --user "$@"
  else
    sudo systemctl "$@"
  fi
}

# ---------------------------------------------------------------------------
# off / status
# ---------------------------------------------------------------------------
cmd_status(){
  echo "=== ByeDPI: статус ==="
  # auto-detect: что реально работает?
  # 1) user+ipset: root-юнит byedpi-<uid>.service
  if [ -f "/etc/systemd/system/byedpi-$UID_NUM.service" ]; then
    echo "-- transparent (root): byedpi-$UID_NUM.service --"
    sudo systemctl --no-pager status "byedpi-$UID_NUM" 2>/dev/null | head -8 || true
    [ -f "/etc/systemd/system/byedpi-redirect-$UID_NUM.service" ] && {
      echo "-- REDIRECT: byedpi-redirect-$UID_NUM.service --"
      sudo systemctl --no-pager status "byedpi-redirect-$UID_NUM" 2>/dev/null | head -4 || true
    }
  # 2) system: byedpi.service в /etc/systemd/system
  elif [ -f /etc/systemd/system/byedpi.service ]; then
    echo "-- system: byedpi.service (override) --"
    sudo systemctl --no-pager status byedpi 2>/dev/null | head -8 || true
    [ -f /etc/systemd/system/byedpi-redirect.service ] && {
      echo "-- REDIRECT: byedpi-redirect.service --"
      sudo systemctl --no-pager status byedpi-redirect 2>/dev/null | head -4 || true
    }
  # 3) user extension: user byedpi.service
  elif [ -f "$HOME/.config/systemd/user/byedpi.service" ]; then
    echo "-- SOCKS (user): byedpi.service --"
    systemctl --user --no-pager status byedpi 2>/dev/null | head -8 || true
  else
    echo "ByeDPI НЕ установлен (ни один юнит не найден)"
  fi
  [ -f "$HOME/.config/byedpi.conf" ]    && echo "user config:   $HOME/.config/byedpi.conf"
  [ -f "$HOME/.config/byedpi-hosts.txt" ] && echo "user hostlist: $HOME/.config/byedpi-hosts.txt"
  [ -f /etc/byedpi.conf ]  && echo "system config:  /etc/byedpi.conf"
  exit 0
}

cmd_off(){
  echo "=== Отключение ByeDPI ==="
  systemctl --user disable --now byedpi.service 2>/dev/null || true
  systemctl --user disable --now byedpi-hosts.timer 2>/dev/null || true
  systemctl --user stop byedpi-hosts.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/byedpi.service"
  rm -f "$HOME/.config/systemd/user/byedpi-hosts.service"
  rm -f "$HOME/.config/systemd/user/byedpi-hosts.timer"
  systemctl --user daemon-reload 2>/dev/null || true

  for n in "byedpi-redirect" "byedpi-redirect-$UID_NUM" \
           "byedpi-hosts.timer" "byedpi-hosts-$UID_NUM.timer"; do
    sudo systemctl disable --now "$n" 2>/dev/null || true
  done
  sudo systemctl stop byedpi-hosts.service 2>/dev/null || true
  sudo systemctl stop "byedpi-hosts-$UID_NUM.service" 2>/dev/null || true
  sudo systemctl disable --now byedpi 2>/dev/null || true
  sudo systemctl disable --now "byedpi-$UID_NUM" 2>/dev/null || true

  sudo iptables -t nat -D OUTPUT -j BYEDPI 2>/dev/null || true
  sudo iptables -t nat -D OUTPUT -j BYEDPI_HOSTS 2>/dev/null || true
  sudo iptables -t nat -D OUTPUT -j "BYEDPI_$UID_NUM" 2>/dev/null || true
  sudo iptables -t nat -F BYEDPI 2>/dev/null || true
  sudo iptables -t nat -F BYEDPI_HOSTS 2>/dev/null || true
  sudo iptables -t nat -F "BYEDPI_$UID_NUM" 2>/dev/null || true
  sudo iptables -t nat -X BYEDPI 2>/dev/null || true
  sudo iptables -t nat -X BYEDPI_HOSTS 2>/dev/null || true
  sudo iptables -t nat -X "BYEDPI_$UID_NUM" 2>/dev/null || true
  sudo ipset destroy BYEDPI_HOSTS 2>/dev/null || true
  sudo ipset destroy "BYEDPI_$UID_NUM" 2>/dev/null || true
  sudo rm -f /etc/systemd/system/byedpi.service \
             /etc/systemd/system/byedpi-$UID_NUM.service \
             /etc/systemd/system/byedpi-redirect.service \
             /etc/systemd/system/byedpi-redirect-$UID_NUM.service \
             /etc/systemd/system/byedpi-hosts.timer \
             /etc/systemd/system/byedpi-hosts-$UID_NUM.timer \
             /etc/systemd/system/byedpi-hosts.service \
             /etc/systemd/system/byedpi-hosts-$UID_NUM.service
  sudo systemctl daemon-reload 2>/dev/null || true
  sudo rm -f /etc/byedpi.conf /etc/byedpi-hosts.txt \
             /usr/local/bin/byedpi-hosts-update.sh \
             "/usr/local/bin/byedpi-hosts-update-$UID_NUM.sh"
  rm -f "$HOME/.config/byedpi.conf" "$HOME/.config/byedpi-hosts.txt"
  echo "ByeDPI отключён. Конфиги и hostlist удалены."
  exit 0
}

# ---------------------------------------------------------------------------
# Конфиг + hostlist
# ---------------------------------------------------------------------------
write_config(){
  mkdir -p "$HOME/.config"
  if [ "$SCOPE" = "user" ]; then
    mkdir -p "$HOME/.config/systemd/user"
    echo "BYEDPI_OPTIONS=\"$HOSTLIST_OPTIONS\"" > "$CFG"
  else
    echo "BYEDPI_OPTIONS=\"$HOSTLIST_OPTIONS\"" | sudo tee "$CFG" > /dev/null
  fi
  log_ok "Конфиг: $CFG"
}

write_hostlist(){
  if [ ! -f "$HOSTS" ]; then
    if [ "$SCOPE" = "user" ]; then
      cat > "$HOSTS" <<'EOL'
# ByeDPI hostlist — домены, к которым применяется desync.
# Список синхронизирован с расширением ZeroOmega (56 доменов).
# Формат: один домен на строку, строки с # игнорируются.
# Правка: отредактируйте и перезапустите сервисы (см. README).
cdnbunny.org
youtube.com
googlevideo.com
play.google.com
yt3.ggpht.com
youtu.be
rutor.info
rutracker.org
rutracker.cc
nnmclub.to
habr.com
instagram.com
archlinuxgui.in
sourceforge.net
scontent-hel3-1.cdninstagram.com
cdninstagram.com
ntc.party
discord.com
discord.gg
opera.com
discordapp.com
discordapp.net
discord.media
discord-attachments-uploads-prd.storage.googleapis.com
dis.gd
discord.co
discordcdn.com
discordstatus.com
proton.me
twimg.com
torproject.org
archive.org
web.archive.org
soundcloud.com
mullvad.net
roskomsvoboda.org
medium.com
hybrid-analysis.com
4pda.to
chatgpt.com
facebook.com
bbc.com
addons.opera.com
twitter.com
holod.media
news.google.com
flibusta.lib
flibusta.is
flibusta.info
linkedin.com
t.co
x.com
ytimg.com
yt3.googleusercontent.com
ggpht.com
EOL
    else
      sudo tee "$HOSTS" > /dev/null <<'EOL'
# ByeDPI hostlist — домены, к которым применяется desync.
# Список синхронизирован с расширением ZeroOmega (56 доменов).
# Формат: один домен на строку, строки с # игнорируются.
# Правка: отредактируйте и перезапустите сервисы (см. README).
cdnbunny.org
youtube.com
googlevideo.com
play.google.com
yt3.ggpht.com
youtu.be
rutor.info
rutracker.org
rutracker.cc
nnmclub.to
habr.com
instagram.com
archlinuxgui.in
sourceforge.net
scontent-hel3-1.cdninstagram.com
cdninstagram.com
ntc.party
discord.com
discord.gg
opera.com
discordapp.com
discordapp.net
discord.media
discord-attachments-uploads-prd.storage.googleapis.com
dis.gd
discord.co
discordcdn.com
discordstatus.com
proton.me
twimg.com
torproject.org
archive.org
web.archive.org
soundcloud.com
mullvad.net
roskomsvoboda.org
medium.com
hybrid-analysis.com
4pda.to
chatgpt.com
facebook.com
bbc.com
addons.opera.com
twitter.com
holod.media
news.google.com
flibusta.lib
flibusta.is
flibusta.info
linkedin.com
t.co
x.com
ytimg.com
yt3.googleusercontent.com
ggpht.com
EOL
    fi
    log_ok "Создан hostlist: $HOSTS"
  else
    log_warn "Hostlist уже есть, не перезаписан: $HOSTS"
  fi
}

# ---------------------------------------------------------------------------
# systemd-юниты
# ---------------------------------------------------------------------------
write_units(){
  if [ "$SCOPE" = "user" ]; then
    # ==== user scope ====
    if [ "$METHOD" = "ipset" ]; then
      # В прозрачном режиме демон обязан работать под root: его собственные
      # исходящие соединения к реальным серверам иначе попали бы под тот же
      # REDIRECT (uid демона совпадает с uid браузера) и зациклились бы.
      systemctl --user disable --now byedpi.service 2>/dev/null || true
      rm -f "$HOME/.config/systemd/user/byedpi.service"
      systemctl --user disable --now byedpi-hosts.timer 2>/dev/null || true
      systemctl --user stop byedpi-hosts.service 2>/dev/null || true
      sudo ipset destroy "$IHOSTS" 2>/dev/null || true
      sudo tee "/etc/systemd/system/byedpi-$UID_NUM.service" >/dev/null <<EOF
[Unit]
Description=ByeDPI transparent (user $USER)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ciadpi \$BYEDPI_OPTIONS
EnvironmentFile=$HOME/.config/byedpi.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      sudo systemctl daemon-reload
      sudo systemctl enable --now "byedpi-$UID_NUM.service" >/dev/null 2>&1 || log_warn "root-демон не запустился, см. sudo journalctl -u byedpi-$UID_NUM"
      log_ok "Демон (root): /etc/systemd/system/byedpi-$UID_NUM.service"
    else
      # миграция с ipset -> extension: гасим root-юниты transparent-режима
      sudo systemctl disable --now "byedpi-$UID_NUM" 2>/dev/null || true
      sudo systemctl disable --now "byedpi-redirect-$UID_NUM" 2>/dev/null || true
      sudo rm -f "/etc/systemd/system/byedpi-$UID_NUM.service" \
                 "/etc/systemd/system/byedpi-redirect-$UID_NUM.service"
      sudo ipset destroy "$IHOSTS" 2>/dev/null || true
      cat > "$HOME/.config/systemd/user/byedpi.service" <<EOF
[Unit]
Description=ByeDPI (user $USER)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ciadpi \$BYEDPI_OPTIONS
EnvironmentFile=%h/.config/byedpi.conf
Restart=on-failure

[Install]
WantedBy=default.target
EOF
      systemctl --user daemon-reload
      systemctl --user enable --now byedpi.service >/dev/null 2>&1 || log_warn "user unit не запустился сразу (включится при входе)"
      log_ok "Юзер-сервис: ~/.config/systemd/user/byedpi.service"
    fi

    if [ "$METHOD" = "ipset" ]; then
      # ipset не нужен: REDIRECT весь TCP 80/443, ciadpi сам фильтрует домены
      # по SNI через --hosts (как расширение). Демон root по правилу
      # --uid-owner НЕ попадает под REDIRECT, поэтому зацикливания нет.
      sudo tee "/etc/systemd/system/byedpi-redirect-$UID_NUM.service" >/dev/null <<EOF
[Unit]
Description=ByeDPI REDIRECT (uid $UID_NUM)
Wants=byedpi-$UID_NUM.service
After=byedpi-$UID_NUM.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '\
iptables -t nat -N $IHOSTS 2>/dev/null || true; \
iptables -t nat -F $IHOSTS; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -d 0.0.0.0/8 -j RETURN; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -d 10.0.0.0/8 -j RETURN; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -d 172.16.0.0/12 -j RETURN; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -d 192.168.0.0/16 -j RETURN; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -d 169.254.0.0/16 -j RETURN; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports $PORT; \
iptables -t nat -A OUTPUT -j $IHOSTS'
ExecStop=/bin/sh -c 'iptables -t nat -D OUTPUT -j $IHOSTS 2>/dev/null || true; iptables -t nat -F $IHOSTS 2>/dev/null || true; iptables -t nat -X $IHOSTS 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
      sudo systemctl daemon-reload
      sudo systemctl enable --now "byedpi-redirect-$UID_NUM.service" >/dev/null 2>&1 || log_warn "Не удалось включить REDIRECT"
    fi
  else
    # ==== system scope ====
    # Свой юнит в /etc/systemd/system перекрывает пакетный /usr/lib (у него
    # нет TYPE=/etc/byedpi.conf для ipset и нет настройки --transparent).
    sudo tee /etc/systemd/system/byedpi.service >/dev/null <<EOF
[Unit]
Description=ByeDPI
Documentation=https://github.com/hufrea/byedpi
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ciadpi \$BYEDPI_OPTIONS
EnvironmentFile=/etc/byedpi.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
    sudo systemctl enable --now byedpi >/dev/null 2>&1 || log_warn "byedpi не запустился, см. sudo journalctl -u byedpi"
    if [ "$METHOD" = "ipset" ]; then
      # зачистка старых unit-ов и ipset из прежних версий установщика
      sudo systemctl disable --now byedpi-hosts.timer 2>/dev/null || true
      sudo systemctl stop byedpi-hosts.service 2>/dev/null || true
      sudo ipset destroy "$IHOSTS" 2>/dev/null || true
      sudo tee /etc/systemd/system/byedpi-redirect.service >/dev/null <<EOF
[Unit]
Description=ByeDPI transparent redirect rules (SNI через --hosts)
Wants=byedpi.service
After=byedpi.service
Before=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '\
iptables -t nat -N $IHOSTS 2>/dev/null || true; \
iptables -t nat -F $IHOSTS; \
iptables -t nat -A $IHOSTS -d 0.0.0.0/8 -j RETURN; \
iptables -t nat -A $IHOSTS -d 10.0.0.0/8 -j RETURN; \
iptables -t nat -A $IHOSTS -d 172.16.0.0/12 -j RETURN; \
iptables -t nat -A $IHOSTS -d 192.168.0.0/16 -j RETURN; \
iptables -t nat -A $IHOSTS -d 169.254.0.0/16 -j RETURN; \
iptables -t nat -A $IHOSTS -p tcp -m owner ! --uid-owner 0 -m multiport --dports 80,443 -j REDIRECT --to-ports $PORT; \
iptables -t nat -A OUTPUT -j $IHOSTS'
ExecStop=/bin/sh -c 'iptables -t nat -D OUTPUT -j $IHOSTS 2>/dev/null || true; iptables -t nat -F $IHOSTS 2>/dev/null || true; iptables -t nat -X $IHOSTS 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
      sudo systemctl daemon-reload
      sudo systemctl enable --now byedpi-redirect >/dev/null 2>&1 || log_warn "Не удалось включить REDIRECT"
    else
      # миграция с ipset -> extension: убираем transparent-правила и hostlist-юниты
      sudo systemctl disable --now byedpi-redirect 2>/dev/null || true
      sudo systemctl disable --now byedpi-hosts.timer 2>/dev/null || true
      sudo systemctl stop byedpi-hosts.service 2>/dev/null || true
      sudo rm -f /etc/systemd/system/byedpi-redirect.service \
                 /etc/systemd/system/byedpi-hosts.timer \
                 /etc/systemd/system/byedpi-hosts.service
      sudo systemctl daemon-reload 2>/dev/null || true
      sudo ipset destroy "$IHOSTS" 2>/dev/null || true
    fi
  fi
}

# ---------------------------------------------------------------------------
# Итог
# ---------------------------------------------------------------------------
show_summary(){
  echo "═══════════════════════════════════════════════════════════"
  echo "  ByeDPI: scope=$SCOPE метод=$METHOD порт=$PORT"
  echo "═══════════════════════════════════════════════════════════"
  echo "Конфиг:   $CFG"
  echo "Hostlist: $HOSTS"
  echo "Стратегия: $DESYNC_ACTIVE $DESYNC_FALLBACK"
  if [ "$METHOD" = "ipset" ]; then
    echo "Прозрачный режим: весь TCP 80/443 -> ByeDPI, дальше фильтр по SNI."
    echo "  Десинхронизируются ТОЛЬКО домены из $HOSTS (как в расширении)."
    echo "  Правка: sudo nano $HOSTS; перезапуск: sudo systemctl restart byedpi"
    [ "$SCOPE" = "user" ] && echo "  (в user-режиме юнит называется byedpi-$UID_NUM)"
  elif [ "$SCOPE" = "system" ]; then
    echo "SOCKS-прокси: 127.0.0.1:$PORT (расширения FoxyProxy/SmartProxy/SwitchyOmega 3)."
    echo "Бэкап Omega: ZeroOmegaOptions-*.bak в репозитории."
  else
    echo "SOCKS-прокси: 127.0.0.1:$PORT (только для этого пользователя)."
    echo "Настройте расширение на этот порт."
  fi
  [ "$SCOPE" = "user" ] && [ "$METHOD" = "extension" ] && echo "Автозапуск при входе включён. Для запуска без входа в сессию: sudo loginctl enable-linger $USER"
}

# ---------------------------------------------------------------------------
# Главный запуск
# ---------------------------------------------------------------------------
case "$ACTION" in
  status) cmd_status ;;
  off)    cmd_off ;;
  install)
    install_packages
    write_config
    write_hostlist
    write_units
    show_summary
    ;;
esac
