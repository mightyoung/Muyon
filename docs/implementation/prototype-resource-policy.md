# 原型页面资源访问限制（B-R2）

范围：`packages/prototype_module` 里的受限 WebView。导航由 `PrototypeWebGuard` 判定；页面自己发起的子资源（脚本、样式、图片、字体、`fetch`/XHR、frame）由 `PrototypeResourcePolicy` 判定。两者都以 `RestrictedWebViewSpec` 的允许根为唯一来源。

## 判定规则（有单元测试）

子资源只允许「允许根内的 `file:` URL」。以下一律拒绝：远程 `https`/`http`、`data:`、`blob:`、`about:`、`javascript:`、`ws(s):`、`ftp:`、含 `..` 或 `%2e%2e` 的路径、其它版本目录与其它本地文件。

已知取舍：严格拒绝 `data:` 后，MES 原型样式表里的一个内联小图（`url(data:image/png…)`）不会显示。

## 各平台由哪一层执行

| 层 | Android | Windows (WebView2) | macOS / iOS (WKWebView) |
|---|---|---|---|
| CSP（文档开始处注入 `<meta>`，`connect-src 'none'`，无远程源） | 是 | 是 | 是 |
| `shouldInterceptRequest`（拒绝时返回 403） | 是 | 是（`WebResourceRequested`） | 无此 API |
| 内容拦截规则（全部拦截，仅豁免版本根） | 无 | 无 | 是 |
| 顶层导航 `shouldOverrideUrlLoading` | 是 | 是 | 是 |
| 新窗口 / 权限请求 | 拒绝 | 拒绝 | 拒绝 |

CSP 对本地文件只能写成 `file:` 这一级来源，不能限定到具体目录；目录级限制依赖拦截层。因此：
- Android、Windows：CSP + 请求拦截两层。
- macOS：CSP + 内容拦截规则。

## 未验证（必须实机确认，当前均为“未验证”）

- 三个平台上 `<meta>` CSP 是否在页面自身资源解析前生效。
- WKWebView 的内容拦截规则是否作用于 `file:` URL（Apple 文档主要描述 http/https，可能不生效；若不生效 macOS 只剩 CSP 一层，目录级越界读取无法被拦截）。
- Windows 上 `shouldInterceptRequest` 对子资源的覆盖范围。
- Vite 构建的 `type="module"` 脚本在 `file://` 下能否加载。

以上均无自动测试覆盖，只有策略生成器与判定逻辑有单元测试。
