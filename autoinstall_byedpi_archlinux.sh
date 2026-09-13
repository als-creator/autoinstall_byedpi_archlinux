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

case "$MODE" in
  --socks)
    echo 'BYEDPI_OPTIONS="-i 127.0.0.1 --port 14228 -Kt,h -s0 -o1 -Ar -o1 -At -f-1 --md5sig -r1+s -As,n -Ku -a5 -An"' \
      | sudo tee /etc/byedpi.conf > /dev/null
    enable_byedpi_socks=1
    ;;
  --transparent)
    # Прозрачный режим: без браузерных расширений.
    # Демон слушает локальный порт и читает настоящий адрес назначения
    # через SO_ORIGINAL_DST, а исходящий 80/443 разворачивается в него
    # правилом NAT (цепочка BYEDPI в OUTPUT).
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

# Включение и запуск byedpi
sudo systemctl enable --now byedpi

if [ "$enable_byedpi_socks" -eq 1 ]; then
  # Убираем transparent-правила, если были включены ранее
  sudo systemctl disable --now byedpi-redirect 2>/dev/null || true
fi

# Прозрачный режим: пишем systemd-юнит с правилами NAT
if [ "$enable_byedpi_socks" -eq 0 ]; then
  sudo tee /etc/systemd/system/byedpi-redirect.service > /dev/null <<'EOF'
[Unit]
Description=ByeDPI transparent redirect rules
Wants=byedpi.service
After=byedpi.service
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
iptables -t nat -A BYEDPI -p tcp -m owner ! --uid-owner 0 -m multiport --dports 80,443 -j REDIRECT --to-ports 14228; \
iptables -t nat -A OUTPUT -j BYEDPI'
ExecStop=/bin/sh -c 'iptables -t nat -D OUTPUT -j BYEDPI 2>/dev/null || true; iptables -t nat -F BYEDPI 2>/dev/null || true; iptables -t nat -X BYEDPI 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now byedpi-redirect
fi

echo "ByeDPI успешно установлен и запущен на адресе 127.0.0.1:14228"
echo "Правило и порт можно изменить в /etc/byedpi.conf"
if [ "$enable_byedpi_socks" -eq 0 ]; then
  echo "Режим: transparent (без расширений). Трафик 80/443 перенаправляется правилом byedpi-redirect."
  echo "Отключить: sudo $0 --transparent-off"
else
  echo "Режим: SOCKS-прокси. Для настройки прокси браузера можно использовать расширения FoxyProxy, SmartProxy или Proxy SwitchyOmega 3"
  echo "Готовый бэкап настроек Proxy SwitchyOmega 3 для восстановления можно взять в репозитории скрипта"
  echo "Переключиться на работу без расширений: sudo $0 --transparent"
fi
echo "sudo systemctl restart byedpi для перезапуска"
echo "sudo systemctl start byedpi для запуска"
echo "sudo systemctl status byedpi для проверки статуса сервиса"
sudo systemctl status byedpi