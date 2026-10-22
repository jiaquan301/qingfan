# 青番 Qingfan

**一个简单、安静的桌面番茄钟。专注当前任务，其余交给时间。**

青番提供可拖动的透明圆形时钟、迷你模式、任务清单和简洁的偏好设置。无需账号，不依赖在线服务；任务与设置保存在本机。

> **版本说明（2026-10-22）**：Flutter V2 已通过 Ubuntu、Windows、macOS 的 CI 构建、自动化界面及原生窗口验收，当前仍是**测试候选版**，位于 [PR #4](https://github.com/jiaquan301/qingfan/pull/4) 的开发分支，**尚未合并 main 或正式发布**。旧版 Ubuntu GTK3 V1.1 仍保留在仓库根目录。以下首先介绍 **V2**，最后说明旧版安装与卸载。Windows 安装包尚未签名，macOS 安装包尚未签名和公证；真实设备的最终兼容性仍需验证。

## 1. 下载 V2 安装包

以下链接均来自已通过验收的 [GitHub Actions 构建 #39745725008](https://github.com/jiaquan301/qingfan/actions/runs/39745725008)，包含最新休息阶段修复（提交 `59c29f2`）。下载的是 GitHub **Artifacts 压缩包**，请先解压；访问下载页可能需要登录 GitHub。

| 系统 | 安装文件 | 下载 |
| --- | --- | --- |
| **Ubuntu 22.04 / 24.04（x86-64）** | `qingfan_2.0.0~dev4_amd64.deb` | [Ubuntu DEB](https://github.com/jiaquan301/qingfan/actions/runs/39745725008/artifacts/12411307813) |
| **Windows 10 / 11（x64）** | `qingfan-v2-windows-x64-installer-unsigned.exe` | [Windows 安装版](https://github.com/jiaquan301/qingfan/actions/runs/39745725008/artifacts/12410798248) |
| **Windows 10 / 11（x64）** | `qingfan-v2-windows-x64-unsigned.zip` | [Windows 便携版](https://github.com/jiaquan301/qingfan/actions/runs/39745725008/artifacts/12411935146) |
| **macOS（测试候选版）** | `qingfan-v2-macos-unsigned.dmg` / `.app` ZIP | [macOS 安装包](https://github.com/jiaquan301/qingfan/actions/runs/39745725008/artifacts/12411696796) |

macOS 当前包由 CI 的 macOS 构建机生成；尚未确认其在所有 Intel 与 Apple Silicon 设备上的分发兼容性。

## 2. 安装与启动

### Ubuntu

1. 下载并解压 `qingfan-v2-ubuntu-deb` 附件，进入 **`.deb` 文件所在目录**。
2. 在该目录打开终端，执行：

   ```bash
   sudo apt install ./qingfan_2.0.0~dev4_amd64.deb
   ```

3. 打开应用程序菜单，搜索 **青番**；或直接运行：

   ```bash
   /usr/lib/qingfan/qingfan
   ```

安装包会自动配置必要的运行依赖与桌面入口，不需要为 V2 单独安装 Python 或 GTK3 开发环境。安装更新版本时，下载新的 `.deb` 再运行 `sudo apt install ./<实际文件名>.deb`。

**注意**：旧版 GTK3 与 V2 可能同时在应用菜单中显示为“青番”。若准备改用 V2，建议先执行下文的旧版卸载步骤，以免启动错误版本。

### Windows

**安装版：** 下载并解压安装附件，双击 `qingfan-v2-windows-x64-installer-unsigned.exe`，按向导完成安装；然后在开始菜单搜索 **青番**。安装时可选择是否创建桌面快捷方式。

**便携版：** 下载便携 ZIP 并完整解压到单独文件夹，双击其中的 `qingfan.exe`。**不要单独复制 EXE**，它需要同目录中的 Flutter 动态库和 `data` 资源。便携版不需要运行安装程序。

Windows 安装包尚无数字签名。如果系统显示安全警告，请先确认文件来自本仓库对应的 GitHub Actions 结果；不要运行来源不明的同名安装包。

### macOS

1. 下载并解压 `qingfan-v2-macos-app-unsigned` 附件。
2. 打开其中的 `.dmg`，将 `qingfan.app` 复制到 **应用程序（Applications）** 文件夹；也可使用附件内的 `.app` 压缩包解压后复制。
3. 从“应用程序”打开青番。

这是未签名、未公证的测试版。macOS 可能阻止首次打开：确认包来源可信后，可按系统提示在 **系统设置 → 隐私与安全性** 中批准该应用。不要为了安装青番而全局关闭系统安全保护。

## 3. 使用方法

### 开始一次专注

1. 打开青番，默认显示完整圆形时钟，初始为 **25:00**。
2. **无需创建任务**，直接点击表盘中央即可开始专注；再次点击暂停或继续。
3. 如需关联任务，点击表盘的**任务清单**图标，新增任务并选择当前任务，再点击底部 **开始专注**。
4. 一轮专注结束后进入休息阶段；只有完整完成的专注轮次才会增加番茄次数。

默认时间：**专注 25 分钟、短休息 5 分钟、每四次专注后的长休息 15 分钟**。可在偏好设置中修改，设置自动保存。

### 随时跳过休息

休息不是强制步骤。短休息或长休息时，可以：

- 在完整表盘点击 **跳过休息 · 开始专注**；
- 打开任务清单，选择新任务，点击 **跳过休息并开始专注**；
- 在表盘“更多”菜单选择 **跳过休息，开始专注**。

休息期间选择“返回专注阶段”（原“重新开始本轮”位置）会先回到新的 **25:00 专注待开始**状态，不会重新开始休息。

**退出与重新打开**：未完成的休息不会继续占用下一次启动，应用将回到新一轮专注；未完成的专注会保留剩余时间并以暂停状态恢复。已完成轮次、任务和设置不会因上述切换而清空。

### 其他操作

| 操作 | 说明 |
| --- | --- |
| 点击表盘中央 | 开始 / 暂停 / 继续当前阶段 |
| 点击任务清单图标 | 添加、选择、完成、恢复、重命名、删除和搜索任务 |
| 点击迷你模式图标 | 切换到较小的悬浮时钟；迷你时钟可再展开 |
| 在表盘外圈空白处按住并移动 | 拖动原生悬浮窗口 |
| 更多菜单 → 偏好设置 | 调整专注/休息时长和背景透明度，自动保存 |
| 更多菜单 → 始终置顶 / 取消置顶 | 切换置顶偏好 |
| 更多菜单 → 重新开始本轮 | 丢弃当前未完成阶段的进度，返回新的专注轮次 |
| 空格键（焦点不在输入框中） | 开始 / 暂停 |
| Windows / Ubuntu：`Ctrl+L` 或 `Ctrl+F` | 打开任务清单 |
| macOS：`Command+L` 或 `Command+F` | 打开任务清单 |
| `Esc` | 退出编辑焦点或关闭任务面板 |

任务完成或删除后提供短暂的**撤销**入口。当前专注运行中不能直接切换任务；若有未完成的专注进度，需要先暂停并确认是否放弃。**Wayland 下始终置顶和窗口拖动取决于桌面环境**，可能无法完全实现。

## 4. 卸载

| 系统 / 版本 | 卸载方法 |
| --- | --- |
| **Ubuntu V2（DEB）** | `sudo apt remove qingfan` |
| **Windows 安装版** | **设置 → 应用 → 已安装的应用 → 青番 → 卸载**；也可以使用开始菜单/安装目录中的卸载程序 |
| **Windows 便携版** | 关闭青番，删除解压出来的便携版文件夹 |
| **macOS** | 退出青番，在“应用程序”中将 `qingfan.app` 移到废纸篓；可删除已下载的 DMG / ZIP |
| **Ubuntu GTK3 V1.1（旧版）** | 在旧版源码目录执行 `./uninstall.sh` |

**默认卸载仅删除程序，不删除用户任务或偏好设置。** V2 数据文件名为 `qingfan_v2.json`，实际位置由操作系统的应用支持目录决定。建议升级或清理前备份该文件；不要将它与 V1.1 的 `state.json` 混为一谈。

需要查找 Ubuntu V2 的数据文件时，可运行：

```bash
find "${XDG_DATA_HOME:-$HOME/.local/share}" -type f -name 'qingfan_v2.json' 2>/dev/null
```

如果仍在使用 **GTK3 V1.1**，其历史数据位于 `~/.local/share/qingfan/state.json`；卸载脚本默认保留该文件。

## 5. 旧版 Ubuntu GTK3 V1.1

旧版安装仍保留，**以下命令安装的是旧版，不是 V2**：

```bash
sudo apt update
sudo apt install python3-gi python3-cairo python3-gi-cairo gir1.2-gtk-3.0 librsvg2-common
git clone https://github.com/jiaquan301/qingfan.git
cd qingfan
./install.sh
```

启动：从应用菜单搜索“青番”，或在该源码目录执行 `./run.sh`。

卸载：在同一源码目录执行 `./uninstall.sh`。上述脚本不会自动升级成 Flutter V2，也不负责卸载 V2 的 `.deb`。

## 6. 开发与验收

Flutter V2 源码、三平台构建步骤和验收说明见 [flutter_app/README.md](flutter_app/README.md)；原始 GTK3 代码位于 `pomodoro/`。

- [V2 产品需求](docs/v2-product-prd.md)
- [V2 技术架构与验收标准](docs/v2-engineering-acceptance.md)
- [跨平台 CI](https://github.com/jiaquan301/qingfan/actions/workflows/flutter-v2.yml)
- [V2 开发 PR #4](https://github.com/jiaquan301/qingfan/pull/4)

候选版已通过 CI 的单元/界面测试、Windows/macOS 原生构建与窗口验收、Ubuntu DEB 安装启动卸载、Windows 安装卸载以及 macOS DMG 挂载卸载；这不等于已通过所有实机、桌面缩放及多显示器组合测试。
