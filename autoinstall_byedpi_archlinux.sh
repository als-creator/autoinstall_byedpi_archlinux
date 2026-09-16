#!/bin/sh
#
# ByeDPI installer (ArchLinux/EndeavourOS)
#
# Установка «как положено» для Arch: пакет byedpi-bin из AUR через yay
# (ставит /usr/bin/ciadpi + /etc/byedpi-bin.conf + byedpi-bin.service).
# Пакетный unit отключается, вместо него пишется свой byedpi.service,
# который запускает launcher /usr/local/bin/byedpi-start, собирающий опции
# ciadpi из раздельных файлов конфига при каждом старте.
#
# Способы применения:
#
#   Режим системы (--system):
#     конфиг-каталог -> /etc/byedpi/  (conf, rule, port, hosts)
#     демон          -> systemd system unit byedpi.service
#
#   Режим пользователя (--user):
#     конфиг-каталог -> ~/.config/byedpi/ (conf, rule, port, hosts)
#     демон          -> systemd USER unit byedpi.service (запускается при входе)
#     порт           -> свой на каждого пользователя (14228 + uid - 1000)
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
# РАЗДЕЛЬНЫЕ ФАЙЛЫ:
#   Правило desync, порт и список доменов живут в отдельных файлах
#   (/etc/byedpi/rule, /etc/byedpi/port, /etc/byedpi/hosts), а конфиг
#   /etc/byedpi/conf указывает на них переменными. Править можно прямо
#   файлы по одному; демон запускается через /usr/local/bin/byedpi-start,
#   который собирает опции ciadpi из этих файлов при каждом старте.
#
# АВТОТЕСТ СТРАТЕГИЙ:
#   При первой установке (и по команде --test) скрипт прогоняет список доменов
#   через кандидатов правил desync и выбирает правило, открывающее больше
#   всего ресурсов из списка. Отключить: --no-test.
#
# Скрипт написан на POSIX sh (работает в bash, dash, ash, zsh).
# Двоичные опции ByeDPI: опции, перечисленные В ПРЕДЕЛАХ одной
# группы --auto, применяются только при срабатывании триггера этой группы.
# Поэтому активная стратегия (fake/disorder/oob) ставится ДО первого --auto.
#
set -u

CIADPI="${CIADPI:-/usr/bin/ciadpi}"

usage(){
  cat <<EOF
Использование: $0 [--system|--user] [--ipset|--extension] [--off|--status|--test] [--port N] [--no-test]
  --system        установить для всех пользователей (конфиг /etc/byedpi/)
  --user          установить только для текущего пользователя
  --ipset         метод ipset: весь TCP 80/443 через ByeDPI, фильтр по SNI
  --extension     метод extension: SOCKS-прокси для браузерного расширения
  --test          перезапустить автотест стратегий и обновить /etc/byedpi/rule
  --no-test       пропустить автотест стратегий при установке
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
ACTION="install"   # install | off | status | test
ARG_PORT=""
NO_TEST=""

for a in "$@"; do
  case "$a" in
    --system)        SCOPE=system ;;
    --user)          SCOPE=user ;;
    --ipset)         METHOD=ipset ;;
    --extension)     METHOD=extension ;;
    --off|--remove)  ACTION=off ;;
    --status|--info) ACTION=status ;;
    --test|--retest) ACTION=test ;;
    --no-test)       NO_TEST=1 ;;
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
# Пакеты: byedpi-bin из AUR через yay (packages/Arch)
# ---------------------------------------------------------------------------
install_packages(){
  if ! command -v yay >/dev/null 2>&1; then
    log_warn "yay не найден — собираю из AUR..."
    sudo pacman -S --needed --noconfirm base-devel git || \
      log_err "Не удалось установить base-devel/git (нужны для сборки yay)"
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
    cd "$tmpdir/yay" || log_err "Не удалось зайти в $tmpdir/yay"
    makepkg -si --noconfirm
    cd /tmp
    trap - EXIT
  fi
  if [ ! -x "$CIADPI" ]; then
    log_ok "Устанавливаю byedpi-bin из AUR через yay..."
    yay -S --noconfirm --needed byedpi-bin
  fi
  [ -x "$CIADPI" ] || log_err "ciadpi не найден: $CIADPI"
  # Пакетный шаблонный юнит byedpi-bin.service не нужен: свой byedpi.service
  # с launcher'ом и раздельными файлами конфига ставится ниже. Отключаем
  # пакетный, чтобы два демона не спорили за порт 14228.
  sudo systemctl disable --now byedpi-bin.service >/dev/null 2>&1 || true
  log_ok "Пакет byedpi-bin из AUR: $CIADPI"
}

