#!/bin/bash

#================================================================================
# PMail 个人域名邮箱一键部署脚本 (v1.5)
#
# 功能:
#   - 自动化环境准备 (Docker, Docker Compose)
#   - 为国内用户优化下载源和镜像
#   - 交互式引导配置域名、SSL证书和数据库
#   - 动态生成配置文件，引导用户进入网页安装向导
#   - 提供专业的部署后指南，包括 PTR 记录设置和邮件评分优化建议
#
# 技术栈:
#   - Docker 容器化部署
#   - Docker Compose 多容器编排
#   - 支持 SQLite/MySQL 数据库
#   - 自动配置 SMTP/IMAP/POP3 服务
#
# 更新 (v1.5):
#   - 最终优化：修复了指南部分颜色代码无法正确解析导致输出混乱的问题。
#
# 使用方法:
#   1. 将此脚本上传到你的服务器
#   2. 运行 chmod +x setup_pmail.sh
#   3. 运行 sudo ./setup_pmail.sh
#
# 系统要求:
#   - Linux 系统 (Debian/Ubuntu/CentOS)
#   - Root 权限
#   - 开放端口: 25, 80, 443, 110, 465, 587, 993, 995
#
# 作者: NFA晨曦
#================================================================================

#==============================================================================
# 颜色定义
# 用于终端输出着色，提高用户体验和可读性
#==============================================================================
GREEN='\033[0;32m'  # 成功信息、完成提示
RED='\033[0;31m'    # 错误信息、警告提示
YELLOW='\033[0;33m' # 注意事项、重要提示
BLUE='\033[0;34m'   # 阶段标题、分隔信息
NC='\033[0m'        # 恢复默认颜色

#==============================================================================
# 全局变量
# 定义脚本运行所需的关键配置参数
#==============================================================================
# 安装目录 - 统一安装到/root目录下，方便管理和权限控制
INSTALL_DIR="/root/pmail" 

# Docker Compose 命令 - 用于存储检测到的正确命令格式（支持新旧两种版本）
DOCKER_COMPOSE_CMD="" 

# PMail 镜像地址 - 默认使用官方最新版本，可根据地区自动切换加速源
PMAIL_IMAGE="ghcr.io/jinnrry/pmail:latest"

#==============================================================================
# 辅助函数
# 提供基础工具函数，用于输出格式化、系统检查和网络操作
#==============================================================================

# 彩色输出函数
# 功能:
#   - 以指定颜色输出文本信息到终端
#   - 自动恢复默认颜色，避免颜色污染
# 参数:
#   - $1: 颜色代码变量 (GREEN/RED/YELLOW/BLUE)
#   - $2: 要显示的消息文本
# 用法示例:
#   print_color "$GREEN" "操作成功"
function print_color() {
    COLOR=$1
    MESSAGE=$2
    echo -e "${COLOR}${MESSAGE}${NC}"
}

