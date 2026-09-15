# ByeDPI Installer and Configurator

Автоматический установщик и конфигуратор **ByeDPI** для дистрибутивов семейства
ArchLinux (проверялось на EndeavourOS и Arch Linux).

---

## Универсальный установщик (любой дистрибутив)

В репозитории есть `install_byedpi_generic.sh` — дистрибутивно-независимая
версия: не требует пакетного менеджера, скачивает готовый бинарник `ciadpi`
с GitHub (hufrea/byedpi releases) с автоопределением архитектуры. Те же
раздельные файлы `/etc/byedpi/{conf,rule,port,hosts}` + launcher и тот же
автотест стратегий. Права root получает автоматически (root → sudo → su),
поэтому подходит и для систем без sudo (например, ALT Linux).

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/install_byedpi_generic.sh -o /tmp/byedpi-generic.sh && sh /tmp/byedpi-generic.sh --ipset
```

---

## Описание сервиса

**ByeDPI** — локальный прокси-демон, который «разжимает» ответы по протоколам DPI
(Deep Packet Inspection) провайдера. Он не подменяет DNS и не маскирует трафик
полностью, а лишь корректирует способ отправки запросов so, чтобы блокирующая
сторона не могла по характерным признакам отличить реальный трафик и зарезать его.

Как это применяется на практике:

- YouTube / rutracker / instagram и прочие заблокированные домены продолжают
  работать без VPN.
- Весь остальной трафик идёт мимо ByeDPI и не затрагивается.

### Что делает скрипт

1. Проверяет наличие AUR-хелпера `yay`; если его нет — скачивает, собирает и
   устанавливает.
2. Устанавливает пакет `byedpi-bin` через `yay`.
3. Пишет конфигурацию ByeDPI отдельными файлами: `/etc/byedpi/port`,
   `/etc/byedpi/rule`, `/etc/byedpi/hosts` и управляющий `/etc/byedpi/conf`
   с переменными-указателями на эти файлы (для user-режима — в `~/.config/byedpi/`).
4. При первой установке **сам подбирает стратегию**: прогоняет список доменов
   через несколько кандидатов правил desync и записывает лучшее в `rule`
   (пересборка — командой `--test`).
5. Создаёт systemd-сервисы: сам демон, а для ipset-режима ещё и правила
   перенаправления (демон запускается через `byedpi-start`, который собирает
   опции ciadpi из этих файлов при каждом старте).
6. Включает автозапуск и выводит статус.

Демон слушает на `127.0.0.1:<порт>` (по умолчанию `14228`).

---

## Установка

> **Важно:** скрипт работает на POSIX sh (`sh`) — совместим с bash, dash, ash, zsh.
> Подстановка `<(...)` (process substitution) — это bash/zsh-фича, которая **не
> работает в POSIX sh/dash**. Поэтому правильный способ запуска — скачать и
> исполнить:

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh
```

Скрипт спрашивает два вопроса, а можно сразу задать их флагами (тогда ввод не нужен):

1. Куда установить — `--system` или `--user`.
2. Как использовать — `--ipset` или `--extension`.

С флагами:

Для всех пользователей, с SOCKS-прокси для расширения браузера:

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh --system --extension
```

Для всех пользователей, без расширений (только домены из hostlist):

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh --system --ipset
```

Только для текущего пользователя, без расширений:

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh --user --ipset
```

Старые короткие флаги работают как раньше: `--transparent` = `--system --ipset`,
`--socks` = `--system --extension`, `--transparent-off` = `--off`.

Запускайте скрипт обычным пользователем с правами sudo, не от root.

---

## Удаление и управление

### Статус

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-status.sh && sh /tmp/byedpi-status.sh --status
```

