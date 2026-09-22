#!/usr/bin/env bash
#
# setup-ssh-key.sh — запускается на ЛОКАЛЬНОМ компьютере.
#
# 1) Генерирует SSH-ключ (если его ещё нет)
# 2) Копирует публичный ключ на сервер (~/.ssh/authorized_keys)
# 3) Проверяет вход без пароля
# 4) По желанию (DISABLE_PASSWORD_AUTH=1) отключает вход по паролю на сервере
#
# Использование:
#   chmod +x setup-ssh-key.sh
#   ./setup-ssh-key.sh user@server.example.com
#   ./setup-ssh-key.sh user@server.example.com 2222        # свой SSH-порт
#
# Или через переменные окружения:
#   SERVER=user@server.example.com PORT=2222 KEY_PATH=~/.ssh/hy2_ed25519 ./setup-ssh-key.sh

set -euo pipefail

log()  { echo "[+] $*"; }
warn() { echo "[-] $*" >&2; }
die()  { warn "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Параметры
# ---------------------------------------------------------------------------
SERVER=${SERVER:-${1:-}}
PORT=${PORT:-${2:-22}}
KEY_PATH=${KEY_PATH:-"$HOME/.ssh/id_ed25519"}
KEY_TYPE=${KEY_TYPE:-ed25519}
KEY_COMMENT=${KEY_COMMENT:-"$(whoami)@$(hostname)-$(date +%Y%m%d)"}
DISABLE_PASSWORD_AUTH=${DISABLE_PASSWORD_AUTH:-0}

if [[ -z "$SERVER" ]]; then
    die "Не указан сервер. Использование: ./setup-ssh-key.sh user@host [port]"
fi

if ! command -v ssh >/dev/null 2>&1; then
    die "Команда ssh не найдена. Установите OpenSSH-клиент."
fi

# ---------------------------------------------------------------------------
# 1. Генерация ключа
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$KEY_PATH")"
chmod 700 "$(dirname "$KEY_PATH")"

if [[ -f "$KEY_PATH" ]]; then
    log "Ключ уже существует: $KEY_PATH (использую его)."
else
    log "Генерирую новый $KEY_TYPE-ключ: $KEY_PATH"
    ssh-keygen -t "$KEY_TYPE" -f "$KEY_PATH" -C "$KEY_COMMENT" -N ""
fi

PUB_KEY_PATH="${KEY_PATH}.pub"
[[ -f "$PUB_KEY_PATH" ]] || die "Публичный ключ не найден: $PUB_KEY_PATH"

# ---------------------------------------------------------------------------
# 2. Копирование ключа на сервер
# ---------------------------------------------------------------------------
log "Копирую публичный ключ на $SERVER (порт $PORT)..."
log "Потребуется один раз ввести пароль от сервера."

if command -v ssh-copy-id >/dev/null 2>&1; then
    ssh-copy-id -p "$PORT" -i "$PUB_KEY_PATH" "$SERVER"
else
    # fallback для систем без ssh-copy-id (например, некоторые версии Windows/macOS)
    PUB_KEY_CONTENT=$(cat "$PUB_KEY_PATH")
    ssh -p "$PORT" "$SERVER" "
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
        grep -qxF '$PUB_KEY_CONTENT' ~/.ssh/authorized_keys || echo '$PUB_KEY_CONTENT' >> ~/.ssh/authorized_keys
    "
fi

# ---------------------------------------------------------------------------
# 3. Проверка входа без пароля
# ---------------------------------------------------------------------------
log "Проверяю вход по ключу без пароля..."
if ssh -p "$PORT" -o BatchMode=yes -o ConnectTimeout=5 -i "$KEY_PATH" "$SERVER" "echo OK" 2>/dev/null | grep -q OK; then
    log "Успех! Вход по ключу работает без пароля."
else
    die "Не удалось войти по ключу без пароля. Проверьте права на сервере (~/.ssh должен быть 700, authorized_keys — 600) и повторите."
fi

# Подсказка про ssh-config, чтобы не указывать ключ и порт каждый раз
HOST_ALIAS=$(echo "$SERVER" | sed 's/[@.]/-/g')
log "Готово. Для удобства можно добавить в ~/.ssh/config:"
cat <<EOF

Host ${HOST_ALIAS}
    HostName $(echo "$SERVER" | cut -d@ -f2)
    User $(echo "$SERVER" | cut -d@ -f1)
    Port ${PORT}
    IdentityFile ${KEY_PATH}

EOF
echo "После этого можно подключаться просто: ssh ${HOST_ALIAS}"

# ---------------------------------------------------------------------------
# 4. (опционально) Отключение входа по паролю на сервере
# ---------------------------------------------------------------------------
if [[ "$DISABLE_PASSWORD_AUTH" == "1" ]]; then
    log "DISABLE_PASSWORD_AUTH=1 — отключаю вход по паролю на сервере..."
    ssh -p "$PORT" -i "$KEY_PATH" "$SERVER" '
        set -e
        sudo sed -i \
            -e "s/^#\?PasswordAuthentication.*/PasswordAuthentication no/" \
            -e "s/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/" \
            -e "s/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/" \
            /etc/ssh/sshd_config
        sudo systemctl restart ssh || sudo systemctl restart sshd
    '
    warn "Вход по паролю отключён. НЕ закрывайте текущую SSH-сессию, пока не убедитесь,"
    warn "что в НОВОМ окне вход по ключу работает — иначе рискуете потерять доступ."
else
    log "Вход по паролю на сервере пока не тронут (если хотите отключить его,"
    log "запустите повторно с DISABLE_PASSWORD_AUTH=1, ИЛИ отключите вручную:"
    log "  PasswordAuthentication no  в /etc/ssh/sshd_config, затем перезапустить sshd)"
fi