# 原型页面资源访问限制（B-R2，2.4 实机验证后修订）

范围：`packages/prototype_module` 里的受限 WebView。导航由 `PrototypeWebGuard` 判定；页面自己发起的子资源（脚本、样式、图片、字体、`fetch`/XHR、frame）由 `PrototypeResourcePolicy` 判定；文件由 `PrototypeSchemeLoader` 读取。三者都以 `RestrictedWebViewSpec` 的允许根为唯一来源。

## 加载方式：自定义 scheme，不再用 `file://`

实机（Android）确认：Vite 构建的 `type="module"` 脚本在 `file://` 下**不执行**（页面空白，探测页 `moduleScript=NOT-RAN`；不是被我们的策略拦的，WebView 自己拒绝）。因此页面改由 `muyon-proto://page/<版本目录内相对路径>` 加载：

- `PrototypeSchemeLoader`（`scheme_loader.dart`）把 URL 映射回允许根内的 `file:` 路径，再交给 `RestrictedWebViewSpec.allowsNavigation` 判定；任何一步失败都返回空（不读文件）。
- 拒绝：原始 URL 含 `..`、`%2e%2e`、`%2f`、`%5c`、`%00`，或 `..\` 形式的路径；非法的百分号编码（例如 `%c0%ae`）按拒绝处理，不抛异常；host 不是 `page`；带端口或用户信息；空路径；映射后不在允许根内；文件不存在或是目录；**符号链接解析后落在允许根之外**（读取前对文件与根目录都做 `resolveSymbolicLinks` 再比较，防止应用数据目录里的链接逃出）。
- 没有打开 `allowUniversalAccessFromFileURLs` / `allowFileAccessFromFileURLs`，WebView 自身 `allowFileAccess: false`；没有本机 HTTP 服务；CSP 没有放宽到任何远程源。
- 子资源只允许 `muyon-proto://page/…` 且映射后在允许根内。`file:`、远程 `https`/`http`、`data:`、`blob:`、`about:`、`javascript:`、`ws(s):`、`ftp:` 一律拒绝。
- 已知取舍：严格拒绝 `data:` 后，MES 原型样式表里的一个内联小图（`url(data:image/png…)`）不会显示。`fetch` 受 `connect-src 'none'` 限制，原型页面不能读取自己的文件。

## 插件（flutter_inappwebview 6.1.5）各平台的实际行为

| 项 | Android | Windows (WebView2) | macOS / iOS (WKWebView) |
|---|---|---|---|
| 自定义 scheme 提供文件 | **`useShouldInterceptRequest` 打开时，插件在 `shouldInterceptRequest` 里提前返回，永远走不到 `onLoadResourceWithCustomScheme`**；所以在 `shouldInterceptRequest` 里直接返回允许的文件（200）、其余 403 | 插件的 Windows 实现存在（`in_app_webview.cpp:844-902`），但有两处缺口：Windows 设置里没有 `resourceCustomSchemes`；WebView2 只为**事先注册**的 scheme 触发 `WebResourceRequested`，注册要走 `WebViewEnvironmentSettings.customSchemeRegistrations`，而我们的代码没有创建这个环境。因此 Windows 上原型页面**很可能打不开**，**未验证** | `resourceCustomSchemes` + `onLoadResourceWithCustomScheme`（`CustomSchemeHandler.swift`），**未验证** |
| `IGNORE_PREVIOUS_RULES` 内容拦截动作 | **构造即抛异常**（Apple 专用），原型页面直接红屏打不开——这是本轮实机发现的缺陷，已改为只在 iOS/macOS 构造内容拦截规则 | 未验证（预期同 Android，已不构造） | 可用 |

## 各平台由哪一层执行

| 层 | Android | Windows | macOS / iOS |
|---|---|---|---|
| CSP（文档开始处注入 `<meta>`，`script/style/img/font/media-src muyon-proto:`，`connect-src 'none'`，无远程源） | 是 | 是 | 是 |
| `shouldInterceptRequest`（允许 → 返回文件；其余 403） | 是 | 是（`WebResourceRequested`，**未验证**） | 无此 API |
| 自定义 scheme 回调（只服务允许根内文件） | 不经过 | 不支持（见上） | 是 |
| 内容拦截规则（全部拦截，仅豁免 `muyon-proto://page/`） | 不构造 | 不构造 | 是 |
| 顶层导航 `shouldOverrideUrlLoading` | 是 | 是 | 是 |
| 新窗口 / 权限请求 | 拒绝 | 拒绝 | 拒绝 |

