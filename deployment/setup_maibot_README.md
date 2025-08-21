# 🤖 MaiBot AI机器人一键部署脚本

## 📖 项目简介

MaiBot 是一个基于先进AI模型的智能聊天机器人，具备丰富的人格系统、记忆功能、表达学习等特性。本脚本提供了完整的一键部署解决方案，让您轻松拥有一个功能强大的AI机器人。

## ⭐ 主要特性

### 🎯 核心功能
- **智能对话**: 基于大语言模型的自然对话能力
- **人格系统**: 可自定义的人格特质和表达风格
- **记忆系统**: 能够记住重要信息并建立联想
- **表达学习**: 学习用户表达方式，个性化回复
- **关系系统**: 建立并记忆与不同用户的关系
- **情绪系统**: 具备情绪变化和表达能力

### 🛠️ 技术栈
- **MaiBot Core**: AI机器人核心服务
- **NapCat**: QQ协议适配器，稳定可靠
- **Adapters**: 协议适配服务，支持多平台
- **MySQL**: 数据持久化存储
- **Chat2DB**: 数据库管理工具
- **Docker**: 容器化部署，简化管理

### 🔧 支持的AI服务商
- **硅基流动 (SiliconFlow)** - 推荐，提供免费额度，模型丰富
- **DeepSeek** - 性价比高，推理能力强
- **OpenAI** - 官方模型，质量稳定
- **智谱AI (GLM)** - 国产优秀模型
- **月之暗面 (Kimi)** - 长上下文支持
- **其他 OpenAI 兼容服务** - 灵活扩展支持

## 🚀 快速开始

### 📋 系统要求
- **操作系统**: Ubuntu 18.04+ / Debian 10+
- **最低配置**: 2核CPU / 2GB内存 / 5GB磁盘空间
- **推荐配置**: 4核CPU / 4GB内存 / 20GB磁盘空间
- **权限要求**: root权限或sudo权限
- **网络要求**: 能够访问Docker Hub和相关下载源
- **开放端口**: 6099 (NapCat WebUI)、8000 (MaiBot)、8095 (Adapters)、10824 (Chat2DB)

### ⚡ 一键部署

#### 🇨🇳 国内用户 (推荐)
```bash
sudo bash -c "$(curl -fsSL https://gitee.com/nfasystem/project_sh/raw/main/deployment/setup_maibot.sh)"
```

#### 🌍 海外用户
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nfachenxi/project_sh/main/deployment/setup_maibot.sh)"
```

## 📝 部署流程

### 1️⃣ 运行脚本
选择运行模式：
- **安装部署模式**: 全新安装MaiBot
- **配置模式**: 修改现有MaiBot配置

### 2️⃣ 环境配置
- 自动检测系统环境（仅支持Ubuntu/Debian）
- 根据地理位置选择镜像源（国内/海外）
- 自动安装Docker和Docker Compose

### 3️⃣ 交互式配置
- **项目目录**: 自定义部署目录名
- **机器人信息**: QQ号、昵称设置
- **AI服务**: 选择AI服务商并配置API密钥
- **数据库**: 设置MySQL密码

### 4️⃣ 自动部署
- 下载配置模板文件
- 生成Docker Compose配置
- 启动所有服务容器
- 验证部署状态

### 5️⃣ 手动配置
部署完成后需要进行以下手动配置：

#### NapCat配置
1. 访问 `http://服务器IP:6099/webui`
2. 使用默认token: `napcat`
3. 扫码登录机器人QQ账号
4. 配置网络连接:
   - 选择 "Websocket客户端"
   - URL: `ws://adapters:8095`
   - 保存并启用

#### 验证部署
- 使用个人QQ向机器人发送测试消息
- 检查机器人是否正常回复
- 查看服务运行状态

## 🔧 高级配置

### 配置模式功能
重新运行脚本选择配置模式，可进行：

#### 基础配置
- **机器人设置**: 修改QQ号、昵称
- **API配置**: 更换AI服务商和密钥
- **网络配置**: 查看和修改端口设置
- **状态查看**: 检查服务运行状态

#### 高级配置编辑器
支持直接编辑以下配置文件：

1. **机器人行为配置** (`bot_config.toml`)
   - 人格系统、聊天控制、表达学习
   - 关系系统、记忆系统、情绪系统
   - 表情包、消息过滤、关键词反应

2. **AI模型配置** (`model_config.toml`)
   - API服务商配置
   - 模型定义和任务分配
   - 嵌入模型、工具模型配置

