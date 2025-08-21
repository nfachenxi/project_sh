#!/bin/bash

#================================================================================
# MaiBot AI机器人一键部署脚本 (v1.0)
#
# 脚本说明:
#   本脚本提供了一个自动化的 MaiBot AI机器人部署解决方案，通过 Docker
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
#      - 一键部署完整技术栈 (MaiBot + NapCat + Adapters + MySQL)
#   3. 配置指引
#      - 提供详细的分步配置说明
#      - 包含权限设置和模型配置指南
#
# 技术栈:
#   - MaiBot Core: AI机器人核心服务
#   - NapCat: QQ协议适配器
#   - Adapters: 协议适配服务
#   - MySQL: 数据持久化存储
#   - Docker: 容器化部署和管理
#
# 使用说明:
#   1. 确保服务器已安装基本系统工具
#   2. 执行: chmod +x setup_maibot.sh
#   3. 运行: sudo ./setup_maibot.sh
#   4. 按照提示完成配置
#
# 注意事项:
#   - 运行脚本需要 root 权限
#   - 仅支持 Ubuntu/Debian 系统
#   - 确保服务器防火墙已开放所需端口 (6099, 8000, 8095, 8120, 10824)
#   - 建议使用干净的服务器环境
#
# 作者: NFA晨曦
# 基于: MaiBot Docker 部署方案
#================================================================================

#==============================================================================
# 终端颜色定义
# 用于提供清晰的视觉反馈，帮助用户理解脚本执行状态
#==============================================================================
GREEN='\033[0;32m'    # 成功消息和正常状态
RED='\033[0;31m'      # 错误消息和失败状态
YELLOW='\033[0;33m'   # 警告消息和重要提示
BLUE='\033[0;34m'     # 标题和分隔信息
CYAN='\033[0;36m'     # 信息提示
NC='\033[0m'          # 重置颜色到终端默认值

# 全局变量定义
PROJECT_DIR=""
MODE=""
SERVER_IP=""
MYSQL_ROOT_PASSWORD=""
SILICONFLOW_KEY=""
ROBOT_QQ=""
BOT_NICKNAME=""
USE_CLEANUP=false
USE_CHINA_MIRROR=false

#==============================================================================
# 信号处理和清理函数
# 确保脚本在异常退出时能够清理残留环境
#==============================================================================

# 设置信号陷阱
trap cleanup_and_exit INT TERM EXIT

# 清理函数
function cleanup_and_exit() {
    local exit_code=$?
    
    if [ "$USE_CLEANUP" = true ] && [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
        print_color "$YELLOW" "\n检测到脚本异常退出，正在清理残留环境..."
        
        # 停止并删除容器
        if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
            cd "$PROJECT_DIR" 2>/dev/null
            docker compose down --volumes --remove-orphans 2>/dev/null || true
            print_color "$GREEN" "容器已清理完成"
        fi
        
        # 清理项目目录
        read -p "是否删除项目目录 $PROJECT_DIR？(y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$PROJECT_DIR" 2>/dev/null || true
            print_color "$GREEN" "项目目录已清理"
        fi
    fi
    
    if [ $exit_code -ne 0 ] && [ $exit_code -ne 130 ]; then
        print_color "$RED" "\n脚本执行过程中发生错误，退出代码: $exit_code"
        print_color "$YELLOW" "如需重新部署，请重新运行脚本"
    fi
    
    exit $exit_code
}

#==============================================================================
# 辅助函数
# 包含了一系列通用工具函数，用于支持脚本的核心功能
#==============================================================================

# 打印带颜色的消息到终端
function print_color() {
    COLOR=$1
    MESSAGE=$2
    echo -e "${COLOR}${MESSAGE}${NC}"
}

# 检查系统中是否存在指定命令
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 验证脚本是否以 root 权限运行
function check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_color "$RED" "错误: 此脚本必须以 root 用户身份运行。"
        print_color "$YELLOW" "请尝试使用 'sudo ./setup_maibot.sh' 运行。"
        exit 1
    fi
}

# 检查操作系统是否为 Ubuntu/Debian
function check_os() {
    if [ ! -f /etc/os-release ]; then
        print_color "$RED" "错误: 无法检测操作系统信息。"
        exit 1
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]] && [[ "$ID_LIKE" != *"ubuntu"* ]] && [[ "$ID_LIKE" != *"debian"* ]]; then
        print_color "$RED" "错误: 此脚本仅支持 Ubuntu 或 Debian 系统。"
        print_color "$YELLOW" "检测到的系统: $PRETTY_NAME"
        exit 1
    fi
    
    print_color "$GREEN" "操作系统检查通过: $PRETTY_NAME"
}

# 获取服务器的公网 IP 地址
function get_public_ip() {
    local ip
    ip=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s --max-time 10 https://ipinfo.io/ip 2>/dev/null)
    echo "$ip"
}

#==============================================================================
# 模式选择函数
# 提供安装部署模式和配置模式两种运行模式
#==============================================================================

function select_mode() {
    print_color "$BLUE" "\n--- 选择运行模式 ---"
    print_color "$CYAN" "请选择您要执行的操作:"
    echo "1) 安装部署模式 - 全新安装 MaiBot"
    echo "2) 配置模式 - 修改现有 MaiBot 配置"
    echo "3) 退出"
    
    while true; do
        read -p "请输入选项 (1-3): " choice
        case "$choice" in
            1 )
                MODE="install"
                print_color "$GREEN" "已选择: 安装部署模式"
                break
                ;;
            2 )
                MODE="config"
                print_color "$GREEN" "已选择: 配置模式"
                break
                ;;
            3 )
                print_color "$YELLOW" "退出脚本"
                exit 0
                ;;
            * ) 
                print_color "$RED" "无效输入，请输入 1、2 或 3。" 
                ;;
        esac
    done
}

