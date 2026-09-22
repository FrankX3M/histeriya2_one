# histeriya2_one — AlmaLinux edition

![license](https://img.shields.io/badge/license-MIT-blue)
![shell](https://img.shields.io/badge/shell-bash-green)
![platform](https://img.shields.io/badge/platform-AlmaLinux%208%2F9-red)

## 📖 Описание

Форк-адаптация проекта **histeriya2_one** для быстрой установки и настройки прокси-сервера **Hysteria 2** на серверах под управлением **AlmaLinux 8/9** (и других RHEL-совместимых дистрибутивов).

Оригинальный скрипт был рассчитан на Debian/Ubuntu (`apt`, `UFW`). Эта версия использует:

- `dnf` вместо `apt` для установки зависимостей;
- `firewalld` вместо `UFW` для открытия портов;
- проверку и (при необходимости) настройку **SELinux**.

Hysteria 2 — современный прокси-протокол на базе QUIC, использующий агрессивную стратегию отправки пакетов для повышения доступности в сетях с потерями и противодействия DPI-блокировкам.

## 🚀 Быстрый старт

### Требования

- Сервер на **AlmaLinux 8+** (или совместимый RHEL-клон)
- Права `root` или `sudo`
- Открытый UDP-порт (по умолчанию 443)

### Установка

#### Шаг 1. Скачайте скрипт

```bash
curl -fsSLO https://raw.githubusercontent.com/<ваш-путь>/install-almalinux.sh
```

или скопируйте `install-almalinux.sh` на сервер вручную.

#### Шаг 2. Запуск

```bash
chmod +x install-almalinux.sh
sudo ./install-almalinux.sh
```

Либо без `chmod`:

```bash
sudo bash install-almalinux.sh
```

#### Шаг 3. Следуйте выводу в терминале

Скрипт автоматически:

- проверит, что запущен от root и (по возможности) что дистрибутив — RHEL-подобный;
- установит зависимости через `dnf` (`curl`, `openssl`, `python3`, `firewalld`, `policycoreutils-python-utils`);
- установит и запустит `firewalld`, если он не активен;
- установит Hysteria 2 из официального релиза (`get.hy2.sh`);
- сгенерирует самоподписанный сертификат (или использует указанный домен);
- настроит `/etc/hysteria/config.yaml`;
- проверит режим SELinux и при `Enforcing` промаркирует нужный UDP-порт;
- откроет порт через `firewall-cmd`;
- включит автозапуск и запустит службу `hysteria-server`.

#### Шаг 4. Получение ссылки

После завершения установки скрипт выведет URI-ссылку вида `hy2://...` для импорта в клиент.

### Переменные окружения

| Переменная      | По умолчанию | Описание                                   |
|-----------------|--------------|---------------------------------------------|
| `HY2_PORT`      | `443`        | UDP-порт для Hysteria 2                     |
| `HY2_DOMAIN`    | (пусто)      | Домен для сертификата (иначе self-signed)   |
| `HY2_PASSWORD`  | (генерируется) | Пароль авторизации                        |
| `HY2_SNI`       | (пусто)      | SNI, если отличается от домена              |
| `HY2_INSECURE`  | `1`          | Флаг `insecure` в ссылке клиента            |

Пример:

```bash
sudo HY2_PORT=8443 HY2_DOMAIN=example.com bash install-almalinux.sh
```

## 🔧 Управление

```bash
# Статус службы
systemctl status hysteria-server --no-pager

# Перезапуск
systemctl restart hysteria-server

# Логи
journalctl -u hysteria-server -f

# Открытые порты в firewalld
firewall-cmd --list-ports

# Режим SELinux
getenforce

# Проверка, что порт слушается
ss -ulnp | grep hysteria
```

## 🛡️ Особенности AlmaLinux

- **firewalld** — правило добавляется как постоянное (`--permanent`) с последующим `--reload`, так что переживёт перезагрузку.
- **SELinux** — если он в режиме `Enforcing`, скрипт пытается пометить UDP-порт как `unreserved_port_t`. Если SELinux в `Disabled` или `Permissive` (частая ситуация на образах у хостеров), этот шаг просто пропускается — блокировок нет.
- Привязка к привилегированному порту (например, 443) обеспечивается через systemd-юнит, который создаёт установщик `get.hy2.sh` (обычно через `AmbientCapabilities=CAP_NET_BIND_SERVICE`), а не через запуск процесса от root напрямую.

## 🩺 Диагностика

Если служба не поднялась:

```bash
journalctl -u hysteria-server -e
```

Если клиент не может подключиться, но служба запущена и порт открыт в `firewall-cmd --list-ports`:

- проверьте, не блокирует ли трафик провайдер/хостер на уровне сети (некоторые VDS-провайдеры фильтруют UDP);
- убедитесь, что в клиенте указаны тот же пароль, SNI и `insecure`, что и в выведенной ссылке.

## 📄 Лицензия

MIT — как и в оригинальном проекте.
