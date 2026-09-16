# ByeDPI Installer and Configurator (Arch Linux)

Автоматический установщик и конфигуратор **ByeDPI** для дистрибутивов семейства
Arch Linux (проверялось на EndeavourOS и Arch Linux). Установка выполняется
**«как положено» для Arch** — через пакет `byedpi-bin` из AUR, а не ручным
скачиванием бинарника.

Установка одной командой:

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh
```

> **Нужен универсальный установщик для любого дистрибутива (не Arch)?**
> Он переехал в отдельный репозиторий
> [als-creator/autoinstall_byedpi](https://github.com/als-creator/autoinstall_byedpi) —
> дистрибутивно-независимый скрипт, который скачивает готовый бинарник
> `ciadpi` с GitHub и работает без пакетного менеджера (в т.ч. на ALT Linux).

---

## Описание сервиса

**ByeDPI** — локальный прокси-демон, который «разжимает» ответы по протоколам
DPI (Deep Packet Inspection) провайдера. Он не подменяет DNS и не маскирует
трафик полностью, а лишь корректирует способ отправки запросов так, чтобы
блокирующая сторона не могла по характерным признакам отличить реальный трафик
и зарезать его.

Как это применяется на практике:

- YouTube / rutracker / instagram и прочие заблокированные домены продолжают
  работать без VPN.
- Весь остальной трафик идёт мимо ByeDPI и не затрагивается.

### Что делает скрипт

1. Проверяет наличие AUR-хелпера `yay`; если его нет — устанавливает
   `base-devel` + `git` через `pacman` и собирает `yay` из AUR.
2. Устанавливает пакет **`byedpi-bin`** из AUR через `yay` (бинарь
   `/usr/bin/ciadpi`). Пакетный шаблонный юнит `byedpi-bin.service`
   отключается, чтобы не конфликтовать с нашим сервисом за порт.
3. Пишет конфигурацию ByeDPI отдельными файлами: `/etc/byedpi/port`,
   `/etc/byedpi/rule`, `/etc/byedpi/hosts` и управляющий `/etc/byedpi/conf`
   с переменными-указателями на эти файлы (для user-режима — в `~/.config/byedpi/`).
   При наличии старого конфига `BYEDPI_OPTIONS=...` (наш прежний
   `/etc/byedpi.conf` или пакетный `/etc/byedpi-bin.conf`) настройки
   автоматически переносятся в новый формат.
4. При первой установке **сам подбирает стратегию**: прогоняет список доменов
   через несколько кандидатов правил desync и записывает лучшее в `rule`
   (пересборка — командой `--test`).
5. Создаёт systemd-сервисы: сам демон (через launcher `byedpi-start`, собирающий
   опции ciadpi из этих файлов при каждом старте), а для ipset-режима ещё и
   правила перенаправления REDIRECT.
6. Включает автозапуск и выводит статус.

Демон слушает на `127.0.0.1:<порт>` (по умолчанию `14228`).

---

## Содержимое репозитория

| Файл | Назначение |
|---|---|
| `autoinstall_byedpi_archlinux.sh` | Установщик для Arch (пакет `byedpi-bin` из AUR). Скачивается и запускается одной командой (см. ниже) |
| `Стратегии byedpi.txt` | Готовые стратегии desync с пояснением синтаксиса `--auto`. Можно копировать строки в файл `/etc/byedpi/rule` (или `~/.config/byedpi/rule`) вручную |
| `ZeroOmegaOptions-2025-08-07T17_33_48.644Z.bak` | Готовый бэкап настроек прокси-расширения SwitchyOmega (ZeroOmega): домены YouTube, rutracker, instagram, discord и др. Импортируется через «Восстановить из файла» |
| `LICENSE.txt` | Лицензия GPL-3.0 |

> **Где универсальный скрипт?** `install_byedpi_generic.sh` (для любого
> дистрибутива, без пакетного менеджера) переехал в репозиторий
> [als-creator/autoinstall_byedpi](https://github.com/als-creator/autoinstall_byedpi).

---

## Установка

### Требования

- Любой дистрибутив семейства Arch (см. список ниже) с доступом в интернет.
- Пользователь с правами `sudo` (не запускайте скрипт от root).
- Для сборки `yay` (если его нет) понадобятся `base-devel` и `git` — скрипт
  установит их сам через `pacman`.

### Важно: как запускать

Скрипт написан на POSIX sh (`sh`) — совместим с bash, dash, ash, zsh.
Подстановка `<(...)` (process substitution) — это bash/zsh-фича, которая
**не работает в POSIX sh/dash**. Поэтому правильный способ запуска — скачать и
исполнить:

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh
```

### Автоматическая установка (интерактивно)

Скрипт задаст два вопроса: **куда установить** (система или только для текущего
пользователя) и **как использовать** (ipset или расширение):

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh
```

### Установка с флагами (без вопросов)

**Вариант 1. Для всех пользователей, с SOCKS-прокси для расширения браузера:**

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh --system --extension
```