#==============================================================================
# 安装与环境配置函数
# 负责系统环境初始化，包括软件源配置、Docker安装和基础工具部署
#==============================================================================

# 安装基础依赖工具
function install_dependencies() {
    print_color "$YELLOW" "正在检查并安装基础依赖..."
    
    # 更新包索引
    apt-get update >/dev/null 2>&1
    
    # 安装必要工具
    local packages=("curl" "wget" "vim" "python3")
    for package in "${packages[@]}"; do
        if ! command_exists "$package"; then
            print_color "$YELLOW" "正在安装 $package..."
            if ! apt-get install -y "$package" >/dev/null 2>&1; then
                print_color "$RED" "$package 安装失败，请检查网络连接。"
                exit 1
            fi
        fi
    done
    
    print_color "$GREEN" "基础依赖检查完成。"
}


# 处理服务器地理位置和软件源配置
function handle_location() {
    print_color "$BLUE" "\n--- 选择安装源 ---"
    print_color "$YELLOW" "为了优化下载速度，请选择您的服务器所在区域。"
    
    local choice
    while true; do
        read -p "您的服务器是否位于中国大陆？(y/n): " choice
        case "$choice" in
            y|Y )
                USE_CHINA_MIRROR=true
                print_color "$GREEN" "将使用中国大陆镜像源进行加速。"
                print_color "$YELLOW" "正在更换系统软件源..."
                bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh)
                print_color "$YELLOW" "正在配置 Docker 加速..."
                bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/DockerInstallation.sh)
                break
                ;;
            n|N )
                print_color "$GREEN" "将使用官方源进行安装。"
                break
                ;;
            * ) 
                print_color "$RED" "无效输入，请输入 'y' 或 'n'。" 
                ;;
        esac
    done
}

# 安装和配置 Docker 环境
function install_docker() {
    if ! command_exists docker; then
        print_color "$YELLOW" "未检测到 Docker，正在为您安装..."
        if ! (curl -fsSL https://get.docker.com | bash -s docker >/dev/null 2>&1); then
            print_color "$RED" "Docker 安装失败。请检查网络或尝试手动安装。"
            exit 1
        fi
        print_color "$GREEN" "Docker 安装成功。"
    else
        print_color "$GREEN" "Docker 已安装。"
    fi
    
    # 启动并设置 Docker 开机自启
    systemctl start docker
    systemctl enable docker
    print_color "$GREEN" "Docker 服务已启动并设为开机自启。"
}

# 验证 Docker Compose 可用性
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
# 配置收集函数
# 负责收集部署所需的基本配置信息
#==============================================================================

function collect_config() {
    print_color "$BLUE" "\n--- 开始收集配置信息 ---"
    
    # 项目目录配置
    read -p "请输入项目部署的目录名 (默认为 maibot): " PROJECT_DIR
    PROJECT_DIR=${PROJECT_DIR:-maibot}
    
    # 机器人QQ号配置
    while true; do
        read -p "请输入您的机器人 QQ 号: " ROBOT_QQ
        if [[ "$ROBOT_QQ" =~ ^[1-9][0-9]{4,10}$ ]]; then
            break
        else
            print_color "$RED" "无效的 QQ 号码，请重新输入。"
        fi
    done
    
    # 机器人昵称配置
    read -p "请输入机器人昵称 (默认为 麦麦): " BOT_NICKNAME
    BOT_NICKNAME=${BOT_NICKNAME:-麦麦}
    
    # AI模型服务配置
    print_color "$YELLOW" "MaiBot 需要 AI 模型服务，请选择您要使用的服务商："
    print_color "$CYAN" "1) 硅基流动 (SiliconFlow) - 推荐，提供免费额度"
    print_color "$CYAN" "2) DeepSeek - 性价比高"
    print_color "$CYAN" "3) 其他 OpenAI 兼容服务"
    print_color "$CYAN" "4) 跳过配置 - 稍后手动配置"
    
    local api_choice
    while true; do
        read -p "请选择 (1-4): " api_choice
        case "$api_choice" in
            1 )
                print_color "$GREEN" "已选择硅基流动服务"
                print_color "$CYAN" "请访问 https://siliconflow.cn 注册并获取 API Key"
                while true; do
                    read -p "请输入您的 SiliconFlow API Key (sk-开头，或输入 'skip' 跳过): " SILICONFLOW_KEY
                    if [ "$SILICONFLOW_KEY" = "skip" ]; then
                        SILICONFLOW_KEY="your-siliconflow-api-key"
                        print_color "$YELLOW" "已跳过 API Key 配置，请稍后手动修改配置文件"
                        break
                    elif [[ "$SILICONFLOW_KEY" =~ ^sk-.+ ]]; then
                        break
                    else
                        print_color "$RED" "无效的 API Key 格式，请输入 sk- 开头的密钥，或输入 'skip' 跳过"
                    fi
                done
                break
                ;;
            2 )
                print_color "$GREEN" "已选择 DeepSeek 服务"
                print_color "$CYAN" "请访问 https://platform.deepseek.com 注册并获取 API Key"
                while true; do
                    read -p "请输入您的 DeepSeek API Key (sk-开头，或输入 'skip' 跳过): " SILICONFLOW_KEY
                    if [ "$SILICONFLOW_KEY" = "skip" ]; then
                        SILICONFLOW_KEY="your-deepseek-api-key"
                        print_color "$YELLOW" "已跳过 API Key 配置，请稍后手动修改配置文件"
                        break
                    elif [[ "$SILICONFLOW_KEY" =~ ^sk-.+ ]]; then
                        break
                    else
                        print_color "$RED" "无效的 API Key 格式，请输入 sk- 开头的密钥，或输入 'skip' 跳过"
                    fi
                done
                break
                ;;
            3 )
                print_color "$GREEN" "已选择其他 OpenAI 兼容服务"
                while true; do
                    read -p "请输入您的 API Key (或输入 'skip' 跳过): " SILICONFLOW_KEY
                    if [ "$SILICONFLOW_KEY" = "skip" ]; then
                        SILICONFLOW_KEY="your-api-key-here"
                        print_color "$YELLOW" "已跳过 API Key 配置，请稍后手动修改配置文件"
                        break
                    elif [ -n "$SILICONFLOW_KEY" ]; then
                        break
                    else
                        print_color "$RED" "API Key 不能为空，或输入 'skip' 跳过"
                    fi
                done
                break
                ;;
            4 )
                print_color "$YELLOW" "已跳过 API Key 配置"
                SILICONFLOW_KEY="your-api-key-here"
                print_color "$CYAN" "部署完成后，请手动编辑配置文件添加 API Key"
                break
                ;;
            * )
                print_color "$RED" "无效选择，请输入 1-4"
                ;;
        esac
    done
    
    # MySQL密码配置
    print_color "$YELLOW" "为了数据持久化，我们将为您部署一个 MySQL 数据库。"
    while true; do
        read -sp "请为 MySQL 的 root 用户设置一个密码: " MYSQL_ROOT_PASSWORD
        echo
        if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
            break
        else
            print_color "$RED" "数据库 root 密码不能为空。"
        fi
    done
    
    # 获取服务器IP
    SERVER_IP=$(get_public_ip)
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="<你的服务器公网IP>"
        print_color "$YELLOW" "警告: 无法自动获取公网IP，请手动替换后续说明中的IP地址。"
    else
        print_color "$GREEN" "检测到服务器公网IP: $SERVER_IP"
    fi
}