3. **环境变量配置** (`.env`)
   - 网络监听配置
   - API密钥配置

4. **适配器配置** (`config.toml`)
   - NapCat连接配置
   - MaiBot服务器配置

5. **Docker配置** (`docker-compose.yml`)
   - 容器服务配置
   - 端口映射和数据卷

6. **LPMM知识库配置** (`lpmm_config.toml`) - 如果启用知识库功能
   - 知识提取和搜索参数
   - 向量数据库配置

### 🎨 配置示例

### 人格系统配置示例
```toml
[personality]
personality_core = "是一个活泼可爱的女孩子"
personality_side = "喜欢开玩笑，有时候会说些奇怪的话"
reply_style = "回复要简短有趣，多用emoji"
```

### 聊天控制配置示例
```toml
[chat]
talk_frequency = 0.8    # 活跃度 (0-1)
focus_value = 0.6       # 专注度 (0-1)
max_context_size = 30   # 上下文长度
mentioned_bot_inevitable_reply = true  # @机器人必回
at_bot_inevitable_reply = true         # 提及机器人必回
```

### 记忆系统配置示例
```toml
[memory]
enable_memory = true               # 启用记忆系统
memory_build_frequency = 1         # 记忆构建频率
memory_compress_rate = 0.1         # 记忆压缩率
forget_memory_interval = 3000      # 遗忘间隔(秒)
memory_forget_time = 48           # 遗忘时间(小时)
memory_ban_words = ["图片", "表情包"]  # 记忆黑名单
```

### 表情包系统配置示例
```toml
[emoji]
emoji_chance = 0.6    # 表情包激活概率
max_reg_num = 60     # 最大注册数量
steal_emoji = true   # 是否偷取表情包
```

### AI模型配置示例
```toml
# API服务商配置
[[api_providers]]
name = "SiliconFlow"
base_url = "https://api.siliconflow.cn/v1"
api_key = "sk-your-api-key-here"
client_type = "openai"

# 模型定义
[[models]]
model_identifier = "Pro/deepseek-ai/DeepSeek-V3"
name = "deepseek-v3"
api_provider = "SiliconFlow"
price_in = 2.0
price_out = 8.0

# 任务模型配置
[model_task_config.replyer]
model_list = ["deepseek-v3"]
temperature = 0.2
max_tokens = 800
```

## 📊 服务管理

### 常用命令
```bash
# 进入项目目录
cd ~/your-project-name

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f

# 重启服务
docker compose restart

# 停止服务
docker compose down

# 启动服务
docker compose up -d
```

### 访问地址
- **NapCat WebUI**: `http://服务器IP:6099/webui` (默认token: `napcat`)
- **Chat2DB数据库管理**: `http://服务器IP:10824`

### 服务状态检查
```bash
# 查看所有容器状态
docker compose ps

# 检查特定服务
docker compose logs maibot-core
docker compose logs maibot-napcat
docker compose logs maibot-adapters

# 检查网络连接
docker network ls | grep maibot
```

## 🔍 故障排查

### 常见问题

1. **容器启动失败**
   - 检查端口冲突 (6099, 8000, 8095, 10824)
   - 验证API密钥有效性
   - 查看容器日志: `docker compose logs`

2. **机器人无响应**
   - 确认QQ账号已登录
   - 检查NapCat网络配置
   - 验证适配器连接状态

3. **配置文件错误**
   - 使用配置模式的语法检查功能
   - 恢复备份文件
   - 重新生成配置模板

4. **API调用失败**
   - 检查API密钥是否正确
   - 验证服务商额度是否充足
   - 确认网络能访问API服务商

5. **容器内存不足**
   - 增加服务器内存配置
   - 调整Docker内存限制
   - 优化模型配置参数

6. **数据库连接问题**
   - 检查MySQL容器状态
   - 验证数据库密码配置
   - 查看数据库连接日志

### 日志查看
```bash
# 查看所有服务日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f maibot-core
docker compose logs -f maibot-napcat
docker compose logs -f maibot-adapters

# 查看最近的错误日志
docker compose logs --tail=50 maibot-core | grep -i error

# 实时监控日志
docker compose logs -f --tail=100
```

### 性能监控
```bash
# 查看容器资源使用情况
docker stats

# 查看磁盘使用情况
df -h

# 查看内存使用情况
free -h

# 查看CPU使用情况
top
```

## 🔐 安全建议

1. **API密钥保护**
   - 妥善保管AI服务商API密钥
   - 定期更换密钥
   - 不要将配置文件上传到公开仓库

