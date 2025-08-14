#!/bin/bash

#================================================================================
# 轻雪机器人 + NapCat 一键部署脚本 (v3)
#
# 脚本说明:
#   本脚本为 Ubuntu/Debian 用户提供了一个自动化的轻雪机器人 + NapCat 部署方案。
#   轻雪机器人是一款功能丰富的 QQ 机器人，基于 NoneBot2 框架开发。NapCat 是一个
#   稳定可靠的 QQ 协议适配器，支持多种连接方式。
#
#   本脚本通过 Docker 部署 NapCat，并在宿主机上部署轻雪机器人，实现了环境隔离与
#   高效通信。脚本会自动处理环境准备、依赖安装、服务配置等复杂步骤，并提供
#   详细的后续配置指引。
#
# 核心特性:
#   - 全自动化部署：从环境准备到服务启动，全程自动化，无需手动干预
#   - 智能网络适配：根据服务器地理位置自动选择最佳软件源和镜像
#   - 多镜像源支持：提供清华、阿里、中科大、豆瓣等多个国内镜像源选择
#   - 完善的依赖处理：自动安装所有必要的系统和 Python 依赖
#   - 服务化管理：配置 systemd 服务实现开机自启和状态监控
#   - 详细配置指引：提供完整的后续配置步骤和常用管理命令
#
# 使用说明:
#   1. 将此脚本保存为 setup_liteyuki_napcat.sh
#   2. 赋予执行权限: chmod +x setup_liteyuki_napcat.sh
#   3. 以 root 权限运行: sudo ./setup_liteyuki_napcat.sh
#   4. 按照屏幕提示完成交互式配置
#
#================================================================================

#==============================================================================
# 终端颜色定义
#==============================================================================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#==============================================================================
# 辅助函数 - 提供基础功能支持
#==============================================================================

# 打印带颜色的消息，增强用户体验
# 参数:
#   $1 - 颜色代码
#   $2 - 要显示的消息
function print_color() {
    COLOR=$1
    MESSAGE=$2
    echo -e "${COLOR}${MESSAGE}${NC}"
}

# 检查命令是否存在于系统中
# 参数:
#   $1 - 要检查的命令名称
# 返回:
#   如果命令存在，返回0；否则返回非0值
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查脚本是否以root权限运行
# 如果不是root用户，显示错误信息并退出
function check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_color "$RED" "错误: 此脚本必须以 root 用户身份运行。"
        print_color "$YELLOW" "请尝试使用 'sudo ./setup_liteyuki_napcat.sh' 运行。"
        exit 1
    fi
}

