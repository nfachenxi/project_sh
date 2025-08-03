#!/bin/bash

#================================================================================
# Koishi + NapCat QQ机器人一键部署脚本 (v2)
#
# 脚本说明:
#   本脚本提供了一个自动化的 Koishi + NapCat QQ机器人部署解决方案，通过 Docker
#   容器技术实现快速部署和简单维护。脚本会自动处理环境准备、依赖安装、服务配置
#   等复杂步骤，最后提供详细的后续配置指引。
#
# 核心功能:
#   1. 智能环境准备
#      - 自动安装 Docker 和 Docker Compose
#      - 根据服务器位置优化软件源和镜像加速
#   2. 自动化部署
#      - 交互式配置信息收集
#      - 自动生成 Docker Compose 配置
#      - 一键部署完整技术栈 (Koishi + NapCat + MySQL)
#   3. 配置指引
#      - 提供详细的分步配置说明
#      - 包含权限设置和插件配置指南
#
# 技术栈:
#   - Koishi: 跨平台机器人框架
#   - NapCat: QQ协议适配器
#   - MySQL: 数据持久化存储
#   - Docker: 容器化部署和管理
#
# 使用说明:
#   1. 确保服务器已安装基本系统工具
#   2. 执行: chmod +x setup_koishi_napcat.sh
#   3. 运行: sudo ./setup_koishi_napcat.sh
#   4. 按照提示完成配置
#
# 注意事项:
#   - 运行脚本需要 root 权限
#   - 确保服务器防火墙已开放所需端口 (5140, 6099)
#   - 建议使用干净的服务器环境
#
# 作者: NFA晨曦
# 基于: NapCat-Docker 的 docker-compose 方案
#================================================================================

#==============================================================================
# 终端颜色定义
# 用于提供清晰的视觉反馈，帮助用户理解脚本执行状态
#==============================================================================
GREEN='\033[0;32m'    # 成功消息和正常状态
RED='\033[0;31m'      # 错误消息和失败状态
YELLOW='\033[0;33m'   # 警告消息和重要提示
BLUE='\033[0;34m'     # 标题和分隔信息
NC='\033[0m'          # 重置颜色到终端默认值

#==============================================================================
# 辅助函数
# 包含了一系列通用工具函数，用于支持脚本的核心功能
#==============================================================================

# 打印带颜色的消息到终端
# 参数:
#   $1 - 颜色代码 (使用预定义的颜色变量)
#   $2 - 要显示的消息
# 用途: 
#   - 提供统一的彩色输出格式
#   - 增强用户交互体验
#   - 突出显示重要信息
function print_color() {
    COLOR=$1
    MESSAGE=$2
    echo -e "${COLOR}${MESSAGE}${NC}"
}

# 检查系统中是否存在指定命令
# 参数:
#   $1 - 要检查的命令名称
# 返回: 
#   - 命令存在返回 0
#   - 不存在返回 1
# 用途: 
#   - 验证依赖命令的可用性
#   - 避免因缺少依赖导致的运行时错误
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 验证脚本是否以 root 权限运行
# 用途: 
#   - 确保脚本具有执行系统级操作的必要权限
#   - 防止权限不足导致的安装失败
# 行为:
#   - 如果不是 root 用户运行，显示错误信息并退出
#   - 提供使用 sudo 的提示信息
function check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_color "$RED" "错误: 此脚本必须以 root 用户身份运行。"
        print_color "$YELLOW" "请尝试使用 'sudo ./setup_koishi_napcat.sh' 运行。"
        exit 1
    fi
}

