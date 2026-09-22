#!/usr/bin/env bash
#
# harden.sh — дополнительная настройка сервера для histeriya2_one
#
# Настраивает:
#   1) Файрвол через nftables (default-deny, разрешены только SSH и порт Hysteria)
#   2) Fail2ban (защита SSH от брутфорса)
#   3) Systemd hardening drop-in для hysteria-server.service
#   4) Системные параметры sysctl: включение BBR, увеличение буферов
#   5) Управление swap (auto / on / off)
#
# Запускать после install.sh, от имени root:
#   chmod +x harden.sh
#   ./harden.sh
#
# Все параметры можно переопределить переменными окружения, например:
#   SSH_PORT=2222 HY2_PORT=8443 SWAP_MODE=on ./harden.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Конфигурация (переопределяется через переменные окружения)
# ---------------------------------------------------------------------------
SSH_PORT=${SSH_PORT:-22}                 # порт SSH, который останется открытым
HY2_PORT=${HY2_PORT:-443}                # UDP-порт Hysteria 2 (как в install.sh)
HY2_SERVICE=${HY2_SERVICE:-hysteria-server}
ALLOW_ICMP=${ALLOW_ICMP:-1}              # разрешить ping (1/0)
ENABLE_BBR=${ENABLE_BBR:-1}              # включить BBR + fq (1/0)
FAIL2BAN_BANTIME=${FAIL2BAN_BANTIME:-1h}
FAIL2BAN_MAXRETRY=${FAIL2BAN_MAXRETRY:-5}
FAIL2BAN_FINDTIME=${FAIL2BAN_FINDTIME:-10m}

# SWAP_MODE:
#   auto — создать swap только если его нет и ОЗУ <= 2 ГБ (по умолчанию)
#   on   — принудительно создать/пересоздать swap размера SWAP_SIZE_MB
#   off  — отключить и удалить существующий swap-файл
SWAP_MODE=${SWAP_MODE:-auto}
SWAP_FILE=${SWAP_FILE:-/swapfile}
SWAP_SIZE_MB=${SWAP_SIZE_MB:-0}          # 0 = определить автоматически

# ---------------------------------------------------------------------------
# Проверки
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "Скрипт нужно запускать от имени root." >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "Поддерживаются только Debian/Ubuntu (apt-get не найден)." >&2
    exit 1
fi

log()  { echo "[+] $*"; }
warn() { echo "[-] $*" >&2; }

# ---------------------------------------------------------------------------
# 0. Установка пакетов
# ---------------------------------------------------------------------------
log "Обновляю списки пакетов и устанавливаю nftables, fail2ban..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nftables fail2ban >/dev/null

# UFW из install.sh конфликтует с nftables — отключаем, если стоит
if command -v ufw >/dev/null 2>&1; then
    log "Обнаружен UFW, отключаю его в пользу nftables..."
    ufw disable >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 1. Файрвол (nftables)
# ---------------------------------------------------------------------------
log "Настраиваю nftables (разрешены: loopback, established, SSH:${SSH_PORT}/tcp, Hysteria:${HY2_PORT}/udp)..."

ICMP_RULES=""
if [[ "$ALLOW_ICMP" == "1" ]]; then
    ICMP_RULES=$'        icmp type echo-request limit rate 10/second accept\n        icmpv6 type { echo-request, nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept'
fi

cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
# Сгенерировано harden.sh — не редактируйте вручную, меняйте переменные и перезапускайте скрипт.

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # локальный трафик и уже установленные соединения
        iif lo accept
        ct state established,related accept
        ct state invalid drop

${ICMP_RULES}

        # SSH
        tcp dport ${SSH_PORT} ct state new accept

        # Hysteria 2 (QUIC/UDP)
        udp dport ${HY2_PORT} accept

        # раскомментируйте, чтобы логировать отброшенные пакеты для отладки
        # log prefix "nft-drop: " counter drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

systemctl enable nftables >/dev/null 2>&1
nft -c -f /etc/nftables.conf   # проверка синтаксиса перед применением
systemctl restart nftables