# 获取服务器公网 IP 地址
# 功能:
#   - 通过多个公共 API 获取当前服务器的公网 IP
#   - 具有容错机制，按优先级尝试多个服务
# 返回:
#   - 成功: 输出服务器公网 IP 地址
#   - 失败: 空字符串
# 策略:
#   - 优先使用 ifconfig.me
#   - 备选 api.ipify.org
#   - 最后尝试 ipinfo.io/ip
function get_public_ip() {
    local ip
    ip=$(curl -s https://ifconfig.me)
    [ -z "$ip" ] && ip=$(curl -s https://api.ipify.org)
    [ -z "$ip" ] && ip=$(curl -s https://ipinfo.io/ip)
    echo "$ip"
}

# 检查命令是否存在
# 功能:
#   - 验证指定命令是否可在系统中执行
# 参数:
#   - $1: 要检查的命令名称
# 返回:
#   - 命令存在: 返回 0 (成功)
#   - 命令不存在: 返回非 0 值 (失败)
# 用法示例:
#   if command_exists docker; then
#       # Docker 已安装的处理逻辑
#   fi
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查 root 权限
# 功能:
#   - 验证脚本是否以 root 用户身份运行
#   - 非 root 用户运行时给出明确提示并退出
# 错误处理:
#   - 非 root 用户: 显示错误信息并以状态码 1 退出
# 注意:
#   - 此函数用于确保脚本有足够权限执行系统级操作
#   - 如安装软件包、配置系统服务等
function check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_color "$RED" "错误: 此脚本必须以 root 用户身份运行。"
        print_color "$YELLOW" "请尝试使用 'sudo ./setup_pmail.sh' 运行。"
        exit 1
    fi
}

#==============================================================================
# 阶段一：环境准备
# 负责检查和配置运行 PMail 所需的基础环境
#==============================================================================

# 检查并设置 Docker Compose 命令
# 功能:
#   - 检测系统中可用的 Docker Compose 版本
#   - 支持新版插件模式 (docker compose) 和传统独立模式 (docker-compose)
#   - 设置全局变量以统一后续命令调用格式
# 检测策略:
#   - 优先检查新版插件模式 (docker compose)
#   - 其次检查传统独立模式 (docker-compose)
# 全局变量:
#   - 设置 DOCKER_COMPOSE_CMD 为检测到的正确命令格式
# 错误处理:
#   - 两种模式都不存在时给出明确错误提示并退出
function check_docker_compose() {
    print_color "$YELLOW" "正在检查 Docker Compose..."
    if docker compose version >/dev/null 2>&1; then
        print_color "$GREEN" "检测到 Docker Compose 插件 (docker compose)。"
        DOCKER_COMPOSE_CMD="docker compose"
    elif command_exists docker-compose; then
        print_color "$GREEN" "检测到旧版 Docker Compose (docker-compose)。"
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        print_color "$RED" "错误: 未能找到 Docker Compose。"
        print_color "$YELLOW" "请确保你的 Docker 安装包含了 Compose 插件，或手动安装它。"
        exit 1
    fi
}

# 环境准备主函数
# 功能:
#   - 检查并确保 root 权限
#   - 安装基础依赖工具
#   - 根据地区优化镜像源
#   - 安装并配置 Docker 环境
# 错误处理:
#   - Docker 安装失败时提供明确错误信息并退出
#   - 无效输入时提供重试机会
# 优化策略:
#   - 为中国大陆用户提供多种镜像加速选项
#   - 使用国内专用安装脚本提高成功率
function phase_1_prepare_environment() {
    print_color "$BLUE" "--- 阶段一：开始准备服务器环境 ---"
    check_root

    # 安装基础依赖
    if ! command_exists curl; then
        print_color "$YELLOW" "正在安装 curl..."
        apt-get update >/dev/null && apt-get install -y curl
    fi

    # 地区检测与镜像优化
    read -p "你的服务器是否位于中国大陆？(y/n, 默认 n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        print_color "$YELLOW" "检测到你位于国内，将为 Docker 及 PMail 镜像启用加速..."
        
        # 为中国大陆用户提供镜像加速选项
        print_color "$YELLOW" "请为 PMail 镜像选择一个加速器 (ghcr.io):"
        echo "1) ghproxy.com (通用代理, 速度可能不稳定)"
        echo "2) ghcr.nju.edu.cn (南京大学镜像, 推荐)"
        echo "3) mirror.ghcr.io (Cloudflare 镜像)"
        while true; do
            read -p "请输入选项 [1-3] (默认 2): " mirror_choice
            mirror_choice=${mirror_choice:-2}
            case "$mirror_choice" in
                1) PMAIL_IMAGE="ghproxy.com/ghcr.io/jinnrry/pmail:latest"; break ;;
                2) PMAIL_IMAGE="ghcr.nju.edu.cn/jinnrry/pmail:latest"; break ;;
                3) PMAIL_IMAGE="mirror.ghcr.io/jinnrry/pmail:latest"; break ;;
                *) print_color "$RED" "无效输入，请输入 1, 2 或 3。" ;;
            esac
        done
        print_color "$GREEN" "已选择镜像: ${PMAIL_IMAGE}"

        # 使用国内镜像安装 Docker
        if ! command_exists docker; then
            bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
        fi
    else
        # 使用官方源安装 Docker
        if ! command_exists docker; then
            curl -fsSL https://get.docker.com | bash
        fi
    fi
    
    # 安装结果验证
    if ! command_exists docker; then
        print_color "$RED" "Docker 安装失败，请检查网络或手动安装。"
        exit 1
    else
        print_color "$GREEN" "Docker 已成功配置。"
    fi

    systemctl start docker && systemctl enable docker >/dev/null 2>&1
    check_docker_compose
    print_color "$GREEN" "✅ 环境准备完成。"
}