#==============================================================================
# 文件生成与部署函数
# 负责生成配置文件、创建目录结构和启动服务
#==============================================================================

function create_project_structure() {
    print_color "$BLUE" "\n--- 正在创建项目结构 ---"
    
    # 创建主项目目录
    mkdir -p "$PROJECT_DIR" && cd "$PROJECT_DIR"
    USE_CLEANUP=true  # 从这里开始启用清理功能
    
    # 创建子目录结构
    mkdir -p docker-config/{mmc,adapters}
    mkdir -p data/MaiMBot
    
    # 创建预留文件
    touch ./data/MaiMBot/maibot_statistics.html
    
    print_color "$GREEN" "项目目录结构创建完成。"
}

function download_template_files() {
    print_color "$BLUE" "\n--- 正在下载配置模板 ---"
    
    local github_base="https://raw.githubusercontent.com"
    local mirror_base="https://github.moeyy.xyz/https://raw.githubusercontent.com"
    
    # 下载 docker-compose.yml
    print_color "$YELLOW" "下载 Docker Compose 配置文件..."
    if ! wget -q "$github_base/SengokuCola/MaiMBot/main/docker-compose.yml" -O docker-compose.yml; then
        print_color "$YELLOW" "GitHub 直连失败，尝试使用镜像源..."
        if ! wget -q "$mirror_base/SengokuCola/MaiMBot/main/docker-compose.yml" -O docker-compose.yml; then
            print_color "$RED" "下载 docker-compose.yml 失败。"
            exit 1
        fi
    fi
    
    # 下载 .env 模板
    print_color "$YELLOW" "下载环境配置模板..."
    if ! wget -q "$github_base/MaiM-with-u/MaiBot/main/template/template.env" -O docker-config/mmc/.env; then
        if ! wget -q "$mirror_base/MaiM-with-u/MaiBot/main/template/template.env" -O docker-config/mmc/.env; then
            print_color "$RED" "下载 .env 模板失败。"
            exit 1
        fi
    fi
    
    # 下载 adapters 配置模板
    print_color "$YELLOW" "下载适配器配置模板..."
    if ! wget -q "$github_base/MaiM-with-u/MaiBot-Napcat-Adapter/main/template/template_config.toml" -O docker-config/adapters/config.toml; then
        if ! wget -q "$mirror_base/MaiM-with-u/MaiBot-Napcat-Adapter/main/template/template_config.toml" -O docker-config/adapters/config.toml; then
            print_color "$RED" "下载适配器配置模板失败。"
            exit 1
        fi
    fi
    
    print_color "$GREEN" "配置模板下载完成。"
}

function modify_docker_compose() {
    print_color "$BLUE" "\n--- 正在配置 Docker Compose 文件 ---"
    
    # 去除 version 字段
    sed -i '/^version:/d' docker-compose.yml
    
    # 取消注释 EULA 相关行
    sed -i 's/^[[:space:]]*#[[:space:]]*- EULA_AGREE=/      - EULA_AGREE=/' docker-compose.yml
    sed -i 's/^[[:space:]]*#[[:space:]]*- PRIVACY_AGREE=/      - PRIVACY_AGREE=/' docker-compose.yml
    
    print_color "$GREEN" "Docker Compose 配置修改完成。"
}

