# Ubuntu 仿 Win11 一键美化脚本（适配华为 MateBook 15d）
该脚本适用于 **Windows11 + Ubuntu 双系统**环境，一键实现终端美化、桌面仿 Win11、Grub 美化、指纹登录/ sudo 验证。

## 🌟 功能清单
1.  系统中文环境配置
2.  终端美化：oh-my-zsh + Powerlevel10k + Meslo Nerd Font
3.  桌面美化：WhiteSur 主题/图标/光标 + GNOME 插件依赖
4.  Grub 启动项美化工具安装
5.  华为 MateBook 15d 指纹适配（登录 + sudo 验证）

## 🚀 一键运行
```bash
# 方式1：直接运行（需 sudo 权限）
wget -O - https://raw.githubusercontent.com/tbtb20110110/Ubuntu-function/main/function.sh | sudo bash

# 方式2：下载后运行
wget https://raw.githubusercontent.com/tbtb20110110/Ubuntu-function/main/function.sh
chmod +x function.sh
sudo ./function.sh
