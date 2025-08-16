#!/bin/bash

# 任何命令执行失败则立即退出
set -e

#================================================================================
# 轻雪机器人 + NapCat 一键部署脚本 (最终版)
#
# 脚本说明:
#   本脚本为电脑小白用户设计，旨在提供一个自动化的轻雪机器人 + NapCat 部署方案。
#   采用混合部署模式：Napcat 在 Docker 中运行，轻雪机器人作为 systemd
#   服务直接在宿主机上运行，以获得最佳的稳定性和易于调试的特性。
#
# 核心功能:
#   1. 智能环境准备: 自动安装所有必要依赖，并根据服务器位置优化下载速度。
#   2. 自动化部署: 自动拉取源码、配置环境、创建后台服务并启动。
#   3. 详尽指引: 提供清晰的后续配置步骤和日常管理命令。
#   4. 强大容错性: 脚本意外中断时，会自动清理残留环境，避免留下垃圾文件。
#
# 技术栈:
#   - 轻雪机器人 (Lihgtsnow-Bot): 作为 systemd 服务运行
#   - NapCat: 在 Docker 容器中运行
#   - Python Virtual Environment (venv): 隔离机器人运行环境
#   - Systemd: 进程守护与日志管理
#
# 使用说明:
#   1. 将此脚本保存为 setup_lightsnow_napcat.sh
#   2. 赋予执行权限: chmod +x setup_lightsnow_napcat.sh
#   3. 以 root 权限运行: sudo ./setup_lightsnow_napcat.sh
#   4. 按照终端提示完成交互式配置
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
BOT_PORT=20216 # 固定使用官方默认端口
BOT_TOKEN=""
SUPERUSER_QQ=""
SCRIPT_SUCCESS=0

#==============================================================================
# 清理函数
#==============================================================================

# 当脚本失败或被中断时，执行此函数以清理环境
function cleanup_on_failure() {
    if [ "$SCRIPT_SUCCESS" -eq 0 ]; then
        print_color "$RED" "\n\n脚本未能成功完成或被中断。"
        print_color "$YELLOW" "正在自动清理残留环境，请稍候..."

        # 清理 systemd 服务
        local SERVICE_FILE="/etc/systemd/system/lightsnow-bot.service"
        if [ -f "$SERVICE_FILE" ]; then
            print_color "$YELLOW" "正在停止并移除 systemd 服务..."
            systemctl stop lightsnow-bot || true
            systemctl disable lightsnow-bot || true
            rm -f "$SERVICE_FILE"
            systemctl daemon-reload
        fi

        # 清理 Docker (Napcat)
        if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker-compose.yml" ] && command_exists docker; then
            print_color "$YELLOW" "正在停止并移除 Napcat Docker 容器..."
            cd "$PROJECT_DIR"
            docker compose down --volumes >/dev/null 2>&1
            cd ..
        fi

        # 清理项目文件
        if [ -d "$PROJECT_DIR" ]; then
            print_color "$YELLOW" "正在删除项目目录: $PROJECT_DIR..."
            rm -rf "$PROJECT_DIR"
        fi
        
        print_color "$GREEN" "环境清理完毕。"
    fi
}

# 设置 trap，捕获退出(EXIT)、中断(INT)、终止(TERM)信号以触发清理函数
trap cleanup_on_failure EXIT INT TERM

#==============================================================================
# 辅助函数
#==============================================================================

function print_color() {
    COLOR=$1
    MESSAGE=$2
    echo -e "${COLOR}${MESSAGE}${NC}"
}

function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

function check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_color "$RED" "错误: 此脚本必须以 root 用户身份运行。"
        print_color "$YELLOW" "请尝试使用 'sudo ./setup_lightsnow_napcat.sh' 运行。"
        exit 1
    fi
}