# 获取服务器的公网 IP 地址
# 返回: 
#   - 成功返回公网 IP 地址
#   - 失败返回空字符串
# 策略:
#   - 依次尝试多个 IP 查询服务，提高可靠性
#   - 所有查询均使用 HTTPS 协议，确保安全性
# 用途:
#   - 用于生成服务访问地址
#   - 提供给用户进行域名解析配置
function get_public_ip() {
    local ip
    ip=$(curl -s https://ifconfig.me)
    [ -z "$ip" ] && ip=$(curl -s https://api.ipify.org)
    [ -z "$ip" ] && ip=$(curl -s https://ipinfo.io/ip)
    echo "$ip"
}

#==============================================================================
# 安装与环境配置函数
# 负责系统环境初始化，包括软件源配置、Docker安装和基础工具部署
#==============================================================================

# 安装基础依赖工具
# 功能:
#   - 检查并安装 curl 工具
#   - curl 用于下载安装脚本和获取公网IP
# 错误处理:
#   - 安装失败时提供明确的错误信息
#   - 建议用户手动安装并重试
function install_dependencies() {
    if ! command_exists curl; then
        print_color "$YELLOW" "未检测到 curl，正在尝试安装..."
        apt-get update >/dev/null 2>&1 && apt-get install -y curl
        if ! command_exists curl; then
            print_color "$RED" "curl 安装失败，请手动安装后再运行此脚本。"
            exit 1
        fi
        print_color "$GREEN" "curl 安装成功。"
    fi
}

# 处理服务器地理位置和软件源配置
# 功能:
#   - 根据服务器位置优化软件源
#   - 自动配置国内镜像加速
# 策略:
#   - 中国大陆服务器: 使用镜像源加速
#   - 海外服务器: 使用官方源
# 优化项:
#   - 系统软件源: 使用就近的镜像站点
#   - Docker 源: 配置镜像加速器
function handle_location() {
    print_color "$BLUE" "\n--- 选择安装源 ---"
    print_color "$YELLOW" "为了优化下载速度，请选择您的服务器所在区域。"
    
    local choice
    while true; do
        read -p "您的服务器是否位于中国大陆？(y/n): " choice
        case "$choice" in
            y|Y )
                print_color "$GREEN" "将使用中国大陆镜像源进行加速。"
                print_color "$YELLOW" "正在更换系统软件源..."
                bash <(curl -sSL https://linuxmirrors.cn/main.sh)
                print_color "$YELLOW" "正在配置 Docker 加速..."
                bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
                break
                ;;
            n|N )
                print_color "$GREEN" "将使用官方源进行安装。"
                break
                ;;
            * ) print_color "$RED" "无效输入，请输入 'y' 或 'n'。" ;;
        esac
    done
}

# 安装和配置 Docker 环境
# 功能:
#   - 检查 Docker 是否已安装
#   - 自动安装最新版 Docker
#   - 配置 Docker 服务
# 配置项:
#   - 服务自启动
#   - 权限设置
# 错误处理:
#   - 安装失败时提供诊断信息
#   - 建议检查网络连接
function install_docker() {
    if ! command_exists docker; then
        print_color "$YELLOW" "未检测到 Docker，正在为您安装..."
        if ! (curl -fsSL https://get.docker.com | bash -s docker); then
            print_color "$RED" "Docker 安装失败。请检查网络或尝试手动安装。"
            exit 1
        fi
        print_color "$GREEN" "Docker 安装成功。"
    fi
    # 启动并设置 Docker 开机自启
    systemctl start docker
    systemctl enable docker
    print_color "$GREEN" "Docker 服务已启动并设为开机自启。"
}

# 验证 Docker Compose 可用性
# 功能:
#   - 检查 Docker Compose v2 插件
#   - 验证版本兼容性
# 错误处理:
#   - 检测到问题时提供明确的错误信息
#   - 提供故障排除建议
# 注意:
#   - 仅支持 Docker Compose v2 插件版本
#   - 不支持独立安装的旧版本
function check_docker_compose() {
    if ! docker compose version >/dev/null 2>&1; then
        print_color "$RED" "Docker Compose (v2 plugin) 未安装或配置不正确。"
        print_color "$YELLOW" "请检查您的 Docker 安装或手动安装 Docker Compose 插件。"
        exit 1
    else
        print_color "$GREEN" "Docker Compose 已准备就绪。"
    fi
}

#==============================================================================
# 用户配置收集函数
# 负责收集部署所需的基本配置信息，包括项目目录、机器人账号和数据库设置
#==============================================================================

# 收集用户配置信息
# 功能:
#   - 收集项目部署目录名
#   - 设置机器人 QQ 账号
#   - 配置服务间通信 Token
#   - 设置数据库密码
# 验证:
#   - QQ 号格式验证
#   - 密码非空验证
# 默认值:
#   - 项目目录: koishi-napcat
#   - Token: 可选
function collect_user_config() {
    print_color "$BLUE" "\n--- 开始收集配置信息 ---"
    
    read -p "请输入项目部署的目录名 (默认为 koishi-napcat): " project_dir
    project_dir=${project_dir:-koishi-napcat}

    while true; do
        read -p "请输入您的机器人 QQ 号 (selfId): " robot_qq
        if [[ "$robot_qq" =~ ^[1-9][0-9]{4,10}$ ]]; then
            break
        else
            print_color "$RED" "无效的 QQ 号码，请重新输入。"
        fi
    done

    read -p "请输入 NapCat 与 Koishi 之间的通信 Token (留空则不使用): " shared_token

    print_color "$YELLOW" "为了数据持久化，我们将为您部署一个 MySQL 数据库。"
    while true; do
        read -sp "请为 MySQL 的 root 用户设置一个密码: " db_root_password
        echo
        if [ -n "$db_root_password" ]; then
            break
        else
            print_color "$RED" "数据库 root 密码不能为空。"
        fi
    done
}

#==============================================================================
# 文件生成与部署函数
# 负责生成配置文件、创建目录结构和启动服务
#==============================================================================

# 创建配置文件并部署服务
# 功能:
#   - 创建项目目录结构
#   - 生成 Docker Compose 配置
#   - 启动容器服务
# 参数:
#   - project_dir: 项目根目录
#   - uid/gid: 当前用户权限
# 配置项:
#   - 容器服务定义
#   - 端口映射
#   - 数据卷挂载
function create_and_deploy() {
    print_color "$BLUE" "\n--- 正在创建配置文件并部署服务 ---"
    
    # 创建项目目录
    mkdir -p "$project_dir" && cd "$project_dir"
    print_color "$GREEN" "项目目录 '$project_dir' 创建成功。"

    # 获取 UID 和 GID
    local uid=$(id -u)
    local gid=$(id -g)

    # 创建 docker-compose.yml 文件
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  napcat:
    container_name: ${project_dir}-napcat
    image: mlikiowa/napcat-docker:latest
    restart: always
    environment:
      - NAPCAT_UID=${uid}
      - NAPCAT_GID=${gid}
      - MODE=koishi
      - KOISHI_TOKEN=${shared_token}
    ports:
      - "6099:6099" # NapCat WebUI 端口
    volumes:
      - ./napcat_config:/app/napcat/config
      - ./napcat_qq_data:/app/.config/QQ
    networks:
      - bot_network

  koishi:
    container_name: ${project_dir}-koishi
    image: koishijs/koishi:latest
    restart: always
    environment:
      - TZ=Asia/Shanghai
      - KOISHI_DATABASE_MYSQL_HOST=db
      - KOISHI_DATABASE_MYSQL_PORT=3306
      - KOISHI_DATABASE_MYSQL_USER=root
      - KOISHI_DATABASE_MYSQL_PASSWORD=${db_root_password}
      - KOISHI_DATABASE_MYSQL_DATABASE=koishi
    ports:
      - "5140:5140" # Koishi 端口
    volumes:
      - ./koishi_data:/koishi
    networks:
      - bot_network
    depends_on:
      - db

  db:
    container_name: ${project_dir}-db
    image: mysql:8.0
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=${db_root_password}
      - MYSQL_DATABASE=koishi
    volumes:
      - ./mysql_data:/var/lib/mysql
    networks:
      - bot_network

networks:
  bot_network:
    driver: bridge
EOF
    print_color "$GREEN" "docker-compose.yml 文件创建成功。"

    # 启动服务
    print_color "$YELLOW" "正在启动所有服务，这可能需要几分钟时间来拉取镜像..."
    if docker compose up -d; then
        print_color "$GREEN" "服务已成功启动！"
    else
        print_color "$RED" "服务启动失败！请检查以上日志输出。"
        print_color "$YELLOW" "您可以进入 '$project_dir' 目录，运行 'docker compose logs -f' 查看详细日志。"
        exit 1
    fi
}

# --- 最终指引函数 ---

function show_summary() {
    local server_ip=$(get_public_ip)
    if [ -z "$server_ip" ]; then
        server_ip="<你的服务器公网IP>"
    fi

    print_color "$BLUE" "\n==================== 自动化部署完成 ===================="
    print_color "$GREEN" "恭喜！Koishi 和 NapCat 已成功部署并正在后台运行。"
    print_color "$YELLOW" "\n接下来，请按照以下步骤完成手动配置："
    
    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 1: 登录 NapCat 并让机器人上线"
    echo -e "--------------------------------------------------"
    echo -e "1. 访问 NapCat WebUI: ${GREEN}http://${server_ip}:6099/webui${NC}"
    echo -e "2. 使用默认登录令牌: ${GREEN}napcat${NC}"
    echo -e "3. 登录后，请扫描屏幕上的二维码，让您的机器人QQ (${GREEN}${robot_qq}${NC}) 上线。"
    echo -e "4. ${YELLOW}重要: NapCat 会自动连接 Koishi，您无需在 NapCat 端进行任何网络配置。${NC}"

    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 2: 配置 Koishi 并连接机器人"
    echo -e "--------------------------------------------------"
    echo -e "1. 访问 Koishi 控制台: ${GREEN}http://${server_ip}:5140${NC}"
    echo -e "2. ${YELLOW}首次访问，务必先更新依赖：${NC}点击左侧菜单的 [依赖管理]，然后点击 [全部更新]，等待完成后点击 [应用更改]。"
    echo -e "3. ${YELLOW}安装适配器：${NC}点击 [插件市场]，搜索 ${GREEN}'adapter-onebot'${NC} 并安装。"
    echo -e "4. ${YELLOW}启用并配置适配器：${NC}"
    echo -e "   a. 返回 [插件配置] 页面，您会看到 ${GREEN}'adapter-onebot'${NC} 插件。"
    echo -e "   b. 点击它旁边的开关以 ${GREEN}启用${NC} 它。"
    echo -e "   c. 启用后，点击插件上的 ${GREEN}[配置]${NC} 按钮。"
    echo -e "5. ${YELLOW}添加机器人实例：${NC}"
    echo -e "   a. 在 ${GREEN}'bots'${NC} 列表中点击 ${GREEN}[添加]${NC} 按钮。"
    echo -e "   b. 填写以下信息："
    echo -e "      - **protocol**: 选择 ${GREEN}ws-reverse${NC} (反向 WebSocket)"
    echo -e "      - **selfId**: 填写您的机器人QQ号 ${GREEN}${robot_qq}${NC}"
    echo -e "      - **token**: 填写您之前设置的通信Token ${GREEN}${shared_token:-（您未设置）}${NC}"
    echo -e "6. 点击右上角的 ${GREEN}[保存]${NC} 按钮，然后启用这个机器人实例。"

    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 3: 设置主人权限"
    echo -e "--------------------------------------------------"
    echo -e "1. ${YELLOW}安装并启用核心插件：${NC}"
    echo -e "   a. 在 [插件配置] 页面，找到 ${GREEN}'auth'${NC} 和 ${GREEN}'inspect'${NC} 插件，并点击开关 ${GREEN}启用${NC} 它们（通常默认已安装）。"
    echo -e "   b. 如果找不到，请在 [插件市场] 中搜索并安装它们。"
    echo -e "2. ${YELLOW}创建管理员账户：${NC}"
    echo -e "   a. 在 [插件配置] 中，找到 ${GREEN}'auth'${NC} 插件并点击 ${GREEN}[配置]${NC}。"
    echo -e "   b. 在 ${GREEN}'users'${NC} 列表中点击 ${GREEN}[添加]${NC}，设置您的管理员 ${GREEN}用户名${NC} 和 ${GREEN}密码${NC}。"
    echo -e "   c. 保存后，点击 Koishi 界面左下角的头像，使用您刚创建的账户登录。"
    echo -e "3. ${YELLOW}绑定主人QQ号：${NC}"
    echo -e "   a. 使用您的 ${GREEN}主人QQ号${NC}，向机器人发送消息：${GREEN}inspect${NC}"
    echo -e "   b. 机器人会回复您的平台信息，记下 ${GREEN}平台 (platform)${NC} 和 ${GREEN}用户 ID (userId)${NC}。"
    echo -e "   c. 返回 Koishi 界面，点击左下角已登录的头像，选择 ${GREEN}[平台绑定]${NC}。"
    echo -e "   d. 输入刚才获取的 ${GREEN}平台${NC} 和 ${GREEN}用户 ID${NC}，点击确定。"
    echo -e "   e. 按照屏幕提示，将显示的 ${GREEN}验证码${NC} 发送给机器人，即可完成绑定，获得最高权限。"

    print_color "$BLUE" "\n==================== 管理与维护 ===================="
    echo -e "您的所有项目文件都位于: ${YELLOW}~/${project_dir}${NC}"
    echo -e "如需管理服务，请先进入该目录: ${YELLOW}cd ~/${project_dir}${NC}"
    echo -e "常用命令:"
    echo -e "  - 停止服务: ${YELLOW}docker compose down${NC}"
    echo -e "  - 启动服务: ${YELLOW}docker compose up -d${NC}"
    echo -e "  - 查看日志: ${YELLOW}docker compose logs -f${NC}"
    print_color "$BLUE" "==================================================\n"
}

#==============================================================================
# 主函数
# 负责脚本整体执行流程控制和用户交互
#==============================================================================

# 主函数
# 功能:
#   - 协调各模块的执行顺序
#   - 提供清晰的部署进度反馈
#   - 确保部署流程的完整性
# 执行流程:
#   1. 环境检查和准备
#   2. 依赖组件安装
#   3. 用户配置收集
#   4. 服务部署和启动
#   5. 配置总结展示
# 错误处理:
#   - 各阶段错误捕获
#   - 友好的错误提示
#   - 失败后的清理操作
function main() {
    clear
    print_color "$BLUE" "========================================================"
    print_color "$BLUE" "      Koishi + NapCat QQ机器人 一键部署脚本"
    print_color "$BLUE" "========================================================"
    
    check_root
    install_dependencies
    handle_location
    install_docker
    check_docker_compose
    collect_user_config
    create_and_deploy
    show_summary
}

# --- 脚本入口 ---
main