### Удаление (полное отключение)

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-off.sh && sh /tmp/byedpi-off.sh --off
```

`--off` останавливает и удаляет сервисы, таймеры, правила iptables/ipset и
конфиг-каталог `/etc/byedpi` (`~/.config/byedpi` для user) для установленных
ранее режимов (и system, и user), а также зачищает следы старых версий
установщика (`/etc/byedpi.conf`, `/etc/byedpi-hosts.txt`).

### Сервис вручную

```bash
sudo systemctl start byedpi
```

```bash
sudo systemctl restart byedpi
```

```bash
sudo systemctl status byedpi
```

```bash
sudo systemctl stop byedpi
```

В user-режиме — те же команды, но для systemd-user без sudo:

```bash
systemctl --user restart byedpi
```

---

## Режимы установки

### system (для всех пользователей)

- конфиг-каталог: `/etc/byedpi/` — `conf`, `rule`, `port`, `hosts`
- демон: systemd-сервис `byedpi.service` (`ExecStart=/usr/local/bin/byedpi-start`)
- порт: `14228`

### user (только для текущего пользователя)

- конфиг-каталог: `~/.config/byedpi/` — `conf`, `rule`, `port`, `hosts`
- демон: systemd-**user**-сервис `byedpi.service` (запускается при входе)
- порт: `14228 + (uid - 1000)`, чтобы у разных пользователей порты не пересекались

В ipset-режиме всё работает под root: демон `byedpi-<uid>.service` и правила
REDIRECT `byedpi-redirect-<uid>.service` — но трафик REDIRECT затронет только
этого пользователя (`--uid-owner`), а hostlist и конфиг остаются в `~/.config`.
Демон обязан быть root: иначе его собственные исходящие соединения к реальным
серверам попали бы под тот же REDIRECT и зациклились.

Каждый пользователь может запустить скрипт повторно со своими флагами
`--user ...`, не затрагивая остальных.

---

## Как использовать: ipset или extension

| | `--ipset` | `--extension` |
|---|---|---|
| Расширения браузера | не нужны | нужны (FoxyProxy / SmartProxy / SwitchyOmega 3) |
| Охват | домены из hostlist (фильтр по SNI) | только то, что настроено в расширении |
| Root | нужен (правила в ядре) | не нужен |
| UDP/QUIC | не обрабатывается | не обрабатывается |

### ipset — работа без расширений

Правило `iptables -t nat` `REDIRECT` (порты 80/443, TCP) заворачивает **весь**
исходящий трафик в локальный порт ByeDPI. Дальше ByeDPI смотрит на SNI
(домен) в TLS-запросе и десинхронизирует только те соединения, чей домен есть
в hostlist — ровно так, как это делает расширение в SOCKS-режиме. Это надёжно
работает и для CDN-доменов (googlevideo и пр.), у которых тысячи IP: фильтр
идёт по домену, а не по IP, поэтому ipset и таймер обновления не нужны.
Остальной трафик просто проходит без обработки.

### extension — SOCKS-прокси для расширения

ByeDPI поднимает SOCKS-прокси на `127.0.0.1:<порт>`. Настройте прокси-расширение
на этот адрес и импортируйте список доменов. В репозитории есть готовый бэкап
настроек для SwitchyOmega с набором доменов для восстановления средствами
расширения.

---

## Как изменить настройки

Порт, правило desync и список доменов лежат в **отдельных файлах** —
менять можно каждый по отдельности, не трогая остальные:

| Что настраиваем | system | user |
|---|---|---|
| список доменов | `/etc/byedpi/hosts` | `~/.config/byedpi/hosts` |
| стратегия desync | `/etc/byedpi/rule` | `~/.config/byedpi/rule` |
| порт | `/etc/byedpi/port` | `~/.config/byedpi/port` |
| управляющий конфиг | `/etc/byedpi/conf` | `~/.config/byedpi/conf` |

`conf` — это управляющий файл с **переменными-указателями** на `rule`/`port`/
`hosts`. Демон запускается через launcher `byedpi-start`, который при каждом
старте читает эти файлы и собирает опции ciadpi — поэтому правки вступают в
силу простым перезапуском сервиса, без переустановки.

### Изменить список доменов (ipset-режим)

```bash
sudo nano /etc/byedpi/hosts
```

```bash
sudo systemctl restart byedpi
```

Для user-режима:

```bash
nano ~/.config/byedpi/hosts
```

```bash
systemctl --user restart byedpi        # user + extension
sudo systemctl restart byedpi-<uid>    # user + ipset
```

### Изменить порт

```bash
sudo nano /etc/byedpi/port             # вписать число, например 14229
sudo systemctl restart byedpi
```

Перезапустите также правила перенаправления в ipset-режиме:

```bash
sudo systemctl restart byedpi-redirect
```

### extension-режим

Список доменов хранится в расширении браузера. Правьте его через интерфейс
расширения или восстановите готовый бэкап из репозитория.

### Смена стратегии desync (автоподбор)

Правило desync лежит в файле `rule` — одной строкой. Готовые варианты можно
взять из файла `Стратегии byedpi.txt` в репозитории:

```bash
sudo nano /etc/byedpi/rule
sudo systemctl restart byedpi
```

**Автоподбор:** при первой установке (и по команде `--test`) скрипт прогоняет
список доменов через несколько кандидатов правил и записывает в `rule` то,
которое открывает больше всего ресурсов из списка:

```bash
sh /tmp/byedpi-install.sh --test
```

Пропустить автоподбор при установке можно флагом `--no-test`.

- `-s0 -o1` — отключение шифрования и отправка первой части (4 байта) сразу;
- `-Ar ... -At` — группы повторения при сбросе/таймауте;
- `-f-1 --md5sig` — отправка заведомо лишней части с MD5-подписью;
- `-r1+s` — повтор первой части с задержкой;
- `-As,n` — группа повторения с беспорядочной отправкой;
- `-Ku -a5` — отключение UDP и задержка повторов 5 мс;
- `-An` — отсутствие активной группы по умолчанию.

### Отключение YouTube через QUIC

Если YouTube грузится, но видео не воспроизводится — отключите QUIC
(`chrome://flags/#enable-quic`), т.к. прозрачный режим перенаправляет только TCP.

---

## Рекомендации по настройке браузера

Для extension-режима используются расширения-переключатели прокси:

- FoxyProxy
- SmartProxy
- Proxy SwitchyOmega 3

Готовый бэкап настроек SwitchyOmega лежит в репозитории. Набор доменов покрывает
страницы, плеер и превью YouTube: `*.youtube.com`, `*.googlevideo.com` (видео),
`*.ytimg.com` / `i.ytimg.com` (превью и картинки), `yt3.ggpht.com` /
`*.ggpht.com` / `yt3.googleusercontent.com` (аватары), а также rutracker,
instagram, discord и др.

---

## Ограничения transparent-режима

Transparent-режим (ipset) перенаправляет только TCP. UDP (например, QUIC от
YouTube) не обрабатывается — при необходимости отключите QUIC в браузере
(`chrome://flags/#enable-quic` → Disabled), чтобы видео шло по TCP 443.

---

## Безопасность

- Запрещает запуск от root.
- Проверяет наличие прав sudo у текущего пользователя.
- В ipset-режиме отсекает служебные подсети (локальные адреса) от
  перенаправления, чтобы не заворачивать собственный трафик.

---

## Поддерживаемые дистрибутивы

Ориентировочно, проверялось на EndeavourOS и Arch Linux:

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

Скрипт ориентирован на установку пакета `byedpi-bin` из AUR через `yay` и готовые
конфиги. Если репозитории ArchLinux не менялись, проблем быть не должно. Для
других дистрибутивов можно форкнуть и адаптировать под свой пакетный менеджер,
предварительно проверив пути установки и конфигов.
