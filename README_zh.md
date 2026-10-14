# Tapper

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Tapper-logo-dark.png">
  <img alt="Tapper" src="Tapper-logo-light.png" width="358">
</picture>

Tapper 为 Apple Magic Mouse 补上 macOS 没有提供的两件事：轻点点击，以及用双指切换空间（Spaces），画面会跟着手指移动。两种操作都可以把手掌放在鼠标上进行。

版本 1.0。支持 macOS 13 及以上；在 macOS 27 和 USB-C 接口的 Magic Mouse 上开发和测试。

[English](README.md) | 中文 | [日本語](README_ja.md)

## 功能

### 轻点点击

- **轻点**鼠标前面三分之二的任意位置即为左键点击。后三分之一的轻触会被忽略，所以搭在上面的手掌不会误点。
- **快速轻点两下**即为双击。
- **拖拽**：轻点一下，再次触碰并保持手指不抬起，然后移动鼠标；抬起手指即放下。
- **轻触也能识别。** 鼠标几乎感觉不到的轻而短的触碰也能点击。
- **静止的手指不碍事。** 在鼠标上静止半秒的手指会被忽略，旁边的另一根手指照样可以轻点。
- **按压照常工作。** 正常按下鼠标只点击一次，Tapper 不会再额外补一次点击。右键请照常按下鼠标右侧（**系统设置 → 鼠标 → 辅助点按**）；轻点右键默认关闭（见[高级设置](#高级设置)）。

### 双指切换空间

用双指向左或向右滑动。滑过一小段距离后，相邻的空间会滑入并跟随手指移动，抬起手指即完成切换。和触控板一样，手指向左滑会带出右边的空间。

- **手掌可以放着。** 双指滑动时，手掌或手的侧面可以搭在鼠标上。
- **不会误滚动。** Tapper 识别出滑动后，指针下方的窗口就不再横向滚动。
- **每次切换一个空间。** 空间开始移动后，抬起手指一定会完成切换；在那之前抬起则取消。已经在第一个或最后一个空间时不会切换，指针下方的窗口可能会改为横向滚动。

使用前，请先在 **系统设置 → 鼠标 → 更多手势** 中关闭系统自带的"轻扫切换全屏显示应用程序"。这个设置开着时，Tapper 不处理双指滑动，以免一次滑动切换两次。

### 菜单里的其他功能

- **Pointer Speed**：调节全系统鼠标速度的滑块，范围 0 到 8。
- **Sensitivity Settings…**：调整轻点与滚动的区分方式。
- **Two-Finger Zoom**（实验性，默认关闭）：在支持双指缩放的应用里，双指朝鼠标前方滑动放大，朝后方滑动缩小。
- **Launch at Login** 和 **Prevent Sleep (Keep Running)**。

## 系统要求

- macOS 13 及以上。双指切换空间已在 macOS 27 上测试。
- Apple Magic Mouse。
- 构建需要 Xcode 或命令行工具（`xcode-select --install`）。运行单元测试需要 Xcode。

## 安装

Tapper 需要从源码构建：

```bash
git clone https://github.com/kkkevinky/Tapper.git
cd Tapper
bash install-final.sh
```

脚本会构建通用版应用（同时支持 Apple 芯片和 Intel），退出正在运行的副本，安装为 `/Applications/Tapper.app`，然后询问是否立即打开（y/N）。旧版本会以 `Tapper_backup_….app` 的形式保留在旁边。只想试用新构建而不安装，可以运行 `bash test-and-install.sh --test-only`。

也可以手动安装，先退出 Tapper，然后：

```bash
bash build.sh
rm -rf /Applications/Tapper.app
ditto build/Tapper.app /Applications/Tapper.app
```

每次构建都使用临时（ad hoc）签名，所以安装新构建后，macOS 会再次请求辅助功能权限。

## 首次启动

1. 从"应用程序"打开 Tapper。菜单栏会出现一个鼠标图标；Tapper 没有程序坞图标。
2. macOS 会请求辅助功能权限。在 **系统设置 → 隐私与安全性 → 辅助功能** 中打开 **Tapper**。授权后一秒内 Tapper 就会开始工作。如果超过一分钟才授权，Tapper 会弹出自己的提示，点 **Retry** 即可。
3. 想让 Tapper 随开机启动，在菜单里打开 **Launch at Login**。
4. 要使用双指切换空间，按上文关闭"轻扫切换全屏显示应用程序"。

Tapper 需要辅助功能权限来发送点击和缩放手势。它通过 Apple 的私有框架 MultitouchSupport 读取触摸，因此无法上架 Mac App Store，macOS 大版本更新后也可能需要更新。

## 菜单

| 菜单项 | 作用 |
| --- | --- |
| Status | 显示 `Running (1 Magic Mouse)`、`Waiting for Magic Mouse` 或 `Disabled`。 |
| Tap to Click | 开关轻点点击。每次启动都会重新打开。Two-Finger Zoom 关闭时，关掉它也会暂停双指切换空间。 |
| Two-Finger Zoom | 开关缩放，设置会保留。 |
| Launch at Login | 登录时自动启动 Tapper。 |
| Prevent Sleep (Keep Running) | Tapper 运行且 Mac 接通电源时，阻止 Mac 进入睡眠（显示器仍可关闭）。默认关闭。 |
| Pointer Speed | 设置这台 Mac 上所有鼠标的速度。**Restore Default** 恢复到 Tapper 首次运行时的速度。 |
| Sensitivity Settings… | 打开下面的设置窗口。 |
| Accessibility Instructions… | 说明如何授予权限。 |
| About Tapper / Quit Tapper | |

## 灵敏度设置

拖动滑块后立即生效，并在重启后保留。

| 滑块 | 默认值 | 含义 |
| --- | --- | --- |
| Max Tap Duration | 0.35 秒 | 触碰超过这个时长就不算轻点。 |
| Movement Tolerance | 8 像素 | 轻点期间指针允许移动的距离。 |
| Double-Tap Window | 0.30 秒 | 双击或拖拽时两次轻点之间允许的间隔。 |
| Surface Movement Limit | 4% | 手指在鼠标上滑动超过这个距离，就算作滚动。 |
| Surface Path Limit | 10% | 同上，按手指移动的总路程计算。 |
| Scroll Velocity Limit | 1.0 /秒 | 手指移动快于这个速度就算作滚动。 |
| Min Tap Duration | 0.03 秒 | 更短的触碰会被忽略。调高会让轻点判定更严格。 |
| Right-Click Hold Time | 0.16 秒 | 轻点右键时手指需要停留的时间。仅在打开轻点右键后生效。 |
| Left/Right Boundary | 60% | 右键区域的起点。仅在打开轻点右键后生效。 |

同一个窗口里还有缩放选项：**Enable Two-Finger Zoom**、**Reverse zoom direction** 和 **Zoom sensitivity**（0.5× 到 2.0×）。**Reset to Defaults** 会恢复所有数值，同时关闭 Two-Finger Zoom。

## 高级设置

有几个选项还没有菜单入口。在终端里设置后，退出并重新打开 Tapper：

```bash
# 在鼠标右侧轻点并稍作停留再抬起即为右键（默认关闭）
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.rightTapEnabled -bool true

# 双指滑动切换空间的方式：dockswipe（默认）、instant、hotkey 或 off
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.swipeMode -string instant

# 反转滑动方向
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.swipeInvert -bool true
```

- `dockswipe`：空间跟随手指移动。
- `instant`：手指滑过一小段距离后立即切换。
- `hotkey`：Tapper 按下你在 **系统设置 → 键盘 → 键盘快捷键 → 调度中心** 里为"向左移动一个空间"/"向右移动一个空间"设置的快捷键。

要恢复默认值，删除对应的键即可，例如 `defaults delete io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.swipeMode`。

## 故障排除

**轻点没有反应。** 确认 **隐私与安全性 → 辅助功能** 里 Tapper 已打开。安装新构建后，把开关关掉再打开，或者移除 Tapper 后重新添加 `/Applications/Tapper.app`。如果状态显示 `Waiting for Magic Mouse`，请检查 Tapper 是否已获得辅助功能权限，以及鼠标是否已连接。鼠标后三分之一的轻点本来就会被忽略。

**每次轻点都点了两下。** 还有另一个轻点点击应用在运行。退出它，并在 **系统设置 → 通用 → 登录项** 里移除它。

**双指滑动不切换空间。** 关闭"轻扫切换全屏显示应用程序"（见上文），并确认 **Tap to Click** 已打开。已经在第一个或最后一个空间时，无法再往外切换。

## 卸载

1. 在 Tapper 菜单里关闭 **Launch at Login**。如果改过指针速度，先点 **Restore Default**。
2. 退出 Tapper，删除 `/Applications/Tapper.app` 以及旁边的 `Tapper_backup_*.app`。
3. 可选：在 **隐私与安全性 → 辅助功能** 里移除 Tapper，并用 `defaults delete io.github.kkkevinky.tapper` 删除它的设置。

## 隐私

Tapper 没有任何联网代码，不会向任何地方发送数据。它把设置保存在自己的偏好设置里，并把手势细节写入本机的 macOS 日志（子系统 `io.github.kkkevinky.tapper`）。

## 致谢与许可证

Tapper 基于 Roger Hughes 的 [Mouse Toucher](https://github.com/slopcore/mousetoucher)，以 MIT 许可证发布，详见 [LICENSE](LICENSE)。

双指切换空间的功能改编了 InstantSpaceSwitcher、FasterSwiper 和 palmpad 的代码，它们的许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

感谢所有逆向分析并整理 MultitouchSupport 框架文档的人。
