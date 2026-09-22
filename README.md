# histeriya2_one

![license](https://img.shields.io/badge/license-MIT-blue)
![last commit](https://img.shields.io/badge/last%20commit-september-green)
![CI](https://img.shields.io/badge/CI-failing-red)
![shell](https://img.shields.io/badge/shell-bash-green)
![python](https://img.shields.io/badge/python-3-blue)
![platform](https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu-blue)
![lint](https://img.shields.io/badge/lint-ruff%20%7C%20shellcheck-blue)

## 📖 Описание

**histeriya2_one** — это набор скриптов для быстрой установки и настройки прокси-сервера **Hysteria 2** на серверах под управлением Debian или Ubuntu. Проект автоматизирует развёртывание, генерацию ключей и настройку брандмауэра, что позволяет поднять защищённое соединение за несколько минут.

Hysteria 2 — это современный прокси-протокол на базе QUIC, который использует агрессивную стратегию отправки пакетов для повышения доступности в сетях с потерями и противодействия DPI-блокировкам. Скрипты проекта написаны на Bash и Python, проходят проверку линтерами `ruff` и `shellcheck`.

## 🚀 Быстрый старт

### Требования

- Сервер на Debian 10+ или Ubuntu 20.04+
- Права `root` или `sudo`
- Открытый UDP-порт (по умолчанию 443)

### Установка

#### Шаг 1. Клонирование репозитория

```bash
git clone https://github.com/FrankX3M/histeriya2_one.git
cd histeriya2_one
```

#### Шаг 2. Запуск скрипта установки

```bash
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

## Управление

```bash
# Проверить статус службы
systemctl status hysteria-server

# Перезапустить
systemctl restart hysteria-server

# Посмотреть логи
journalctl -u hysteria-server -f
```

## 📦 Связанные проекты

- [hysteria_naive](https://github.com/FrankX3M/hysteria_naive) — связка Hysteria 2 и NaiveProxy для обхода блокировок.

## 📄 Лицензия

Проект распространяется под лицензией MIT. Подробности в файле [LICENSE](LICENSE).

## 🤝 Вклад

Приветствуются pull request'ы и issue. Перед отправкой изменений убедитесь, что код проходит проверку:

```bash
shellcheck *.sh
ruff check .
```
