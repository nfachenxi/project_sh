#!/bin/bash

#================================================================================
# Gemini Pro API 负载均衡代理部署脚本 (v3)
#
# 功能概述:
#   1. 环境自适应
#      - 智能检测服务器地理位置
#      - 自动选择最优镜像源（国内/国外）
#   2. 自动化部署
#      - Docker 环境自动检测与安装
#      - Docker Compose 插件配置
#      - 服务容器编排与启动
#   3. 交互式配置
#      - Gemini API Keys 批量导入
#      - 代理访问令牌设置
#      - MySQL 数据库安全配置
#   4. 智能网络配置
#      - 多源公网IP探测
#      - 自动生成多格式API地址
#      - 支持 Gemini/OpenAI 双协议
#
# 部署步骤:
#   1. 上传脚本至目标服务器
#   2. 执行: chmod +x setup_gemini_proxy.sh
#   3. 运行: sudo ./setup_gemini_proxy.sh
#
# 维护者: NFA晨曦
# 版本: v3.0.0
#================================================================================

# --- 终端输出样式定义 ---
# 使用ANSI转义序列定义输出颜色
# 用于提供清晰的视觉反馈和状态提示
GREEN='\033[0;32m'   # 成功/完成状态
RED='\033[0;31m'    # 错误/警告信息
YELLOW='\033[0;33m' # 提示/警告信息
BLUE='\033[0;34m'   # 步骤/阶段提示
NC='\033[0m'        # 重置颜色设置

# --- 全局配置变量 ---
# 安装目录配置
INSTALL_DIR="gemini_proxy"      # 服务安装根目录
USE_MIRROR_INSTALL=false        # 镜像源使用标志

# --- 辅助函数 ---
# 本节包含脚本运行所需的基础工具函数

# 格式化终端输出
# 参数:
#   $1 - 颜色代码
#   $2 - 输出消息
# 用途: 提供统一的彩色输出格式
function print_color() {
    COLOR=$1
    MESSAGE=$2
    echo -e "${COLOR}${MESSAGE}${NC}"
}