# 获取服务器公网IP地址
# 尝试多个IP查询服务以提高成功率
# 返回:
#   服务器的公网IP地址
function get_public_ip() {
    print_color "$YELLOW" "正在尝试获取服务器公网IP..."
    local ip
    # 依次尝试多个IP查询服务
    ip=$(curl -s https://ifconfig.me)
    [ -z "$ip" ] && ip=$(curl -s https://api.ipify.org)
    [ -z "$ip" ] && ip=$(curl -s https://ipinfo.io/ip)
    echo "$ip"
}

# 暂停脚本执行，等待用户确认后继续
# 参数:
#   $1 - 显示给用户的提示信息
function pause_for_user() {
    print_color "$YELLOW" "\n$1"
    read -n 1 -s -r -p "请按任意键继续..."
    echo
}

#==============================================================================
# 环境准备与安装 - 配置系统环境并安装必要组件
#==============================================================================

# 根据服务器地理位置配置最佳软件源
# 为国内服务器配置镜像源加速，为海外服务器使用官方源
# 设置全局变量:
#   IS_CHINA - 标记服务器是否位于中国大陆
function handle_location() {
    print_color "$BLUE" "\n--- 1. 环境与软件源配置 ---"
    print_color "$YELLOW" "为了优化下载速度，请选择您的服务器所在区域。"
    
    while true; do
        read -p "您的服务器是否位于中国大陆？(y/n): " choice
        case "$choice" in
            y|Y )
                IS_CHINA=true
                print_color "$GREEN" "将使用中国大陆镜像源进行加速。"
                print_color "$YELLOW" "正在更换系统软件源..."
                # 使用LinuxMirrors项目提供的一键更换脚本
                bash <(curl -sSL https://linuxmirrors.cn/main.sh)
                print_color "$YELLOW" "正在配置 Docker 加速..."
                # 配置Docker镜像加速
                bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
                break
                ;;
            n|N )
                IS_CHINA=false
                print_color "$GREEN" "将使用官方源进行安装。"
                break
                ;;
            * ) print_color "$RED" "无效输入，请输入 'y' 或 'n'。" ;;
        esac
    done
}

# 安装系统核心依赖包
# 安装部署过程中必需的基础工具和库
function install_dependencies() {
    print_color "$BLUE" "\n--- 2. 安装核心依赖 ---"
    print_color "$YELLOW" "正在更新软件包列表..."
    # 静默更新软件包列表
    apt-get update >/dev/null 2>&1
    
    print_color "$YELLOW" "正在安装 curl, git, python3-venv..."
    # 安装基本工具包
    apt-get install -y curl git python3-venv
    # 验证关键依赖是否安装成功
    if ! command_exists curl || ! command_exists git || ! command_exists python3; then
        print_color "$RED" "核心依赖 (curl, git, python3) 安装失败，请手动安装后重试。"
        exit 1
    fi
    print_color "$GREEN" "核心依赖安装成功。"
}

# 安装 Playwright 浏览器自动化所需的系统依赖
# 这些依赖对于轻雪机器人的网页截图等功能至关重要
function install_playwright_deps() {
    print_color "$YELLOW" "正在为轻雪机器人安装 Playwright 系统依赖库..."
    # 安装Playwright所需的所有系统库
    apt-get install -y libnss3 libnspr4 libdbus-1-3 libatk1.0-0 libatk-bridge2.0-0 \
                       libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
                       libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 \
                       libasound2 libatspi2.0-0
    print_color "$GREEN" "Playwright 系统依赖库安装完成。"
}

# 安装 Docker 和 Docker Compose
# 根据服务器环境选择合适的安装方式并配置服务
function install_docker() {
    if ! command_exists docker; then
        print_color "$YELLOW" "未检测到 Docker，正在为您安装..."
        if [ "$IS_CHINA" = true ]; then
            # 国内服务器使用镜像加速安装Docker
            # 注意：Docker加速已在handle_location函数中配置
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
            if [ $? -ne 0 ]; then
                print_color "$RED" "Docker 安装失败。请检查网络或尝试手动安装。"
                exit 1
            fi
        else
            # 海外服务器直接使用官方安装脚本
            if ! (curl -fsSL https://get.docker.com | bash -s docker); then
                print_color "$RED" "Docker 安装失败。请检查网络或尝试手动安装。"
                exit 1
            fi
        fi
        print_color "$GREEN" "Docker 安装成功。"
    else
        print_color "$GREEN" "检测到 Docker 已安装。"
    fi
    
    # 启动Docker服务并设置开机自启
    systemctl start docker
    systemctl enable docker
    print_color "$GREEN" "Docker 服务已启动并设为开机自启。"
    
    # 检查Docker Compose是否可用（Docker v2插件形式）
    if ! docker compose version >/dev/null 2>&1; then
        print_color "$RED" "Docker Compose (v2 plugin) 未安装或配置不正确。"
        print_color "$YELLOW" "请检查您的 Docker 安装或手动安装 Docker Compose 插件。"
        exit 1
    fi
    print_color "$GREEN" "Docker Compose 已准备就绪。"
}

#==============================================================================
# 用户配置收集 - 获取用户自定义配置参数
#==============================================================================

# 选择Python包管理器(pip)的国内镜像源
# 设置全局变量:
#   PIP_INDEX_URL - 选定的pip镜像源URL
#   PIP_TRUSTED_HOST - 对应的可信主机名
function select_pip_mirror() {
    print_color "$BLUE" "\n--- Python 依赖下载加速配置 ---"
    print_color "$YELLOW" "请选择一个用于下载 Python 依赖的国内镜像源："
    
    PS3="请输入选项 (1-4): "
    select mirror in "清华大学" "阿里云" "中国科学技术大学" "豆瓣"; do
        case $mirror in
            "清华大学")
                # 清华大学镜像源配置
                PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
                PIP_TRUSTED_HOST="pypi.tuna.tsinghua.edu.cn"
                break
                ;;
            "阿里云")
                # 阿里云镜像源配置
                PIP_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/"
                PIP_TRUSTED_HOST="mirrors.aliyun.com"
                break
                ;;
            "中国科学技术大学")
                # 中科大镜像源配置
                PIP_INDEX_URL="https://pypi.mirrors.ustc.edu.cn/simple/"
                PIP_TRUSTED_HOST="pypi.mirrors.ustc.edu.cn"
                break
                ;;
            "豆瓣")
                # 豆瓣镜像源配置
                PIP_INDEX_URL="http://pypi.douban.com/simple/"
                PIP_TRUSTED_HOST="pypi.douban.com"
                break
                ;;
            *)
                print_color "$RED" "无效选项，请重新选择。"
                ;;
        esac
    done
    print_color "$GREEN" "您已选择使用 $mirror 镜像源。"
}

