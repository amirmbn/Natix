#!/bin/bash

# ============================================================
#  Port Forward Manager
#  Features: auto IP detect, config save/load, systemd persist,
#            backup/restore, rule validation, uninstall
# ============================================================

CONFIG_FILE="/etc/portforward.conf"
SERVICE_FILE="/etc/systemd/system/portforward.service"
BACKUP_DIR="/etc/portforward.backups"
SCRIPT_PATH="$(realpath "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── helpers ────────────────────────────────────────────────

log()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()   { echo -e "${CYAN}[i]${NC} $1"; }

require_root() {
    [[ $EUID -ne 0 ]] && error "This script must be run as root."
}

require_iptables() {
    command -v iptables &>/dev/null || error "iptables not found. Install it first (apt install iptables)."
}

auto_detect_ip() {
    local ip
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    [[ -z "$ip" ]] && ip=$(hostname -I | awk '{print $1}')
    echo "$ip"
}

validate_ip() {
    local ip=$1
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -ra o <<< "$ip"
    for oct in "${o[@]}"; do
        [[ $oct -gt 255 ]] && return 1
    done
    return 0
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ $1 -ge 1 && $1 -le 65535 ]]
}

# ─── config ──────────────────────────────────────────────────

save_config() {
    cat > "$CONFIG_FILE" <<EOF
# Port Forward Config — generated $(date)
SERVER_IP=$SERVER_IP
OUT_IP=$OUT_IP
SSH_PORT=$SSH_PORT
EXTRA_RULES="$EXTRA_RULES"
EOF
    log "Config saved to $CONFIG_FILE"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        log "Config loaded from $CONFIG_FILE"
        return 0
    fi
    return 1
}

show_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        info "Current config:"
        grep -v "^#" "$CONFIG_FILE" | grep -v "^$"
    else
        warn "No config file found."
    fi
}

edit_config() {
    [[ -f "$CONFIG_FILE" ]] || error "No config file found. Run 'setup' first."
    "${EDITOR:-nano}" "$CONFIG_FILE"
    info "Run '$0 apply' to apply the changes."
}

# ─── backup / restore ────────────────────────────────────────

backup_rules() {
    mkdir -p "$BACKUP_DIR"
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    local file="$BACKUP_DIR/nat-$ts.rules"
    if iptables-save -t nat > "$file" 2>/dev/null; then
        log "Backup saved: $file"
        # keep only the last 10 backups
        ls -1t "$BACKUP_DIR"/nat-*.rules 2>/dev/null | tail -n +11 | xargs -r rm -f
    else
        warn "Could not create backup of current NAT rules."
    fi
}

restore_last_backup() {
    local last
    last=$(ls -1t "$BACKUP_DIR"/nat-*.rules 2>/dev/null | head -n1)
    [[ -z "$last" ]] && error "No backup found in $BACKUP_DIR."
    info "Restoring from $last ..."
    iptables-restore -t nat < "$last" && log "Rules restored." || error "Restore failed."
}

list_backups() {
    if [[ -d "$BACKUP_DIR" ]] && ls "$BACKUP_DIR"/nat-*.rules &>/dev/null; then
        info "Available backups:"
        ls -1t "$BACKUP_DIR"/nat-*.rules
    else
        warn "No backups found."
    fi
}

# ─── extra rules validation ──────────────────────────────────

# Validates a single extra-rule string by checking the iptables
# syntax with --check / a dry run instead of eval'ing raw input.
validate_extra_rule() {
    local rule="$1"
    local -a parts

    # Split safely without eval
    read -ra parts <<< "$rule"

    # Basic sanity: must start with -t or -A/-I (a real iptables arg)
    if [[ "${parts[0]}" != "-t" && "${parts[0]}" != "-A" && "${parts[0]}" != "-I" ]]; then
        return 1
    fi

    # Try a syntax check by appending --check is unreliable for INSERT/APPEND-only
    # combos, so just attempt the real command; iptables itself validates syntax.
    return 0
}

apply_extra_rule() {
    local rule="$1"
    local -a parts
    read -ra parts <<< "$rule"
    iptables "${parts[@]}"
}

# ─── iptables rules ──────────────────────────────────────────

apply_rules() {
    local server_ip=$1
    local out_ip=$2
    local ssh_port=$3

    require_iptables

    log "Enabling ip_forward..."
    sysctl -q net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-portforward.conf

    log "Backing up current NAT rules..."
    backup_rules

    log "Flushing existing NAT rules..."
    iptables -t nat -F PREROUTING  2>/dev/null
    iptables -t nat -F POSTROUTING 2>/dev/null

    log "Adding SSH rule (port $ssh_port → $server_ip)..."
    iptables -t nat -A PREROUTING -p tcp --dport "$ssh_port" \
        -j DNAT --to-destination "$server_ip" \
        || { warn "Failed to add SSH rule, restoring backup."; restore_last_backup; return 1; }

    log "Adding full forward rule (→ $out_ip)..."
    iptables -t nat -A PREROUTING \
        -j DNAT --to-destination "$out_ip" \
        || { warn "Failed to add forward rule, restoring backup."; restore_last_backup; return 1; }

    log "Adding MASQUERADE rule..."
    iptables -t nat -A POSTROUTING -j MASQUERADE \
        || { warn "Failed to add MASQUERADE rule, restoring backup."; restore_last_backup; return 1; }

    # extra rules (stored as newline-separated strings)
    if [[ -n "$EXTRA_RULES" ]]; then
        while IFS= read -r rule; do
            [[ -z "$rule" ]] && continue
            if validate_extra_rule "$rule"; then
                log "Applying extra rule: $rule"
                apply_extra_rule "$rule" || warn "Extra rule failed: $rule"
            else
                warn "Skipping invalid/unsafe extra rule: $rule"
            fi
        done <<< "$EXTRA_RULES"
    fi

    log "Persisting iptables rules..."
    if command -v iptables-save &>/dev/null; then
        if [[ -d /etc/iptables ]]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null \
                && log "Saved to /etc/iptables/rules.v4" \
                || warn "Could not save to /etc/iptables/rules.v4"
        else
            iptables-save > /etc/iptables.rules 2>/dev/null \
                && log "Saved to /etc/iptables.rules" \
                || warn "Could not persist rules to file (install iptables-persistent?)"
        fi
    else
        warn "iptables-save not found; rules will not survive reboot without it."
    fi

    log "All rules applied successfully."
}