# 为国内用户添加镜像代理前缀
function add_docker_proxy_for_china() {
    print_color "$BLUE" "\n--- 为国内用户配置镜像代理 ---"
    
    # 创建临时文件来处理docker-compose.yml
    local temp_file=$(mktemp)
    
    # 读取原文件并处理每一行
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*image:[[:space:]]* ]]; then
            # 提取镜像名
            local image_line="$line"
            local image_name=$(echo "$line" | sed 's/^[[:space:]]*image:[[:space:]]*//' | sed 's/[[:space:]]*$//')
            
            # 检查是否已经有代理前缀
            if [[ ! "$image_name" =~ ^docker\.gh-proxy\.com/ ]]; then
                # 添加代理前缀
                local new_line=$(echo "$line" | sed "s|image:[[:space:]]*\(.*\)|image: docker.gh-proxy.com/\1|")
                echo "$new_line" >> "$temp_file"
                print_color "$CYAN" "镜像代理: $image_name -> docker.gh-proxy.com/$image_name"
            else
                echo "$line" >> "$temp_file"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < docker-compose.yml
    
    # 替换原文件
    mv "$temp_file" docker-compose.yml
    
    print_color "$GREEN" "镜像代理配置完成，所有镜像将通过国内代理拉取。"
}

function modify_env_config() {
    print_color "$BLUE" "\n--- 正在配置环境变量 ---"
    
    # 修改 .env 文件
    sed -i "s/HOST=127.0.0.1/HOST=0.0.0.0/" docker-config/mmc/.env
    sed -i "s/SILICONFLOW_KEY=sk-xxxxxx/SILICONFLOW_KEY=$SILICONFLOW_KEY/" docker-config/mmc/.env
    
    print_color "$GREEN" "环境变量配置完成。"
}

function modify_adapter_config() {
    print_color "$BLUE" "\n--- 正在配置适配器 ---"
    
    # 修改适配器配置文件
    sed -i 's/host = "127.0.0.1"/host = "0.0.0.0"/' docker-config/adapters/config.toml
    sed -i 's/host = "localhost"/host = "core"/' docker-config/adapters/config.toml
    
    print_color "$GREEN" "适配器配置完成。"
}

function initial_container_startup() {
    print_color "$BLUE" "\n--- 正在进行初始化启动 ---"
    print_color "$YELLOW" "首次启动容器以生成配置文件，请耐心等待..."
    
    if ! docker compose up -d; then
        print_color "$RED" "初始化启动失败！"
        exit 1
    fi
    
    # 等待15秒让容器完全启动
    print_color "$YELLOW" "等待容器初始化..."
    sleep 15
    
    # 停止容器
    docker compose down
    
    print_color "$GREEN" "初始化启动完成，配置文件已生成。"
}

function modify_bot_config() {
    print_color "$BLUE" "\n--- 正在配置机器人设置 ---"
    
    local config_file="docker-config/mmc/bot_config.toml"
    
    if [ -f "$config_file" ]; then
        # 修改QQ号和昵称
        sed -i "s/qq_account = [0-9]*/qq_account = $ROBOT_QQ/" "$config_file"
        sed -i "s/nickname = \".*\"/nickname = \"$BOT_NICKNAME\"/" "$config_file"
        
        print_color "$GREEN" "机器人配置修改完成。"
    else
        print_color "$YELLOW" "警告: 配置文件未找到，将在启动后手动配置。"
    fi
}

function start_services() {
    print_color "$BLUE" "\n--- 正在启动服务 ---"
    print_color "$YELLOW" "正在启动所有服务，这可能需要几分钟时间来拉取镜像..."
    
    if docker compose up -d; then
        print_color "$GREEN" "服务已成功启动！"
        
        # 验证服务状态
        print_color "$YELLOW" "正在验证服务状态..."
        sleep 10
        
        local running_count=$(docker compose ps --filter "status=running" --format "table {{.Service}}" | grep -v SERVICE | wc -l)
        if [ "$running_count" -ge 3 ]; then
            print_color "$GREEN" "服务验证完成，$running_count 个容器正在运行。"
        else
            print_color "$YELLOW" "警告: 部分服务可能未正常启动，请检查日志。"
        fi
        
        USE_CLEANUP=false  # 部署成功后禁用清理功能
    else
        print_color "$RED" "服务启动失败！请检查以上日志输出。"
        print_color "$YELLOW" "您可以进入 '$PROJECT_DIR' 目录，运行 'docker compose logs -f' 查看详细日志。"
        exit 1
    fi
}

#==============================================================================
# 配置模式函数
# 处理配置模式的相关操作
#==============================================================================

function config_mode() {
    print_color "$BLUE" "\n--- 配置模式 ---"
    print_color "$YELLOW" "请选择要配置的项目:"
    echo "1) 修改机器人基本设置 (QQ号、昵称等)"
    echo "2) 修改AI模型配置"
    echo "3) 修改网络和端口设置"
    echo "4) 查看当前配置"
    echo "5) 高级配置编辑器"
    echo "6) 重启服务"
    echo "7) 返回主菜单"
    
    read -p "请输入选项 (1-7): " config_choice
    
    case "$config_choice" in
        1 )
            config_bot_settings
            ;;
        2 )
            config_model_settings
            ;;
        3 )
            config_network_settings
            ;;
        4 )
            show_current_config
            ;;
        5 )
            advanced_config_editor
            ;;
        6 )
            restart_services
            ;;
        7 )
            return
            ;;
        * )
            print_color "$RED" "无效选项，请重新选择。"
            ;;
    esac
    
    # 询问是否继续配置
    echo
    read -p "是否继续配置其他选项？(y/n): " continue_config
    if [[ "$continue_config" =~ ^[Yy]$ ]]; then
        config_mode
    fi
}