#==============================================================================
# 阶段二：收集配置信息
# 交互式收集用户配置，用于生成 PMail 配置文件
#==============================================================================

# 收集配置信息主函数
# 功能:
#   - 交互式收集用户域名、邮箱和数据库配置
#   - 支持 SQLite 和 MySQL 两种数据库类型
#   - 提供合理默认值和选项说明
# 收集项目:
#   - 主域名: 用于邮件系统的主域名
#   - Webmail 域名: 用于访问 Web 界面的域名
#   - SSL 证书邮箱: 用于申请 Let's Encrypt 证书
#   - 数据库配置: 类型选择和连接信息
# 错误处理:
#   - 必填项使用循环确保用户输入
#   - 可选项提供合理默认值
# 安全考虑:
#   - 密码输入使用 -sp 参数隐藏显示
function phase_2_collect_config() {
    print_color "$BLUE" "\n--- 阶段二：收集 PMail 配置信息 ---"

    # 收集域名信息
    while true; do
        read -p "请输入你的主域名 (例如: example.com): " PMAIL_DOMAIN
        [ -n "$PMAIL_DOMAIN" ] && break
    done
    read -p "请输入你的 Webmail 域名 (默认: mail.${PMAIL_DOMAIN}): " PMAIL_WEB_DOMAIN
    [ -z "$PMAIL_WEB_DOMAIN" ] && PMAIL_WEB_DOMAIN="mail.${PMAIL_DOMAIN}"

    # 收集 SSL 证书信息
    while true; do
        read -p "请输入用于申请SSL证书的邮箱: " PMAIL_SSL_EMAIL
        [ -n "$PMAIL_SSL_EMAIL" ] && break
    done

    # 数据库配置选择
    print_color "$YELLOW" "\n请选择数据库类型:"
    echo "1) SQLite (推荐, 简单, 适合个人使用)"
    echo "2) MySQL (高级, 性能更好)"
    read -p "请输入选项 [1-2] (默认 1): " db_choice
    db_choice=${db_choice:-1}
    case "$db_choice" in
        2)
            # MySQL 数据库配置
            DB_TYPE="mysql"
            read -p "你是否已有可用的 MySQL 数据库？(y/n, 默认 n): " mysql_existing_choice
            if [[ "$mysql_existing_choice" == "y" || "$mysql_existing_choice" == "Y" ]]; then
                # 使用现有 MySQL 数据库
                IS_NEW_MYSQL=false
                read -p "请输入 MySQL 主机地址: " MYSQL_HOST
                read -p "请输入 MySQL 端口 (默认 3306): " MYSQL_PORT
                [ -z "$MYSQL_PORT" ] && MYSQL_PORT=3306
                read -p "请输入 MySQL 数据库名: " MYSQL_DB_NAME
                read -p "请输入 MySQL 用户名: " MYSQL_USER
                read -sp "请输入 MySQL 密码: " MYSQL_PASSWORD
                echo
            else
                # 创建新的 MySQL 容器
                IS_NEW_MYSQL=true
                print_color "$YELLOW" "将在 Docker 中为你创建一个新的 MySQL 数据库。"
                read -sp "请为新 MySQL 设置 root 用户密码: " MYSQL_ROOT_PASSWORD
                echo
                PMAIL_DB_NAME="pmail"
                PMAIL_DB_USER="pmail"
                read -sp "请为 PMail 专用数据库用户 'pmail' 设置密码: " PMAIL_DB_PASSWORD
                echo
            fi
            ;;
        *)
            # SQLite 数据库配置 (简单模式)
            DB_TYPE="sqlite"
            ;;
    esac
    print_color "$GREEN" "✅ 配置信息收集完成。"
}

