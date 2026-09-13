# ByeDPI Installer and Configurator

Этот скрипт автоматически устанавливает и настраивает утилиту **ByeDPI** на дистрибутивах семейства ArchLinux.

<details>
  <summary>Ориентировочно поддерживаемые дистры, проверялось на EndeavourOS и ArchLinux</summary>

- ArcoLinux  
- Arch Linux  
- Carli  
- Alci  
- Ariser  
- EndeavourOS  
- Garuda  
- Manjaro  
- RebornOS  
- Archcraft  
- CachyOS  
- Archman  
- Biglinux  
- Artix  
- ParchLinux  
- StormOS  
- Mabox  
- ArchBang  
- Crystal Linux  
- Liya  
- Bluestar Linux  
- Calam-Arch-Installer  

_Скрипт ориентирован на скачивание из репозитория ArchLinux пакета byedpi-bin через yay и установку готовых конфигов для моего провайдера. Если репозитории ArchLinux не менялись, проблем быть не должно. Для других дистров можно форкнуть и адаптировать под свой пакетный менеджер, предварительно проверив пути установки и конфиги._

</details>

---

## 🔒 Безопасность

- Запрещает запуск от root (чтобы избежать непредвиденных проблем).  
- Проверяет, есть ли у текущего пользователя права sudo.

---

## ⚙️ Что делает скрипт

1. Проверяет наличие менеджера пакетов `yay` (AUR-хелпер) и при отсутствии — скачивает, собирает и устанавливает его.  
2. Собираетт и устанавливает пакет `byedpi-bin` через `yay`.  
3. Записывает конфигурацию ByeDPI в `/etc/byedpi.conf` с предустановленными параметрами.  
4. Включает и запускает сервис `byedpi` через systemd по адресу 127.0.0.1:14228
5. Выводит полезные инструкции и статус сервиса.

---

## 📝 Конфигурация

Файл настроек находится по пути:


/etc/byedpi.conf

В нем настроены параметры запуска ByeDPI, включая адрес для прослушивания и правила для доменов.

---

## 🚀 Как управлять сервисом

- Запуск:


sudo systemctl start byedpi

- Перезапуск (после изменения настроек):


sudo systemctl restart byedpi

- Проверка статуса:


sudo systemctl status byedpi

- Остановка:


sudo systemctl stop byedpi

---

## 🌐 Рекомендации по настройке браузера

Для настройки доменов можно использовать расширения:

- FoxyProxy  
- SmartProxy  
- Proxy SwitchyOmega 3  

> В репозитории есть готовый бэкап настроек для Proxy SwitchyOmega 3 с набором доменов для восстановления средствами расширения.

Набор доменов покрывает страницы, плеер и превью YouTube:
`*.youtube.com`, `*.googlevideo.com` (видео), `*.ytimg.com` / `i.ytimg.com`
(превью и картинки), `yt3.ggpht.com` / `*.ggpht.com` / `yt3.googleusercontent.com`
(аватары), а также rutracker, instagram, discord и др.

---

## ⚠️ Важно

Не запускайте скрипт от root, используйте обычного пользователя с sudo. Если у вас нет прав sudo — скрипт остановит выполнение.

---
### Автоматическая установка

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh | sh
```

По умолчанию скрипт работает как SOCKS-прокси (нужны расширения в браузере).

---

## 🌐 Работа без расширений (transparent-режим)

ByeDPI умеет работать прозрачно для всей системы — без FoxyProxy/SwitchyOmega.
Обработке подлежат **только домены из hostlist** (как работает zapret), весь
остальной трафик идёт напрямую, не через прокси.

```bash
sh <(curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh) --transparent
```

Что при этом происходит:
- В конфиг добавляется флаг `-E` (transparent). Демон читает настоящий адрес назначения через `SO_ORIGINAL_DST` и обрабатывает его без SOCKS-рукопожатия.
- Домены из `/etc/byedpi-hosts.txt` резолвятся в IP-адреса и складываются в ipset `BYEDPI_HOSTS`.
- Создаётся systemd-юнит `byedpi-redirect.service`: `iptables -t nat` правило `REDIRECT` матчит ТОЛЬКО пакеты, чей адрес назначения есть в ipset `BYEDPI_HOSTS` (порты 80/443, TCP), и заворачивает их в 127.0.0.1:14228.
- Хосты вне списка проходят мимо — без изменения.
- Собственный трафик пакетов демона (`--uid-owner ! 0`) и локальные подсети исключены из перенаправления.
- Таймер `byedpi-hosts.timer` обновляет ipset каждый час (`byedpi-hosts.service`).
- Правила переживают перезагрузку.

Управление списком доменов:

```bash
sudo nano /etc/byedpi-hosts.txt
sudo systemctl restart byedpi-hosts byedpi-redirect
```

Отключить и вернуть SOCKS-режим:

```bash
sh <(curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh) --transparent-off
```

> ⚠️ Transparent-режим перенаправляет только TCP. UDP (например, QUIC от YouTube)
> не обрабатывается — при необходимости отключите QUIC в браузере
> (`chrome://flags/#enable-quic` → Disabled), чтобы видео шло по TCP 443.
