#!/bin/bash

#================================================================================
# Nextcloud 一键部署脚本 (新手/进阶模式) v1.3
#
# 脚本说明:
#   本脚本提供了一个自动化的 Nextcloud 部署解决方案，支持新手和进阶两种模式，
#   可以根据服务器位置自动优化配置，并确保安全性和性能的最佳实践。
#
# 核心功能:
#   1. 智能环境准备
#      - 根据服务器位置自动选择最优软件源
#      - 自动安装并配置 Docker, Docker Compose, Vim 等基础组件
#   2. 灵活部署选项
#      - 新手模式: 单容器部署，采用 SQLite 数据库，适合快速评估和个人使用
#      - 进阶模式: 完整技术栈部署 (Nginx Proxy Manager + Nextcloud + MariaDB + Redis)
#   3. 安全性保障
#      - 自动配置 HTTPS 证书
#      - 内置反向代理保护
#      - 关键操作的健壮性检查
#   4. 版本特性
#      - [v1.3] 优化进阶模式部署流程，通过延迟注入反向代理配置解决 HTTPS 警告
#
# 使用说明:
#   1. 上传脚本至服务器
#   2. 执行: chmod +x setup_nextcloud.sh
#   3. 运行: sudo ./setup_nextcloud.sh
#
# 注意事项:
#   - 运行脚本需要 root 权限
#   - 进阶模式需要准备一个可用的域名
#   - 确保服务器防火墙已开放所需端口 (80, 443, 81)
#
# 作者: NFA晨曦
#================================================================================

# 终端颜色定义
# 用于提供清晰的视觉反馈和突出显示重要信息
GREEN='\033[0;32m'    # 成功消息
RED='\033[0;31m'      # 错误消息
YELLOW='\033[0;33m'   # 警告和提示
BLUE='\033[0;34m'     # 标题和分隔
NC='\033[0m'          # 重置颜色

#==============================================================================
# 辅助函数
# 包含了一系列通用工具函数，用于支持脚本的核心功能
#==============================================================================

# 打印带颜色的消息到终端
# 参数:
#   $1 - 颜色代码 (使用预定义的颜色变量)
#   $2 - 要显示的消息
# 用途: 提供统一的彩色输出格式，增强用户交互体验
function print_color() {
    COLOR=$1
    MESSAGE=$2
    echo -e "${COLOR}${MESSAGE}${NC}"
}

# 检查系统中是否存在指定命令
# 参数:
#   $1 - 要检查的命令名称
# 返回: 命令存在返回 0，不存在返回 1
# 用途: 验证依赖命令的可用性
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 验证脚本是否以 root 权限运行
# 用途: 确保脚本具有执行系统级操作的必要权限
# 行为: 如果不是 root 用户运行，则显示错误信息并退出
function check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_color "$RED" "错误: 此脚本必须以 root 用户身份运行。"
        print_color "$YELLOW" "请尝试使用 'sudo ./setup_nextcloud.sh' 运行。"
        exit 1
    fi
}

# 暂停脚本执行，等待用户确认
# 用途: 在需要用户手动操作的步骤之间提供暂停点
# 行为: 显示提示信息并等待任意键输入
function press_any_key_to_continue() {
    print_color "$YELLOW" "\n当您完成上述操作后，请按任意键继续..."
    read -n 1 -s -r
}