# ---------------------------------------------------------------------------
# Пути по режиму
# ---------------------------------------------------------------------------
if [ "$SCOPE" = "user" ]; then
  DIR="$HOME/.config/byedpi"
  IHOSTS="BYEDPI_$UID_NUM"                    # цепочка iptables на пользователя
  PORT=$(( 14228 + UID_NUM - 1000 ))
  [ -n "$ARG_PORT" ] && PORT="$ARG_PORT"
else
  DIR="/etc/byedpi"
  IHOSTS="BYEDPI_HOSTS"
  PORT="${ARG_PORT:-14228}"
fi
CFG="$DIR/conf"
PORT_FILE="$DIR/port"
RULE_FILE="$DIR/rule"
HOSTS_FILE="$DIR/hosts"
LAUNCHER="/usr/local/bin/byedpi-start"

# Параметры демона (длинная стратегия desync). Используется, если файла
# rule ещё нет (первая установка) или автотест не нашёл лучшего правила.
# ВАЖНО: в ByeDPI опция --auto разделяет опции на группы. Опции ДО первого
# --auto применяются ВСЕГДА (активная стратегия), опции ПОСЛЕ --auto — только
# при срабатывании события (torst/ssl_err/...).
DESYNC_ACTIVE="-d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1 -As -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -S -a1"
DESYNC_FALLBACK=""
RULE="$DESYNC_ACTIVE $DESYNC_FALLBACK"

# ---------------------------------------------------------------------------
# Запись файла (с учётом необходимости sudo для system-режима)
# ---------------------------------------------------------------------------
wfile(){ # путь, содержимое
  if [ "$SCOPE" = "user" ]; then
    mkdir -p "$(dirname "$1")"
    printf '%s\n' "$2" > "$1"
  else
    sudo mkdir -p "$(dirname "$1")"
    printf '%s\n' "$2" | sudo tee "$1" > /dev/null
  fi
}

# ---------------------------------------------------------------------------
# Автотест стратегий: какое правило открывает больше ресурсов из hostlist
# ---------------------------------------------------------------------------
TEST_PROBES="i.ytimg.com pbs.twimg.com yt3.ggpht.com www.youtube.com discord.com rutracker.org x.com www.instagram.com"

# Кандидаты <имя>|<правило> (строки через \n). Первый — текущая длинная
# стратегия; остальные — короткие стратегии для ТСПУ (проверенные в бою).
TEST_RULES="\
long-strategy|-d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1 -As -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -S -a1
tlsrec-disorder|-Kt,h --tlsrec 1+s --disorder 1 --auto=torst --timeout 3
fake-found|-Kt,h --fake -1 --md5sig --auto=torst --timeout 3
disorder-1|-Kt,h --disorder 1 --auto=torst --timeout 3
split-1|-Kt,h --split 1+s --disorder 3+s --auto=torst --timeout 3
tlsrec-3|-Kt,h --tlsrec 3+s --auto=torst --timeout 3
base-long|-Kt,h -s0 -o1 -Ar -o1 -At -f-1 --md5sig -r1+s -As,n -Ku -a5 -An"

