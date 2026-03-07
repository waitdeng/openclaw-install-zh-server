# OpenClaw 中文版服务器安装脚本

一个用于 **OpenClaw 汉化版服务器部署与维护** 的自动化脚本。

支持：

-   自动安装 OpenClaw 汉化版
-   查看可用版本并选择安装
-   升级 / 降级版本
-   版本回退
-   自动备份配置
-   恢复配置
-   自动修复 npm PATH
-   自动创建 `openclaw` 命令
-   自动初始化 daemon
-   自动尝试 systemd 用户服务

适合：

-   VPS
-   Linux 服务器
-   Ubuntu / Debian
-   DevOps 自动化部署

------------------------------------------------------------------------

# 目录

-   [项目特点](#项目特点)
-   [环境要求](#环境要求)
-   [快速开始](#快速开始)
-   [使用示例](#使用示例)
-   [配置备份](#配置备份)
-   [常用命令](#常用命令)

------------------------------------------------------------------------

# 项目特点

### 自动版本管理

支持

-   安装指定版本
-   自动查看可用版本
-   版本升级
-   版本降级
-   版本回退

### 自动配置备份

安装前自动备份

    ~/.openclaw

备份目录

    ~/.openclaw-backups/

### 自动修复 PATH

如果 `npm install -g` 后 `openclaw` 不在 PATH：

脚本会自动：

-   修复 PATH
-   添加到 shell profile
-   创建软链接

### 自动 daemon 初始化

安装完成后执行

    openclaw onboard --install-daemon

### 服务器增强

兼容：

-   root 环境
-   SSH 环境
-   systemd user service

------------------------------------------------------------------------

# 环境要求

系统

    Linux
    Ubuntu / Debian 推荐

Node.js

    >= 22
    推荐 >= 22.12

如果 Node 未安装，脚本会自动安装。

------------------------------------------------------------------------

# 快速开始

## 1 下载脚本

    git clone https://github.com/waitdeng/openclaw-install-zh-server.git
    cd openclaw-install-zh-server

或直接下载脚本

    wget -O openclaw-install.sh https://raw.githubusercontent.com/waitdeng/openclaw-install-zh-server/main/openclaw-install-zh-server.sh && chmod +x openclaw-install.sh && ./openclaw-install.sh

## 2 添加执行权限

    chmod +x openclaw-install-zh-server.sh

## 3 运行

    ./openclaw-install-zh-server.sh

------------------------------------------------------------------------

# 使用示例

## 交互式安装

    ./openclaw-install-zh-server.sh

脚本会显示

    1. 安装/切换版本
    2. 回退版本
    3. 恢复配置

## 安装指定版本

    ./openclaw-install-zh-server.sh 1.2.3

## 非交互安装

    ACTION=install OPENCLAW_VERSION=1.2.3 ./openclaw-install-zh-server.sh

## 回退版本

    ACTION=rollback OPENCLAW_VERSION=1.2.2 ./openclaw-install-zh-server.sh

## 仅恢复配置

    ACTION=restore-config ./openclaw-install-zh-server.sh

## 安装失败自动恢复配置

    AUTO_RESTORE_CONFIG_ON_FAIL=1 ./openclaw-install-zh-server.sh

## 跳过 daemon 初始化

    SKIP_ONBOARD=1 ./openclaw-install-zh-server.sh

------------------------------------------------------------------------

# 配置备份

安装或升级前自动备份

    ~/.openclaw

备份目录

    ~/.openclaw-backups/openclaw-backup-20260307-120000

恢复备份

    ACTION=restore-config ./openclaw-install-zh-server.sh

------------------------------------------------------------------------

# 常用命令

查看版本

    openclaw --version

打开面板

    openclaw dashboard

查看 gateway

    openclaw gateway status

查看 systemd

    systemctl --user status 'openclaw-gateway*'

查看日志

    journalctl --user -u openclaw-gateway-default.service -n 100

------------------------------------------------------------------------



# Star History

如果这个脚本对你有帮助，请点一个 ⭐
