# OpenClaw 中文版服务器安装脚本

<p align="center">
  <img src="https://img.shields.io/badge/OpenClaw-Installer-blue" alt="OpenClaw Installer" />
  <img src="https://img.shields.io/badge/Platform-Linux-green" alt="Platform Linux" />
  <img src="https://img.shields.io/badge/Shell-Bash-orange" alt="Shell Bash" />
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="MIT License" />
</p>

一个面向 **OpenClaw 汉化版** 的 Linux 服务器安装与维护脚本，适合 VPS、云服务器、Ubuntu / Debian 以及 SSH 场景。

## 特性

- 查看可用版本并交互选择安装
- 安装 / 切换指定版本
- 回退到旧版本
- 安装前自动备份配置
- 支持恢复历史配置
- 自动修复 `npm -g` 的 `PATH`
- 自动尝试创建 `openclaw` 命令软链接
- 自动执行 `openclaw onboard --install-daemon`
- 自动尝试启用 `systemd --user`

---

## 目录

- [项目结构](#项目结构)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [使用方式](#使用方式)
- [环境变量](#环境变量)
- [配置备份与恢复](#配置备份与恢复)
- [常用命令](#常用命令)
- [FAQ](#faq)
- [变更日志](#变更日志)
- [License](#license)

---

## 项目结构

建议仓库结构如下：

```text
openclaw-install-zh-server/
├─ openclaw-install-zh-server.sh
├─ README.md
├─ LICENSE
└─ CHANGELOG.md
```

---

## 环境要求

系统要求：

```text
Linux
推荐 Ubuntu / Debian
```

Node.js 要求：

```text
>= 22
推荐 >= 22.12.0
```

如果系统未安装合适版本的 Node.js，脚本会尝试自动安装。

---

## 快速开始

### 方式一：git clone

```bash
git clone https://github.com/waitdeng/openclaw-install-zh-server.git
cd openclaw-install-zh-server
chmod +x openclaw-install-zh-server.sh
./openclaw-install-zh-server.sh
```

### 方式二：wget

```bash
wget -O openclaw-install.sh https://raw.githubusercontent.com/waitdeng/openclaw-install-zh-server/main/openclaw-install-zh-server.sh
chmod +x openclaw-install.sh
./openclaw-install.sh
```

### 方式三：curl 一键运行

```bash
curl -fsSL https://raw.githubusercontent.com/waitdeng/openclaw-install-zh-server/main/openclaw-install-zh-server.sh | bash
```

---

## 使用方式

### 交互模式

```bash
./openclaw-install-zh-server.sh
```

脚本会显示：

```text
[1] 安装 / 切换到指定版本
[2] 回退到指定旧版本
[3] 仅恢复配置备份
```

### 非交互模式

安装指定版本：

```bash
ACTION=install OPENCLAW_VERSION=1.2.3 ./openclaw-install-zh-server.sh
```

回退到指定版本：

```bash
ACTION=rollback OPENCLAW_VERSION=1.2.2 ./openclaw-install-zh-server.sh
```

仅恢复配置：

```bash
ACTION=restore-config ./openclaw-install-zh-server.sh
```

安装失败时自动恢复最近配置备份：

```bash
AUTO_RESTORE_CONFIG_ON_FAIL=1 ./openclaw-install-zh-server.sh
```

跳过 daemon 初始化：

```bash
SKIP_ONBOARD=1 ./openclaw-install-zh-server.sh
```

---

## 环境变量

| 变量名 | 说明 | 示例 |
|---|---|---|
| `OPENCLAW_VERSION` | 指定目标版本 | `OPENCLAW_VERSION=1.2.3` |
| `ACTION` | 操作模式：`install` / `rollback` / `restore-config` | `ACTION=rollback` |
| `AUTO_RESTORE_CONFIG_ON_FAIL` | 安装失败时自动恢复最近配置备份，`0` 或 `1` | `AUTO_RESTORE_CONFIG_ON_FAIL=1` |
| `SKIP_ONBOARD` | 跳过 `openclaw onboard --install-daemon`，`0` 或 `1` | `SKIP_ONBOARD=1` |
| `OPENCLAW_STATE_DIR` | 自定义 OpenClaw 状态目录 | `OPENCLAW_STATE_DIR=/data/openclaw` |
| `OPENCLAW_BACKUP_DIR` | 自定义配置备份目录 | `OPENCLAW_BACKUP_DIR=/data/openclaw-backups` |

---

## 配置备份与恢复

默认状态目录：

```bash
~/.openclaw
```

默认备份目录：

```bash
~/.openclaw-backups
```

安装、切换、回退前会自动备份配置。

只恢复配置：

```bash
ACTION=restore-config ./openclaw-install-zh-server.sh
```

---

## 常用命令

查看版本：

```bash
openclaw --version
```

打开面板：

```bash
openclaw dashboard
```

查看 gateway 状态：

```bash
openclaw gateway status
```

查看 systemd 用户服务状态：

```bash
systemctl --user status 'openclaw-gateway*'
```

查看日志：

```bash
journalctl --user -u openclaw-gateway-default.service -n 100 --no-pager
```

---

## FAQ

<details>
<summary><strong>安装后找不到 <code>openclaw</code> 命令怎么办？</strong></summary>

先检查：

```bash
which openclaw
npm prefix -g
ls -l "$(npm prefix -g)/bin/openclaw"
```

然后重新加载 shell：

```bash
source ~/.bashrc
hash -r
```

</details>

<details>
<summary><strong><code>systemctl --user</code> 不稳定怎么办？</strong></summary>

这通常发生在 root 用户、纯 SSH 会话或者没有完整用户会话环境时。

建议执行：

```bash
loginctl enable-linger "$(whoami)"
```

同时更推荐使用普通用户运行 OpenClaw。

</details>

<details>
<summary><strong>生产环境升级建议是什么？</strong></summary>

推荐顺序：

```bash
AUTO_RESTORE_CONFIG_ON_FAIL=1 SKIP_ONBOARD=1 ./openclaw-install-zh-server.sh
openclaw --version
openclaw onboard --install-daemon
```

</details>

---

## 变更日志

### v1.0.0

- 初始版本
- 支持查看版本并安装
- 支持 daemon 初始化

### v1.1.0

- 增加服务器环境优化
- 自动修复 PATH
- 自动尝试创建命令软链接

### v1.2.0

- 增加版本回退功能
- 增加安装失败自动回退

### v1.3.0

- 增加配置自动备份
- 增加配置恢复模式
- 增加安装失败自动恢复配置开关

---

## License

MIT

如果这个项目对你有帮助，欢迎点一个 ⭐