# 查找MaiBot项目目录的辅助函数
function find_maibot_project() {
    # 如果当前已经设置了PROJECT_DIR并且有效，直接使用
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker-config/mmc/.env" ]; then
        return 0
    fi
    
    # 搜索可能的MaiBot项目目录
    local search_paths=("/root" "/home" "/opt" "$(pwd)")
    local existing_dirs=()
    
    for search_path in "${search_paths[@]}"; do
        if [ -d "$search_path" ]; then
            while IFS= read -r -d '' dir; do
                if [ -f "$dir/docker-config/mmc/.env" ] && [ -f "$dir/docker-compose.yml" ]; then
                    existing_dirs+=("$dir")
                fi
            done < <(find "$search_path" -maxdepth 3 -name "docker-compose.yml" -print0 2>/dev/null | head -20)
        fi
    done
    
    # 去重
    IFS=$'\n' existing_dirs=($(printf "%s\n" "${existing_dirs[@]}" | sort -u))
    
    if [ ${#existing_dirs[@]} -eq 0 ]; then
        print_color "$RED" "未找到现有的 MaiBot 部署，请先运行安装模式。"
        print_color "$CYAN" "提示: 如果您刚完成安装，请重新运行脚本并选择配置模式。"
        return 1
    fi
    
    if [ ${#existing_dirs[@]} -eq 1 ]; then
        PROJECT_DIR="${existing_dirs[0]}"
        print_color "$GREEN" "找到 MaiBot 项目: $PROJECT_DIR"
    else
        print_color "$YELLOW" "找到多个 MaiBot 部署，请选择:"
        for i in "${!existing_dirs[@]}"; do
            echo "$((i+1))) ${existing_dirs[i]}"
        done
        read -p "请选择项目目录 (1-${#existing_dirs[@]}): " dir_choice
        if [[ "$dir_choice" =~ ^[1-9][0-9]*$ ]] && [ "$dir_choice" -le "${#existing_dirs[@]}" ]; then
            PROJECT_DIR="${existing_dirs[$((dir_choice-1))]}"
            print_color "$GREEN" "已选择项目: $PROJECT_DIR"
        else
            print_color "$RED" "无效选择"
            return 1
        fi
    fi
    
    if [ ! -d "$PROJECT_DIR" ]; then
        print_color "$RED" "项目目录不存在: $PROJECT_DIR"
        return 1
    fi
    
    return 0
}

function config_bot_settings() {
    print_color "$BLUE" "\n--- 修改机器人基本设置 ---"
    
    if ! find_maibot_project; then
        return
    fi
    
    cd "$PROJECT_DIR" || {
        print_color "$RED" "无法进入项目目录 $PROJECT_DIR"
        return
    }
    
    print_color "$GREEN" "正在配置项目: $PROJECT_DIR"
    
    local bot_config="docker-config/mmc/bot_config.toml"
    if [ -f "$bot_config" ]; then
        print_color "$YELLOW" "当前机器人配置:"
        print_color "$CYAN" "QQ账号: $(grep 'qq_account' "$bot_config" | cut -d'=' -f2 | tr -d ' ')"
        print_color "$CYAN" "昵称: $(grep 'nickname' "$bot_config" | cut -d'=' -f2 | tr -d ' "')"
        
        echo
        read -p "是否要修改QQ账号？(y/n): " modify_qq
        if [[ "$modify_qq" =~ ^[Yy]$ ]]; then
            read -p "请输入新的QQ账号: " new_qq
            if [[ "$new_qq" =~ ^[1-9][0-9]{4,10}$ ]]; then
                sed -i "s/qq_account = [0-9]*/qq_account = $new_qq/" "$bot_config"
                print_color "$GREEN" "QQ账号已更新为: $new_qq"
            else
                print_color "$RED" "无效的QQ账号格式"
            fi
        fi
        
        read -p "是否要修改机器人昵称？(y/n): " modify_name
        if [[ "$modify_name" =~ ^[Yy]$ ]]; then
            read -p "请输入新的昵称: " new_name
            if [ -n "$new_name" ]; then
                sed -i "s/nickname = \".*\"/nickname = \"$new_name\"/" "$bot_config"
                print_color "$GREEN" "昵称已更新为: $new_name"
            fi
        fi
        
        read -p "修改完成后是否重启服务？(y/n): " restart_choice
        if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
            restart_services
        fi
    else
        print_color "$RED" "配置文件不存在: $bot_config"
    fi
}

function config_model_settings() {
    print_color "$BLUE" "\n--- 修改AI模型配置 ---"
    
    if ! find_maibot_project; then
        return
    fi
    
    cd "$PROJECT_DIR" || {
        print_color "$RED" "无法进入项目目录 $PROJECT_DIR"
        return
    }
    
    local env_file="docker-config/mmc/.env"
    if [ -f "$env_file" ]; then
        print_color "$YELLOW" "当前API配置:"
        print_color "$CYAN" "$(grep 'SILICONFLOW_KEY' "$env_file" 2>/dev/null || echo "未找到API Key配置")"
        
        echo
        read -p "是否要修改API Key？(y/n): " modify_api
        if [[ "$modify_api" =~ ^[Yy]$ ]]; then
            read -p "请输入新的API Key: " new_api_key
            if [ -n "$new_api_key" ]; then
                sed -i "s/SILICONFLOW_KEY=.*/SILICONFLOW_KEY=$new_api_key/" "$env_file"
                print_color "$GREEN" "API Key已更新"
                
                read -p "修改完成后是否重启服务？(y/n): " restart_choice
                if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
                    restart_services
                fi
            fi
        fi
    else
        print_color "$RED" "环境配置文件不存在: $env_file"
    fi
}

function config_network_settings() {
    print_color "$BLUE" "\n--- 修改网络和端口设置 ---"
    
    if ! find_maibot_project; then
        return
    fi
    
    cd "$PROJECT_DIR" || {
        print_color "$RED" "无法进入项目目录 $PROJECT_DIR"
        return
    }
    
    print_color "$YELLOW" "当前端口配置:"
    if [ -f "docker-compose.yml" ]; then
        print_color "$CYAN" "端口映射:"
        grep -E "^\s*-\s*\"[0-9]+:[0-9]+\"" docker-compose.yml | sed 's/^[[:space:]]*/  /'
    fi
    
    print_color "$YELLOW" "如需修改端口配置，请手动编辑以下文件:"
    print_color "$CYAN" "$PROJECT_DIR/docker-compose.yml"
    print_color "$CYAN" "修改后使用选项6重启服务"
}

function advanced_config_editor() {
    print_color "$BLUE" "\n--- 高级配置编辑器 ---"
    
    if ! find_maibot_project; then
        return
    fi
    
    cd "$PROJECT_DIR" || {
        print_color "$RED" "无法进入项目目录 $PROJECT_DIR"
        return
    }
    
    print_color "$GREEN" "项目位置: $PROJECT_DIR"
    print_color "$YELLOW" "\n请选择要编辑的配置文件:"
    echo
    echo "1) 机器人行为配置 (bot_config.toml)"
    echo "   - 人格系统、聊天控制、表达学习"
    echo "   - 关系系统、记忆系统、情绪系统" 
    echo "   - 表情包、消息过滤、关键词反应"
    echo
    echo "2) AI模型配置 (model_config.toml)"
    echo "   - API服务商配置"
    echo "   - 模型定义和任务分配"
    echo "   - 嵌入模型、工具模型配置"
    echo
    echo "3) 环境变量配置 (.env)"
    echo "   - 网络监听配置"
    echo "   - API密钥配置"
    echo
    echo "4) 适配器配置 (config.toml)"
    echo "   - NapCat连接配置"
    echo "   - MaiBot服务器配置"
    echo
    echo "5) Docker配置 (docker-compose.yml)"
    echo "   - 容器服务配置"
    echo "   - 端口映射和数据卷"
    echo
    echo "6) LPMM知识库配置 (lpmm_config.toml) - 如果存在"
    echo
    echo "7) 返回配置菜单"
    
    local editor_choice
    while true; do
        read -p "请选择要编辑的配置 (1-7): " editor_choice
        case "$editor_choice" in
            1 )
                edit_config_file "docker-config/mmc/bot_config.toml" "机器人行为配置"
                break
                ;;
            2 )
                edit_config_file "docker-config/mmc/model_config.toml" "AI模型配置"
                break
                ;;
            3 )
                edit_config_file "docker-config/mmc/.env" "环境变量配置"
                break
                ;;
            4 )
                edit_config_file "docker-config/adapters/config.toml" "适配器配置"
                break
                ;;
            5 )
                edit_config_file "docker-compose.yml" "Docker配置"
                break
                ;;
            6 )
                edit_config_file "docker-config/mmc/lpmm_config.toml" "LPMM知识库配置"
                break
                ;;
            7 )
                return
                ;;
            * )
                print_color "$RED" "无效选择，请输入 1-7"
                ;;
        esac
    done
}