#==============================================================================
# 阶段三：生成配置文件并部署
# 根据用户配置生成必要文件并启动服务
#==============================================================================

# 生成配置文件并部署服务主函数
# 功能:
#   - 创建必要的目录结构
#   - 根据用户配置生成 config.json 配置文件
#   - 生成 docker-compose.yml 服务编排文件
#   - 启动 Docker 容器服务
# 配置生成:
#   - 根据数据库类型生成对应的连接字符串
#   - 配置邮件服务所需的域名和端口信息
#   - 为 MySQL 模式添加数据库服务配置
# 错误处理:
#   - 服务启动失败时提供详细的诊断信息
#   - 提供日志查看命令帮助用户排查问题
# 注意事项:
#   - 所有配置文件都存储在 ${INSTALL_DIR} 目录下
#   - 使用 Docker 卷挂载确保数据持久化
function phase_3_generate_and_deploy() {
    print_color "$BLUE" "\n--- 阶段三：生成配置文件并部署服务 ---"
    
    # 创建必要的目录结构
    mkdir -p ${INSTALL_DIR}/{config,plugins}
    cd ${INSTALL_DIR}

    # 根据数据库类型生成连接字符串
    if [ "$DB_TYPE" == "sqlite" ]; then
        # SQLite 模式 - 使用本地文件
        DB_DSN="./config/pmail.db"
    elif [ "$IS_NEW_MYSQL" = true ]; then
        # 新建 MySQL 容器模式 - 使用容器名称作为主机名
        DB_DSN="${PMAIL_DB_USER}:${PMAIL_DB_PASSWORD}@tcp(pmail-mysql:3306)/${PMAIL_DB_NAME}?charset=utf8mb4&parseTime=True&loc=Local"
    else
        # 使用现有 MySQL 模式 - 使用用户提供的连接信息
        DB_DSN="${MYSQL_USER}:${MYSQL_PASSWORD}@tcp(${MYSQL_HOST}:${MYSQL_PORT})/${MYSQL_DB_NAME}?charset=utf8mb4&parseTime=True&loc=Local"
    fi

    # 生成 PMail 配置文件
    cat > config/config.json << EOF
{
  "logLevel": "info",
  "domain": "${PMAIL_DOMAIN}",
  "webDomain": "${PMAIL_WEB_DOMAIN}",
  "dkimPrivateKeyPath": "config/dkim/dkim.priv",
  "sslType": "0",
  "SSLPrivateKeyPath": "config/ssl/private.key",
  "SSLPublicKeyPath": "config/ssl/public.crt",
  "dbDSN": "${DB_DSN}",
  "dbType": "${DB_TYPE}",
  "httpsEnabled": 0,
  "spamFilterLevel": 1,
  "httpPort": 80,
  "httpsPort": 443,
  "isInit": false
}
EOF
    print_color "$GREEN" "config.json 文件已生成。"

    # 生成 Docker Compose 配置文件
    cat > docker-compose.yml << EOF
services:
  pmail:
    image: ${PMAIL_IMAGE}
    container_name: pmail
    restart: unless-stopped
    ports:
      - "25:25"    # SMTP 服务
      - "80:80"    # HTTP Web 界面
      - "443:443"  # HTTPS Web 界面
      - "110:110"  # POP3 服务
      - "465:465"  # SMTPS 服务
      - "587:587"  # SMTP 提交服务
      - "993:993"  # IMAPS 服务
      - "995:995"  # POP3S 服务
    volumes:
      - ./config:/work/config    # 配置文件目录
      - ./plugins:/work/plugins  # 插件目录
EOF

    # 为 MySQL 模式添加数据库服务配置
    if [ "$DB_TYPE" == "mysql" ] && [ "$IS_NEW_MYSQL" = true ]; then
        cat >> docker-compose.yml << EOF
    depends_on:
      mysql:
        condition: service_healthy

  mysql:
    image: mysql:8.0
    container_name: pmail-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${PMAIL_DB_NAME}
      MYSQL_USER: ${PMAIL_DB_USER}
      MYSQL_PASSWORD: ${PMAIL_DB_PASSWORD}
    volumes:
      - ./mysql_data:/var/lib/mysql  # MySQL 数据持久化
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF
    fi
    print_color "$GREEN" "docker-compose.yml 文件已生成。"

    # 启动服务
    print_color "$YELLOW" "正在启动 PMail 服务，请稍候..."
    ${DOCKER_COMPOSE_CMD} up -d
    if [ $? -eq 0 ]; then
        print_color "$GREEN" "✅ PMail 服务已成功启动！"
    else
        print_color "$RED" "PMail 服务启动失败！"
        print_color "$YELLOW" "提示: 如果错误与网络或镜像拉取有关，请尝试重新运行脚本并选择其他镜像加速器。"
        print_color "$YELLOW" "你也可以手动检查日志：cd ${INSTALL_DIR} && ${DOCKER_COMPOSE_CMD} logs -f"
        exit 1
    fi
}