test_strategies(){ # hostlist-файл -> on stdout лучшее правило; прогресс в stderr
    hosts="$1"
    [ -f "$hosts" ] || log_err "Нет hostlist: $hosts"
    command -v curl >/dev/null 2>&1 || log_err "Для автотеста нужно curl"
    [ -x "$CIADPI" ] || log_err "Нет ciadpi: $CIADPI"

    tport=$(( 14600 + ($$ % 250) ))
    resfile="/tmp/byedpi-test-$$.res"
    pdir="/tmp/byedpi-probes-$$"
    mkdir -p "$pdir"
    > "$resfile"

    echo "=== Автотест стратегий desync ===" >&2
    echo "Пробы: $TEST_PROBES" >&2
    printf '%b\n' "$TEST_RULES" | while IFS='|' read -r name rule; do
      [ -n "$rule" ] || continue
      "$CIADPI" -H "$hosts" -i 127.0.0.1 --port "$tport" $rule >/dev/null 2>&1 &
      cpid=$!
      sleep 0.6
      i=0
      curls=""
      for h in $TEST_PROBES; do
        i=$((i+1))
        ( code=$(curl -k -sS -m 4 --socks5-hostname 127.0.0.1:"$tport" -o /dev/null -w "%{http_code}" "https://$h/" 2>/dev/null)
          echo "$code" > "$pdir/$i" ) &
        curls="$curls $!"
      done
      wait $curls
      kill "$cpid" 2>/dev/null
      wait "$cpid" 2>/dev/null
      ok=0; total=0
      for f in "$pdir"/*; do
        [ -f "$f" ] || continue
        total=$((total+1))
        code=$(cat "$f")
        if [ -n "$code" ] && [ "$code" != "000" ]; then ok=$((ok+1)); fi
      done
      echo "  [$name] $rule  →  открылось $ok из $total" >&2
      echo "$name|$ok|$total|$rule" >> "$resfile"
    done
    rm -rf "$pdir"

    best=""; bname=""; bscore=-1; btotal=0
    while IFS='|' read -r name score total rule; do
      if [ "${score:-0}" -gt "$bscore" ]; then
        bscore=$score; btotal=$total; bname=$name; best=$rule
      fi
    done < "$resfile"
    rm -f "$resfile"

    if [ -z "$best" ]; then
      log_warn "Ни одно правило не открыло ни одного домена (проверьте сеть/DNS)." >&2
      echo "$DESYNC_ACTIVE $DESYNC_FALLBACK"
      return 0
    fi
    echo "=== Лучшая стратегия: [$bname] → открылось $bscore из $btotal ===" >&2
    echo "$best"
}

# ---------------------------------------------------------------------------
# Выбор scope и перезапуск демона (для --test)
# ---------------------------------------------------------------------------
detect_scope(){
  if [ -f /etc/byedpi/conf ]; then SCOPE=system
  elif [ -f "$HOME/.config/byedpi/conf" ]; then SCOPE=user
  else log_err "ByeDPI не установлен (нет ни /etc/byedpi/conf, ни ~/.config/byedpi/conf)."
  fi
}

restart_daemon(){
  if [ -f "/etc/systemd/system/byedpi-$UID_NUM.service" ]; then
    sudo systemctl restart "byedpi-$UID_NUM" || log_warn "см. sudo journalctl -u byedpi-$UID_NUM"
  elif [ -f /etc/systemd/system/byedpi.service ]; then
    sudo systemctl restart byedpi || log_warn "см. sudo journalctl -u byedpi"
  elif [ -f "$HOME/.config/systemd/user/byedpi.service" ]; then
    systemctl --user restart byedpi || log_warn "см. journalctl --user -u byedpi"
  fi
  log_ok "Демон перезапущен."
}

# ---------------------------------------------------------------------------
# off / status / test
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
  [ -f "$HOME/.config/byedpi/conf" ]    && { echo "user config:   ~/.config/byedpi/conf";   [ -f "$HOME/.config/byedpi/rule" ] && echo "user rule:     $(cat "$HOME/.config/byedpi/rule")";   [ -f "$HOME/.config/byedpi/port" ] && echo "user port:     $(cat "$HOME/.config/byedpi/port")"; }
  [ -f /etc/byedpi/conf ]               && { echo "system config: /etc/byedpi/conf";        [ -f /etc/byedpi/rule ] && echo "system rule:   $(cat /etc/byedpi/rule)";          [ -f /etc/byedpi/port ] && echo "system port:   $(cat /etc/byedpi/port)"; }
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

  # пакетный юнит byedpi-bin.service (из AUR-пакета) тоже отключаем
  sudo systemctl disable --now byedpi-bin.service 2>/dev/null || true

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
  sudo rm -rf /etc/byedpi /usr/local/bin/byedpi-start
  rm -rf "$HOME/.config/byedpi"
  sudo rm -f /etc/byedpi.conf /etc/byedpi-hosts.txt \
             /usr/local/bin/byedpi-hosts-update.sh \
             "/usr/local/bin/byedpi-hosts-update-$UID_NUM.sh"
  rm -f "$HOME/.config/byedpi.conf" "$HOME/.config/byedpi-hosts.txt"
  echo "ByeDPI отключён. Конфиги и hostlist удалены."
  exit 0
}

cmd_test(){
  detect_scope
  if [ "$SCOPE" = "user" ]; then
    DIR="$HOME/.config/byedpi"; HOSTS_FILE="$DIR/hosts"; RULE_FILE="$DIR/rule"
  else
    DIR=/etc/byedpi; HOSTS_FILE="$DIR/hosts"; RULE_FILE="$DIR/rule"
  fi
  [ -f "$HOSTS_FILE" ] || log_err "Нет hostlist: $HOSTS_FILE (сначала установите ByeDPI)."
  best=$(test_strategies "$HOSTS_FILE")
  wfile "$RULE_FILE" "$best"
  log_ok "Правило записано: $RULE_FILE"
  restart_daemon
}

# ---------------------------------------------------------------------------
# Конфиг + файлы (port / hosts / rule / conf)
# ---------------------------------------------------------------------------
# Перенос значений из старого конфига (один большой BYEDPI_OPTIONS) в новый
# формат с раздельными файлами, если новый каталог ещё пуст. Учитываются и
# старый конфиг установщика /etc/byedpi.conf, и конфиг пакета byedpi-bin
# (тоже BYEDPI_OPTIONS="...", ставится пакетом в /etc/byedpi-bin.conf).
migrate_old_conf(){
  old=/etc/byedpi.conf
  [ "$SCOPE" = "user" ] && old="$HOME/.config/byedpi.conf"
  if [ ! -f "$old" ] && [ -f /etc/byedpi-bin.conf ] && [ "$SCOPE" = "system" ]; then
    old=/etc/byedpi-bin.conf
  fi
  [ -f "$old" ] && [ ! -f "$RULE_FILE" ] || return 0
  OP=$(grep '^BYEDPI_OPTIONS=' "$old" | head -1 | cut -d'=' -f2- | tr -d '"')
  [ -n "$OP" ] || return 0
  p=$(printf '%s' "$OP" | sed -n 's/.*--port \([0-9][0-9]*\).*/\1/p')
  [ -n "$p" ] && { PORT="$p"; [ -z "$ARG_PORT" ] || PORT="$ARG_PORT"; }
  r=$(printf '%s' "$OP" | sed -e 's#^-E -H [^ ]* ##' -e 's#^-i 127.0.0.1 --port [0-9][0-9]* ##')
  [ -n "$r" ] && RULE="$r"
  log_ok "Перенёс настройки из старого конфига: $old"
}