function edit_config_file() {
    local config_file="$1"
    local config_name="$2"
    
    print_color "$BLUE" "\n--- 编辑 $config_name ---"
    
    if [ ! -f "$config_file" ]; then
        print_color "$RED" "配置文件不存在: $config_file"
        read -p "是否要创建该文件？(y/n): " create_file
        if [[ "$create_file" =~ ^[Yy]$ ]]; then
            # 创建目录（如果不存在）
            mkdir -p "$(dirname "$config_file")"
            touch "$config_file"
            print_color "$GREEN" "已创建文件: $config_file"
        else
            return
        fi
    fi
    
    print_color "$YELLOW" "即将使用 vim 编辑器打开配置文件"
    print_color "$CYAN" "文件路径: $PROJECT_DIR/$config_file"
    print_color "$CYAN" "vim 使用提示:"
    print_color "$CYAN" "  - 按 'i' 进入插入模式"
    print_color "$CYAN" "  - 按 'Esc' 退出插入模式"
    print_color "$CYAN" "  - 输入 ':wq' 保存并退出"
    print_color "$CYAN" "  - 输入 ':q!' 不保存退出"
    echo
    
    read -p "按 Enter 键继续，或输入 'c' 取消: " continue_edit
    if [[ "$continue_edit" == "c" ]]; then
        return
    fi
    
    # 备份原文件
    local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$config_file" "$backup_file" 2>/dev/null && {
        print_color "$GREEN" "已创建备份文件: $backup_file"
    }
    
    # 使用vim编辑
    print_color "$YELLOW" "正在打开编辑器..."
    vim "$config_file"
    
    # 检查文件是否被修改
    if [ -f "$backup_file" ]; then
        if ! diff -q "$config_file" "$backup_file" >/dev/null 2>&1; then
            print_color "$GREEN" "配置文件已修改完成"
            
            # 配置文件语法检查
            case "$config_file" in
                *.toml )
                    print_color "$YELLOW" "检查 TOML 语法..."
                    if command_exists python3; then
                        python3 -c "import tomllib; tomllib.load(open('$config_file', 'rb'))" 2>/dev/null && {
                            print_color "$GREEN" "TOML 语法检查通过"
                        } || {
                            print_color "$RED" "TOML 语法检查失败，请检查配置文件格式"
                        }
                    fi
                    ;;
                docker-compose.yml )
                    print_color "$YELLOW" "检查 Docker Compose 语法..."
                    if docker compose config >/dev/null 2>&1; then
                        print_color "$GREEN" "Docker Compose 语法检查通过"
                    else
                        print_color "$RED" "Docker Compose 语法检查失败，请检查配置文件格式"
                    fi
                    ;;
            esac
            
            read -p "配置修改完成，是否重启服务？(y/n): " restart_choice
            if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
                restart_services
            fi
        else
            print_color "$YELLOW" "配置文件未发生变化"
            rm -f "$backup_file"
        fi
    fi
}

