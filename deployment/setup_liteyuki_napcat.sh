#!/bin/bash

# 任何命令执行失败则立即退出
set -e

#================================================================================
# 轻雪机器人 + NapCat 一键部署脚本 (v3 - 优化国内下载体验)
#
# 脚本说明:
#   本脚本为电脑小白用户设计，旨在提供一个自动化的轻雪机器人 + NapCat 部署方案。
#   通过 Docker 和 Docker Compose 技术，实现快速部署和简单维护。脚本会自动处理
#   环境准备、依赖安装、服务配置等复杂步骤，并提供清晰的后续配置指引。
#
# 核心功能:
#   1. 智能环境准备
#      - 自动检测并安装 Docker 和 Git
#      - 根据用户服务器位置智能优化软件源和 Docker 镜像加速
#   2. 自动化部署
#      - 交互式收集少量必要配置
#      - 自动拉取轻雪机器人源码，并为国内用户提供清晰的加速指引和默认选项
#      - 自动生成 Dockerfile 和 Docker Compose 配置文件
#      - 一键部署轻雪机器人和 Napcat 适配器
#   3. 详尽的配置指引
#      - 提供详细的分步图文式说明，指导用户完成 Napcat 的 QQ 登录和与机器人的对接
#   4. 强大的容错性
#      - 当脚本执行失败或被用户中途取消 (Ctrl+C) 时，会自动清理所有已创建的
#        文件和 Docker 容器，确保环境的纯净。
#
# 技术栈:
#   - 轻雪机器人 (Lihgtsnow-Bot): 基于 NoneBot2 的 QQ 机器人
#   - NapCat: QQ 协议适配器，作为 OneBot v11 反向 WebSocket 客户端
#   - Docker: 容器化部署和管理
#
# 使用说明:
#   1. 将此脚本保存为 setup_lightsnow_napcat.sh
#   2. 赋予执行权限: chmod +x setup_lightsnow_napcat.sh
#   3. 以 root 权限运行: sudo ./setup_lightsnow_napcat.sh
#   4. 按照终端提示完成交互式配置
#
# 注意事项:
#   - 运行脚本需要 root 权限
#   - 请确保服务器防火墙已开放所需端口 (默认为 6099 和 8080)
#   - 建议在纯净的 Debian 12 或 Ubuntu 系统上运行
#================================================================================

#--- 终端颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#--- 全局变量 ---
IS_CHINA=0
SERVER_PUBLIC_IP=""
PROJECT_DIR="lightsnow-project"
BOT_PORT=8080
BOT_TOKEN=""
SCRIPT_SUCCESS=0 # 脚本成功完成的标志，0=失败/进行中, 1=成功

#==============================================================================
# 清理函数
#==============================================================================

# 当脚本失败或被中断时执行此函数
function cleanup_on_failure() {
    # 仅在脚本未成功完成时执行清理
    if [ "$SCRIPT_SUCCESS" -eq 0 ]; then
        print_color "$RED" "\n\n脚本未能成功完成或被中断。"
        print_color "$YELLOW" "正在自动清理残留环境，请稍候..."

        # 检查项目目录是否存在
        if [ -d "$PROJECT_DIR" ]; then
            cd "$PROJECT_DIR"
            # 检查 docker-compose.yml 是否存在，以及 docker 命令是否可用
            if [ -f "docker-compose.yml" ] && command_exists docker; then
                print_color "$YELLOW" "正在停止并移除相关的 Docker 容器..."
                # 使用 --volumes 确保清理所有相关数据
                docker compose down --volumes >/dev/null 2>&1
            fi
            cd ..
            print_color "$YELLOW" "正在删除项目目录: $PROJECT_DIR..."
            rm -rf "$PROJECT_DIR"
        fi
        
        print_color "$GREEN" "环境清理完毕。"
    fi
}

# 设置 trap，捕获退出(EXIT)、中断(INT)、终止(TERM)信号
trap cleanup_on_failure EXIT INT TERM

#==============================================================================
# 辅助函数
#==============================================================================

