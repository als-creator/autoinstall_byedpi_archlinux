# ByeDPI Installer and Configurator

Автоматический установщик и конфигуратор **ByeDPI** для дистрибутивов семейства
ArchLinux (проверялось на EndeavourOS и Arch Linux).

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
3. Пишет конфигурацию ByeDPI с предустановленными параметрами (путь зависит от
   выбранного режима, см. ниже).
4. Создаёт systemd-сервисы: сам демон, а для ipset-режима ещё и правила
   перенаправления + таймер обновления списка доменов.
5. Включает автозапуск и выводит статус.

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
конфиги (`/etc/byedpi.conf`, `~/.config/byedpi.conf`) и hostlist для
установленных ранее режимов (и system, и user).

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

- конфиг: `/etc/byedpi.conf`
- hostlist: `/etc/byedpi-hosts.txt` (для ipset-режима)
- демон: systemd-сервис `byedpi.service`
- порт: `14228`

### user (только для текущего пользователя)

- конфиг: `~/.config/byedpi.conf`
- hostlist: `~/.config/byedpi-hosts.txt` (для ipset-режима)
- демон: systemd-**user**-сервис `byedpi.service` (запускается при входе)
- порт: `14228 + (uid - 1000)`, чтобы у разных пользователей порты не пересекались

В ipset-режиме правила REDIRECT привязаны к `--uid-owner` текущего пользователя и
затрагивают только его трафик. Сам ipset живёт в ядре, поэтому корневые unit-ы
`byedpi-hosts-<uid>` и `byedpi-redirect-<uid>` всё же создаются в
`/etc/systemd/system`, но читают hostlist из `~/.config`.

Каждый пользователь может запустить скрипт повторно со своими флагами
`--user ...`, не затрагивая остальных.

---

## Как использовать: ipset или extension

| | `--ipset` | `--extension` |
|---|---|---|
| Расширения браузера | не нужны | нужны (FoxyProxy / SmartProxy / SwitchyOmega 3) |
| Охват | только домены из hostlist | только то, что настроено в расширении |
| Root | нужен (правила в ядре) | не нужен |
| UDP/QUIC | не обрабатывается | не обрабатывается |

### ipset — работа без расширений

Домены из hostlist резолвятся в IP-адреса и складываются в ipset. Правило
`iptables -t nat` `REDIRECT` матчит ТОЛЬКО пакеты, чей адрес назначения есть в
этом ipset (порты 80/443, TCP), и заворачивает их в локальный порт ByeDPI.
Остальной трафик идёт напрямую. ipset обновляется таймером каждый час.

### extension — SOCKS-прокси для расширения

ByeDPI поднимает SOCKS-прокси на `127.0.0.1:<порт>`. Настройте прокси-расширение
на этот адрес и импортируйте список доменов. В репозитории есть готовый бэкап
настроек для SwitchyOmega с набором доменов для восстановления средствами
расширения.

---

## Как изменить список доменов

### ipset-режим (без расширений)

Отредактируйте hostlist и перезапустите сервисы:

```bash
sudo nano /etc/byedpi-hosts.txt                                # system
sudo systemctl restart byedpi-hosts byedpi-redirect

nano ~/.config/byedpi-hosts.txt                                # user
systemctl --user restart byedpi-hosts byedpi-redirect          # user
```

Изменения ipset пересоберутся автоматически либо по таймеру (раз в час), либо
при перезапуске сервисов.

### extension-режим

Список доменов хранится в расширении браузера. Правьте его через интерфейс
расширения или восстановите готовый бэкап из репозитория. Изменения конфига:

```bash
sudo nano /etc/byedpi.conf
```

```bash
sudo systemctl restart byedpi
```

### Смена стратегии desync

Параметры стратегии лежат в файле `BYEDPI_OPTIONS` внутри конфига. Готовые
стратегии можно взять из файла `Стратегии byedpi.txt` в репозитории —
подставьте нужную строку в конфиг и перезапустите сервис.

Стратегия по умолчанию:

```
-Kt,h -s0 -o1 -Ar -o1 -At -f-1 --md5sig -r1+s -As,n -Ku -a5 -An
```

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