function pause_prompt() {
    print_color "$YELLOW" "\n$1"
    read -p "请按 [Enter] 键继续..."
}

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
    print_color "$BLUE" "\n--- 2. 安装基础依赖 ---"
    apt-get update >/dev/null 2>&1
    
    # 安装 git 和 curl
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

    # 安装 Python 虚拟环境工具
    if ! dpkg -s python3-venv &> /dev/null; then
        print_color "$YELLOW" "正在安装 python3-venv..."
        apt-get install -y python3-venv
        if ! dpkg -s python3-venv &> /dev/null; then
            print_color "$RED" "python3-venv 安装失败，请手动安装后再运行此脚本。"
            exit 1
        fi
        print_color "$GREEN" "python3-venv 安装成功。"
    else
        print_color "$GREEN" "python3-venv 已安装。"
    fi

    # 为 htmlrender 插件安装浏览器运行所需的系统依赖
    print_color "$YELLOW" "正在为 htmlrender 插件安装浏览器运行依赖..."
    apt-get install -y libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libatspi2.0-0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2
    print_color "$GREEN" "浏览器依赖安装完成。"

    print_color "$YELLOW" "正在安装中文字体 (文泉驿正黑)..."
    apt-get install -y fonts-wqy-zenhei
    print_color "$GREEN" "中文字体安装完成。"
}