# 收集用户自定义配置信息
# 设置全局变量:
#   PUBLIC_IP - 服务器公网IP地址
#   project_dir - 项目部署根目录
#   superuser_qq - 机器人超级管理员QQ号
#   onebot_token - 通信安全Token
function collect_user_config() {
    print_color "$BLUE" "\n--- 3. 收集部署配置信息 ---"
    
    # 获取服务器公网IP
    PUBLIC_IP=$(get_public_ip)
    if [ -n "$PUBLIC_IP" ]; then
        print_color "$GREEN" "成功获取到公网IP: $PUBLIC_IP"
    else
        print_color "$RED" "自动获取公网IP失败！"
        # 自动获取失败时要求用户手动输入
        while true; do
            read -p "请手动输入您的服务器IP地址: " PUBLIC_IP
            if [[ -n "$PUBLIC_IP" ]]; then
                break
            else
                print_color "$RED" "IP地址不能为空。"
            fi
        done
    fi

    # 设置项目部署根目录
    read -p "请输入项目部署的根目录名 (默认为 liteyuki_bot): " project_dir
    project_dir=${project_dir:-liteyuki_bot}
    
    # 设置机器人超级管理员QQ号
    while true; do
        read -p "请输入您的机器人超级管理员 QQ 号 (superusers): " superuser_qq
        # 验证QQ号格式是否正确
        if [[ "$superuser_qq" =~ ^[1-9][0-9]{4,10}$ ]]; then
            break
        else
            print_color "$RED" "无效的 QQ 号码，请重新输入。"
        fi
    done
    
    # 设置通信安全Token
    print_color "$YELLOW" "\n为了安全，建议为轻雪机器人与 NapCat 之间的通信设置一个 Token。"
    print_color "$YELLOW" "如果您在公网环境部署，强烈建议设置此项。"
    read -p "请输入通信 Token (留空则不使用): " onebot_token
}

#==============================================================================
# 部署与文件生成 - 部署服务并生成配置文件
#==============================================================================

# 部署NapCat服务
# 创建必要的目录结构，生成Docker配置，并启动服务
function deploy_napcat() {
    print_color "$BLUE" "\n--- 4. 部署 NapCat ---"
    
    # 创建NapCat数据目录
    mkdir -p "$project_dir/napcat_data/config"
    mkdir -p "$project_dir/napcat_data/qq_data"
    
    # 生成docker-compose.yml配置文件
    cat > "$project_dir/docker-compose.yml" << EOF
services:
  napcat:
    image: mlikiowa/napcat-docker:latest
    container_name: napcat
    restart: always
    network_mode: bridge
    mac_address: 02:42:ac:11:00:02
    ports:
      - "6099:6099"
    volumes:
      - ./napcat_data/config:/app/napcat/config
      - ./napcat_data/qq_data:/app/.config/QQ
    environment:
      - NAPCAT_UID=$(id -u)
      - NAPCAT_GID=$(id -g)
EOF
    print_color "$GREEN" "docker-compose.yml 文件创建成功。"
    
    # 启动NapCat Docker服务
    print_color "$YELLOW" "正在启动 NapCat 服务，首次启动需要拉取镜像，请稍候..."
    (cd "$project_dir" && docker compose up -d)
    if [ $? -eq 0 ]; then
        print_color "$GREEN" "NapCat 服务已成功启动！"
    else
        print_color "$RED" "NapCat 服务启动失败！请检查以上日志输出。"
        exit 1
    fi
}