function show_current_config() {
    print_color "$BLUE" "\n--- 查看当前配置 ---"
    
    if ! find_maibot_project; then
        return
    fi
    
    cd "$PROJECT_DIR" || {
        print_color "$RED" "无法进入项目目录 $PROJECT_DIR"
        return
    }
    
    print_color "$GREEN" "项目位置: $PROJECT_DIR"
    
    # 显示服务状态
    print_color "$YELLOW" "\n=== 服务状态 ==="
    if command_exists docker && docker compose ps >/dev/null 2>&1; then
        docker compose ps
    else
        print_color "$RED" "无法获取服务状态，请确保在正确的项目目录中"
    fi
    
    # 显示机器人配置
    print_color "$YELLOW" "\n=== 机器人配置 ==="
    local bot_config="docker-config/mmc/bot_config.toml"
    if [ -f "$bot_config" ]; then
        print_color "$CYAN" "QQ账号: $(grep 'qq_account' "$bot_config" | cut -d'=' -f2 | tr -d ' ' || echo '未配置')"
        print_color "$CYAN" "昵称: $(grep 'nickname' "$bot_config" | cut -d'=' -f2 | tr -d ' "' || echo '未配置')"
    else
        print_color "$RED" "机器人配置文件不存在"
    fi
    
    # 显示API配置
    print_color "$YELLOW" "\n=== API配置 ==="
    local env_file="docker-config/mmc/.env"
    if [ -f "$env_file" ]; then
        local api_key=$(grep 'SILICONFLOW_KEY' "$env_file" | cut -d'=' -f2)
        if [ -n "$api_key" ] && [ "$api_key" != "your-api-key-here" ] && [ "$api_key" != "your-siliconflow-api-key" ]; then
            print_color "$CYAN" "API Key: ${api_key:0:8}... (已配置)"
        else
            print_color "$RED" "API Key: 未正确配置"
        fi
    else
        print_color "$RED" "环境配置文件不存在"
    fi
    
    # 显示端口配置
    print_color "$YELLOW" "\n=== 端口配置 ==="
    if [ -f "docker-compose.yml" ]; then
        print_color "$CYAN" "开放的端口:"
        grep -E "^\s*-\s*\"[0-9]+:[0-9]+\"" docker-compose.yml | sed 's/^[[:space:]]*/  /' || print_color "$RED" "未找到端口配置"
    else
        print_color "$RED" "Docker Compose配置文件不存在"
    fi
    
    # 显示访问地址
    print_color "$YELLOW" "\n=== 访问地址 ==="
    local server_ip=$(get_public_ip)
    if [ -n "$server_ip" ]; then
        print_color "$CYAN" "NapCat WebUI: http://$server_ip:6099/webui"
        print_color "$CYAN" "Chat2DB: http://$server_ip:10824"
    else
        print_color "$CYAN" "NapCat WebUI: http://你的服务器IP:6099/webui"
        print_color "$CYAN" "Chat2DB: http://你的服务器IP:10824"
    fi
}