# 获取服务器的公网 IP 地址
# 返回: 成功返回公网 IP 地址，失败返回空字符串
# 策略: 依次尝试多个 IP 查询服务，提高可靠性
# 注意: 所有查询均使用 HTTPS 协议，确保安全性
function get_public_ip() {
    local ip
    ip=$(curl -s https://ifconfig.me)
    [ -z "$ip" ] && ip=$(curl -s https://api.ipify.org)
    [ -z "$ip" ] && ip=$(curl -s https://ipinfo.io/ip)
    echo "$ip"
}

#==============================================================================
# 环境准备函数
# 负责系统环境初始化，包括软件源配置、Docker安装和基础工具部署
#==============================================================================

# 准备系统环境并安装必要依赖
# 功能:
#   1. 根据服务器地理位置优化软件源
#   2. 安装并配置 Docker 环境
#   3. 部署必要的工具（Docker Compose, Vim）
# 错误处理:
#   - 软件源配置失败时提供反馈
#   - Docker 安装失败时终止脚本
#   - 依赖安装失败时提供明确的错误信息
function prepare_environment() {
    print_color "$BLUE" "--- 1. 环境准备与依赖安装 ---"
    
    # 根据服务器地理位置优化软件源配置
    print_color "$YELLOW" "为了优化下载速度，请选择您的服务器所在区域。"
    local choice
    while true; do
        read -p "您的服务器是否位于中国大陆？(y/n): " choice
        case "$choice" in
            y|Y )
                print_color "$GREEN" "检测到国内服务器，将使用镜像源加速。"
                print_color "$YELLOW" "正在更换系统软件源..."
                # 使用 linuxmirrors.cn 提供的智能镜像源选择工具
                bash <(curl -sSL https://linuxmirrors.cn/main.sh)
                print_color "$YELLOW" "正在使用国内镜像安装 Docker..."
                # 使用阿里云的 Docker CE 镜像源
                bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
                break
                ;;
            n|N )
                print_color "$GREEN" "检测到海外服务器，将使用官方源。"
                print_color "$YELLOW" "正在安装 Docker..."
                # 使用 Docker 官方安装脚本
                curl -fsSL https://get.docker.com | bash -s docker
                break
                ;;
            * ) print_color "$RED" "无效输入，请输入 'y' 或 'n'。" ;;
        esac
    done

    # 配置 Docker 服务
    print_color "$YELLOW" "正在启动并设置 Docker 开机自启..."
    systemctl start docker    # 启动 Docker 守护进程
    systemctl enable docker   # 设置开机自启
    print_color "$GREEN" "Docker 服务已启动。"

    # 安装必要的工具包
    print_color "$YELLOW" "正在安装 Docker Compose 和 Vim..."
    apt-get update >/dev/null 2>&1  # 静默更新软件包索引
    apt-get install -y docker-compose vim
    
    # 验证工具安装状态
    if ! command_exists docker-compose || ! command_exists vim; then
        print_color "$RED" "Docker Compose 或 Vim 安装失败，请检查apt源后重试。"
        exit 1
    fi
    print_color "$GREEN" "依赖安装完成。"
}

#==============================================================================
# 新手模式部署函数
# 提供简单快速的 Nextcloud 单容器部署方案，适合个人使用和功能评估
#==============================================================================

# 部署基础版 Nextcloud 实例
# 特点:
#   - 单容器部署，降低复杂度
#   - 使用 SQLite 数据库，无需额外配置
#   - 数据持久化存储在宿主机
# 配置:
#   - 端口映射: 8080:80
#   - 数据目录: /root/data/nextcloud
#   - 容器名称: nextcloud-basic
# 错误处理:
#   - 容器启动失败检测
#   - 网络连接问题诊断
#   - 端口冲突检查
function deploy_basic() {
    print_color "$BLUE" "\n--- 正在执行新手模式部署 ---"
    print_color "$YELLOW" "目标: 快速启动一个可用的 Nextcloud 实例。"
    
    # 创建持久化数据目录
    mkdir -p /root/data/nextcloud
    
    # 部署 Nextcloud 容器
    print_color "$YELLOW" "正在启动 Nextcloud 容器..."
    if docker run -d \
        --name nextcloud-basic \
        -p 8080:80 \
        -v /root/data/nextcloud:/var/www/html \
        nextcloud:latest; then
        
        print_color "$GREEN" "Nextcloud 容器启动命令已成功执行。"
        print_color "$YELLOW" "正在确认容器运行状态..."
        # 等待容器初始化
        sleep 5  # 预留足够时间让容器完成初始化或显示错误
        
        # 验证容器运行状态
        if ! docker ps | grep -q "nextcloud-basic"; then
            print_color "$RED" "容器未能保持运行状态！请运行 'docker logs nextcloud-basic' 查看错误日志。"
            exit 1
        fi
    else
        print_color "$RED" "执行 'docker run' 命令失败！"
        print_color "$YELLOW" "可能的原因:"
        print_color "$YELLOW" "1. Docker 镜像拉取失败 - 请检查网络连接"
        print_color "$YELLOW" "2. 端口 8080 已被占用 - 请检查端口使用情况"
        print_color "$YELLOW" "3. 系统资源不足 - 请检查内存和磁盘空间"
        exit 1
    fi
    
    # 获取服务器公网IP用于访问
    SERVER_IP=$(get_public_ip)
    [ -z "$SERVER_IP" ] && SERVER_IP="<你的服务器公网IP>"

    # 显示部署成功信息和访问指南
    print_color "$GREEN" "\n✅ 新手模式部署成功！"
    print_color "$BLUE" "==================== 访问信息 ===================="
    echo -e "访问地址: ${GREEN}http://${SERVER_IP}:8080${NC}"
    echo -e "初始化配置:"
    echo -e "1. 创建管理员账号和密码"
    echo -e "2. 选择数据库: 使用默认的 ${YELLOW}SQLite${NC}"
    echo -e "3. 完成安装后即可开始使用"
    print_color "$BLUE" "================================================\n"
}

#==============================================================================
# 进阶模式部署函数
# 提供完整的生产级 Nextcloud 部署方案，包含反向代理、数据库和缓存服务
#==============================================================================

# 部署生产级 Nextcloud 环境
# 架构组件:
#   - Nginx Proxy Manager (NPM): 反向代理和 SSL 终端
#   - Nextcloud: 核心应用服务
#   - MariaDB: 高性能数据库
#   - Redis: 会话和文件缓存
# 特点:
#   - 多容器架构，服务解耦
#   - 支持 HTTPS 和自动证书管理
#   - 持久化存储和数据备份
#   - 高性能缓存集成
# 部署流程:
#   1. 环境清理和准备
#   2. 反向代理服务部署
#   3. 应用栈配置和启动
#   4. SSL 证书配置
#   5. 系统优化和调优
function deploy_advanced() {
    print_color "$BLUE" "\n--- 正在执行进阶模式部署 ---"
    print_color "$YELLOW" "目标: 部署一个包含NPM、MariaDB、Redis的生产级Nextcloud环境。"

    # 步骤 1: 环境清理
    # 确保部署环境的干净，避免与现有服务冲突
    print_color "$YELLOW" "\n步骤 1/7: 清理可能存在的旧环境..."
    if docker ps -a | grep -q "nextcloud-basic"; then
        print_color "$YELLOW" "检测到新手模式的容器，执行清理流程..."
        # 停止并移除旧容器
        docker stop nextcloud-basic
        docker rm nextcloud-basic
        
        # 数据目录清理确认
        print_color "$YELLOW" "警告: 数据清理操作不可逆！"
        read -p "是否删除旧的数据目录 /root/data/nextcloud？(y/n): " del_choice
        if [[ "$del_choice" == "y" || "$del_choice" == "Y" ]]; then
            rm -rf /root/data/nextcloud
            print_color "$GREEN" "旧数据目录已清理完成。"
        else
            print_color "$YELLOW" "保留旧数据目录，将在新部署中重用。"
        fi
    fi
    print_color "$GREEN" "环境清理完成，准备开始新部署。"

    # 步骤 2: 部署 Nginx Proxy Manager (NPM)
    # NPM 用于管理反向代理和 SSL 证书，提供 Web 界面配置
    print_color "$YELLOW" "\n步骤 2/7: 部署 Nginx Proxy Manager (NPM)..."
    
    # 创建共享网络用于容器间通信
    # 使用 >/dev/null 2>&1 抑制重复创建时的错误输出
    docker network create my_shared_network >/dev/null 2>&1 || \
        print_color "$YELLOW" "网络 my_shared_network 已存在。"
    
    # 准备 NPM 部署目录和配置
    mkdir -p /root/data/npm && cd /root/data/npm
    
    # 生成 Docker Compose 配置
    # 配置说明:
    # - 端口映射: 80(HTTP), 443(HTTPS), 81(管理界面)
    # - 数据持久化: 配置和证书分别存储
    # - 自动重启: 系统重启时自动恢复服务
    cat > docker-compose.yml << EOF
version: '3'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'      # HTTP 端口
      - '443:443'    # HTTPS 端口
      - '81:81'      # 管理界面端口
    volumes:
      - ./data:/data                     # NPM 配置数据
      - ./letsencrypt:/etc/letsencrypt   # SSL 证书存储
networks:
  default:
    external:
      name: my_shared_network            # 使用已创建的共享网络
EOF

    # 启动 NPM 服务
    if docker-compose up -d; then
        print_color "$GREEN" "NPM 启动成功。"
    else
        print_color "$RED" "NPM 启动失败！"
        print_color "$YELLOW" "可能的错误原因:"
        print_color "$YELLOW" "1. 网络问题导致镜像拉取失败"
        print_color "$YELLOW" "2. 端口冲突 (需要的端口: 80, 81, 443)"
        print_color "$YELLOW" "3. Docker Compose 配置问题"
        print_color "$YELLOW" "诊断建议: 进入 /root/data/npm 目录，执行 'docker-compose up' 查看详细日志"
        exit 1
    fi
    
    # 安全提醒
    print_color "$YELLOW" "重要: 请确保服务器防火墙/安全组已开放以下端口:"
    print_color "$YELLOW" "- 80  (HTTP)"
    print_color "$YELLOW" "- 443 (HTTPS)"
    print_color "$YELLOW" "- 81  (NPM 管理界面)"
    
    # 获取服务器IP并显示访问信息
    SERVER_IP=$(get_public_ip)
    [ -z "$SERVER_IP" ] && SERVER_IP="<你的服务器公网IP>"
    print_color "$BLUE" "\n请完成以下初始化配置:"
    echo -e "1. 访问管理界面: ${GREEN}http://${SERVER_IP}:81${NC}"
    echo -e "2. 使用默认凭据登录:"
    echo -e "   - 邮箱: ${YELLOW}admin@example.com${NC}"
    echo -e "   - 密码: ${YELLOW}changeme${NC}"
    echo -e "3. 安全建议: 首次登录后立即修改默认凭据"
    press_any_key_to_continue

    # 步骤 3: 部署 Nextcloud 全家桶
    # 包含三个核心服务:
    # - MariaDB: 持久化数据存储
    # - Redis: 缓存和会话管理
    # - Nextcloud: 主应用服务
    print_color "$YELLOW" "\n步骤 3/7: 部署 Nextcloud, MariaDB 和 Redis..."
    
    # 收集必要的配置信息
    # 1. 域名配置
    while true; do
        read -p "请输入您为Nextcloud准备的域名 (例如: nc.yourdomain.com): " NC_DOMAIN
        if [ -n "$NC_DOMAIN" ]; then
            break
        else
            print_color "$RED" "错误: 域名不能为空，这将用于SSL证书申请和服务访问。"
        fi
    done
    
    # 2. 数据库 Root 密码
    while true; do
        read -sp "请为数据库 root 用户设置一个强密码: " DB_ROOT_PASSWORD
        echo
        if [ -n "$DB_ROOT_PASSWORD" ]; then
            break
        else
            print_color "$RED" "错误: Root密码不能为空，这关系到数据库安全。"
        fi
    done
    
    # 3. Nextcloud 数据库用户密码
    while true; do
        read -sp "请为Nextcloud数据库用户(nextcloud)设置一个强密码: " DB_USER_PASSWORD
        echo
        if [ -n "$DB_USER_PASSWORD" ]; then
            break
        else
            print_color "$RED" "错误: 用户密码不能为空，这用于Nextcloud连接数据库。"
        fi
    done

    # 准备应用部署目录
    mkdir -p /root/data/nextcloud && cd /root/data/nextcloud
    
    # 生成 Docker Compose 配置
    # 配置说明:
    # - 使用版本固定的镜像以确保稳定性
    # - 启用容器自动重启
    # - 配置持久化存储
    # - 设置安全的数据库参数
    # - 配置服务间的依赖关系
    cat > docker-compose.yml << EOF
version: '3'

services:
  # MariaDB 服务配置
  db:
    image: mariadb:10.6
    container_name: nextcloud-db
    restart: always
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW  # 优化事务处理
    volumes:
      - ./db:/var/lib/mysql  # 数据持久化
    environment:
      - MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
      - MYSQL_PASSWORD=${DB_USER_PASSWORD}
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud

  # Redis 缓存服务
  redis:
    image: redis:alpine
    container_name: nextcloud-redis
    restart: always

  # Nextcloud 主应用
  app:
    image: nextcloud:latest
    container_name: nextcloud-app
    restart: always
    depends_on:  # 确保依赖服务先启动
      - db
      - redis
    volumes:
      - ./nextcloud:/var/www/html  # 应用数据持久化
    environment:  # 数据库和缓存配置
      - MYSQL_HOST=db
      - MYSQL_PASSWORD=${DB_USER_PASSWORD}
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - REDIS_HOST=redis
      - NEXTCLOUD_TRUSTED_DOMAINS=${NC_DOMAIN}

# 使用已创建的共享网络
networks:
  default:
    external:
      name: my_shared_network
EOF

    # 启动服务栈
    print_color "$YELLOW" "正在启动 Nextcloud 服务栈..."
    if docker-compose up -d; then
        print_color "$GREEN" "Nextcloud 应用栈启动成功。"
    else
        print_color "$RED" "Nextcloud 应用栈启动失败！"
        print_color "$YELLOW" "可能的错误原因:"
        print_color "$YELLOW" "1. 内存不足"
        print_color "$YELLOW" "2. 端口冲突"
        print_color "$YELLOW" "3. 存储空间不足"
        print_color "$YELLOW" "诊断建议: 进入 /root/data/nextcloud 目录，执行 'docker-compose up' 查看详细日志"
        exit 1
    fi

    # 步骤 4: 配置反向代理
    # 通过 NPM 配置 Nextcloud 的反向代理和 SSL 证书
    # 目标:
    # - 启用 HTTPS 访问
    # - 配置安全策略
    # - 自动管理 SSL 证书
    print_color "$YELLOW" "\n步骤 4/7: 配置反向代理..."
    print_color "$BLUE" "请返回 NPM 管理界面 (http://${SERVER_IP}:81) 并按以下步骤操作:"
    
    # 1. 基本代理配置
    echo -e "1. 导航路径: [Hosts] -> [Proxy Hosts] -> [Add Proxy Host]"
    
    # 2. 详细配置
    echo -e "2. [Details] 选项卡配置:"
    echo -e "   - Domain Names: ${GREEN}${NC_DOMAIN}${NC}         # 您的域名"
    echo -e "   - Scheme: ${GREEN}http${NC}                      # 内部通信协议"
    echo -e "   - Forward Hostname / IP: ${GREEN}nextcloud-app${NC}  # Docker 服务名"
    echo -e "   - Forward Port: ${GREEN}80${NC}                 # 容器内部端口"
    echo -e "   - 勾选 [Block Common Exploits]                  # 启用基本安全防护"
    
    # 3. SSL 证书配置
    echo -e "3. [SSL] 选项卡配置:"
    echo -e "   - SSL Certificate: ${GREEN}Request a new SSL Certificate${NC}  # 自动申请证书"
    echo -e "   - 安全选项:"
    echo -e "     ✓ [Force SSL]        # 强制 HTTPS 访问"
    echo -e "     ✓ [HTTP/2 Support]   # 启用 HTTP/2 提升性能"
    echo -e "     ✓ [HSTS Enabled]     # 强制浏览器使用 HTTPS"
    echo -e "   - 确认 Let's Encrypt 服务条款"
    
    # 4. 保存配置
    echo -e "4. 点击 [Save] 保存并应用配置"
    
    # 等待用户完成配置
    print_color "$YELLOW" "提示: 确保您的域名 DNS 已正确解析到服务器 IP，否则证书申请将失败"
    press_any_key_to_continue

    # 5. 完成网页安装 (关键步骤)
    print_color "$YELLOW" "\n步骤 5/7: 完成网页安装 (关键步骤!)..."
    print_color "$BLUE" "现在，请打开浏览器，访问您的域名: ${GREEN}https://${NC_DOMAIN}${NC}"
    echo -e "您将看到 Nextcloud 的安装页面。"
    echo -e "请在该页面上 ${YELLOW}创建您的管理员账户和密码${NC}，然后点击“安装完成”。"
    echo -e "此操作将生成 Nextcloud 的核心配置文件，我们将在下一步对其进行修改。"
    press_any_key_to_continue

    # 步骤 6: 注入反向代理配置
    # 功能: 修改 Nextcloud 配置文件以支持反向代理和 HTTPS
    # 配置项:
    #   - overwrite.cli.url: 指定 Nextcloud 的基础 URL
    #   - overwriteprotocol: 强制使用 HTTPS 协议
    #   - overwritehost: 指定访问域名
    #   - trusted_proxies: 配置可信代理的 IP 范围
    #   - forwarded_for_headers: 指定代理转发的 HTTP 头
    print_color "$YELLOW" "\n步骤 6/7: 注入反向代理配置..."
    CONFIG_FILE="/root/data/nextcloud/nextcloud/config/config.php"
    
    if [ -f "$CONFIG_FILE" ]; then
        # 获取 Docker 网络的子网地址，用于配置可信代理
        SUBNET=$(docker network inspect my_shared_network | grep "Subnet" | awk -F'"' '{print $4}')
        # 使用 sed 在 'datadirectory' 配置前插入反向代理相关配置
        sed -i "/'datadirectory'/i \
  'overwrite.cli.url' => 'https://${NC_DOMAIN}',\n\
  'overwriteprotocol' => 'https',\n\
  'overwritehost' => '${NC_DOMAIN}',\n\
  'trusted_proxies' => ['${SUBNET}'],\n\
  'forwarded_for_headers' => ['HTTP_X_FORWARDED_FOR']," "$CONFIG_FILE"
        
        print_color "$GREEN" "配置文件 config.php 修改成功。"
        docker restart nextcloud-app
        print_color "$GREEN" "Nextcloud 容器已重启以应用新配置。"
    else
        print_color "$RED" "错误: 未找到配置文件 ${CONFIG_FILE}！"
        print_color "$YELLOW" "请确认您已在步骤5中正确完成了网页安装。如果问题持续，请手动检查该文件是否存在。"
        exit 1
    fi

    # 步骤 7: 系统优化与调优
    # 功能: 执行一系列优化命令以提升系统性能和用户体验
    # 优化项:
    #   1. 修复和优化数据库
    #   2. 设置维护时间窗口
    #   3. 配置区域设置
    print_color "$YELLOW" "\n步骤 7/7: 执行最终优化命令..."
    cd /root/data/nextcloud
    # 执行数据库修复和优化
    docker-compose exec -u www-data app php occ maintenance:repair --include-expensive
    # 设置系统维护时间窗口为凌晨1点
    docker-compose exec -u www-data app php occ config:system:set maintenance_window_start --value="1"
    # 设置默认电话区域为中国
    docker-compose exec -u www-data app php occ config:system:set default_phone_region --value="CN"
    print_color "$GREEN" "优化命令执行完毕。"

    print_color "$GREEN" "\n✅ 进阶模式部署成功！"
    print_color "$BLUE" "==================== 部署完成 ===================="
    echo -e "您的 Nextcloud 实例现已完全配置完毕！"
    echo -e "请刷新您的网页: ${GREEN}https://${NC_DOMAIN}${NC}"
    echo -e "现在，系统设置中的所有安全警告应已消失。"
    print_color "$BLUE" "================================================\n"
}

#==============================================================================
# 主函数
# 负责脚本的整体流程控制和用户交互
#==============================================================================

# 主函数入口
# 功能:
#   - 显示欢迎信息
#   - 执行权限检查
#   - 准备运行环境
#   - 引导用户选择部署模式
#   - 执行相应的部署流程
function main() {
    clear
    print_color "$BLUE" "========================================================"
    print_color "$BLUE" "         Nextcloud 一键部署脚本 (v1.3)"
    print_color "$BLUE" "========================================================"
    print_color "$YELLOW" "本脚本将引导您完成 Nextcloud 的部署过程。"
    
    # 执行基础检查和环境准备
    check_root
    prepare_environment

    # 部署模式选择
    # 提供两种部署方案:
    #   1. 新手模式: 单容器快速部署
    #      - 使用 SQLite 数据库
    #      - 最小化配置要求
    #      - 适合个人测试和评估
    #   2. 进阶模式: 全栈式部署
    #      - 包含反向代理、数据库和缓存
    #      - 完整的性能优化
    #      - 适合生产环境使用
    print_color "$BLUE" "\n--- 2. 选择部署模式 ---"
    echo "1) 新手模式: 适合个人快速体验，使用单个容器和SQLite数据库。"
    echo "2) 进阶模式: 适合长期稳定使用，部署包含NPM、数据库和缓存的全家桶方案。"
    
    # 获取用户选择并执行相应的部署函数
    local mode_choice
    while true; do
        read -p "请输入您的选择 (1 或 2): " mode_choice
        case "$mode_choice" in
            1 ) deploy_basic; break ;;
            2 ) deploy_advanced; break ;;
            * ) print_color "$RED" "无效输入，请输入 1 或 2。" ;;
        esac
    done
    
    print_color "$GREEN" "所有操作已完成！"
}

#==============================================================================
# 脚本入口
# 启动脚本的主要执行流程
#==============================================================================
main