write_port(){
  if [ -f "$PORT_FILE" ]; then
    if [ -n "$ARG_PORT" ]; then
      wfile "$PORT_FILE" "$PORT"
      log_warn "Порт обновлён: $PORT_FILE → $PORT"
    else
      PORT=$(grep -E '^[0-9]+$' "$PORT_FILE" | head -1)
      [ -z "$PORT" ] && { PORT=14228; wfile "$PORT_FILE" "$PORT"; }
      log_ok "Порт (из файла): $PORT"
    fi
  else
    wfile "$PORT_FILE" "$PORT"
    log_ok "Порт: $PORT_FILE → $PORT"
  fi
}

write_hostlist(){
  if [ ! -f "$HOSTS_FILE" ]; then
    if [ "$SCOPE" = "user" ]; then
      cat > "$HOSTS_FILE" <<'EOL'
# ByeDPI hostlist — домены, к которым применяется desync.
# Список синхронизирован с расширением ZeroOmega (55 доменов).
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
      sudo mkdir -p "$DIR"
      sudo tee "$HOSTS_FILE" > /dev/null <<'EOL'
# ByeDPI hostlist — домены, к которым применяется desync.
# Список синхронизирован с расширением ZeroOmega (55 доменов).
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
    log_ok "Создан hostlist: $HOSTS_FILE"
  else
    log_warn "Hostlist уже есть, не перезаписан: $HOSTS_FILE"
    grep -cE '^[a-z0-9]+' "$HOSTS_FILE" 2>/dev/null | xargs -r echo "  доменов в списке:"
  fi
}

