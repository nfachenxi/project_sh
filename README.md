# 一键部署与工具脚本集合

## 📖 项目简介

欢迎来到我的脚本仓库！

本项目旨在收集和分享各类实用的一键部署与自动化工具脚本（Shell），力求将复杂繁琐的配置与安装流程简化为单行命令，让所有人都能轻松部署和使用各种开源项目。

所有脚本都经过测试，并尽可能提供交互式选项，以方便用户进行自定义配置。

## 🚀 使用方法

您只需复制所需脚本对应的“一键执行命令”，然后在您的服务器终端中执行即可。建议使用 `root` 用户或 `sudo` 权限运行。

通用执行格式：
```bash
sudo bash -c "$(curl -fsSL <脚本的URL地址>)"
```

---

## 📜 脚本列表

| 脚本名称                     | 功能描述                                                     | 一键执行命令                                                 |
| :--------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| **Gemini 轮询代理**          | 一键部署 Gemini API 密钥轮询代理服务，通过号池实现API的稳定、免费调用。支持 OpenAI 格式。 | **Gitee (国内推荐):** <br> `sudo bash -c "$(curl -fsSL https://gitee.com/nfasystem/project_sh/raw/main/deployment/setup_gemini_proxy.sh)"` <br><br> **GitHub (海外推荐):** <br> `sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nfachenxi/project_sh/main/deployment/setup_gemini_proxy.sh)"` |
| **Nextcloud 私有云盘**       | 提供新手和进阶两种模式，一键部署功能完善的 Nextcloud 私有云盘。进阶模式包含NPM反代、HTTPS及性能优化。 | **Gitee (国内推荐):** <br> `sudo bash -c "$(curl -fsSL https://gitee.com/nfasystem/project_sh/raw/main/deployment/setup_nextcloud.sh)"` <br><br> **GitHub (海外推荐):** <br> `sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nfachenxi/project_sh/main/deployment/setup_nextcloud.sh)"` |
| **Koishi + NapCat QQ机器人** | 一键部署基于 NapCat 的 Koishi QQ 机器人，包含数据库，提供完整的交互式配置引导。 | **Gitee (国内推荐):** <br> `sudo bash -c "$(curl -fsSL https://gitee.com/nfasystem/project_sh/raw/main/deployment/setup_koishi_napcat.sh)"` <br><br> **GitHub (海外推荐):** <br> `sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nfachenxi/project_sh/main/deployment/setup_koishi_napcat.sh)"` |
| **PMail 个人域名邮箱**       | 一键部署 PMail 个人域名邮箱服务器。交互式引导完成环境准备、数据库配置，并提供专业的 DNS 和 PTR 记录设置指南，助您获得高分邮件服务。 | **Gitee (国内推荐):** <br> `sudo bash -c "$(curl -fsSL https://gitee.com/nfasystem/project_sh/raw/main/deployment/setup_pmail.sh)"` <br><br> **GitHub (海外推荐):** <br> `sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nfachenxi/project_sh/main/deployment/setup_pmail.sh)"` |


---

## ⚠️ 注意事项

-   请在了解脚本具体功能后，再在您的服务器上执行。
-   所有脚本均在 `Debian` / `Ubuntu` 系统上测试通过，不保证与其他系统的完全兼容性。
-   执行来自互联网的脚本存在风险，请确保您信任脚本的来源。

## 🤝 贡献与反馈

如果您在使用过程中遇到任何问题，或有好的脚本推荐，欢迎通过 `Issues` 提出。



## 🙏 致谢

本仓库中的部分脚本功能实现，离不开以下优秀开源项目的支持，在此表示衷心感谢：

- **[snailyp/gemini-balance](https://github.com/snailyp/gemini-balance)**: Gemini API 轮询代理的核心项目。
- **[SuperManito/LinuxMirrors](https://github.com/SuperManito/LinuxMirrors)**: 提供强大易用的国内镜像源一键更换脚本（`linuxmirrors.cn`）。
- **[Nextcloud](https://github.com/nextcloud/server)**: 强大的开源私有云盘解决方案。
- **[Nginx Proxy Manager](https://github.com/NginxProxyManager/nginx-proxy-manager)**: 提供简单易用的图形化界面来管理反向代理和SSL证书。
- **[Koishi](https://github.com/koishijs/koishi)**: 强大的机器人框架，拥有丰富的插件生态。
- **[NapCat-Docker](https://github.com/NapNeko/NapCat-Docker)**: 提供稳定、易于部署的 NapCat Docker 镜像。
- **[Jinnrry/PMail](https://github.com/Jinnrry/PMail)**: 追求极简部署、极致资源占用的个人域名邮箱服务器。