# 部署轻雪机器人
# 克隆代码、安装依赖、配置服务并启动
function deploy_liteyukibot() {
    print_color "$BLUE" "\n--- 5. 部署轻雪机器人 ---"
    
    # 设置仓库地址
    local official_repo="https://github.com/LiteyukiStudio/LiteyukiBot"
    local liteyuki_repo="$official_repo"
    
    # 根据地理位置选择合适的仓库源
    print_color "$YELLOW" "轻雪机器人的官方仓库地址是: $official_repo"
    if [ "$IS_CHINA" = true ]; then
        print_color "$YELLOW" "您位于国内，推荐使用镜像或代理加速 Git 克隆。"
        print_color "$YELLOW" "Liteyuki 官方镜像源: https://git.liteyuki.org/bot/app"
        print_color "$YELLOW" "您也可以使用 GitHub 代理网站 (如 https://gh-proxy.com/ 或 https://github.akams.cn/) 生成代理地址。"
        read -p "请输入完整的克隆地址 (留空则使用官方镜像源): " custom_repo_url
        liteyuki_repo=${custom_repo_url:-"https://git.liteyuki.org/bot/app"}
    fi
    
    # 克隆轻雪机器人代码仓库
    print_color "$YELLOW" "正在从 $liteyuki_repo 克隆项目..."
    if ! git clone "$liteyuki_repo" "$project_dir/LiteyukiBot" --depth=1; then
        print_color "$RED" "Git 克隆失败！请检查您的网络或克隆地址是否正确。"
        exit 1
    fi
    
    local bot_dir="$project_dir/LiteyukiBot"
    
    # 创建Python虚拟环境
    print_color "$YELLOW" "正在创建 Python 虚拟环境..."
    python3 -m venv "$bot_dir/venv"
    
    # 国内环境选择镜像源
    if [ "$IS_CHINA" = true ]; then
        select_pip_mirror
    fi
    
    # 安装Python依赖
    print_color "$YELLOW" "正在安装 Python 依赖，将显示详细日志，请耐心等待..."
    local pip_cmd="$bot_dir/venv/bin/pip"
    local playwright_cmd="$bot_dir/venv/bin/playwright"
    
    if [ "$IS_CHINA" = true ]; then
        # 使用国内镜像源安装依赖
        $pip_cmd install -v -i "$PIP_INDEX_URL" --trusted-host "$PIP_TRUSTED_HOST" -r "$bot_dir/requirements.txt"
        $pip_cmd install -v -i "$PIP_INDEX_URL" --trusted-host "$PIP_TRUSTED_HOST" nonebot-adapter-onebot
    else
        # 使用官方源安装依赖
        $pip_cmd install -v -r "$bot_dir/requirements.txt"
        $pip_cmd install -v nonebot-adapter-onebot
    fi
    print_color "$GREEN" "Python 依赖安装完成。"
    
    # 安装Playwright浏览器内核
    print_color "$YELLOW" "正在安装 Playwright 浏览器内核，这可能需要一些时间..."
    $playwright_cmd install
    print_color "$GREEN" "Playwright 浏览器内核安装完成。"
    
    # 生成轻雪机器人配置文件
    print_color "$YELLOW" "正在生成轻雪机器人配置文件..."
    cat > "$bot_dir/config.yml" << EOF
# NoneBot 核心配置
nonebot:
  host: 0.0.0.0
  port: 20216
  superusers: ["$superuser_qq"]
  nickname: ["轻雪"]
  drivers: ["~onebot.v11"]
  onebot_access_token: "$onebot_token"

# LiteyukiBot 特定配置
liteyuki:
  log_level: "INFO"
  auto_update: true
EOF
    print_color "$GREEN" "config.yml 文件创建成功。"
    
    # 创建systemd服务实现开机自启和后台运行
    print_color "$YELLOW" "正在创建 systemd 服务，以便后台运行轻雪机器人..."
    local service_file="/etc/systemd/system/liteyukibot.service"
    local work_dir=$(realpath "$bot_dir")
    
    cat > "$service_file" << EOF
[Unit]
Description=LiteyukiBot Service
After=network.target

[Service]
Type=simple
User=$(who am i | awk '{print $1}')
WorkingDirectory=$work_dir
ExecStart=$work_dir/venv/bin/python main.py
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动并设置开机自启
    systemctl daemon-reload
    systemctl enable liteyukibot.service
    systemctl start liteyukibot.service
    
    print_color "$GREEN" "轻雪机器人已作为后台服务启动。"
    print_color "$YELLOW" "您可以使用 'sudo systemctl status liteyukibot' 查看状态。"
    print_color "$YELLOW" "使用 'sudo journalctl -fu liteyukibot' 查看实时日志。"
}

#==============================================================================
# 最终指引 - 提供部署后的配置步骤和管理指南
#==============================================================================

