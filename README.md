# ByeDPI Installer (Arch Linux)

Установщик и конфигуратор **ByeDPI** для дистрибутивов семейства Arch Linux
(EndeavourOS, Manjaro, Garuda, CachyOS и др.). byedpi ставится **как положено
для Arch** — пакетом `byedpi-bin` из AUR, а скрипт предоставляет перебор
стратегий, раздельные файлы конфига и удобное управление.

**Важно:** это тот же **универсальный скрипт** (`install_byedpi_generic.sh`),
что и в репозитории [als-creator/autoinstall_byedpi](https://github.com/als-creator/autoinstall_byedpi),
переименованный в `autoinstall_byedpi_archlinux.sh`. Отличие **только одно** —
источник byedpi:

| Репозиторий | Источник byedpi |
|---|---|
| `autoinstall_byedpi` | бинарник `ciadpi` скачивается с GitHub |
| `autoinstall_byedpi_archlinux` (этот) | пакет `byedpi-bin` из AUR через `yay` |

Установка одной командой:

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi.sh && sh /tmp/byedpi.sh
```

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

1. Проверяет наличие AUR-хелпера `yay`; если его нет — ставит `base-devel` +
   `git` через `pacman` и собирает `yay` из AUR.
2. Устанавливает пакет **`byedpi-bin`** из AUR (бинарь `/usr/bin/ciadpi`).
   Пакетный шаблонный юнит `byedpi-bin.service` отключается, чтобы не
   конфликтовать с нашим сервисом за порт.
3. Пишет конфигурацию отдельными файлами: `/etc/byedpi/port`,
   `/etc/byedpi/rule`, `/etc/byedpi/hosts` и управляющий `/etc/byedpi/conf`
   с переменными-указателями на эти файлы.
4. При первой установке **сам подбирает стратегию (перебор)**: прогоняет список
   доменов через несколько кандидатов правил desync и записывает лучшее в
   `rule` (пересборка — командой `--test`).
5. Создаёт сервис: через **systemd**, если он используется, иначе через
   `/etc/init.d/byedpi`. Демон запускается через launcher `byedpi-start`,
   который собирает опции ciadpi из отдельных файлов при каждом старте.
6. Включает автозапуск и выводит статус.

Демон слушает на `127.0.0.1:<порт>` (по умолчанию `14228`).

> **Права root:** скрипт сам определяет способ повышения прав — от root
> напрямую, иначе через `sudo`, иначе через `su -s /bin/sh -c '...' root`.

---

## Содержимое репозитория

| Файл | Назначение |
|---|---|
| `autoinstall_byedpi_archlinux.sh` | Универсальный установщик (переименован из `install_byedpi_generic.sh`), источник byedpi — пакет `byedpi-bin` из AUR |
| `Стратегии byedpi.txt` | Готовые стратегии desync с пояснением синтаксиса `--auto`. Можно копировать строки в файл `/etc/byedpi/rule` вручную |
| `ZeroOmegaOptions-2025-08-07T17_33_48.644Z.bak` | Готовый бэкап настроек прокси-расширения SwitchyOmega (ZeroOmega): домены YouTube, rutracker, instagram, discord и др. Импортируется через «Восстановить из файла» |
| `LICENSE.txt` | Лицензия GPL-3.0 |

---

## Установка

### Требования

- Любой дистрибутив семейства Arch (см. список ниже) с доступом в интернет.
- Пользователь с правами `sudo` (можно запускать и от root — скрипт сам
  определит нужный способ прав).
- Если `yay` нет — скрипт сам установит `base-devel` и `git` и соберёт `yay`
  из AUR.

### Автоматическая установка

По умолчанию (без флагов) скрипт ставит ByeDPI в **SOCKS-режиме** для
расширения браузера:

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi.sh && sh /tmp/byedpi.sh
```

### Установка с флагами

**Вариант 1. Без расширений (весь TCP 80/443 через ByeDPI, фильтр по SNI):**

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi.sh && sh /tmp/byedpi.sh --ipset
```

**Вариант 2. SOCKS-прокси для расширения браузера (явно):**

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi.sh && sh /tmp/byedpi.sh --extension
```

> **Какой вариант выбрать?**
> - `--ipset` — всё работает само, расширения в браузере не нужны (нужен root:
>   и при установке, и для правил iptables в ядре; список доменов правится в
>   файле `hosts`).
> - `--extension` — нужна настройка расширения в браузере; root нужен один раз
>   при установке (конфиг и сервис ставятся системно в `/etc`).
>
> Подробнее — в разделе «Как использовать: ipset или extension».

---

## Управление

### Статус

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi.sh && sh /tmp/byedpi.sh --status
```

### Полное удаление (отключение)

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi.sh && sh /tmp/byedpi.sh --off
```

`--off` останавливает и удаляет сервисы (`byedpi.service` или
`/etc/init.d/byedpi`), правила iptables и конфиг `/etc/byedpi`. Пакет
`byedpi-bin` из AUR остаётся установленным — его удаляет pacman, а не скрипт.

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

Если systemd не используется — те же действия через init-скрипт:

```bash
/etc/init.d/byedpi restart
```

---

## Как использовать: ipset или extension

| | `--ipset` | `--extension` |
|---|---|---|
| Расширения браузера | не нужны | нужны (FoxyProxy / SmartProxy / SwitchyOmega 3) |
| Охват | домены из hostlist (фильтр по SNI) | только то, что настроено в расширении |
| Root | нужен: установка + правила iptables в ядре | нужен при установке: конфиг и сервис ставятся в `/etc` (демон — системный сервис) |
| UDP/QUIC | не обрабатывается | не обрабатывается |

> Отдельного «пользовательского» режима без root в этом скрипте нет: конфиг
> всегда в `/etc/byedpi`, сервис — системный (systemd или init.d). Права нужны
> при установке/удалении/перезапуске сервиса.

### ipset — работа без расширений

Правило `iptables -t nat` `REDIRECT` (порты 80/443, TCP) заворачивает **весь**
исходящий трафик в локальный порт ByeDPI. Дальше ByeDPI смотрит на SNI (домен)
в TLS-запросе и десинхронизирует только те соединения, чей домен есть в
hostlist — как это делает расширение в SOCKS-режиме. Это надёжно работает и для
CDN-доменов (googlevideo), у которых тысячи IP: фильтр идёт по домену, а не по
IP, поэтому ipset и таймер обновления не нужны. Остальной трафик идёт напрямую.

Отредактировать список доменов:

```bash
sudo nano /etc/byedpi/hosts
```

Перезапустить демон:

```bash
sudo systemctl restart byedpi
```

### extension — SOCKS-прокси

ByeDPI поднимает SOCKS на `127.0.0.1:<порт>`. Настройте прокси-расширение на
этот адрес и импортируйте список доменов. Готовый бэкап настроек SwitchyOmega
(`ZeroOmegaOptions-*.bak`) лежит в репозитории — импортируется через
«Восстановить из файла» в настройках расширения.

---

## Как изменить настройки

Порт, правило desync и список доменов лежат в **отдельных файлах** — менять их
можно по одному, не трогая остальные:

| Что настраиваем | Файл |
|---|---|
| список доменов | `/etc/byedpi/hosts` |
| стратегия desync | `/etc/byedpi/rule` |
| порт | `/etc/byedpi/port` |
| управляющий конфиг | `/etc/byedpi/conf` |

`conf` — управляющий файл с **переменными-указателями** на `rule`/`port`/`hosts`.
Демон запускается через launcher `byedpi-start`, который при каждом старте
читает эти файлы и собирает опции ciadpi — правки вступают в силу перезапуском
сервиса без переустановки.

### Изменить список доменов (ipset-режим)

Редактируем файл:

```bash
sudo nano /etc/byedpi/hosts
```

Перезапускаем демон:

```bash
sudo systemctl restart byedpi
```

### Сменить порт

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

### Смена стратегии desync (автоподбор)

Правило лежит в файле `rule` одной строкой. Готовые варианты — в файле
`Стратегии byedpi.txt` репозитория.

Редактируем правило:

```bash
sudo nano /etc/byedpi/rule
```

Перезапускаем демон:

```bash
sudo systemctl restart byedpi
```

**Автоподбор (перебор):** при первой установке (и по команде `--test`) скрипт
прогоняет список доменов через нескольких кандидатов правил и записывает в
`rule` то, которое открывает больше всего ресурсов из списка:

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_byedpi_archlinux/main/autoinstall_byedpi_archlinux.sh -o /tmp/byedpi.sh && sh /tmp/byedpi.sh --test
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

- Повышает права автоматически: от root напрямую, иначе через `sudo`, иначе
  через `su -s /bin/sh -c '...' root`.
- В ipset-режиме отсекает служебные подсети (локальные адреса) от
  перенаправления, чтобы не заворачивать собственный трафик.

---

## Полный список флагов

```
Использование: autoinstall_byedpi_archlinux.sh [--ipset|--extension] [--off|--status|--test] [--port N] [--no-test]
  --ipset         метод ipset: весь TCP 80/443 через ByeDPI, фильтр по SNI
  --extension     метод extension: SOCKS-прокси для браузерного расширения
  --test          перезапустить автотест стратегий и обновить /etc/byedpi/rule
  --no-test       пропустить автотест стратегий при установке
  --off | --remove  отключить и удалить всё
  --status|--info   показать текущее состояние
  --port N        изменить порт
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
из репозитория [als-creator/autoinstall_byedpi](https://github.com/als-creator/autoinstall_byedpi),
а для ALT Linux — [autoinstall_byedpi_altlinux](https://github.com/als-creator/autoinstall_byedpi_altlinux).