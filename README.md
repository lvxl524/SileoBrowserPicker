# Sileo 浏览器选择 (SileoBrowserPicker)

越狱插件：拦截 Sileo 商店「付款服务提供商」登录时的鉴权流程（`ASWebAuthenticationSession`），让你可以选择用 **第三方浏览器** 打开登录页，而不是被锁死在 Safari 共享 Cookie 里。

## 为什么需要它

Sileo 付款登录默认用 `ASWebAuthenticationSession`（iOS 13+ 与 Safari 共享 Cookie）。如果你在 Safari 里登录了 A 账号，付款登录就会用 A 账号；想在付款时用 B 账号，只能退出 Safari 再登录 B——非常麻烦。

本插件在 `start` 阶段拦截登录请求，按你的设置把鉴权 URL 丢给 **Alook / Chrome / 夸克** 打开。付款平台回调 `sileo://authentication_success?token=...&payment_secret=...` 时，由插件 hook 的 AppDelegate 接收并喂回原回调，完成登录。

## 支持的模式

| 模式 | 说明 |
|---|---|
| 禁用 | 不改任何行为（原始 Sileo 流程） |
| Safari（默认） | 原始行为，与 Safari 共享 Cookie |
| Safari（独立会话） | `prefersEphemeralWebBrowserSession`，隔离 Cookie，不影响 Safari 登录态 |
| Alook | `Alook://<完整 URL>` |
| Chrome | `googlechromes://`（自动替换 https://） |
| 夸克 | `quark://web?target=<编码 URL>` |
| 每次询问 | 每次登录弹窗让你选 |

## 安装

1. 下载 Release 里的 `com.mosheng.sileobrowserpicker_1.0.0_iphoneos-arm64.deb`
2. 用 Sileo / Filza 安装
3. 重启 Sileo
4. 打开 **设置 → Sileo 浏览器选择**，启用并选择浏览器

> 适用环境：Dopamine 2.0 / iOS 15+ / rootless 越狱。
> 注入目标：`org.coolstar.SileoStore`、`com.amywhile.sileo`。

## 工作原理（简述）

1. Hook `ASWebAuthenticationSession -initWithURL:callbackURLScheme:completionHandler:` 记录 URL / scheme / 回调 block
2. Hook `-start`：根据偏好决定走原生 Safari、Safari 独立会话，或把 URL 丢给第三方浏览器（返回 YES 假装已启动）
3. Hook `UIApplication -setDelegate:`，运行时对 Sileo 的 AppDelegate 交换 `application:openURL:options:`
4. 第三方浏览器完成登录后回调 `sileo://...`，被交换方法拦截并直接调用原回调 block
5. 若用户在 1.2s 内回到 Sileo 却没完成登录，自动以 `canceledLogin` 取消，避免卡死

## 构建

```bash
git clone https://github.com/lvxl524/SileoBrowserPicker
cd SileoBrowserPicker
make package FINALPACKAGE=1
```

需要 Theos 与 iOS SDK（CI 已用 GitHub Actions 自动构建，直接下载 Release 即可）。

## 已知限制

- **夸克** 的 URL Scheme 为多方推测值，若点击后无反应，请反馈，我会调整候选格式。
- 第三方浏览器需已安装，否则 `openURL:` 会失败（可重试或在设置里换模式）。

## License

MIT