**Вариант 2. Для всех пользователей, без расширений (только домены из hostlist):**

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh --system --ipset
```

**Вариант 3. Только для текущего пользователя, без расширений:**

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh --user --ipset
```

> Старые короткие флаги работают как раньше: `--transparent` = `--system --ipset`,
> `--socks` = `--system --extension`, `--transparent-off` = `--off`.

> **Какой вариант выбрать?**
> - `--ipset` — всё работает само, расширения в браузере не нужны (но нужен
>   root и правится файл `hosts`).
> - `--extension` — нужна настройка расширения в браузере, зато root не нужен.
>
> Подробнее — в разделе «Как использовать: ipset или extension».

---

## Управление

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
ранее режимов (и system, и user), отключает пакетный `byedpi-bin.service`, а
также зачищает следы старых версий установщика (`/etc/byedpi.conf`,
`/etc/byedpi-hosts.txt`).

> После `--off` пакет `byedpi-bin` остаётся установленным в системе (его
> удаляет `pacman`, а не скрипт). При повторном запуске установщика скрипт
> просто не станет его ставить заново.

### Сервис вручную

Запуск:

```bash
sudo systemctl start byedpi
```

Перезапуск после смены настроек:

```bash
sudo systemctl restart byedpi
```

Статус:

```bash
sudo systemctl status byedpi
```

Остановка:

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

Отредактировать список доменов:

```bash
sudo nano /etc/byedpi/hosts
```

Для user-режима:

```bash
nano ~/.config/byedpi/hosts
```

Перезапустить демон:

```bash
sudo systemctl restart byedpi
```

### extension — SOCKS-прокси для расширения

ByeDPI поднимает SOCKS-прокси на `127.0.0.1:<порт>`. Настройте прокси-расширение
на этот адрес и импортируйте список доменов. В репозитории есть готовый бэкап
настроек для SwitchyOmega (`ZeroOmegaOptions-*.bak`) с набором доменов для
восстановления средствами расширения.

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

Редактируем файл:

```bash
sudo nano /etc/byedpi/hosts
```

Перезапускаем демон:

```bash
sudo systemctl restart byedpi
```

Для user-режима — файл и перезапуск:

```bash
nano ~/.config/byedpi/hosts
```

```bash
systemctl --user restart byedpi        # user + extension
```

```bash
sudo systemctl restart byedpi-<uid>    # user + ipset
```

### Изменить порт

Вписать число, например `14229`:

```bash
sudo nano /etc/byedpi/port
```

Перезапустить демон:

```bash
sudo systemctl restart byedpi
```

В ipset-режиме перезапустите также правила перенаправления:

```bash
sudo systemctl restart byedpi-redirect
```

### extension-режим

Список доменов хранится в расширении браузера. Правьте его через интерфейс
расширения или восстановите готовый бэкап из репозитория.

### Смена стратегии desync (автоподбор)

Правило desync лежит в файле `rule` — одной строкой. Готовые варианты можно
взять из файла `Стратегии byedpi.txt` в репозитории.

Редактируем правило:

```bash
sudo nano /etc/byedpi/rule
```

Перезапускаем демон:

```bash
sudo systemctl restart byedpi
```

**Автоподбор:** при первой установке (и по команде `--test`) скрипт прогоняет
список доменов через несколько кандидатов правил и записывает в `rule` то,
которое открывает больше всего ресурсов из списка:

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi-install.sh && sh /tmp/byedpi-install.sh --test
```

Пропустить автоподбор при установке можно флагом `--no-test`.

Коротко про синтаксис правил:

- `-s0 -o1` — отключение шифрования и отправка первой части (4 байта) сразу;
- `-Ar ... -At` — группы повторения при сбросе/таймауте;
- `-f-1 --md5sig` — отправка заведомо лишней части с MD5-подписью;
- `-r1+s` — повтор первой части с задержкой;
- `-As,n` — группа повторения с беспорядочной отправкой;
- `-Ku -a5` — отключение UDP и задержка повторов 5 мс;
- `-An` — отсутствие активной группы по умолчанию.

### Отключение YouTube через QUIC

Если YouTube грузится, но видео не воспроизводится — отключите QUIC
(`chrome://flags/#enable-quic` → Disabled), т.к. прозрачный режим
перенаправляет только TCP.

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

## Полный список флагов

```
Использование: autoinstall_byedpi_archlinux.sh [--system|--user] [--ipset|--extension] [--off|--status|--test] [--port N] [--no-test]
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
```

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

Скрипт ориентирован на установку пакета `byedpi-bin` из AUR через `yay` и
готовые конфиги. Для других дистрибутивов используйте универсальный установщик
из репозитория [als-creator/autoinstall_byedpi](https://github.com/als-creator/autoinstall_byedpi).