function restart_services() {
    print_color "$BLUE" "\n--- 重启服务 ---"
    
    # 如果没有设置PROJECT_DIR，尝试查找
    if [ -z "$PROJECT_DIR" ]; then
        if ! find_maibot_project; then
            return
        fi
    fi
    
    if [ ! -d "$PROJECT_DIR" ] || [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
        print_color "$RED" "无效的项目目录路径: $PROJECT_DIR"
        return
    fi
    
    cd "$PROJECT_DIR" || {
        print_color "$RED" "无法进入项目目录"
        return
    }
    
    print_color "$YELLOW" "正在重启服务..."
    if docker compose restart; then
        print_color "$GREEN" "服务重启完成。"
        
        # 等待服务启动并检查状态
        print_color "$YELLOW" "等待服务启动..."
        sleep 5
        
        print_color "$CYAN" "当前服务状态:"
        docker compose ps
    else
        print_color "$RED" "服务重启失败，请检查日志:"
        print_color "$YELLOW" "docker compose logs -f"
    fi
}

#==============================================================================
# 最终指引函数
# 显示部署完成后的配置说明
#==============================================================================

function show_summary() {
    print_color "$BLUE" "\n==================== 🎉 MaiBot 部署完成 ===================="
    print_color "$GREEN" "恭喜！MaiBot AI机器人已成功部署并正在后台运行。"
    
    # 如果使用了镜像代理，提示用户
    if [ "$USE_CHINA_MIRROR" = true ]; then
        print_color "$CYAN" "📡 已为国内用户配置镜像代理，所有容器镜像通过 docker.gh-proxy.com 加速拉取。"
    fi
    
    print_color "$YELLOW" "\n接下来，请按照以下步骤完成手动配置："
    
    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 1: 配置 NapCat 并让机器人上线"
    echo -e "--------------------------------------------------"
    echo -e "1. 访问 NapCat WebUI: ${GREEN}http://${SERVER_IP}:6099/webui${NC}"
    echo -e "2. 使用默认登录令牌: ${GREEN}napcat${NC}"
    echo -e "3. 登录后，请扫描屏幕上的二维码，让您的机器人QQ (${GREEN}${ROBOT_QQ}${NC}) 上线。"
    echo -e "4. ${YELLOW}配置网络连接:${NC}"
    echo -e "   a. 点击 ${GREEN}[网络配置]${NC}"
    echo -e "   b. 点击 ${GREEN}[新建]${NC}"
    echo -e "   c. 选择 ${GREEN}[Websocket客户端]${NC}"
    echo -e "   d. 填写以下信息:"
    echo -e "      - 名称: ${GREEN}MaiBot${NC}"
    echo -e "      - URL: ${GREEN}ws://adapters:8095${NC}"
    echo -e "      - 信息格式: 保持默认的 ${GREEN}Array${NC}"
    echo -e "      - Token: ${GREEN}留空（如需安全性可自定义）${NC}"
    echo -e "   e. 点击 ${GREEN}[保存]${NC} 并启用连接"

    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 2: 验证服务连接状态"
    echo -e "--------------------------------------------------"
    echo -e "1. 检查容器运行状态:"
    echo -e "   ${YELLOW}cd ~/$PROJECT_DIR && docker compose ps${NC}"
    echo -e "2. 查看服务日志:"
    echo -e "   ${YELLOW}docker compose logs -f${NC}"
    echo -e "3. 确认所有服务都显示为 ${GREEN}running${NC} 状态"

    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 3: 测试机器人功能"
    echo -e "--------------------------------------------------"
    echo -e "1. 使用您的个人QQ向机器人发送消息测试连接"
    echo -e "2. 可以发送 ${GREEN}@${BOT_NICKNAME} 你好${NC} 进行测试"
    echo -e "3. 如果机器人能够回复，说明配置成功"

    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "步骤 4: 数据库管理 (可选)"
    echo -e "--------------------------------------------------"
    echo -e "1. 访问 Chat2DB: ${GREEN}http://${SERVER_IP}:10824${NC}"
    echo -e "2. 数据库配置:"
    echo -e "   - 类型: ${GREEN}SQLite${NC}"
    echo -e "   - 文件路径: ${GREEN}/data/MaiMBot/MaiBot.db${NC}"

    echo -e "\n--------------------------------------------------"
    print_color "$BLUE" "🔧 高级配置选项"
    echo -e "--------------------------------------------------"
    echo -e "• 机器人配置文件: ${YELLOW}~/$PROJECT_DIR/docker-config/mmc/bot_config.toml${NC}"
    echo -e "• 模型配置文件: ${YELLOW}~/$PROJECT_DIR/docker-config/mmc/model_config.toml${NC}"
    echo -e "• 环境变量文件: ${YELLOW}~/$PROJECT_DIR/docker-config/mmc/.env${NC}"
    echo -e "• 修改配置后请重启: ${YELLOW}docker compose restart${NC}"

    print_color "$BLUE" "\n==================== 📱 管理与维护 ===================="
    echo -e "您的所有项目文件都位于: ${YELLOW}~/${PROJECT_DIR}${NC}"
    echo -e "如需管理服务，请先进入该目录: ${YELLOW}cd ~/${PROJECT_DIR}${NC}"
    echo -e "常用命令:"
    echo -e "  - 停止服务: ${YELLOW}docker compose down${NC}"
    echo -e "  - 启动服务: ${YELLOW}docker compose up -d${NC}"
    echo -e "  - 重启服务: ${YELLOW}docker compose restart${NC}"
    echo -e "  - 查看日志: ${YELLOW}docker compose logs -f${NC}"
    echo -e "  - 查看状态: ${YELLOW}docker compose ps${NC}"
    
    print_color "$CYAN" "\n💡 提示: 如需进一步自定义机器人行为，请参考配置文档进行详细设置。"
    
    print_color "$BLUE" "\n==================== 🔧 后续配置管理 ===================="
    print_color "$YELLOW" "MaiBot 部署完成后，您可以随时使用配置模式进行管理："
    print_color "$CYAN" "1. 重新运行脚本: ${YELLOW}sudo ./setup_maibot.sh${NC}"
    print_color "$CYAN" "2. 选择 ${GREEN}配置模式${NC}"
    print_color "$CYAN" "3. 可进行以下操作:"
    print_color "$CYAN" "   • 修改机器人 QQ 号和昵称"
    print_color "$CYAN" "   • 更换 AI 模型 API 密钥"
    print_color "$CYAN" "   • 查看服务运行状态"
    print_color "$CYAN" "   • 编辑高级配置 (人格、聊天、记忆等)"
    print_color "$CYAN" "   • 重启服务使配置生效"
    
    print_color "$BLUE" "==================================================\n"
    
    # 询问是否立即进入配置模式
    echo
    read -p "是否要立即进入配置模式进行进一步设置？(y/n): " enter_config
    if [[ "$enter_config" =~ ^[Yy]$ ]]; then
        print_color "$GREEN" "\n正在进入配置模式..."
        sleep 1
        config_mode
    else
        print_color "$YELLOW" "您可以随时重新运行脚本进入配置模式。"
    fi
}

#==============================================================================
# 主函数
# 负责脚本整体执行流程控制和用户交互
#==============================================================================

function main() {
    clear
    print_color "$BLUE" "========================================================"
    print_color "$BLUE" "           MaiBot AI机器人 一键部署脚本"
    print_color "$BLUE" "========================================================"
    
    # 基础环境检查
    check_root
    check_os
    
    # 模式选择
    select_mode
    
    if [ "$MODE" = "install" ]; then
        # 安装部署模式
        install_dependencies
        handle_location
        install_docker
        check_docker_compose
        collect_config
        create_project_structure
        download_template_files
        modify_docker_compose
        
        # 如果是国内用户，添加镜像代理
        if [ "$USE_CHINA_MIRROR" = true ]; then
            add_docker_proxy_for_china
        fi
        
        modify_env_config
        modify_adapter_config
        initial_container_startup
        modify_bot_config
        start_services
        show_summary
    elif [ "$MODE" = "config" ]; then
        # 配置模式
        config_mode
    fi
}

# --- 脚本入口 ---
main "$@"