# 打印带颜色的消息
function print_color() {
    COLOR=$1
    MESSAGE=$2
    echo -e "${COLOR}${MESSAGE}${NC}"
}

# 检查命令是否存在
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查是否以 root 权限运行
function check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_color "$RED" "错误: 此脚本必须以 root 用户身份运行。"
        print_color "$YELLOW" "请尝试使用 'sudo ./setup_lightsnow_napcat.sh' 运行。"
        exit 1
    fi
}

# 暂停脚本，等待用户按回车键继续
function pause_prompt() {
    print_color "$YELLOW" "\n$1"
    read -p "请按 [Enter] 键继续..."
}

# 获取服务器公网 IP
function get_public_ip() {
    print_color "$BLUE" "正在获取服务器公网 IP 地址..."
    local ip
    ip=$(curl -s https://ifconfig.me)
    [ -z "$ip" ] && ip=$(curl -s https://api.ipify.org)
    [ -z "$ip" ] && ip=$(curl -s https://ipinfo.io/ip)
    
    if [ -z "$ip" ]; then
        print_color "$RED" "自动获取公网 IP 失败。"
        while true; do
            read -p "请输入您的服务器公网 IP: " ip
            if [[ -n "$ip" ]]; then
                break
            else
                print_color "$RED" "IP 地址不能为空，请重新输入。"
            fi
        done
    fi
    SERVER_PUBLIC_IP=$ip
    print_color "$GREEN" "服务器公网 IP 为: $SERVER_PUBLIC_IP"
}

#==============================================================================
# 环境准备与安装
#==============================================================================

# 检测操作系统
function detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "debian" || "$ID" == "ubuntu" ]]; then
            print_color "$GREEN" "检测到兼容的操作系统: $PRETTY_NAME"
        else
            print_color "$RED" "错误: 此脚本仅支持 Debian 和 Ubuntu 系统。"
            exit 1
        fi
    else
        print_color "$RED" "错误: 无法检测到操作系统类型。"
        exit 1
    fi
}

# 初始设置，询问地理位置
function initial_setup() {
    print_color "$BLUE" "\n--- 1. 环境初始化 ---"
    print_color "$YELLOW" "为了优化下载速度，请选择您的服务器所在区域。"
    
    local choice
    while true; do
        read -p "您的服务器是否位于中国大陆？(y/n): " choice
        case "$choice" in
            y|Y )
                IS_CHINA=1
                print_color "$GREEN" "已选择中国大陆。后续将使用镜像源进行加速。"
                break
                ;;
            n|N )
                IS_CHINA=0
                print_color "$GREEN" "已选择国外。后续将使用官方源进行安装。"
                break
                ;;
            * ) print_color "$RED" "无效输入，请输入 'y' 或 'n'。" ;;
        esac
    done
}

# 安装基础依赖
function install_dependencies() {
    print_color "$BLUE" "\n--- 2. 安装基础依赖 (Git, Curl) ---"
    apt-get update >/dev/null 2>&1
    
    for pkg in git curl; do
        if ! command_exists $pkg; then
            print_color "$YELLOW" "正在安装 $pkg..."
            apt-get install -y $pkg
            if ! command_exists $pkg; then
                print_color "$RED" "$pkg 安装失败，请手动安装后再运行此脚本。"
                exit 1
            fi
            print_color "$GREEN" "$pkg 安装成功。"
        else
            print_color "$GREEN" "$pkg 已安装。"
        fi
    done
}

