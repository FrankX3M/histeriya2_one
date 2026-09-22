![license](https://img.shields.io/badge/license-MIT-blue) ![last commit](https://img.shields.io/badge/last%20commit-september-green) ![CI](https://img.shields.io/badge/CI-failing-red) ![shell](https://img.shields.io/badge/shell-bash-green) ![python](https://img.shields.io/badge/python-3-blue) ![platform](https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu-blue) ![lint](https://img.shields.io/badge/lint-ruff%20%7C%20shellcheck-blue)

## 📖 Описание

**histeriya2_one** — это набор скриптов для быстрой установки, настройки и защиты прокси-сервера **Hysteria 2** на серверах под управлением Debian или Ubuntu. Проект автоматизирует развёртывание, генерацию ключей, настройку брандмауэра и базовый security-хардening, что позволяет поднять защищённое соединение за несколько минут.

Hysteria 2 — это современный прокси-протокол на базе QUIC, который использует агрессивную стратегию отправки пакетов для повышения доступности в сетях с потерями и противодействия DPI-блокировкам. Скрипты проекта написаны на Bash и Python, проходят проверку линтерами `ruff` и `shellcheck`.

## 📂 Состав проекта

| Файл | Где запускать | Назначение |
| --- | --- | --- |
| [`install.sh`](install.sh) | на сервере | Установка Hysteria 2, генерация сертификата и конфига, запуск службы |
| [`harden.sh`](harden.sh) | на сервере | Файрвол (nftables), Fail2ban, systemd-hardening службы, sysctl (BBR/буферы), управление swap |
| [`setup-ssh-key.sh`](setup-ssh-key.sh) | на локальном компьютере | Генерация SSH-ключа и настройка входа на сервер без пароля |

## 🚀 Быстрый старт

### Требования

- Сервер на Debian 10+ или Ubuntu 20.04+
- Права `root` или `sudo`
- Открытый UDP-порт (по умолчанию 443)

### Установка

#### Шаг 1. Клонирование репозитория

```
git clone https://github.com/FrankX3M/histeriya2_one.git
cd histeriya2_one
```

#### Шаг 2. Запуск скрипта установки

```
chmod +x install.sh
./install.sh
```

#### Шаг 3. Следуйте инструкциям в терминале

Скрипт автоматически:

- Установит Hysteria 2 из официальных релизов.
- Сгенерирует самоподписанный сертификат (или запросит Let's Encrypt).
- Настроит конфигурационный файл `config.yaml`.
- Откроет необходимые порты через UFW.
- Включит автозапуск службы.

#### Шаг 4. Получение ссылки

После завершения установки скрипт выведет URI-ссылку вида `hysteria2://...` для импорта в клиент.

## 🔒 Хардening сервера (`harden.sh`)

После `install.sh` рекомендуется дополнительно закалить сервер:

```
chmod +x harden.sh
./harden.sh
```

Скрипт настраивает:

- **Файрвол (nftables)** — политика default-deny, открыты только SSH и UDP-порт Hysteria. Отключает UFW, если тот был поставлен `install.sh`, чтобы не было конфликта фаерволов.
- **Fail2ban** — защита SSH от перебора паролей (`jail sshd`, настраиваемые `bantime`/`maxretry`/`findtime`).
- **Systemd** — hardening drop-in для `hysteria-server.service`: `Restart=on-failure`, `NoNewPrivileges`, `ProtectSystem=strict`, лимиты дескрипторов и точечные capabilities вместо запуска от root.
- **Системные параметры (sysctl)** — включение **BBR** (`tcp_congestion_control=bbr`, `fq`) и увеличенные буферы сокетов/UDP для QUIC-нагрузки, плюс базовое сетевое ужесточение (`rp_filter`, `tcp_syncookies` и т.д.).
- **Swap** — управляется параметром `SWAP_MODE` (по умолчанию `auto`): создаётся автоматически только если его ещё нет и ОЗУ ≤ 2 ГБ; `on` — принудительно создать/пересоздать; `off` — отключить и удалить.

Все параметры переопределяются переменными окружения:

```
SSH_PORT=2222 HY2_PORT=8443 SWAP_MODE=off ./harden.sh
```

Основные переменные: `SSH_PORT`, `HY2_PORT`, `HY2_SERVICE`, `ALLOW_ICMP`, `ENABLE_BBR`, `FAIL2BAN_BANTIME`, `FAIL2BAN_MAXRETRY`, `FAIL2BAN_FINDTIME`, `SWAP_MODE`, `SWAP_FILE`, `SWAP_SIZE_MB`.

## 🔑 Вход без пароля (`setup-ssh-key.sh`)

Скрипт запускается **на локальном компьютере** (не на сервере) и настраивает SSH-ключ для входа на сервер без пароля:

```
chmod +x setup-ssh-key.sh
./setup-ssh-key.sh user@server.example.com
```

Что делает:

1. Генерирует ed25519-ключ (`~/.ssh/id_ed25519` по умолчанию), если его ещё нет.
2. Копирует публичный ключ на сервер (`ssh-copy-id`, либо вручную через `ssh`, если `ssh-copy-id` недоступен).
3. Проверяет, что вход по ключу действительно работает без пароля.
4. Выводит готовый блок для `~/.ssh/config`, чтобы дальше подключаться одной командой.
5. По желанию (`DISABLE_PASSWORD_AUTH=1`) отключает вход по паролю в `sshd_config` на сервере — но только после того, как подтверждён рабочий вход по ключу.

```
DISABLE_PASSWORD_AUTH=1 ./setup-ssh-key.sh user@server.example.com
```

Рекомендуемый порядок работы с сервером:

```
./setup-ssh-key.sh user@server.example.com   # 1. с локального компьютера: ключ без пароля
ssh user@server.example.com                  # 2. заходим на сервер
./install.sh                                 # 3. на сервере: ставим Hysteria 2
./harden.sh                                  # 4. на сервере: файрвол, fail2ban, sysctl, swap
```

## Управление

```
# Проверить статус службы
systemctl status hysteria-server

# Перезапустить
systemctl restart hysteria-server

# Посмотреть логи
journalctl -u hysteria-server -f

# Проверить состояние файрвола и fail2ban после harden.sh
nft list ruleset
fail2ban-client status sshd
```

## 📦 Связанные проекты

- [hysteria_naive](https://github.com/FrankX3M/hysteria_naive) — связка Hysteria 2 и NaiveProxy для обхода блокировок.

## 📄 Лицензия

Проект распространяется под лицензией MIT. Подробности в файле [LICENSE](LICENSE).

## 🤝 Вклад

Приветствуются pull request'ы и issue. Перед отправкой изменений убедитесь, что код проходит проверку:

```
shellcheck *.sh
ruff check .
```