write_rule(){
  # Если правило уже есть — не трогаем (его мог настроить пользователь);
  # пересобрать можно командой --test.
  if [ -f "$RULE_FILE" ]; then
    log_ok "Правило уже есть, не перезаписано: $RULE_FILE"
    return 0
  fi
  if [ -z "$NO_TEST" ]; then
    best=$(test_strategies "$HOSTS_FILE")
    [ -n "$best" ] && RULE="$best"
  fi
  wfile "$RULE_FILE" "$RULE"
  log_ok "Правило desync: $RULE_FILE"
}

write_conf(){
  if [ "$METHOD" = "ipset" ]; then MODE=transparent; else MODE=socks; fi
  if [ -f "$CFG" ] && grep -Fq "BYEDPI_MODE=\"$MODE\"" "$CFG"; then
    log_ok "Конфиг уже есть, не перезаписан: $CFG"
    return 0
  fi
  cat > /tmp/byedpi-conf.$$ <<EOF
# ByeDPI — управляющий конфиг.
# Порт, правило desync и список доменов лежат в отдельных файлах,
# на которые указывают переменные ниже. Править можно прямо эти
# файлы, после чего перезапустить сервис (см. --status).
BYEDPI_MODE="$MODE"
BYEDPI_BIND="127.0.0.1"
BYEDPI_PORT_FILE="$PORT_FILE"
BYEDPI_RULE_FILE="$RULE_FILE"
BYEDPI_HOSTS_FILE="$HOSTS_FILE"
EOF
  wfile "$CFG" "$(cat /tmp/byedpi-conf.$$)"
  rm -f /tmp/byedpi-conf.$$
  log_ok "Конфиг: $CFG"
}

write_launcher(){
  sudo tee "$LAUNCHER" > /dev/null <<'EOF'
#!/bin/sh
# ByeDPI launcher: собирает опции ciadpi из отдельных файлов конфига.
# Использование: byedpi-start [путь/conf]   (по умолчанию /etc/byedpi/conf)
set -u
CFG="${1:-/etc/byedpi/conf}"
[ -f "$CFG" ] || { echo "byedpi-start: нет конфига $CFG" >&2; exit 1; }
. "$CFG"

for v in BYEDPI_PORT_FILE BYEDPI_RULE_FILE BYEDPI_HOSTS_FILE; do
  eval "f=\${$v:-}"
  [ -n "$f" ] || { echo "byedpi-start: в $CFG не задано $v" >&2; exit 1; }
  [ -r "$f" ] || { echo "byedpi-start: нет файла $v = $f" >&2; exit 1; }
done

BIND="${BYEDPI_BIND:-127.0.0.1}"
CIADPI_BIN="${BYEDPI_BIN:-}"
[ -n "$CIADPI_BIN" ] || CIADPI_BIN=$(command -v ciadpi 2>/dev/null || echo /usr/local/bin/ciadpi)
[ -x "$CIADPI_BIN" ] || { echo "byedpi-start: нет ciadpi ($CIADPI_BIN)" >&2; exit 1; }
PORT="$(cat "$BYEDPI_PORT_FILE")"
RULE="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$BYEDPI_RULE_FILE")"
case "${BYEDPI_MODE:-socks}" in
  transparent) exec "$CIADPI_BIN" -E -H "$BYEDPI_HOSTS_FILE" -i "$BIND" --port "$PORT" $RULE ;;
  socks)       exec "$CIADPI_BIN" -i "$BIND" --port "$PORT" $RULE ;;
  *) echo "byedpi-start: неизвестный BYEDPI_MODE=$BYEDPI_MODE" >&2; exit 1 ;;