# 安装 Docker
function install_docker() {
    print_color "$BLUE" "\n--- 3. 安装 Docker 环境 ---"
    if command_exists docker; then
        print_color "$GREEN" "Docker 已安装，跳过安装步骤。"
    else
        print_color "$YELLOW" "未检测到 Docker，正在为您安装..."
        if [ $IS_CHINA -eq 1 ]; then
            print_color "$YELLOW" "使用国内镜像源安装 Docker..."
            bash <(curl -sSL https://linuxmirrors.cn/main.sh) # 更换系统源
            bash <(curl -sSL https://linuxmirrors.cn/docker.sh) # 安装并配置 Docker 加速
        else
            print_color "$YELLOW" "使用官方脚本安装 Docker..."
            if ! (curl -fsSL https://get.docker.com | bash); then
                print_color "$RED" "Docker 安装失败。请检查网络或尝试手动安装。"
                exit 1
            fi
        fi
        print_color "$GREEN" "Docker 安装成功。"
    fi

    # 启动并设置 Docker 开机自启
    systemctl start docker
    systemctl enable docker
    print_color "$GREEN" "Docker 服务已启动并设为开机自启。"

    # 验证 Docker Compose v2
    if ! docker compose version >/dev/null 2>&1; then
        print_color "$RED" "Docker Compose (v2 插件) 未安装或配置不正确。"
        print_color "$YELLOW" "请检查您的 Docker 安装或手动安装 Docker Compose 插件。"
        exit 1
    else
        print_color "$GREEN" "Docker Compose 已准备就绪。"
    fi
}

#==============================================================================
# 用户配置与源码下载
#==============================================================================

# 收集用户配置
function collect_user_config() {
    print_color "$BLUE" "\n--- 4. 收集机器人配置信息 ---"
    
    read -p "请输入项目部署的目录名 (默认为 lightsnow-project): " dir_input
    PROJECT_DIR=${dir_input:-lightsnow-project}

    read -p "请输入轻雪机器人监听的端口 (默认为 8080): " port_input
    BOT_PORT=${port_input:-8080}

    print_color "$YELLOW" "为了安全，建议为机器人连接设置一个访问令牌 (Access Token)。"
    read -p "请输入您的访问令牌 (留空将不设置): " token_input
    BOT_TOKEN=${token_input}
}

# 克隆轻雪机器人仓库
function clone_robot_repo() {
    print_color "$BLUE" "\n--- 5. 下载轻雪机器人源码 ---"
    
    # 检查目标目录是否存在，提供更灵活的选项
    if [ -d "$PROJECT_DIR" ]; then
        print_color "$YELLOW" "目录 '$PROJECT_DIR' 已存在。"
        read -p "是否删除现有目录并重新下载? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_color "$YELLOW" "正在删除现有目录..."
            if ! rm -rf "$PROJECT_DIR"; then
                print_color "$RED" "删除现有目录失败，请检查权限"
                exit 1
            fi
        else
            print_color "$YELLOW" "已跳过下载步骤"
            return 0
        fi
    fi

    local official_repo_url="https://github.com/Ikaros-521/Lihgtsnow-Bot.git"
    local clone_url="$official_repo_url"  # 默认使用官方地址
    # 使用第一个代码中的官方镜像源作为默认代理
    local default_proxy_url="https://git.liteyuki.org/bot/app"

    # 显示仓库信息
    print_color "$YELLOW" "轻雪机器人的官方仓库地址是: ${GREEN}$official_repo_url${NC}"

    # 国内用户特殊处理
    if [ $IS_CHINA -eq 1 ]; then
        print_color "$YELLOW" "检测到您位于国内，推荐使用代理加速下载。"
        print_color "$YELLOW" "可用的代理服务: https://gh-proxy.com/ 或 https://github.akams.cn/"
        print_color "$YELLOW" "官方镜像源: ${GREEN}$default_proxy_url${NC}"
        
        read -p "请输入克隆地址 (留空使用官方镜像源，输入'0'使用官方地址): " custom_clone_url
        
        # 处理用户输入
        if [ -z "$custom_clone_url" ]; then
            clone_url="$default_proxy_url"
        elif [ "$custom_clone_url" = "0" ]; then
            clone_url="$official_repo_url"
        else
            clone_url="$custom_clone_url"
        fi
    fi

    # 显示克隆信息并执行克隆，增加深度参数加快速度
    print_color "$YELLOW" "正在从 ${GREEN}$clone_url${NC} 克隆代码..."
    if git clone --depth=1 "$clone_url" "$PROJECT_DIR"; then
        print_color "$GREEN" "✅ 轻雪机器人源码下载成功，位于目录: $PROJECT_DIR"
        return 0
    else
        print_color "$RED" "❌ 源码下载失败！"
        
        # 针对国内用户提供额外帮助信息
        if [ $IS_CHINA -eq 1 ]; then
            print_color "$YELLOW" "建议尝试其他代理地址，例如:"
            print_color "$YELLOW" "https://ghproxy.com/${official_repo_url}"
            print_color "$YELLOW" "https://github.akams.cn/${official_repo_url}"
        fi
        
        exit 1
    fi
}

#==============================================================================
# 配置文件生成与部署
#==============================================================================

# 配置轻雪机器人
function configure_robot() {
    print_color "$BLUE" "\n--- 6. 自动配置机器人环境 ---"
    cd "$PROJECT_DIR"

    # 创建 .env.prod 文件
    print_color "$YELLOW" "正在生成机器人配置文件 .env.prod..."
    cat > .env.prod << EOF
# .env.prod
ENVIRONMENT=prod
HOST=0.0.0.0
PORT=$BOT_PORT
LOG_LEVEL=INFO
SUPERUSERS=["123456789"] # 请在机器人运行后通过指令添加
NICKNAME=["轻雪"]
COMMAND_START=["/"]
ACCESS_TOKEN=$BOT_TOKEN
EOF
    print_color "$GREEN" ".env.prod 文件创建成功。"

    # 创建 Dockerfile
    print_color "$YELLOW" "正在为轻雪机器人生成 Dockerfile..."
    cat > Dockerfile << EOF
# 使用 Python 3.10-slim 作为基础镜像
FROM python:3.10-slim

# 设置工作目录
WORKDIR /app

# 复制依赖文件
COPY requirements.txt .

# 安装依赖，如果在中国则使用清华镜像源
RUN if [ "$IS_CHINA" = "1" ]; then \
        pip install --no-cache-dir -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple; \
    else \
        pip install --no-cache-dir -r requirements.txt; \
    fi

# 复制项目所有文件
COPY . .

# 暴露端口
EXPOSE $BOT_PORT

# 启动命令
CMD ["nb", "run", "--host", "0.0.0.0", "--port", "$BOT_PORT"]
EOF
    # 将 IS_CHINA 变量传递给 Docker build 过程
    sed -i "s/IS_CHINA=1/IS_CHINA=${IS_CHINA}/" Dockerfile
    print_color "$GREEN" "Dockerfile 创建成功。"
    
    cd ..
}

# 创建 docker-compose.yml 文件并部署
function create_and_deploy() {
    print_color "$BLUE" "\n--- 7. 创建 Docker Compose 配置并部署 ---"
    cd "$PROJECT_DIR"

    # 获取 UID 和 GID
    local uid=$(id -u)
    local gid=$(id -g)

    print_color "$YELLOW" "正在生成 docker-compose.yml..."
    cat > docker-compose.yml << EOF
services:
  napcat:
    image: mlikiowa/napcat-docker:latest
    container_name: napcat
    restart: always
    network_mode: bridge
    mac_address: 02:42:ac:11:00:02
    environment:
      - NAPCAT_UID=${uid}
      - NAPCAT_GID=${gid}
    ports:
      - "6099:6099"
      - "3001:3001"
    volumes:
      - ./napcat_data/config:/app/napcat/config
      - ./napcat_data/qq:/app/.config/QQ

  lightsnow:
    build: .
    container_name: lightsnow-bot
    restart: always
    network_mode: bridge
    ports:
      - "${BOT_PORT}:${BOT_PORT}"
    volumes:
      - ./:/app
EOF
    print_color "$GREEN" "docker-compose.yml 文件创建成功。"

    # 启动服务
    print_color "$YELLOW" "正在启动所有服务，首次启动需要拉取和构建镜像，可能需要几分钟..."
    docker compose up -d
    print_color "$GREEN" "服务已成功在后台启动！"
    cd ..
}

#==============================================================================
# 最终指引
#==============================================================================

function final_instructions() {
    print_color "$BLUE" "\n======================== 部署完成 ========================"
    print_color "$GREEN" "恭喜！轻雪机器人和 NapCat 已成功部署并正在后台运行。"
    print_color "$YELLOW" "\n接下来，请务必按照以下步骤完成手动配置："
    
    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 1: 登录 NapCat 并扫描二维码"
    echo -e "--------------------------------------------------"
    echo -e "1. 在浏览器中打开 NapCat WebUI 地址: ${GREEN}http://${SERVER_PUBLIC_IP}:6099/webui${NC}"
    echo -e "2. 首次登录，请输入默认令牌: ${GREEN}napcat${NC}，然后点击登录。"
    echo -e "3. 屏幕上会出现一个二维码，请使用您准备作为机器人的 QQ 手机版扫描该二维码进行登录。"
    
    pause_prompt "请在完成 QQ 扫码登录后，按回车键继续下一步指引..."

    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 2: 在 NapCat 中配置与轻雪机器人的连接"
    echo -e "--------------------------------------------------"
    echo -e "1. 登录成功后，您会看到 NapCat 的主界面。"
    echo -e "2. 在左侧菜单栏中，点击 ${GREEN}[网络配置]${NC}。"
    echo -e "3. 在右侧界面中，点击 ${GREEN}[新建]${NC} 按钮。"
    echo -e "4. 在弹出的窗口中，选择连接方式为 ${GREEN}[Websocket客户端]${NC}。"
    echo -e "5. 现在，请依次填写以下信息："
    echo -e "   - ${YELLOW}名称:${NC}         随意填写，例如: ${GREEN}lightsnow_bot${NC}"
    echo -e "   - ${YELLOW}URL:${NC}          这是关键！请填写: ${GREEN}ws://${SERVER_PUBLIC_IP}:${BOT_PORT}/onebot/v11/ws${NC}"
    echo -e "   - ${YELLOW}信息格式:${NC}     保持默认的 ${GREEN}Array${NC}"
    echo -e "   - ${YELLOW}Token:${NC}        ${GREEN}${BOT_TOKEN:-（您未设置Token）}${NC} (如果您之前设置了令牌，请务必填写)"
    echo -e "6. 填写完毕后，点击 ${GREEN}[保存]${NC} 按钮。"
    echo -e "7. 保存后，您应该能看到列表里新增了一项连接，并且状态显示为 ${GREEN}已连接${NC}。"
    echo -e "\n${GREEN}至此，您的机器人已经完全上线并可以正常工作了！${NC}"

    print_color "$BLUE" "\n====================== 管理与维护 ======================"
    echo -e "您的所有项目文件都位于当前目录下的: ${YELLOW}${PROJECT_DIR}${NC}"
    echo -e "如需管理服务，请先进入该目录: ${YELLOW}cd ${PROJECT_DIR}${NC}"
    echo -e "常用命令:"
    echo -e "  - 停止所有服务: ${YELLOW}docker compose down${NC}"
    echo -e "  - 启动所有服务: ${YELLOW}docker compose up -d${NC}"
    echo -e "  - 查看实时日志: ${YELLOW}docker compose logs -f${NC}"
    echo -e "  - 查看指定服务日志: ${YELLOW}docker compose logs -f lightsnow-bot${NC} 或 ${YELLOW}docker compose logs -f napcat${NC}"
    print_color "$BLUE" "========================================================\n"
}

#==============================================================================
# 主函数
#==============================================================================
function main() {
    clear
    print_color "$BLUE" "========================================================"
    print_color "$BLUE" "      轻雪机器人 + NapCat QQ机器人 一键部署脚本"
    print_color "$BLUE" "========================================================"
    
    check_root
    detect_os
    initial_setup
    install_dependencies
    install_docker
    get_public_ip
    collect_user_config
    clone_robot_repo
    configure_robot
    create_and_deploy
    final_instructions

    # 所有步骤成功完成后，将成功标志设为1，以防止 cleanup_on_failure 函数执行清理
    SCRIPT_SUCCESS=1
}

# --- 脚本入口 ---
main