2. **网络安全**
   - 配置防火墙规则
   - 使用强密码
   - 定期更新系统和容器镜像

3. **数据备份**
   - 定期备份配置文件
   - 备份数据库数据
   - 保存重要的聊天记录

## 🆕 更新说明

### 镜像加速优化
- 国内用户自动使用 `docker.gh-proxy.com` 镜像代理
- 大幅提升容器镜像拉取速度
- 解决Docker Hub访问慢的问题

### 配置管理增强
- 新增高级配置编辑器
- 支持vim可视化编辑
- 自动备份和语法检查
- 配置修改后可立即重启服务

## 💡 最佳实践

### 🎯 机器人人格调优建议
1. **人格设定**
   - 保持人格一致性，避免矛盾设定
   - 根据使用场景调整表达风格
   - 适当设置个性化特征

2. **聊天控制优化**
   - 新部署建议先设置较低的活跃度 (0.3-0.5)
   - 根据群聊活跃程度调整回复频率
   - 使用时间段调整功能优化不同时间的表现

3. **记忆系统配置**
   - 初期可适当提高记忆构建频率
   - 定期清理无用记忆词汇
   - 根据使用情况调整遗忘参数

### 🔧 性能优化建议
1. **资源配置**
   - 根据使用频率调整服务器配置
   - 定期清理Docker镜像和容器
   - 监控数据库大小，及时备份

2. **API使用优化**
   - 合理设置模型参数，平衡质量和成本
   - 使用不同模型处理不同任务
   - 定期检查API使用量和余额

3. **网络优化**
   - 国内用户建议使用镜像加速
   - 配置合适的超时参数
   - 定期检查网络连接状态

### 📱 多平台部署
MaiBot 通过适配器支持多个聊天平台：
- **QQ**: 通过 NapCat 适配器
- **微信**: 需要额外配置微信适配器
- **Telegram**: 支持 Telegram Bot API
- **Discord**: 支持 Discord 机器人

### 🔄 备份与恢复策略
1. **定期备份**
   ```bash
   # 备份配置文件
   tar -czf maibot_config_$(date +%Y%m%d).tar.gz docker-config/
   
   # 备份数据库
   docker compose exec maibot-mysql mysqldump -u root -p maibot > maibot_db_$(date +%Y%m%d).sql
   ```

2. **恢复流程**
   ```bash
   # 恢复配置文件
   tar -xzf maibot_config_20241220.tar.gz
   
   # 恢复数据库
   docker compose exec -T maibot-mysql mysql -u root -p maibot < maibot_db_20241220.sql
   ```

## 🤝 贡献与支持

### 相关项目
- **[MaiBot](https://github.com/MaiM-with-u/MaiBot)**: MaiBot核心项目
- **[NapCat](https://github.com/NapNeko/NapCat)**: QQ协议适配器
- **[MaiBot-Napcat-Adapter](https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter)**: 协议适配服务

### 问题反馈
如果您在使用过程中遇到问题，请：
1. 查看故障排查部分
2. 检查容器日志
3. 搜索已有Issues是否有相似问题
4. 提交新的Issue时请提供：
   - 系统信息 (OS版本、Docker版本)
   - 错误日志
   - 配置文件 (请隐藏敏感信息)
   - 复现步骤

### 社区支持
- **GitHub Issues**: 报告Bug和功能请求
- **讨论区**: 技术交流和使用心得
- **Wiki**: 详细文档和教程

### 贡献指南
欢迎为项目做出贡献：
- 🐛 报告Bug
- 💡 提出新功能建议
- 📚 完善文档
- 🔧 提交代码改进
- 🌍 翻译文档

## 📄 许可证

本脚本遵循相应的开源许可证，具体请参考各个组件项目的许可证条款。

---

## 📈 版本历史

### v1.0.0 (最新)
- ✨ 完整的一键部署功能
- 🎛️ 双模式设计：安装模式 + 配置模式
- 🖥️ 高级配置编辑器，支持vim编辑
- 🌍 国内外镜像源自动选择
- 🔧 多AI服务商支持
- 📱 完整的故障排查指南
- 🔐 安全配置和备份建议

### 未来规划
- 🌐 Web配置面板
- 📊 性能监控仪表板
- 🤖 更多平台适配器
- 📚 知识库管理界面
- 🔄 自动更新功能

---

**享受您的AI机器人之旅！** 🎉

> 如果这个项目对您有帮助，请给个⭐️支持一下！
