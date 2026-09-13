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