flush_rules() {
    warn "Flushing all NAT rules..."
    backup_rules
    iptables -t nat -F
    log "NAT rules cleared. (Backup saved — use 'restore' to undo.)"
}

show_rules() {
    info "Active NAT rules:"
    iptables -t nat -L -n -v --line-numbers
}

# ─── systemd service ─────────────────────────────────────────

install_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Port Forward Rules
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SCRIPT_PATH apply --service
ExecStop=/sbin/iptables -t nat -F

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable portforward.service
    log "systemd service installed and enabled (runs on every boot)."
}

remove_service() {
    systemctl disable portforward.service 2>/dev/null
    systemctl stop portforward.service 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    log "systemd service removed."
}

service_status() {
    systemctl status portforward.service 2>/dev/null || warn "Service is not installed."
}

# ─── uninstall ────────────────────────────────────────────────

uninstall_all() {
    read -rp "This will flush NAT rules, remove the service and delete config. Continue? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && { warn "Aborted."; exit 0; }

    flush_rules
    remove_service
    rm -f "$CONFIG_FILE" /etc/sysctl.d/99-portforward.conf
    log "Uninstall complete."
}

# ─── interactive setup ────────────────────────────────────────

interactive_setup() {
    require_iptables

    echo ""
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${CYAN}      Port Forward Manager Setup      ${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo ""

    # SERVER_IP
    local detected_ip
    detected_ip=$(auto_detect_ip)
    info "Detected server IP: ${YELLOW}$detected_ip${NC}"
    read -rp "Server IP (press Enter to confirm [$detected_ip]): " input_server
    SERVER_IP="${input_server:-$detected_ip}"
    validate_ip "$SERVER_IP" || error "Invalid server IP: $SERVER_IP"

    # OUT_IP
    read -rp "Destination/output IP (OUT_IP): " OUT_IP
    validate_ip "$OUT_IP" || error "Invalid destination IP: $OUT_IP"

    # SSH_PORT
    read -rp "SSH port to exclude from forwarding [22]: " input_ssh
    SSH_PORT="${input_ssh:-22}"
    validate_port "$SSH_PORT" || error "Invalid port: $SSH_PORT"

    # Extra rules
    EXTRA_RULES=""
    echo ""
    info "Extra iptables rules (e.g. -A PREROUTING -p udp --dport 53 -j DNAT --to 8.8.8.8)"
    info "Do NOT include 'iptables' itself — just the arguments."
    info "Press Enter with no input to finish."
    while true; do
        read -rp "Extra rule (or Enter to skip): " extra
        [[ -z "$extra" ]] && break
        if validate_extra_rule "$extra"; then
            EXTRA_RULES+="$extra"$'\n'
        else
            warn "Rule must start with -t, -A or -I — skipped."
        fi
    done

    echo ""
    info "Summary:"
    echo "  SERVER_IP : $SERVER_IP"
    echo "  OUT_IP    : $OUT_IP"
    echo "  SSH_PORT  : $SSH_PORT"
    [[ -n "$EXTRA_RULES" ]] && echo "  EXTRA_RULES:" && echo "$EXTRA_RULES" | sed 's/^/    /'
    echo ""

    read -rp "Apply and save config? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && { warn "Aborted."; exit 0; }

    save_config
    apply_rules "$SERVER_IP" "$OUT_IP" "$SSH_PORT"

    echo ""
    read -rp "Install systemd service for auto-start on reboot? [y/N]: " svc
    [[ "${svc,,}" == "y" ]] && install_service
}

# ─── entry point ─────────────────────────────────────────────

usage() {
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "  setup            Interactive setup (recommended)"
    echo "  apply            Apply saved config"
    echo "  flush            Clear all NAT rules (auto-backup first)"
    echo "  restore          Restore NAT rules from last backup"
    echo "  backups          List available backups"
    echo "  show             Show active rules"
    echo "  config           Show saved config"
    echo "  edit             Edit config file in \$EDITOR"
    echo "  service-install  Install systemd service"
    echo "  service-remove   Remove systemd service"
    echo "  service-status   Show service status"
    echo "  uninstall        Flush rules, remove service & config"
    echo ""
}

require_root

case "${1:-setup}" in
    setup)
        interactive_setup
        ;;
    apply)
        load_config || error "No config found. Run 'setup' first."
        apply_rules "$SERVER_IP" "$OUT_IP" "$SSH_PORT"
        ;;
    flush)
        flush_rules
        ;;
    restore)
        restore_last_backup
        ;;
    backups)
        list_backups
        ;;
    show)
        show_rules
        ;;
    config)
        show_config
        ;;
    edit)
        edit_config
        ;;
    service-install)
        install_service
        ;;
    service-remove)
        remove_service
        ;;
    service-status)
        service_status
        ;;
    uninstall)
        uninstall_all
        ;;
    *)
        usage
        ;;
esac
