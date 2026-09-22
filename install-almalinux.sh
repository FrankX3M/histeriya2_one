#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Установка Hysteria 2 — версия для AlmaLinux 8/9
#  (адаптировано из install.sh проекта histeriya2_one,
#   изначально рассчитанного на Debian/Ubuntu)
# ============================================================

HY2_PORT=${HY2_PORT:-443}
HY2_DOMAIN=${HY2_DOMAIN:-}
HY2_PASSWORD=${HY2_PASSWORD:-}
HY2_SNI=${HY2_SNI:-}
HY2_INSECURE=${HY2_INSECURE:-1}

if [[ $EUID -ne 0 ]]; then
    echo "Скрипт нужно запускать от имени root." >&2
    exit 1
fi

# --- Проверка, что это RHEL-подобная система ---
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "almalinux" && "${ID_LIKE:-}" != *rhel* && "${ID_LIKE:-}" != *fedora* ]]; then
        echo "[!] Похоже, это не AlmaLinux/RHEL-подобная система (обнаружено: ${PRETTY_NAME:-неизвестно})." >&2
        echo "    Скрипт может не сработать. Продолжаю через 5 секунд..." >&2
        sleep 5
    fi
else
    echo "[!] Не удалось определить дистрибутив (/etc/os-release отсутствует)." >&2
fi

# --- Установка зависимостей через dnf ---
echo "[+] Устанавливаю зависимости (curl, openssl, python3, firewalld, policycoreutils)..."
dnf install -y curl openssl python3 firewalld policycoreutils-python-utils tar >/dev/null

# --- Firewalld вместо UFW ---
if ! systemctl is-active --quiet firewalld; then
    echo "[+] Запускаю firewalld..."
    systemctl enable --now firewalld >/dev/null 2>&1
fi

if [[ -z "$HY2_PASSWORD" ]]; then
    HY2_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)
    echo "[+] Сгенерирован пароль: $HY2_PASSWORD"
fi

HY2_HOST=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com || hostname -I | awk '{print $1}')
echo "[+] Внешний IP: $HY2_HOST"

echo "[+] Устанавливаю Hysteria 2..."
bash <(curl -fsSL https://get.hy2.sh/)

# --- Сертификаты в /etc/hysteria ---
CERT_DIR="/etc/hysteria"
CERT_FILE="$CERT_DIR/hy2.crt"
KEY_FILE="$CERT_DIR/hy2.key"
mkdir -p "$CERT_DIR"

if [[ -z "$HY2_DOMAIN" ]]; then
    HY2_SNI=${HY2_SNI:-"bing.com"}
    echo "[+] Домен не указан. Самоподписанный сертификат для SNI=$HY2_SNI"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -subj "/CN=$HY2_SNI" -days 36500 2>/dev/null
else
    HY2_SNI=${HY2_SNI:-"$HY2_DOMAIN"}
    echo "[+] Самоподписанный сертификат для домена $HY2_DOMAIN"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -subj "/CN=$HY2_DOMAIN" -days 36500 2>/dev/null
fi

# --- Права на файлы и каталог ---
# Пользователь hysteria создаётся установщиком hy2
id hysteria >/dev/null 2>&1 || useradd --system --no-create-home hysteria
chown -R hysteria:hysteria "$CERT_DIR"
chmod 755 "$CERT_DIR"
chmod 644 "$CERT_FILE"
chmod 600 "$KEY_FILE"

# --- Конфиг ---
cat > /etc/hysteria/config.yaml <<EOF
listen: :$HY2_PORT
tls:
  cert: $CERT_FILE
  key: $KEY_FILE
auth:
  type: password
  password: $HY2_PASSWORD
ignoreClientBandwidth: true
EOF
chown hysteria:hysteria /etc/hysteria/config.yaml
chmod 640 /etc/hysteria/config.yaml

# --- SELinux: проверяем режим и, если нужно, открываем порт в контексте ---
if command -v getenforce >/dev/null 2>&1; then
    SELINUX_MODE=$(getenforce)
    echo "[+] SELinux: $SELINUX_MODE"
    if [[ "$SELINUX_MODE" == "Enforcing" ]]; then
        # Если порт не входит в стандартный список разрешённых для network-сервисов,
        # можно явно промаркировать его. Для UDP это обычно не требуется, но на всякий случай:
        semanage port -a -t unreserved_port_t -p udp "$HY2_PORT" 2>/dev/null || \
        semanage port -m -t unreserved_port_t -p udp "$HY2_PORT" 2>/dev/null || true
    fi
fi

# --- Открываем порт в firewalld (аналог ufw allow) ---
echo "[+] Открываю порт $HY2_PORT/udp в firewalld..."
firewall-cmd --permanent --add-port="${HY2_PORT}/udp" >/dev/null
firewall-cmd --reload >/dev/null

# --- Запуск ---
systemctl enable hysteria-server >/dev/null 2>&1
systemctl restart hysteria-server
sleep 2

if systemctl is-active --quiet hysteria-server; then
    echo "[+] Hysteria 2 успешно запущен."
else
    echo "[-] Ошибка запуска. Смотрите: journalctl -u hysteria-server -e" >&2
    exit 1
fi

# --- Ссылка hy2:// ---
urlenc() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
    else
        printf '%s' "$1" | jq -sRr @uri
    fi
}

LINK_AUTH=$(urlenc "$HY2_PASSWORD")
LINK_SNI=$(urlenc "$HY2_SNI")
HY2_URI="hy2://${LINK_AUTH}@${HY2_HOST}:${HY2_PORT}/?insecure=${HY2_INSECURE}&sni=${LINK_SNI}#Hysteria2"

echo ""
echo "============================================================"
echo "Ссылка для подключения (hy2://):"
echo "$HY2_URI"
echo "============================================================"
echo "Адрес: $HY2_HOST"
echo "Порт: $HY2_PORT"
echo "Пароль: $HY2_PASSWORD"
echo "SNI: $HY2_SNI"