function install_docker() {
    print_color "$BLUE" "\n--- 3. 安装 Docker 环境 (用于 Napcat) ---"
    if command_exists docker; then
        print_color "$GREEN" "Docker 已安装，跳过安装步骤。"
    else
        print_color "$YELLOW" "未检测到 Docker，正在为您安装..."
        if [ $IS_CHINA -eq 1 ]; then
            print_color "$YELLOW" "使用国内镜像源安装 Docker..."
            bash <(curl -sSL https://linuxmirrors.cn/main.sh)
            bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
        else
            print_color "$YELLOW" "使用官方脚本安装 Docker..."
            if ! (curl -fsSL https://get.docker.com | bash); then
                print_color "$RED" "Docker 安装失败。请检查网络或尝试手动安装。"
                exit 1
            fi
        fi
        print_color "$GREEN" "Docker 安装成功。"
    fi

    systemctl start docker
    systemctl enable docker
    print_color "$GREEN" "Docker 服务已启动并设为开机自启。"

    if ! docker compose version >/dev/null 2>&1; then
        print_color "$RED" "Docker Compose (v2 插件) 未安装或配置不正确。"
        exit 1
    else
        print_color "$GREEN" "Docker Compose 已准备就绪。"
    fi
}

#==============================================================================
# 用户配置与源码下载
#==============================================================================

function collect_user_config() {
    print_color "$BLUE" "\n--- 4. 收集机器人配置信息 ---"
    
    read -p "请输入项目部署的目录名 (默认为 lightsnow-project): " dir_input
    PROJECT_DIR=${dir_input:-lightsnow-project}

    print_color "$GREEN" "轻雪机器人将使用默认端口: $BOT_PORT"

    print_color "$YELLOW" "为了安全，建议为机器人连接设置一个访问令牌 (Access Token)。"
    read -p "请输入您的访问令牌 (留空将不设置): " token_input
    BOT_TOKEN=${token_input}

    print_color "$YELLOW" "\n请输入您的 QQ 号码，以设置为机器人的超级管理员 (Superuser)。"
    while true; do
        read -p "请输入您的 QQ 号: " qq_input
        if [[ "$qq_input" =~ ^[1-9][0-9]{4,10}$ ]]; then
            SUPERUSER_QQ=$qq_input
            print_color "$GREEN" "超级管理员 QQ 已设置为: $SUPERUSER_QQ"
            break
        else
            print_color "$RED" "无效的 QQ 号码，请重新输入。"
        fi
    done
}


function clone_robot_repo() {
    print_color "$BLUE" "\n--- 5. 下载轻雪机器人源码 ---"
    
    if [ -d "$PROJECT_DIR" ]; then
        print_color "$YELLOW" "目录 '$PROJECT_DIR' 已存在。"
        read -p "是否删除现有目录并重新下载? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_color "$YELLOW" "正在删除现有目录..."
            rm -rf "$PROJECT_DIR"
        else
            print_color "$YELLOW" "已跳过下载步骤。"
            return
        fi
    fi

    local official_repo_url="https://github.com/Ikaros-521/Lihgtsnow-Bot.git"
    local clone_url="$official_repo_url"
    local default_proxy_url="https://git.liteyuki.org/bot/app"

    print_color "$YELLOW" "轻雪机器人的官方仓库地址是: ${GREEN}$official_repo_url${NC}"

    if [ $IS_CHINA -eq 1 ]; then
        print_color "$YELLOW" "检测到您位于国内，推荐使用代理加速下载。"
        print_color "$YELLOW" "可用的代理服务: https://gh-proxy.com/ 或 https://github.akams.cn/"
        print_color "$YELLOW" "官方镜像源: ${GREEN}$default_proxy_url${NC}"
        read -p "请输入克隆地址 (留空使用官方镜像源，输入'0'使用官方地址): " custom_clone_url
        
        if [ -z "$custom_clone_url" ]; then
            clone_url="$default_proxy_url"
        elif [ "$custom_clone_url" = "0" ]; then
            clone_url="$official_repo_url"
        else
            clone_url="$custom_clone_url"
        fi
    fi

    print_color "$YELLOW" "正在从 ${GREEN}$clone_url${NC} 克隆代码..."
    if git clone --depth=1 "$clone_url" "$PROJECT_DIR"; then
        print_color "$GREEN" "✅ 轻雪机器人源码下载成功，位于目录: $PROJECT_DIR"
    else
        print_color "$RED" "❌ 源码下载失败！"
        exit 1
    fi
}

#==============================================================================
# 机器人环境配置与部署
#==============================================================================

function setup_python_environment() {
    print_color "$BLUE" "\n--- 6. 配置 Python 环境并安装依赖 ---"
    cd "$PROJECT_DIR"

    print_color "$YELLOW" "正在创建 Python 虚拟环境..."
    python3 -m venv venv
    
    print_color "$YELLOW" "正在激活虚拟环境并安装依赖，请稍候..."
    local pip_cmd="./venv/bin/pip install --no-cache-dir -r requirements.txt"
    if [ $IS_CHINA -eq 1 ]; then
        pip_cmd+=" -i https://pypi.tuna.tsinghua.edu.cn/simple"
    fi
    
    $pip_cmd
    
    print_color "$GREEN" "✅ Python 依赖安装完成。"
    cd ..
}

# 创建并启动 systemd 服务
function create_and_start_systemd_service() {
    print_color "$BLUE" "\n--- 7. 创建并启动机器人后台服务 (Systemd) ---"
    
    local project_abs_path
    project_abs_path=$(realpath "$PROJECT_DIR")
    
    print_color "$YELLOW" "正在生成机器人配置文件 .env.prod..."
    cat > "${project_abs_path}/.env.prod" << EOF
# .env.prod
ENVIRONMENT=prod
HOST=0.0.0.0
PORT=$BOT_PORT
LOG_LEVEL=INFO
SUPERUSERS=["${SUPERUSER_QQ}"]
NICKNAME=["轻雪"]
COMMAND_START=["/"]
ACCESS_TOKEN=$BOT_TOKEN
EOF
    print_color "$GREEN" ".env.prod 文件创建成功。"

    print_color "$YELLOW" "正在创建 systemd 服务文件..."
    local service_file="/etc/systemd/system/lightsnow-bot.service"
    cat > "$service_file" << EOF
[Unit]
Description=Lightsnow QQ Bot Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${project_abs_path}

ExecStart=${project_abs_path}/venv/bin/python -u main.py
Restart=on-failure
RestartSec=5s

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    print_color "$GREEN" "Systemd 服务文件创建成功: $service_file"

    print_color "$YELLOW" "正在重载 systemd 并启动服务..."
    systemctl daemon-reload
    systemctl enable lightsnow-bot
    systemctl start lightsnow-bot

    # 等待几秒钟让服务有时间启动或失败
    sleep 3
    if systemctl is-active --quiet lightsnow-bot; then
        print_color "$GREEN" "✅ 轻雪机器人服务已成功启动！"
    else
        print_color "$RED" "❌ 轻雪机器人服务启动失败！"
        print_color "$YELLOW" "请使用 'journalctl -u lightsnow-bot -n 50' 命令查看详细错误日志。"
        exit 1
    fi
}



function deploy_napcat() {
    print_color "$BLUE" "\n--- 8. 部署 Napcat 适配器 (Docker) ---"
    cd "$PROJECT_DIR"

    local uid=$(id -u)
    local gid=$(id -g)

    print_color "$YELLOW" "正在生成 docker-compose.yml (仅包含 Napcat)..."
    cat > docker-compose.yml << EOF
services:
  napcat:
    image: docker.gh-proxy.com/mlikiowa/napcat-docker:latest
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
EOF
    print_color "$GREEN" "docker-compose.yml 文件创建成功。"

    print_color "$YELLOW" "正在后台启动 Napcat 服务..."
    docker compose up -d
    print_color "$GREEN" "✅ Napcat 服务已成功在后台启动！"
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
    echo -e "   - ${YELLOW}URL:${NC}          ${RED}这是最关键的一步！请务必填写:${NC} ${GREEN}ws://172.17.0.1:${BOT_PORT}/onebot/v11/ws${NC}"
    echo -e "     ${YELLOW}(注意: 这里使用 172.17.0.1 是为了让 Docker 容器能访问到服务器本身)${NC}"
    echo -e "   - ${YELLOW}信息格式:${NC}     保持默认的 ${GREEN}Array${NC}"
    echo -e "   - ${YELLOW}Token:${NC}        ${GREEN}${BOT_TOKEN:-（您未设置Token）}${NC} (如果您之前设置了令牌，请务必填写)"
    echo -e "6. 填写完毕后，点击 ${GREEN}[保存]${NC} 按钮。"
    echo -e "7. 保存后，您应该能看到列表里新增了一项连接，并且状态显示为 ${GREEN}已连接${NC}。"
    echo -e "\n${GREEN}至此，您的机器人已经完全上线并可以正常工作了！${NC}"

    print_color "$BLUE" "\n====================== 管理与维护 ======================"
    echo -e "您的所有项目文件都位于当前目录下的: ${YELLOW}${PROJECT_DIR}${NC}"
    echo -e "\n--- 轻雪机器人管理 (Systemd) ---"
    echo -e "  - 查看状态: ${YELLOW}systemctl status lightsnow-bot${NC}"
    echo -e "  - 启动服务: ${YELLOW}systemctl start lightsnow-bot${NC}"
    echo -e "  - 停止服务: ${YELLOW}systemctl stop lightsnow-bot${NC}"
    echo -e "  - 重启服务: ${YELLOW}systemctl restart lightsnow-bot${NC}"
    echo -e "  - ${RED}查看实时日志:${NC} ${YELLOW}journalctl -u lightsnow-bot -f${NC} (按 Ctrl+C 退出)"
    
    echo -e "\n--- Napcat 管理 (Docker) ---"
    echo -e "  - (先进入项目目录: cd ${PROJECT_DIR})"
    echo -e "  - 停止服务: ${YELLOW}docker compose down${NC}"
    echo -e "  - 启动服务: ${YELLOW}docker compose up -d${NC}"
    echo -e "  - 查看日志: ${YELLOW}docker compose logs -f napcat${NC}"
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
    setup_python_environment
    create_and_start_systemd_service
    deploy_napcat
    final_instructions

    SCRIPT_SUCCESS=1
}

# --- 脚本入口 ---
main