if systemctl is-active --quiet nftables; then
    log "nftables применён и активен."
else
    warn "Не удалось запустить nftables. Смотрите: journalctl -u nftables -e"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Fail2ban
# ---------------------------------------------------------------------------
log "Настраиваю fail2ban для SSH..."

SSHD_LOGPATH="/var/log/auth.log"
[[ -f /var/log/secure ]] && SSHD_LOGPATH="/var/log/secure"   # RHEL-семейство, на всякий случай

cat > /etc/fail2ban/jail.local <<EOF
# Сгенерировано harden.sh

[DEFAULT]
bantime  = ${FAIL2BAN_BANTIME}
findtime = ${FAIL2BAN_FINDTIME}
maxretry = ${FAIL2BAN_MAXRETRY}
backend  = systemd

[sshd]
enabled  = true
port     = ${SSH_PORT}
logpath  = ${SSHD_LOGPATH}
EOF

systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban

if systemctl is-active --quiet fail2ban; then
    log "fail2ban активен (jail sshd, maxretry=${FAIL2BAN_MAXRETRY}, bantime=${FAIL2BAN_BANTIME})."
else
    warn "Не удалось запустить fail2ban. Смотрите: journalctl -u fail2ban -e"
fi

# ---------------------------------------------------------------------------
# 3. Systemd hardening для hysteria-server.service
# ---------------------------------------------------------------------------
if systemctl list-unit-files | grep -q "^${HY2_SERVICE}.service"; then
    log "Добавляю systemd hardening drop-in для ${HY2_SERVICE}..."

    mkdir -p "/etc/systemd/system/${HY2_SERVICE}.service.d"
    cat > "/etc/systemd/system/${HY2_SERVICE}.service.d/override.conf" <<EOF
# Сгенерировано harden.sh — ограничение прав и ресурсов сервиса

[Service]
# Автоперезапуск при падении
Restart=on-failure
RestartSec=3s

# Лимиты
LimitNOFILE=1048576

# Изоляция и ограничение прав
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictRealtime=true
LockPersonality=true
# Разрешаем запись только туда, где лежат сертификаты и конфиг
ReadWritePaths=/etc/hysteria

# Сеть: разрешаем bind на привилегированные порты (443 и т.п.) без root
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
EOF

    systemctl daemon-reload
    systemctl restart "${HY2_SERVICE}"

    if systemctl is-active --quiet "${HY2_SERVICE}"; then
        log "${HY2_SERVICE} перезапущен с hardening-настройками."
    else
        warn "${HY2_SERVICE} не запустился после hardening. Откатите override.conf при необходимости."
        warn "journalctl -u ${HY2_SERVICE} -e"
    fi
else
    warn "Юнит ${HY2_SERVICE}.service не найден — пропускаю systemd hardening (сначала запустите install.sh)."
fi

# ---------------------------------------------------------------------------
# 4. sysctl: BBR и буферы
# ---------------------------------------------------------------------------
log "Настраиваю sysctl (BBR=${ENABLE_BBR}, буферы для UDP/QUIC-нагрузки)..."

BBR_LINES=""
if [[ "$ENABLE_BBR" == "1" ]]; then
    if ! modprobe tcp_bbr 2>/dev/null; then
        warn "Модуль tcp_bbr не загрузился (возможно, уже встроен в ядро) — продолжаю."
    fi
    BBR_LINES=$'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr'
fi

cat > /etc/sysctl.d/99-hysteria-tuning.conf <<EOF
# Сгенерировано harden.sh

${BBR_LINES}

# Увеличенные буферы сокетов (важно для UDP/QUIC при высоком throughput)
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096

net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.udp_mem = 65536 131072 262144

net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1

# Базовое сетевое ужесточение
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
EOF

sysctl --system >/dev/null

CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "н/д")
log "sysctl применён. Текущий congestion control: ${CURRENT_CC}."

