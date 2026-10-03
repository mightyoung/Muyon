# MuSpace 设计修订证据索引

收集：2026-10-03；只读历史记录与源码，不是本次产品测试。原路径、原文件SHA-256、复制/摘录SHA-256及已核验源码hash见[source-manifest.json](source-manifest.json)。源码以dirty工作区实际字节为准，不能只用HEAD还原未提交内容。

| ID | 仓内证据 | 来源日期与明确边界 |
|---|---|---|
| E01 | [科研verification摘录](research-verification-excerpts.md)及manifest中的reader/store/LAN/pubspec、两spec/plan、worktree首测试hash | verification标题2026-10-02，内含2026-10-03 skill测试记录：40项通过与合成草稿格式校验是原作者记录，本轮未重跑。旧“未验原生PDF”不能覆盖后来E02。源码证明pdfrx与表/服务存在，不证明所有平台release通过 |
| E02 | [合成Android验收原文](research-android-synthetic-acceptance.md) | 原记录2026-10-03，V2324A Android16；PDF/页笔记、任务导入、手工run、结果ZIP导出和空Markdown报告有限通过，同机回导失败、接纳受阻。无网络传输/真实命令/私人材料。后来worktreeTask1修复提交存在，不等本轮新真机PASS |
| E03 | [询价release摘录](supplier-release-evidence-excerpts.md)及manifest中的两个supplier_core/pubspec、DAG、siq_mcp/mcp_server/tools、9/30Android说明hash | release表标更新2026-09-24，引用2026-09-27核心534/应用116日志；仍有规模超门、Android/Windows延期、无macOS target。DAG分支与hubfix不是同一API/存储。9/30说明widget通过不等新APK实机通过 |
| E04 | [Vue窄屏边界摘录](vue-narrow-boundaries-excerpts.md) | 原报告2026-10-03：受信冻结页面Android入口/抽屉/返回/筛选/进程重开通过；宽表横滑仍限制；Mac/Win、后台/性能/恶意插件未测。不是科研阅读或原型安全发布证据 |

复制范围只含文字报告/逐字摘录与文件hash，不复制私人截图、APK、真实研究材料、设备凭据或日志环境变量。报告中的原相对链接是历史来源引用，附件未复制这些依赖，不能凭链接出现声称相关场景已核对；本设计采用的结论以索引列出的范围和实际读取为限。source-manifest记录原字节hash，摘录新增分隔说明，摘录hash另记。

案例Task2 interrupted来自授权任务的明确交接；实际磁盘只有首个case_store_test与不存在的case_models/case_store依赖，未发现通过报告。本索引不伪造一份运行日志。所有兄弟项目保持只读，未来实施候选须重核当前提交、dirty差异及许可。
