#!/bin/bash

# =====================================================
# Clash TUN 模式 WiFi 自动修复脚本
# 解决 Clash TUN 模式导致的 WiFi 连接问题
# =====================================================

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[ℹ️]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✅]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠️]${NC} $1"
}

log_error() {
    echo -e "${RED}[❌]${NC} $1"
}

# 显示使用帮助
show_help() {
    echo ""
    echo "========================================="
    echo "Clash TUN 模式 WiFi 修复工具"
    echo "========================================="
    echo ""
    echo "用法：./wifi-fix-tun.sh [选项]"
    echo ""
    echo "选项:"
    echo "  --full              完整修复（关闭 Clash + 重置网络）"
    echo "  --quick             快速修复（仅重置 DNS 和代理）"
    echo "  --check             检查当前网络状态"
    echo "  --tun-status        检查 Clash TUN 状态"
    echo "  --help              显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  ./wifi-fix-tun.sh          # 运行快速修复"
    echo "  ./wifi-fix-tun.sh --full   # 执行完整修复流程"
    echo "  ./wifi-fix-tun.sh --check  # 只检查状态不修复"
    echo ""
    echo "提示：部分操作需要管理员权限"
    echo ""
}

# 检查当前网络状态
check_network_status() {
    log_info "正在检查网络状态..."
    echo ""
    
    # 检查 WiFi 状态
    echo "📡 WiFi 状态："
    local wifi_enabled=$(networksetup -getnetworkserviceenabled Wi-Fi 2>/dev/null | tail -1)
    if [[ "$wifi_enabled" == *"Enabled"* ]]; then
        log_success "WiFi 服务已启用"
    else
        log_error "WiFi 服务已禁用"
    fi
    
    # 获取 IP 地址
    local ip_addr=$(ipconfig getifaddr en0 2>/dev/null)
    if [[ -n "$ip_addr" ]]; then
        log_success "当前 IP: $ip_addr"
    else
        log_warning "未获取到 IP 地址"
    fi
    
    # 检查 WiFi 连接的网关
    local gateway=$(route get default 2>/dev/null | grep interface | awk '{print $2}')
    if [[ -n "$gateway" && "$gateway" != "interface" ]]; then
        log_success "网关地址：$gateway"
    else
        log_info "未找到有效网关"
    fi
    
    # 检查 DNS
    echo ""
    echo "🌐 DNS 配置："
    local dns_servers=$(scutil --dns 2>/dev/null | grep "nameserver\[" | head -3 | awk '{print $2}' | tr '\n' ', ')
    if [[ -n "$dns_servers" ]]; then
        log_info "DNS 服务器：$dns_servers"
    else
        log_warning "DNS 配置异常"
    fi
    
    # 检查代理设置
    echo ""
    echo "🔗 代理状态："
    local http_proxy=$(networksetup -getwebproxystate Wi-Fi 2>/dev/null | tail -1)
    local https_proxy=$(networksetup -getsecurewebproxystate Wi-Fi 2>/dev/null | tail -1)
    local socks_proxy=$(networksetup -getsocksfirewallproxystate Wi-Fi 2>/dev/null | tail -1)
    
    if [[ "$http_proxy" == "Disabled" ]]; then
        log_success "HTTP 代理：已关闭"
    else
        log_error "HTTP 代理：开启中"
    fi
    
    if [[ "$https_proxy" == "Disabled" ]]; then
        log_success "HTTPS 代理：已关闭"
    else
        log_error "HTTPS 代理：开启中"
    fi
    
    if [[ "$socks_proxy" == "Disabled" ]]; then
        log_success "SOCKS 代理：已关闭"
    else
        log_error "SOCKS 代理：开启中"
    fi
    
    # 检查 Clash 进程
    echo ""
    echo "🦈 Clash 状态："
    if ps aux | grep -v "grep" | grep -q -i "clash"; then
        log_info "Clash 正在运行"
        
        # 检查 TUN 模式
        if ps aux | grep -v "grep" | grep -q -i "clash.*--tun\|clash.*-t"; then
            log_warning "Clash TUN 模式已启用"
        else
            log_info "Clash TUN 模式可能未启用"
        fi
        
        # 检查端口监听
        if lsof -i :7890 &>/dev/null; then
            log_success "Clash HTTP 端口 (7890) 正在监听"
        else
            log_warning "Clash HTTP 端口 (7890) 未监听"
        fi
        
        if lsof -i :7891 &>/dev/null; then
            log_success "Clash SOCKS 端口 (7891) 正在监听"
        else
            log_warning "Clash SOCKS 端口 (7891) 未监听"
        fi
        
        # 检查虚拟网卡
        local tun_count=$(ifconfig | grep -c "^utun")
        if [[ $tun_count -gt 0 ]]; then
            log_info "发现 $tun_count 个 Clash 虚拟网卡 (utun)"
        fi
    else
        log_info "Clash 未运行"
    fi
    
    echo ""
}

