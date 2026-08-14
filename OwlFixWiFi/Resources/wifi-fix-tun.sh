#!/bin/bash

# OwlFixWiFi 安全命令行辅助工具
# 自动模式只清理由“本地端口已经失效”确认的代理残留，不会关闭正在工作的 Clash。

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[ℹ️]${NC} $1"; }
log_success() { echo -e "${GREEN}[✅]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠️]${NC} $1"; }
log_error() { echo -e "${RED}[❌]${NC} $1"; }

show_help() {
    echo "OwlFixWiFi 安全网络检查工具"
    echo ""
    echo "用法：./wifi-fix-tun.sh [--check|--quick|--tun-status|--full|--help]"
    echo "  --check       只检查 Wi-Fi、Clash、TUN、代理与 DNS"
    echo "  --quick       仅清理已确认失效的本地代理/Fake-IP DNS 残留"
    echo "  --tun-status  检查 Mihomo 核心与 Clash 专属 TUN 路由"
    echo "  --full        打开 OwlFixWiFi；深度修复必须在应用中手动授权"
}

clash_core_running() {
    if [[ -S /tmp/verge/verge-mihomo.sock ]] && \
       /usr/bin/curl --unix-socket /tmp/verge/verge-mihomo.sock -fsS --max-time 2 http://localhost/version >/dev/null 2>&1; then
        return 0
    fi

    local name
    for name in verge-mihomo mihomo clash-meta clash-premium sing-box; do
        if /usr/bin/pgrep -x "$name" >/dev/null 2>&1; then return 0; fi
    done
    return 1
}

proxy_output() {
    case "$1" in
        HTTP) networksetup -getwebproxy Wi-Fi 2>/dev/null ;;
        HTTPS) networksetup -getsecurewebproxy Wi-Fi 2>/dev/null ;;
        SOCKS) networksetup -getsocksfirewallproxy Wi-Fi 2>/dev/null ;;
    esac
}

proxy_enabled() {
    proxy_output "$1" | awk -F': ' '$1 == "Enabled" {print $2; exit}' | grep -q '^Yes$'
}

proxy_endpoint() {
    proxy_output "$1" | awk -F': ' '$1 == "Server" {server=$2} $1 == "Port" {port=$2} END {print server ":" port}'
}

disable_proxy() {
    case "$1" in
        HTTP) networksetup -setwebproxystate Wi-Fi off ;;
        HTTPS) networksetup -setsecurewebproxystate Wi-Fi off ;;
        SOCKS) networksetup -setsocksfirewallproxystate Wi-Fi off ;;
    esac
}

check_proxy() {
    local kind="$1"
    if ! proxy_enabled "$kind"; then
        log_info "$kind 代理：已关闭"
        return
    fi

    local endpoint host port
    endpoint=$(proxy_endpoint "$kind")
    host=${endpoint%:*}
    port=${endpoint##*:}
    if [[ "$host" == "127.0.0.1" || "$host" == "localhost" || "$host" == "::1" ]]; then
        if /usr/bin/nc -z -w 1 127.0.0.1 "$port" >/dev/null 2>&1; then
            log_success "$kind 代理：$endpoint 正常监听（有效配置）"
        else
            log_warning "$kind 代理：$endpoint 未监听（失效残留）"
        fi
    else
        log_info "${kind} 代理：${endpoint}（手动/单位代理，不自动修改）"
    fi
}

check_network_status() {
    log_info "检查 Wi-Fi、Clash 与代理链路"
    local ip gateway dns
    ip=$(ipconfig getifaddr en0 2>/dev/null || true)
    gateway=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')
    dns=$(networksetup -getdnsservers Wi-Fi 2>/dev/null | tr '\n' ' ')

    if [[ -z "$ip" ]]; then
        log_error "Wi-Fi 未获取到 IP"
    elif [[ "$ip" == 169.254.* ]]; then
        log_error "Wi-Fi 仅取得自分配 IP：${ip}（DHCP 失败）"
    else
        log_success "Wi-Fi IP：${ip}；网关：${gateway:-未知}"
    fi
    log_info "Wi-Fi DNS：${dns:-自动获取}"

    check_proxy HTTP
    check_proxy HTTPS
    check_proxy SOCKS

    if clash_core_running; then
        log_success "Mihomo 核心可响应"
    else
        log_warning "Mihomo 核心未运行或控制接口无响应"
    fi

    if route -n get 198.18.0.1 2>/dev/null | grep -q 'interface: utun'; then
        log_success "Clash Fake-IP TUN 路由已启用"
    else
        log_info "未检测到 Clash Fake-IP TUN 路由"
    fi
}

repair_proxy_if_residual() {
    local kind="$1"
    if ! proxy_enabled "$kind"; then return 0; fi

    local endpoint host port
    endpoint=$(proxy_endpoint "$kind")
    host=${endpoint%:*}
    port=${endpoint##*:}

    if [[ "$host" != "127.0.0.1" && "$host" != "localhost" && "$host" != "::1" ]]; then
        log_warning "${kind} 为手动/单位代理 ${endpoint}，已保护不修改"
        return 0
    fi
    if /usr/bin/nc -z -w 1 127.0.0.1 "$port" >/dev/null 2>&1; then
        log_success "$kind 代理 $endpoint 正常工作，已保留"
        return 0
    fi

    if disable_proxy "$kind" >/dev/null 2>&1 && ! proxy_enabled "$kind"; then
        log_success "已关闭失效的 $kind 代理 $endpoint"
        return 0
    fi
    log_error "$kind 代理关闭失败"
    return 1
}

quick_fix() {
    log_info "执行安全快速修复"
    local failed=0
    repair_proxy_if_residual HTTP || failed=1
    repair_proxy_if_residual HTTPS || failed=1
    repair_proxy_if_residual SOCKS || failed=1

    local dns
    dns=$(networksetup -getdnsservers Wi-Fi 2>/dev/null || true)
    if [[ "$dns" == *"198.18."* || "$dns" == *"198.19."* ]]; then
        if clash_core_running; then
            log_success "Fake-IP DNS 正由 Clash 使用，已保留"
        elif networksetup -setdnsservers Wi-Fi Empty >/dev/null 2>&1; then
            log_success "已清除 Clash 停止后的 Fake-IP DNS 残留"
        else
            log_error "Fake-IP DNS 清理失败"
            failed=1
        fi
    else
        log_info "未发现 Fake-IP DNS 残留"
    fi

    if [[ $failed -eq 0 ]]; then
        log_success "快速修复完成并通过校验"
    else
        log_error "快速修复未完全成功"
        return 1
    fi
}

open_full_fix() {
    log_warning "深度/TUN 修复会操作 root 权限的 Mihomo 与系统网络服务，不能在脚本中静默冒充成功。"
    log_info "已尝试后台打开 OwlFixWiFi，请在应用中手动选择对应修复并完成一次系统授权。"
    open -g -a OwlFixWiFi >/dev/null 2>&1 || true
}

main() {
    case "${1:-}" in
        --help|-h) show_help ;;
        --check|--tun-status) check_network_status ;;
        --full) open_full_fix ;;
        --quick|"") quick_fix; check_network_status ;;
        *) log_error "未知选项：$1"; show_help; return 1 ;;
    esac
}

main "$@"