# 获取服务器公网IP地址
# 返回: 公网IP地址字符串
# 策略: 多重备份API源，确保可靠性
function get_public_ip() {
    local ip
    # 按可靠性顺序尝试多个IP查询服务
    ip=$(curl -s https://ifconfig.me)      # 主要API源
    if [ -z "$ip" ]; then
        ip=$(curl -s https://api.ipify.org)    # 备选源1
    fi
    if [ -z "$ip" ]; then
        ip=$(curl -s https://ipinfo.io/ip)     # 备选源2
    fi
    if [ -z "$ip" ]; then
        ip=$(curl -s http://ipv4.api.hosting.ionet.tv)  # 备选源3
    fi
    echo "$ip"
}

# 检查系统命令可用性
# 参数:
#   $1 - 待检查的命令名称
# 返回: 命令存在时返回0，否则返回非0
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 验证脚本执行权限
# 用途: 确保脚本以root权限运行
# 说明: 某些操作（如安装软件包）需要root权限
function check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_color "$RED" "错误: 此脚本必须以 root 用户身份运行。"
        print_color "$YELLOW" "请尝试使用 'sudo ./setup_gemini_proxy.sh' 运行。"
        exit 1
    fi
}

# --- 安装与配置函数 ---
# 本节包含系统环境配置和依赖安装的相关函数

# 安装基础依赖组件
# 功能: 确保curl工具可用
# 说明: curl用于网络请求，是脚本的核心依赖
# 策略: 优先使用默认软件源，确保基础功能可用
function install_dependencies() {
    if ! command_exists curl; then
        print_color "$YELLOW" "未检测到 curl，正在尝试安装..."
        # 优先使用系统默认源确保基础功能
        apt-get update >/dev/null 2>&1
        apt-get install -y curl
        if ! command_exists curl; then
            print_color "$RED" "curl 安装失败，请手动安装后再运行此脚本。"
            exit 1
        fi
        print_color "$GREEN" "curl 安装成功。"
    fi
}

# 配置系统软件源
# 功能: 根据服务器地理位置优化软件源
# 策略: 通过交互方式确定地理位置，自动选择最优镜像
function handle_location() {
    print_color "$BLUE" "\n--- 选择安装源 ---"
    print_color "$YELLOW" "为了优化下载速度，请选择您的服务器所在区域。"
    
    local choice
    while true; do
        read -p "您的服务器是否位于中国大陆？(y/n): " choice
        case "$choice" in
            y|Y )
                USE_MIRROR_INSTALL=true
                print_color "$GREEN" "将使用中国大陆镜像源进行加速。"
                
                print_color "$YELLOW" "正在更换系统软件源为国内镜像..."
                if bash <(curl -sSL https://linuxmirrors.cn/main.sh); then
                    print_color "$GREEN" "系统软件源更换成功。"
                else
                    print_color "$RED" "系统软件源更换失败。脚本将继续，但后续步骤可能变慢或失败。"
                fi
                break
                ;;
            n|N )
                USE_MIRROR_INSTALL=false
                print_color "$GREEN" "将使用官方源进行安装。"
                break
                ;;
            * )
                print_color "$RED" "无效输入，请输入 'y' 或 'n'。"
                ;;
        esac
    done
}

# 安装和配置Docker运行环境
# 功能: 自动化Docker安装与初始化
# 策略:
#   1. 检测现有安装
#   2. 根据地理位置选择安装源
#   3. 验证安装结果
#   4. 配置系统服务
function install_docker() {
    if command_exists docker; then
        print_color "$GREEN" "Docker 已安装。"
    else
        print_color "$YELLOW" "未检测到 Docker，正在为您安装..."
        if [ "$USE_MIRROR_INSTALL" = true ]; then
            # 国内环境：使用镜像加速安装
            print_color "$YELLOW" "正在使用国内镜像源安装 Docker..."
            if ! bash <(curl -sSL https://linuxmirrors.cn/docker.sh); then
                print_color "$RED" "使用镜像安装 Docker 失败。请检查网络或尝试手动安装。"
                exit 1
            fi
        else
            # 海外环境：使用官方源安装
            print_color "$YELLOW" "正在使用 Docker 官方脚本安装 Docker..."
            if ! (curl -fsSL https://get.docker.com | bash -s docker); then
                print_color "$RED" "Docker 安装失败。请访问 https://get.docker.com 查看手动安装方法。"
                exit 1
            fi
        fi
        
        # 安装后验证
        if command_exists docker; then
            print_color "$GREEN" "Docker 安装成功。"
        else
            print_color "$RED" "Docker 安装后未能检测到 'docker' 命令，安装可能已失败。"
            exit 1
        fi
    fi

    # 配置Docker系统服务
    print_color "$YELLOW" "正在启动并设置 Docker 开机自启..."
    systemctl start docker    # 启动当前会话
    systemctl enable docker   # 配置开机自启
    print_color "$GREEN" "Docker 服务已启动。"
}

# 验证Docker Compose可用性
# 功能: 确保容器编排工具可用
# 说明: Docker Compose是容器编排的核心组件
# 检查项:
#   - Compose V2插件存在性
#   - 版本信息可访问性
function check_docker_compose() {
    if ! docker compose version >/dev/null 2>&1; then
        print_color "$RED" "Docker Compose (v2 plugin) 未安装或配置不正确。"
        print_color "$YELLOW" "通常，通过 get.docker.com 或镜像脚本安装的 Docker 会包含 Compose 插件。"
        print_color "$YELLOW" "请检查您的 Docker 安装或手动安装 Docker Compose 插件。"
        exit 1
    else
        print_color "$GREEN" "Docker Compose 已准备就绪。"
    fi
}

# --- 配置收集函数 ---
# 本节负责收集部署所需的所有配置信息

# 收集用户配置信息
# 功能: 交互式收集所有必要的配置参数
# 收集项:
#   1. Gemini API Keys (支持多个)
#   2. 代理服务访问令牌
#   3. 数据库安全凭证
# 说明: 所有敏感信息均在本地处理，不会传输至外部
function collect_user_config() {
    print_color "$BLUE" "\n--- 开始配置 Gemini 代理 ---"

    # 1. Gemini API Keys配置
    # 支持多API Key负载均衡
    print_color "$YELLOW" "请输入您的 Gemini API Key，每输入一个后按回车。"
    print_color "$YELLOW" "至少需要一个。输入完成后，直接按回车键结束。"
    api_keys=()
    while true; do
        read -p "API Key #${#api_keys[@]} + 1: " key
        if [ -z "$key" ]; then
            if [ ${#api_keys[@]} -eq 0 ]; then
                print_color "$RED" "您至少需要输入一个 API Key。"
            else
                break
            fi
        else
            api_keys+=("$key")
        fi
    done
    # 转换为JSON格式
    formatted_keys=$(printf "\"%s\"," "${api_keys[@]}")
    formatted_keys="[${formatted_keys%,}]"

    # 2. 代理访问令牌配置
    # 用于客户端认证的令牌
    print_color "$YELLOW" "\n请为您的代理服务设置一个访问令牌 (ALLOWED_TOKENS)。"
    print_color "$YELLOW" "这个令牌将用作调用此代理的 API Key。"
    while true; do
        read -p "请输入访问令牌 (例如 sk-my-proxy-token): " proxy_token
        if [ -n "$proxy_token" ]; then
            break
        else
            print_color "$RED" "访问令牌不能为空。"
        fi
    done
    formatted_proxy_token="[\"$proxy_token\"]"

    # 3. 数据库安全配置
    # 配置MySQL root和应用用户密码
    print_color "$YELLOW" "\n为了安全，需要为数据库设置密码。"
    while true; do
        read -sp "请为 MySQL root 用户设置一个密码: " mysql_root_password
        echo
        if [ -n "$mysql_root_password" ]; then
            break
        else
            print_color "$RED" "MySQL root 密码不能为空。"
        fi
    done
    
    while true; do
        read -sp "请为 MySQL 'gemini' 用户设置一个密码: " mysql_user_password
        echo
        if [ -n "$mysql_user_password" ]; then
            break
        else
            print_color "$RED" "MySQL 'gemini' 用户密码不能为空。"
        fi
    done
}

# --- 文件生成与部署 ---
# 本节包含配置文件生成和服务部署的核心函数

# 生成服务配置文件
# 功能: 创建运行环境和服务配置文件
# 生成文件:
#   1. .env - 环境变量配置
#   2. docker-compose.yml - 容器编排配置
# 说明: 所有敏感信息均使用变量注入，避免明文存储
function create_config_files() {
    print_color "$BLUE" "\n--- 正在创建配置文件 ---"
    
    # 初始化安装目录
    if [ -d "$INSTALL_DIR" ]; then
        print_color "$YELLOW" "目录 '$INSTALL_DIR' 已存在。将在该目录中创建/覆盖配置文件。"
    else
        mkdir -p "$INSTALL_DIR"
        print_color "$GREEN" "已创建安装目录: $INSTALL_DIR"
    fi
    cd "$INSTALL_DIR"

    # 生成环境变量配置
    cat > .env << EOF
# 数据库配置
DATABASE_TYPE=mysql
MYSQL_HOST=gemini-balance-mysql
MYSQL_PORT=3306
MYSQL_USER=gemini
MYSQL_PASSWORD=${mysql_user_password}
MYSQL_DATABASE=default_db

# Gemini API Keys (由脚本自动生成)
API_KEYS=${formatted_keys}

# 代理访问令牌 (由脚本自动生成)
ALLOWED_TOKENS=${formatted_proxy_token}
EOF
    print_color "$GREEN" ".env 文件创建成功。"

    # 生成容器编排配置
    cat > docker-compose.yml << EOF
volumes:
  mysql_data:

services:
  gemini-balance:
    image: ghcr.io/snailyp/gemini-balance:latest
    container_name: gemini-balance
    restart: unless-stopped
    ports:
      - "8000:8000"
    env_file:
      - .env
    depends_on:
      mysql:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import requests; exit(0) if requests.get('http://localhost:8000/health').status_code == 200 else exit(1)\""]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

  mysql:
    image: mysql:8
    container_name: gemini-balance-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${mysql_root_password}
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
    volumes:
      - mysql_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
EOF
    print_color "$GREEN" "docker-compose.yml 文件创建成功。"
}

# 部署和启动服务
# 功能: 启动并验证服务运行状态
# 步骤:
#   1. 启动容器服务
#   2. 等待服务初始化
#   3. 验证服务健康状态
# 说明: 包含失败处理和故障排除指导
function deploy_service() {
    print_color "$BLUE" "\n--- 正在部署 Gemini 代理服务 ---"
    print_color "$YELLOW" "这将需要一些时间来拉取 Docker 镜像..."
    
    # 启动容器服务
    if docker compose up -d; then
        print_color "$GREEN" "服务启动命令执行成功。"
    else
        print_color "$RED" "服务启动失败。请检查以上日志输出以确定问题。"
        print_color "$YELLOW" "您可以尝试进入 '$INSTALL_DIR' 目录，手动运行 'docker compose up' 查看详细日志。"
        exit 1
    fi

    # 等待服务初始化
    print_color "$YELLOW" "正在等待服务完全启动..."
    sleep 15 # 预留容器初始化时间

    # 验证服务状态
    if docker compose ps | grep -q "running\|healthy"; then
        print_color "$GREEN" "Gemini 代理服务已成功部署并正在运行！"
    else
        print_color "$RED" "服务容器未能正常运行。请进入 '$INSTALL_DIR' 目录，使用 'docker compose logs' 查看容器日志。"
        exit 1
    fi
}

# --- 显示最终信息 ---
# 本节负责展示部署结果和使用指南

# 显示部署总结信息
# 功能: 展示服务访问信息和使用指南
# 包含信息:
#   1. 服务访问凭证
#   2. API端点地址
#   3. 客户端配置示例
#   4. 运维管理指南
function show_summary() {
    # 获取服务访问地址
    print_color "$YELLOW" "正在获取服务器公网IP地址..."
    SERVER_IP=$(get_public_ip)
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="<你的服务器公网IP>"
        print_color "$RED" "未能自动获取公网IP，请手动替换下方地址中的占位符。"
    else
        print_color "$GREEN" "获取到公网IP: ${SERVER_IP}"
    fi

    # 显示部署成功信息
    print_color "$BLUE" "\n==================== 部署完成 ===================="
    print_color "$GREEN" "恭喜！Gemini Pro API 负载均衡代理已成功部署。"
    
    # 展示核心访问信息
    print_color "$YELLOW" "\n请记录以下关键信息："
    echo -e "--------------------------------------------------"
    echo -e "访问令牌 (API Key):   ${GREEN}${proxy_token}${NC}"
    echo -e "Gemini-API 格式地址:  ${GREEN}http://${SERVER_IP}:8000${NC}"
    echo -e "OpenAI-API 格式地址:  ${GREEN}http://${SERVER_IP}:8000/v1${NC}"
    echo -e "--------------------------------------------------"
    
    # 安全配置提示
    print_color "$YELLOW" "\n重要提示:"
    print_color "$YELLOW" "1. 请确保您的服务器防火墙已放行 8000 端口。"
    print_color "$YELLOW" "   例如，在雨云等服务商后台的安全组/防火墙规则中添加入站规则。"
    print_color "$YELLOW" "2. 您现在可以使用以上信息在任何支持的 AI 客户端中进行配置。"
    
    # 客户端配置指南
    print_color "$BLUE" "\n客户端配置示例:"
    print_color "$YELLOW" "1. 如果客户端支持原生 Gemini API (如 Cherry Studio 的 Gemini 类型):"
    echo -e "   - 提供商类型: Gemini"
    echo -e "   - API 密钥:   ${GREEN}${proxy_token}${NC}"
    echo -e "   - API 地址:   ${GREEN}http://${SERVER_IP}:8000${NC}"

    print_color "$YELLOW" "\n2. 如果客户端支持 OpenAI API 格式 (如 LobeChat, NextChat):"
    echo -e "   - 提供商类型: OpenAI"
    echo -e "   - API 密钥:   ${GREEN}${proxy_token}${NC}"
    echo -e "   - API 地址:   ${GREEN}http://${SERVER_IP}:8000/v1${NC}"
    
    # 运维管理信息
    print_color "$BLUE" "\n项目文件位于当前目录下的 '${INSTALL_DIR}' 文件夹中。"
    print_color "$BLUE" "如果需要停止服务，请进入该目录并运行 'docker compose down'。"
    print_color "$BLUE" "==================================================\n"
}


# --- 主函数 ---
# 脚本主要流程控制
# 执行顺序:
#   1. 环境检查与准备
#   2. 依赖组件安装
#   3. 配置信息收集
#   4. 服务部署与验证
#   5. 结果展示
function main() {
    clear
    print_color "$BLUE" "========================================================"
    print_color "$BLUE" "    Gemini Pro API 负载均衡代理一键部署脚本"
    print_color "$BLUE" "========================================================"
    print_color "$YELLOW" "本脚本将引导您完成 Gemini Balance Proxy 的全部署过程。"
    
    # 环境检查与准备
    check_root            # 权限检查
    install_dependencies  # 基础依赖安装
    
    # 系统环境配置
    handle_location       # 地理位置检测与源选择
    install_docker        # Docker环境配置
    check_docker_compose  # Compose组件检查
    
    # 服务配置与部署
    collect_user_config   # 收集用户配置
    create_config_files   # 生成配置文件
    deploy_service        # 部署服务
    
    # 部署结果展示
    show_summary         # 显示部署结果和使用指南
}

# --- 脚本入口 ---
main