# 显示部署完成后的配置指南和管理命令
# 引导用户完成NapCat登录、连接配置和机器人测试
function show_summary() {
    print_color "$BLUE" "\n==================== 自动化部署完成 ===================="
    print_color "$GREEN" "恭喜！轻雪机器人和 NapCat 已成功部署并正在后台运行。"
    print_color "$YELLOW" "\n接下来，请按照以下步骤完成手动配置："
    
    # 步骤1: 登录NapCat并让机器人QQ上线
    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 1: 登录 NapCat 并让机器人 QQ 上线"
    echo -e "--------------------------------------------------"
    echo -e "1. 在浏览器中访问 NapCat WebUI: ${GREEN}http://${PUBLIC_IP}:6099/webui${NC}"
    echo -e "2. 首次访问默认的Token密码为 ${GREEN}napcat${NC}"
    echo -e "3. 进入登陆界面后, 点击扫码登陆，使用您的手机 QQ 扫描屏幕上的二维码。"
    echo -e "4. 等待机器人 QQ 账号成功上线。"

    # 步骤2: 配置NapCat与轻雪机器人的连接
    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 2: 在 NapCat 中配置与轻雪机器人的连接"
    echo -e "--------------------------------------------------"
    pause_for_user "请在完成上一步 [登录 NapCat] 后按任意键继续..."
    
    echo -e "1. 在 NapCat WebUI 左侧菜单中，点击 ${GREEN}[网络配置]${NC}。"
    echo -e "2. 点击 ${GREEN}[新建]${NC} 按钮, 选择 ${GREEN}Websocket客户端${NC} 选项。"
    echo -e "3. 在弹出的窗口中，填写以下信息："
    echo -e "   - **名称**: ${GREEN}自行填写 (例如: liteyuki-bot)${NC}"
    echo -e "   - **WebSocket 地址**: ${GREEN}ws://${PUBLIC_IP}:20216/onebot/v11/ws${NC}"
    echo -e "   - **AccessToken**: ${YELLOW}填写您之前设置的 Token: ${GREEN}${onebot_token:-（您未设置）}${NC}"
    echo -e "4. 点击 ${GREEN}[保存]${NC}。"
    echo -e "5. 如果一切正常，点击左侧的 ${GREEN}[猫猫日志]${NC} 你会看到已连接。"

    # 步骤3: 测试机器人功能
    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 3: 测试机器人"
    echo -e "--------------------------------------------------"
    echo -e "1. 使用您的任意 QQ 号，向机器人 QQ 发送一条消息，例如：${GREEN}菜单${NC}。"
    echo -e "2. 如果机器人有回复，则表示整个链路已成功打通！"
    echo -e "3. 您可以查看轻雪机器人的实时日志来排查问题:"
    echo -e "   ${YELLOW}sudo journalctl -fu liteyukibot${NC}"

    # 提供服务管理和维护指南
    print_color "$BLUE" "\n==================== 管理与维护 ===================="
    echo -e "您的所有项目文件都位于: ${YELLOW}~/${project_dir}${NC}"
    echo -e "常用命令:"
    echo -e "  - 管理 NapCat (需在 ~/${project_dir} 目录下执行):"
    echo -e "    - 停止: ${YELLOW}docker compose down${NC}"
    echo -e "    - 启动: ${YELLOW}docker compose up -d${NC}"
    echo -e "    - 查看日志: ${YELLOW}docker compose logs -f napcat${NC}"
    echo -e "  - 管理轻雪机器人:"
    echo -e "    - 停止: ${YELLOW}sudo systemctl stop liteyukibot${NC}"
    echo -e "    - 启动: ${YELLOW}sudo systemctl start liteyukibot${NC}"
    echo -e "    - 重启: ${YELLOW}sudo systemctl restart liteyukibot${NC}"
    echo -e "    - 查看状态: ${YELLOW}sudo systemctl status liteyukibot${NC}"
    print_color "$BLUE" "==================================================\n"
}

#==============================================================================
# 主函数
#==============================================================================
function main() {
    clear
    print_color "$BLUE" "========================================================"
    print_color "$BLUE" "      轻雪机器人 + NapCat 一键部署脚本 (v3)"
    print_color "$BLUE" "========================================================"
    
    check_root
    handle_location
    install_dependencies
    install_playwright_deps
    install_docker
    collect_user_config
    deploy_napcat
    deploy_liteyukibot
    show_summary
}

# --- 脚本入口 ---
main