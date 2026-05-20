# ChatGPTQuotaMenu

一个放在 macOS 菜单栏里的 Codex 额度小浮窗。

如果你经常用 Codex，却总是不知道“5 小时额度还剩多少”“本周额度什么时候重置”，这个小工具就是为这个场景做的：它会自动读取本机 Codex 的额度信息，显示剩余百分比、重置时间，并根据一周额度的使用节奏给你一句简单提醒。


## 它能做什么

- 在菜单栏显示 Codex 剩余额度概览。
- 点击菜单栏后，可以显示或隐藏一个轻量悬浮窗。
- 悬浮窗可拖动，位置会自动记住。
- 每 1 分钟自动刷新一次，也可以手动刷新。
- 显示两类额度：`5小时额度` 和 `一周额度`。
- 一周额度会带日期显示重置时间。
- 根据一周额度消耗速度提醒你：
  - `放心花！节奏正常`
  - `抓紧花！赶快薅羊毛！`
  - `稍微悠着点，使用进度已超时间X%`
  - `要省着点花啦，使用进度已超时间X%`
  - `真的得收着用了！花完警告！`

## 它怎么判断“该不该省着点”

它不是只看还剩多少，而是比较两个进度：

```text
时间进度 = 本周已经过去了多少
使用进度 = 一周额度已经用了多少
```

如果使用进度明显快于时间进度，就提醒你省着点；如果剩余额度不多但时间进度也差不多到头了，就提醒你赶快用。

## 使用前需要知道

这个应用读取的是 **Codex 客户端本地的额度信息**，不是 OpenAI API billing，也不是 ChatGPT 网页上的聊天额度。

你需要先在 Codex 客户端或 Codex CLI 里登录 ChatGPT 账号。登录好之后，本工具会通过本机的 `codex app-server` 读取 rate limit 信息。

它不会读取你的聊天内容，不会读取 Chrome/Safari 登录态，也不会导出 cookie。

## 运行

项目是一个原生 macOS Swift 应用，不是 Electron。

在本地运行：

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache \
  swift run --disable-sandbox \
  --cache-path /private/tmp/swiftpm-cache \
  --config-path /private/tmp/swiftpm-config \
  --security-path /private/tmp/swiftpm-security \
  --manifest-cache local
```

如果你的 SwiftPM 环境可以正常写用户缓存，也可以直接运行：

```bash
swift run
```

## 打包成 macOS App

```bash
bash Scripts/build_app.sh
```

生成结果：

```text
dist/ChatGPTQuotaMenu.app
```

然后可以直接打开：

```bash
open dist/ChatGPTQuotaMenu.app
```

## 菜单栏操作

点击菜单栏图标后，会出现一个很小的菜单：

```text
隐藏悬浮框
刷新
诊断
退出
```

悬浮框只负责展示额度，不放多余按钮。

## 已知限制

- 依赖本机已安装并登录的 Codex。
- 依赖 Codex 本地 `account/rateLimits/read` 接口；如果未来 Codex 改接口，应用需要跟着更新。
- 当前测试文件保留在仓库里，但某些只有 Command Line Tools、没有完整 Xcode 的环境可能无法运行 `swift test`。

## 适合谁

适合经常用 Codex、但不想每次打开客户端才知道额度还剩多少的人。

它的目标不是做复杂仪表盘，而是让你一眼知道：现在还能不能继续放心花。