#==============================================================================
# 阶段四：后续操作指南
# 提供部署后的配置指南和最佳实践建议
#==============================================================================

# 部署后操作指南主函数
# 功能:
#   - 获取服务器公网 IP 地址
#   - 提供防火墙配置建议
#   - 指导用户完成网页安装和 DNS 配置
#   - 说明 PTR 记录设置的重要性和方法
#   - 提供邮件服务评分优化建议
#   - 列出常用服务管理命令
# 关键步骤:
#   1. 防火墙端口开放
#   2. 网页安装向导完成
#   3. DNS 记录配置
#   4. PTR 反向解析设置
#   5. 邮件服务优化
# 注意事项:
#   - PTR 记录设置是提高邮件送达率的关键
#   - 域名选择会影响邮件信誉评分
#   - 服务管理需要使用正确的 Docker Compose 命令
function phase_4_post_install_guide() {
    local SERVER_IP=$(get_public_ip)
    print_color "$BLUE" "\n==================== 部署完成 - 请务必执行以下后续步骤 ===================="
    
    # 1. 防火墙配置指南
    print_color "$YELLOW" "\n1. 防火墙配置"
    print_color "$YELLOW" "请确保你的服务器防火墙/安全组已放行以下端口：25, 80, 443, 110, 465, 587, 993, 995"
    echo "如果你使用 ufw，可以运行以下命令："
    print_color "$GREEN" "ufw allow 25,80,443,110,465,587,993,995/tcp"

    # 2. 网页安装与 DNS 配置指南
    print_color "$YELLOW" "\n2. 网页安装与 DNS 配置"
    print_color "$YELLOW" "现在，请用浏览器访问以下地址，完成管理员账户创建和获取 DNS 配置："
    print_color "$GREEN" "http://${SERVER_IP}"
    echo "在网页安装向导中，PMail 会为你生成所有必需的 DNS 记录 (包括 A, MX, SPF, DKIM)。"
    print_color "$YELLOW" "请根据向导提供的确切信息，在你的【域名提供商】（如Cloudflare, 阿里云）后台完成配置。"

    # 3. PTR 记录设置指南 (关键步骤)
    print_color "$RED" "\n3.【关键】设置反向 DNS (PTR 记录) (需要服务器提供商支持)"
    print_color "$RED" "这是提高邮件送达率、避免被标记为垃圾邮件的【最重要】步骤之一！"
    print_color "$YELLOW" "你需要登录到你的【服务器提供商】（如 Vultr, DigitalOcean）的控制台，而不是域名提供商。"
    echo "找到你服务器的网络设置部分，为你的 IP 地址添加一条 PTR 记录。"
    echo -e "  - IP 地址: ${GREEN}${SERVER_IP}${NC}"
    echo -e "  - PTR 记录值 (或反向解析域名): ${GREEN}${PMAIL_WEB_DOMAIN}${NC}"
    print_color "$YELLOW" "注意：此设置生效可能需要几分钟到几小时不等。"

    # 4. 邮件评分优化建议
    print_color "$BLUE" "\n4. 邮件评分优化建议"
    print_color "$YELLOW" "完成以上步骤后，你的邮件系统已基本可用。如需获得更高评分，请注意以下几点："
    echo -e "  - ${RED}域名信誉 (TLD 问题)${NC}: 邮件测试服务可能会对某些新顶级域名（如 .top, .xyz, .icu）扣分。"
    echo "    这是域名本身的属性，无法通过技术配置解决。如需最高信誉，建议使用 .com/.net 等传统域名。"
    echo -e "  - ${RED}邮件内容 (HTML 混淆问题)${NC}: 如果你遇到 'HTML_OBFUSCATE' 相关的扣分，这通常与你【发送邮件的客户端】有关，"
    echo "    而非 PMail 服务器。请尝试发送纯文本邮件或使用简洁的 HTML 格式，避免复杂的签名和模板。"
    echo -e "  - ${YELLOW}次要问题 (如 MSGID_SHORT)${NC}: 这类问题通常是 PMail 软件自身的一些小细节，对送达率影响极小，可暂时忽略。"

    # 5. 服务管理命令
    print_color "$YELLOW" "\n5. 服务管理"
    echo "PMail 已安装在 ${INSTALL_DIR} 目录中。"
    echo "常用命令："
    echo "  - 进入目录: cd ${INSTALL_DIR}"
    echo "  - 停止服务: ${DOCKER_COMPOSE_CMD} down"
    echo "  - 启动服务: ${DOCKER_COMPOSE_CMD} up -d"
    echo "  - 查看日志: ${DOCKER_COMPOSE_CMD} logs -f"
    echo "  - 更新服务: ${DOCKER_COMPOSE_CMD} pull && ${DOCKER_COMPOSE_CMD} up -d"
    print_color "$BLUE" "================================================================================"
}

#==============================================================================
# 主函数：脚本执行流程控制
# 按顺序调用各阶段函数，完成完整的部署流程
#==============================================================================

# 主函数
# 功能:
#   - 清理终端显示
#   - 显示脚本标题
#   - 按顺序执行四个阶段函数
# 执行流程:
#   1. 环境准备阶段 - 安装依赖、检测地区、安装 Docker
#   2. 配置收集阶段 - 收集域名和数据库配置信息
#   3. 生成部署阶段 - 创建配置文件并启动服务
#   4. 后续指南阶段 - 提供部署后的配置和优化建议
# 错误处理:
#   - 各阶段函数内部包含错误处理逻辑
#   - 关键步骤失败时会终止脚本执行
function main() {
    clear
    print_color "$BLUE" "================================================="
    print_color "$BLUE" "      PMail 个人域名邮箱一键部署脚本"
    print_color "$BLUE" "================================================="
    
    # 执行四个主要阶段
    phase_1_prepare_environment  # 环境准备
    phase_2_collect_config       # 配置收集
    phase_3_generate_and_deploy  # 生成配置并部署
    phase_4_post_install_guide   # 后续操作指南
}

# --- 脚本入口点 ---
main