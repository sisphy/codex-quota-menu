# ChatGPTQuotaMenu

一个原生 macOS 菜单栏小工具，读取本机 Codex app-server 暴露的 Codex rate limit 信息。

## 功能

- 菜单栏显示 Codex 额度的简短状态。
- 点击菜单栏图标打开浮窗，显示 5 小时额度和一周额度。
- 调用本机 `codex app-server --listen stdio://` 的 `account/rateLimits/read`。
- 每 1 分钟自动刷新一次，打开浮窗时立即刷新。
- 读取失败时保留上一次成功快照。

## 运行

当前 Codex 沙箱不能写 SwiftPM 的默认用户缓存，所以在这里运行时建议使用本地/临时缓存参数：

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache \
  swift run --disable-sandbox \
  --cache-path /private/tmp/swiftpm-cache \
  --config-path /private/tmp/swiftpm-config \
  --security-path /private/tmp/swiftpm-security \
  --manifest-cache local
```

首次运行前，请先在 Codex 客户端或 CLI 中完成 ChatGPT 登录。应用读取的是 Codex 本地账号状态，不再依赖 ChatGPT 网页解析。

## 构建

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache \
  swift build --disable-sandbox \
  --cache-path /private/tmp/swiftpm-cache \
  --config-path /private/tmp/swiftpm-config \
  --security-path /private/tmp/swiftpm-security \
  --manifest-cache local
```

生成 `.app` 包：

```bash
bash Scripts/build_app.sh
```

生成结果在 `dist/ChatGPTQuotaMenu.app`。

## 已知限制

- 本应用不读取 Chrome/Safari 登录态，不读取聊天内容，不导出 cookie。
- Codex app-server 协议是本地客户端协议；如果未来 Codex 改名或变更 `account/rateLimits/read` 返回结构，需要同步调整解析。
- 当前环境只有 Command Line Tools，缺少可用的 `XCTest`/`Testing` 模块；测试文件已保留，安装匹配的完整 Xcode 后可用 `swift test` 跑解析器测试。