目录级限制现在由 `PrototypeSchemeLoader` 保证（只能映射到允许根内），不再依赖 CSP 的 `file:` 来源。

## 实机验证记录

设备：vivo V2324A，Android 16（API 36），调试包；探测页 + 真实 MES 原型（`mes-security-model/prototype-vue/dist`，只读，未重新构建）。探测脚本和应用在临时目录，不在仓库里。

| # | 项目 | 平台 | 做法 | 结果 |
|---|---|---|---|---|
| 1 | Vite `type="module"` 脚本在 `file://` 下能否加载 | Android | 探测页含模块脚本，`file://` 入口 | **不能**（`NOT-RAN`），页面空白 |
| 1b | 同上，改用 `muyon-proto://` | Android | 同一探测页和真实 MES 页 | **能**（`moduleScript=ran`）；真实页面完整渲染（来源健康列表） |
| 2 | `<meta>` CSP 在页面自身资源解析前是否生效 | Android | 探测页读取 `meta[http-equiv=Content-Security-Policy]` | 存在（`cspMeta=present`）。是否先于页面资源解析：脚本在 `AT_DOCUMENT_START` 注入，页面内联脚本运行时已存在；更早的外部资源无法单独区分，**严格意义上仍未验证** |
| 3 | 越界访问是否被拦截 | Android | 探测页：远程图片、远程 `fetch`、`data:` 图片、其它目录图片与文件、自身文件 `fetch` | 全部拦截（`blocked`）；允许根内图片正常加载（`LOADED`）；日志有对应 `onBlocked` |
| 3b | 点击指向允许根之外的顶层链接（S7） | Android（vivo V2324A，Android 16，调试包） | 原型页含三个链接：`https://example.com/`、`file:///etc/hosts`、根内 `inner.html`；在手机上逐个点击，读 logcat 与 `onBlocked` 日志 | 远程链接：守卫拦截，日志 `BLOCKED https://example.com/`，界面横幅“已拦截越界访问”，页面不跳转。`file:///etc/hosts`：**由 Chromium 自行拒绝**（控制台 `Not allowed to load local resource: file:///etc/hosts`），页面不变，**没有走到我们的守卫**，所以守卫对 `file:` 顶层导航的拦截在这条路径上没有被实机执行。根内链接：正常打开（`INNER PAGE OK`） |
| 4 | Windows `shouldInterceptRequest` 覆盖范围 / 自定义 scheme | Windows | — | **未验证**（本轮没有 Windows 设备） |
| 5 | WKWebView 内容拦截规则、自定义 scheme、CSP | macOS / iOS | — | **未验证**：本机没有安装 Xcode，`flutter run -d macos` 报 "Xcode not installed" |

另外在设备上看到的：`getDefaultProguardFile` 与新版 AGP 不兼容的构建问题只出现在新建的探测工程里，仓库里的 `apps/muyon` 用的是固定的 AGP 8.11.1，不受影响。

## 仍未验证

- macOS：页面能否通过 `muyon-proto` 正常渲染（自定义 scheme 请求在 WKWebView 上的行为）。

- Windows：自定义 scheme 是否可用（原生未见实现，很可能不可用，届时原型页面在 Windows 上打不开，需要另选方案）；`shouldInterceptRequest` 的覆盖范围。
- macOS / iOS：自定义 scheme 请求是否经过内容拦截规则；CSP 是否生效。
- 三个平台上 CSP 是否先于页面的**外部**资源解析（Android 只验证了 `<meta>` 存在和越界请求被拦）。

自动测试：策略判定、CSP 文本、内容拦截规则、`PrototypeSchemeLoader` 的路径解析（`..`、`%2e%2e`、编码斜杠、其它版本目录、绝对路径、空路径、正常文件）有单元测试；WebView 本身没有自动测试。