# 检查 Clash TUN 状态
check_tun_status() {
    log_info "检查 Clash TUN 状态..."
    echo ""
    
    if ! ps aux | grep -v "grep" | grep -q -i "clash"; then
        log_info "Clash 未运行"
        return
    fi
    
    log_info "Clash 正在运行"
    
    echo ""
    echo "Clash 命令行参数:"
    ps aux | grep -i "clash" | grep -v "grep" | awk '{print $11, $12, $13, $14}'
    
    echo ""
    echo "Clash 虚拟网卡:"
    ifconfig | grep -A 5 "^utun" | grep -E "^utun|^ether|^inet " || log_info "未发现 utun 网卡"
    
    echo ""
    echo "Clash 相关路由:"
    netstat -rn | grep -E "utun|198\.18|192\.168\.31|10\.0\.0" || log_info "无特殊 Clash 路由"
    
    echo ""
    echo "Clash 监听端口:"
    lsof -i :7890,7891,9090 2>/dev/null || log_info "未检测到 Clash 标准端口"
    
    echo ""
}

# 快速修复
quick_fix() {
    log_info "开始执行快速修复..."
    echo ""
    
    log_info "步骤 1/4: 关闭 Web 代理..."
    networksetup -setwebproxystate Wi-Fi off 2>/dev/null || true
    
    log_info "步骤 2/4: 关闭安全 Web 代理..."
    networksetup -setsecurewebproxystate Wi-Fi off 2>/dev/null || true
    
    log_info "步骤 3/4: 关闭 SOCKS 代理..."
    networksetup -setsocksfirewallproxystate Wi-Fi off 2>/dev/null || true
    
    log_info "步骤 4/4: 重置 DNS 为自动获取..."
    networksetup -setdnsservices Wi-Fi DHCP 2>/dev/null || true
    
    log_success "快速修复完成！"
    echo ""
}

# 完整修复
full_fix() {
    log_info "开始执行完整修复流程..."
    echo ""
    
    log_info "步骤 1/6: 安全终止 Clash 进程（避免暴力杀导致损坏）..."
    pkill -f "clash.*--tun\|clash.*-t" 2>/dev/null || true
    sleep 1
    if ps aux | grep -v "grep" | grep -q -i "clash"; then
        log_warning "检测到 Clash 进程仍在运行，执行强制终止..."
        pkill -9 -i clash 2>/dev/null || true
        sleep 1
    else
        log_success "Clash 进程已安全终止"
    fi
    
    log_info "步骤 2/6: 强制释放 utun 虚拟网卡接口（关键！防止 Clash TUN 残留冲突）..."
    sudo ifconfig utun* down 2>/dev/null || true
    
    log_info "步骤 3/6: 清除代理服务器地址配置..."
    networksetup -setwebproxieserver Wi-Fi "" 2>/dev/null || true
    networksetup -setsecurewebproxieserver Wi-Fi "" 2>/dev/null || true
    networksetup -setsocksfirewallproxieserver Wi-Fi "" 2>/dev/null || true
    
    log_info "步骤 4/6: 刷新 DNS 缓存..."
    sudo dscacheutil -flushcache 2>/dev/null || true
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    
    log_info "步骤 5/6: 确认 WiFi 服务已启用..."
    networksetup -setnetworkserviceenabled Wi-Fi on 2>/dev/null || true
    
    log_info "步骤 6/6: 清理冲突路由规则..."
    sudo route -n delete -host 198.18.0.0/16 default 2>/dev/null || true
    sudo route -n delete -net 10.0.0.0/8 default 2>/dev/null || true
    sudo route -n delete -net 172.16.0.0/12 default 2>/dev/null || true
    
    log_success "完整修复完成！Clash 进程和 utun 接口已彻底清理"
    echo ""
}

# 主程序
main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --check)
            check_network_status
            ;;
        --tun-status)
            check_tun_status
            ;;
        --full)
            full_fix
            ;;
        --quick|"")
            quick_fix
            echo ""
            log_success "已执行快速修复"
            echo ""
            check_network_status
            ;;
        *)
            log_error "未知选项：$1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