# ---------------------------------------------------------------------------
# 5. Управление swap
# ---------------------------------------------------------------------------
manage_swap() {
    local mode="$1"
    local mem_total_mb
    mem_total_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    local has_swap="0"
    [[ $(swapon --show=NAME --noheadings 2>/dev/null | wc -l) -gt 0 ]] && has_swap="1"

    case "$mode" in
        off)
            if [[ "$has_swap" == "1" ]]; then
                log "SWAP_MODE=off — отключаю и удаляю swap..."
                swapoff -a || true
                sed -i '\#^\S\+\s\+none\s\+swap\s#d' /etc/fstab
                [[ -f "$SWAP_FILE" ]] && rm -f "$SWAP_FILE"
                log "Swap отключён."
            else
                log "SWAP_MODE=off — swap уже отсутствует, ничего не делаю."
            fi
            return
            ;;
        auto)
            if [[ "$has_swap" == "1" ]]; then
                log "SWAP_MODE=auto — swap уже настроен, пропускаю."
                return
            fi
            if [[ "$mem_total_mb" -gt 2048 ]]; then
                log "SWAP_MODE=auto — ОЗУ ${mem_total_mb} МБ (>2 ГБ), swap не требуется, пропускаю."
                return
            fi
            log "SWAP_MODE=auto — ОЗУ ${mem_total_mb} МБ, создаю swap..."
            ;;
        on)
            if [[ "$has_swap" == "1" ]]; then
                log "SWAP_MODE=on — существующий swap будет пересоздан."
                swapoff -a || true
                sed -i '\#^\S\+\s\+none\s\+swap\s#d' /etc/fstab
                [[ -f "$SWAP_FILE" ]] && rm -f "$SWAP_FILE"
            fi
            ;;
        *)
            warn "Неизвестное значение SWAP_MODE='$mode' (ожидалось auto/on/off), пропускаю управление swap."
            return
            ;;
    esac

    local size_mb="$SWAP_SIZE_MB"
    if [[ "$size_mb" -le 0 ]]; then
        # эвристика: swap = ОЗУ, но не больше 2048 МБ и не меньше 512 МБ
        size_mb=$mem_total_mb
        [[ "$size_mb" -gt 2048 ]] && size_mb=2048
        [[ "$size_mb" -lt 512 ]] && size_mb=512
    fi

    log "Создаю swap-файл ${SWAP_FILE} размером ${size_mb} МБ..."
    if command -v fallocate >/dev/null 2>&1 && fallocate -l "${size_mb}M" "$SWAP_FILE" 2>/dev/null; then
        :
    else
        dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$size_mb" status=none
    fi
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE" >/dev/null
    swapon "$SWAP_FILE"

    if ! grep -q "^${SWAP_FILE} " /etc/fstab 2>/dev/null; then
        echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
    fi

    # разумные значения для VPS с proxy-нагрузкой
    if ! grep -q '^vm.swappiness' /etc/sysctl.d/99-hysteria-tuning.conf; then
        {
            echo ""
            echo "vm.swappiness = 10"
            echo "vm.vfs_cache_pressure = 50"
        } >> /etc/sysctl.d/99-hysteria-tuning.conf
        sysctl --system >/dev/null
    fi

    log "Swap создан и включён (${size_mb} МБ)."
}

manage_swap "$SWAP_MODE"

# ---------------------------------------------------------------------------
# Итог
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Хардening завершён:"
echo "  Firewall (nftables): SSH ${SSH_PORT}/tcp, Hysteria ${HY2_PORT}/udp"
echo "  Fail2ban: jail sshd, bantime=${FAIL2BAN_BANTIME}, maxretry=${FAIL2BAN_MAXRETRY}"
echo "  Systemd:  override.conf для ${HY2_SERVICE} (если юнит найден)"
echo "  Sysctl:   BBR=${ENABLE_BBR}, congestion control=${CURRENT_CC}"
echo "  Swap:     режим=${SWAP_MODE}"
echo "============================================================"
echo "Проверить статус:"
echo "  nft list ruleset"
echo "  fail2ban-client status sshd"
echo "  systemctl status ${HY2_SERVICE}"
echo "  sysctl net.ipv4.tcp_congestion_control"
echo "  swapon --show"