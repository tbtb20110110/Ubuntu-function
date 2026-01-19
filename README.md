# Ubuntu 双系统一键美化脚本（仿Win11+指纹适配）
适配 **Ubuntu 22.04/24.04 LTS**，华为 MateBook 15d 指纹模块，实现终端美化、桌面仿Win11、Grub美化、指纹登录+sudo验证。

## 功能清单
- ✅ 系统中文环境配置
- ✅ 终端美化：Meslo Nerd Font 字体 + Dracula 配色
- ✅ 桌面美化：WhiteSur 主题（仿Win11）+ 任务栏扩展
- ✅ Grub 美化：Win11风格启动菜单
- ✅ 指纹适配：登录解锁 + sudo 权限验证

## 使用步骤
### 1. 下载脚本
```bash
wget -q https://raw.githubusercontent.com/tbtb20110110/Ubuntu-function/main/function.sh -O function.sh
chmod +x function.sh
sudo bash ./function.sh