esac
EOF
  sudo chmod 755 "$LAUNCHER"
  log_ok "Launcher: $LAUNCHER"
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
ExecStart=$LAUNCHER $HOME/.config/byedpi/conf
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
ExecStart=$LAUNCHER %h/.config/byedpi/conf
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
. $HOME/.config/byedpi/conf; \
P="\$(cat "\$BYEDPI_PORT_FILE")"; \
iptables -t nat -N $IHOSTS 2>/dev/null || true; \
iptables -t nat -F $IHOSTS; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -d 0.0.0.0/8 -j RETURN; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -d 10.0.0.0/8 -j RETURN; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -d 172.16.0.0/12 -j RETURN; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -d 192.168.0.0/16 -j RETURN; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -d 169.254.0.0/16 -j RETURN; \
iptables -t nat -A $IHOSTS -m owner --uid-owner $UID_NUM -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports "\$P"; \
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
    # Свой юнит /etc/systemd/system/byedpi.service запускает launcher,
    # который читает раздельные файлы rule/port/hosts через /etc/byedpi/conf.
    # Пакетный byedpi-bin.service отключён в install_packages и по
    # команде --off, чтобы не занимать тот же порт 14228.
    sudo tee /etc/systemd/system/byedpi.service >/dev/null <<EOF
[Unit]
Description=ByeDPI
Documentation=https://github.com/hufrea/byedpi
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$LAUNCHER /etc/byedpi/conf
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
. /etc/byedpi/conf; \
P="\$(cat "\$BYEDPI_PORT_FILE")"; \
iptables -t nat -N $IHOSTS 2>/dev/null || true; \
iptables -t nat -F $IHOSTS; \
iptables -t nat -A $IHOSTS -d 0.0.0.0/8 -j RETURN; \
iptables -t nat -A $IHOSTS -d 10.0.0.0/8 -j RETURN; \
iptables -t nat -A $IHOSTS -d 172.16.0.0/12 -j RETURN; \
iptables -t nat -A $IHOSTS -d 192.168.0.0/16 -j RETURN; \
iptables -t nat -A $IHOSTS -d 169.254.0.0/16 -j RETURN; \
iptables -t nat -A $IHOSTS -p tcp -m owner ! --uid-owner 0 -m multiport --dports 80,443 -j REDIRECT --to-ports "\$P"; \
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
  echo "Пакет:    byedpi-bin (AUR), бинарь $CIADPI"
  echo "Каталог:  $DIR"
  echo "Порт:     $PORT_FILE → $PORT"
  echo "Правило:  $RULE_FILE"
  echo "Hostlist: $HOSTS_FILE"
  echo "Конфиг:   $CFG"
  if [ "$METHOD" = "ipset" ]; then
    echo "Прозрачный режим: весь TCP 80/443 -> ByeDPI, дальше фильтр по SNI."
    echo "  Десинхронизируются ТОЛЬКО домены из $HOSTS_FILE (как в расширении)."
    echo "  Правка: sudo nano $HOSTS_FILE (или $RULE_FILE / $PORT_FILE);"
    echo "  перезапуск: sudo systemctl restart byedpi"
    [ "$SCOPE" = "user" ] && echo "  (в user-режиме юнит называется byedpi-$UID_NUM)"
  elif [ "$SCOPE" = "system" ]; then
    echo "SOCKS-прокси: 127.0.0.1:$PORT (расширения FoxyProxy/SmartProxy/SwitchyOmega 3)."
    echo "Бэкап Omega: ZeroOmegaOptions-*.bak в репозитории."
  else
    echo "SOCKS-прокси: 127.0.0.1:$PORT (только для этого пользователя)."
    echo "Настройте расширение на этот порт."
  fi
  if [ "$NO_TEST" != "1" ]; then
    echo "Пересборка правила: $0 --test"
  fi
  [ "$SCOPE" = "user" ] && [ "$METHOD" = "extension" ] && echo "Автозапуск при входе включён. Для запуска без входа в сессию: sudo loginctl enable-linger $USER"
}

# ---------------------------------------------------------------------------
# Главный запуск
# ---------------------------------------------------------------------------
case "$ACTION" in
  status) cmd_status ;;
  off)    cmd_off ;;
  test)   cmd_test ;;
  install)
    install_packages
    migrate_old_conf
    write_port
    write_hostlist
    write_rule
    write_conf
    write_launcher
    write_units
    show_summary
    ;;
esac