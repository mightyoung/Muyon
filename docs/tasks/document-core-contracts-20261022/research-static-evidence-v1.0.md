# Muyon 办公类 APK 静态取证附件

本附件与《Muyon-公共Office与Agent文件编辑研究-v2.0》配套；未安装运行。

# Microsoft Word / Excel / PowerPoint APK 静态取证

核查时间：2026-10-22 UTC。实际位置：云端。仅解 ZIP、Android Manifest、资源、DEX 字节码；未安装、运行、登录、调用内部 API 或修改 Muyon 仓库。本文是样本取证，不是三款产品的运行验收，也不是免费许可证明。

## 1. 样本身份与真实性边界

### Microsoft Word
- 来源：[用户 Drive 原文件](https://drive.google.com/file/d/1zgM5FZxKFzJOV2tJEuokvirWnF2jFpJh/view)，文件名 base9.apk，147334769 bytes。
- package：com.microsoft.office.word；版本：16.0.20228.20090；versionCode：2006247667；minSdk 33 / targetSdk 35。
- APK SHA-256：`2a0f936cf6ba6cc77f2398f2cd063f428d4c610bcea57c69a0d9e94d35739111`。
- ZIP CRC：全部通过；包含 6 个 DEX、63 个 arm64-v8a 本地库。

### Microsoft Excel
- 来源：[用户 Drive 原文件](https://drive.google.com/file/d/1JIKKYdSLE4LiGBavTSelMA-UUYglivPP/view)，文件名 base8.apk，141475483 bytes。
- package：com.microsoft.office.excel；版本：16.0.20228.20090；versionCode：2006247667；minSdk 33 / targetSdk 35。
- APK SHA-256：`7186fff1adf48ad19c15221e2ca0b554e8529abf298d5ebbbbb82f5ff6633eed`。
- ZIP CRC：全部通过；包含 6 个 DEX、58 个 arm64-v8a 本地库。

### Microsoft PowerPoint
- 来源：[用户 Drive 原文件](https://drive.google.com/file/d/1SUlFVUhWqJLpqbAi8Rm5q2XBEtgQoCXQ/view)，文件名 base10.apk，135270154 bytes。
- package：com.microsoft.office.powerpoint；版本：16.0.20228.20090；versionCode：2006247667；minSdk 33 / targetSdk 35。
- APK SHA-256：`6cf16fcc9ad78a319c82fccd742904423f805d8cacd369eefe1969e3b6688fc8`。
- ZIP CRC：全部通过；包含 6 个 DEX、60 个 arm64-v8a 本地库。

三包解析到同一证书 SHA-256：`b925136f3ea7c0a1951690a1ab313910da81f40994a85342ec622888f1287051`。证书主题包含“Microsoft Corporation Third Party Marketplace (Do Not Trust)”，Manifest 的 appStore 为 CHINA、appType 为 full、devapk 为 false。以上均是包内自述/证书内容；未与微软官方公布指纹进行可信比对，未做完整 APK 签名链密码学验签。因此不能以名称认定官方原版，也不能以 Do Not Trust 字样单独判定恶意。ZIP CRC 只证明压缩成员完整，不能证明来源安全。

## 2. 证据等级
- S1：Manifest / 文件 / 本地库 / 资源存在。只证明包内内容与声明。
- S2：DEX 中实际方法、字段、调用边界。可证明客户端已编译结构与代码路径，不能证明路径已启用或运行成功。
- S3：设备运行、后端响应、文档往返保真测试。本次没有 S3。

## 3. 格式路由与阅读实现
1. Word 主入口 `com.microsoft.office.word.WordActivity` 声明 DOC/DOCX、DOCM、RTF、ODT、TXT、PDF 等 MIME；Excel 主入口 `com.microsoft.office.excel.excelMainActivity` 声明 XLS/XLSX/XLSM/XLSB、ODS、CSV；PowerPoint 的 `PPTActivity` 与 `PPTEmbeddedActivity` 声明 PPT/PPTX/PPTM、PPSX/PPSM、ODP 等（S1）。声明宏容器 MIME 不代表会执行宏，更不代表宏编辑/保真受支持。
2. 三包还各自包含 `com.microsoft.android.crosssell.activities.WordCrossSellHandlerActivity`、`ExcelCrossSellHandlerActivity`、`PowerpointCrossSellHandlerActivity`、`PdfCrossSellHandlerActivity`。这些是跨产品路由入口，不能因为 Excel APK 里有 Word MIME 就宣称 Excel 内嵌完整 Word 引擎。
3. Word `classes6.dex`：`PdfMainDocumentSurface.openAndRenderPdfFile(String)` 根据分支调用 `PdfController.c(String)` 或 `WordPdfActivity.createPdfFragmentOpenAndRenderFile(String,long)`，返回 `PdfOpenResult`；`openAndRenderPdfFileFromIntentData()` 从 Activity Intent 取 URI，调用 `PdfController.e(Uri)`，并有空 Activity、空 Intent、空 URI、未初始化 controller 的失败分支（S2）。这比仅看 PDF 资源更能证明存在实际打开/渲染接线，但仍未验证任何 PDF 成功打开。
4. 本地库：Word 有 `libwlibandroid.so`、`libwlibandroidearlyboot.so`、`libPdfControl.so`；Excel 有 `libxlnextandroid.so`；PowerPoint 有 `libppt_android.so`、`libppt_earlyboot.so`、`libpptjni.so`。三者共同具有 `libmsoandroid.so`、多组 mso 库、`libstg.so`、`libmsxml.so`、`libdwritecore.so`、`liboartandroid.so`、`libchartandroid.so`、`liblicensebridge.so` 等（S1）。可推断为共享 Office 基础设施 + 格式专属核心的分层，但没有反汇编这些 native 实现，不声称算法/文档模型细节已恢复。

## 4. 保存、导出和许可不是一个布尔按钮
以下调用在 Word `classes5.dex` 中定位；三个 APK 的 class 索引可复查共有名称，当前详细字节码取证以 Word 为主。
- `mso/document/uiproperties/model/savepane/SavePanePropertiesUI` 分别注册 `ManualSaveRequested`、`SaveAsRequested`、`OpportunisticSaveAndUploadRequested`、`SaveErrorActionRequested`、`SetAutoSaveSwitchStateAndOpportunisticSaveRequested`。注册方法创建 typed EventEntry，获取 native handle，调用对应 `nativeRegister…`，保存 callback cookie；完成入口触发 event handler 并注销 cookie（S2）。这是 UI/native 事件分层，不是磁盘原子保存证明。
- `AutoSaveState.<clinit>` 实际构造 Enabled / Disabled / Unavailable；`DocumentSaveDisabledReason.<clinit>` 构造 None / Unknown / ReadOnly / NotSignedIn / O365SignInRequired / InsufficientLicensePrivileges / SubscriptionRequired / QuickReply。其 `SavePanePropertiesUI` getter/setter 经 FastObject typed 属性访问（S2）。不能把它推广成当前套餐收费表，也不能断言所有编辑都要求订阅。
- `mso/docs/model/sharingfm/SharedDocumentUI.SaveToLocation(StorageLocationUI, ICompletionHandler)` 获取 document 与 location native handle，调用 `nativeSaveToLocationAsync`；`SaveToLocationOverride` 有异步 native 与 completion handler；`onSaveToLocationComplete` 是独立回调（S2）。目标位置、请求和完成分开，值得 Muyon 借鉴。
- `mso/docs/appdocsfm/ExportDescriptorOperationUI.Begin()` 获取 native handle，调用 `nativeBegin`；类还存在 Reset/Cancel 与 CopyFlags（S2）。不能仅据此确认 PDF 导出布局保真、异步取消安全或所有导出类型可用。
- `officehub/objectmodel/OHubUploadCommandConflictPolicy` 实际 enum 常量 KeepServer / KeepLocal / Manual（S2）。存在冲突策略不代表自动合并无损。
- `mso/license/LicenseFeaturesHelper.canRunCopilotFeature*`、`canRunCopilotProFeature*` 为 native；Manifest 声明 BILLING、CHECK_LICENSE、INTERNET，有 licensing/commercialpaywallsdk/identity 代码。资源中有订阅/AI credits，以及“音频需要 AutoSave，可能需上传 OneDrive”的提示（S1/S2）。这只能证明能力/授权/云依赖分支存在，无法证明用户账户权益、请求成本、目前区域可用性。

## 5. PowerPoint 冲突处理比文件覆盖更细
PowerPoint `classes5.dex`：
- `view/fm/ConflictResolutionComponentUI.GetCurrentLocalSlide()` 调 nativeGetCurrentLocalSlide；`GetCurrentServerSlide()` 调 nativeGetCurrentServerSlide。
- `getlocalConflictingSlides()` / `getserverConflictingSlides()` 返回 FastVector_SlideMoniker；存在 local/server ThumbnailComponent 和 `slidesResolvedToServerChanges`。
- `OnConflictsResolved(ICompletionHandler)` 调 `nativeOnConflictsResolvedAsync`，完成回调再调用 `ICompletionHandler.onComplete`。
- widgets 包有 Phone/Tablet 两种 ConflictResolutionView、BaseConflictResolutionView 的前/后/完成按钮状态及缩略图组件。
上述为 S2，可证明客户端对幻灯片粒度、本地/服务器两个候选版本、用户选择和异步完成进行了建模。未测试多人同改、离线重连、版本丢失和最终上传结果。Muyon 第一阶段应先保存两版并让用户对比，不能照抄“KeepLocal”就默默覆盖远端。

## 6. 可借鉴与不可复用
可借鉴的是分层与交互约束：格式路由可查询；Reader 与文件操作解耦；保存、另存、上传、导出各自独立状态；只读与授权原因明确；冲突可逐对象预览；完成凭回执而不是按钮点击。应转化为自有 typed command / result，不复制专有实现。
不应把这些 APK 的 native 库、DEX、UI bundle 抽出并嵌入 Muyon。用户提供包只授权研究，不提供微软代码/SDK商用再分发许可。本报告不推荐绕过签名、授权检查、DRM、订阅或内部 API。

## 7. 明确未覆盖
- 没有安装/运行或截图；没有实际创建、编辑、保存、恢复或导出样本；没有网络调用。
- 未证明原子写、崩溃恢复、数据无损；LensCloudRecoveryManager 属扫描上传流程，不当作通用 Office 编辑恢复证明。
- 未验证 DOCX 修订/批注保留、PPTX 母版/动画/备注/图表、XLSX 公式重算/缓存/外链/透视表/宏、字体替换、嵌入对象。
- 未查清 native 内部算法，未提取授权令牌或调用证书相关业务。
- 包来自用户 Drive；签名真实性未建立。版本较新不等于该设备可安装、账号已授权或特性已启用。

## 8. 对 Muyon 公共能力的直接改进建议
1. 文档能力枚举应区分 view / annotate / structured-edit / recalculate / render / export / sync；每项有 supported、read-only、unsupported、needs-license、needs-network、unknown，而非一个 supportsOffice。
2. 本地暂存成功、正式版本提交、云同步成功分别发回执。Agent 的“已保存”必须有 revision/hash/目标和验证结果。
3. 初次编辑输出副本；任何覆盖需 expectedRevision 比对；冲突保留双方版本；PDF、DOCX、PPTX、XLSX 统一事务边界，但各格式用不同语义验证器。
4. 快捷工具栏按格式/选区显示；无能力时说明原因。资源和 MIME 只服务 capability discovery，不能当成成功结果。
5. 公共组件负责访问 scope、revision、selection/anchor、annotation、export；科研、对话、群组业务仅授权对应文件，不能因共享引擎获得全部私有文件。

## 9. 可复核文件
本报告同目录保留 `base8/9/10.json` 与 Manifest；`ms/base*-classes.json` 为 DEX 类/方法索引；`ms/word-selected-bytecode.json`、`ms/excel-ppt-bytecode.json` 为定位的调用证据；`ms/base*-strings.json` 为资源 ID 与文案定位。未将原 APK 或专有实现代码提交仓库。

## 10. Excel 编辑模式补充（同次增量）
`base8.apk / classes5.dex` 中 `excel/pages/FormulaBarControl.getEditModeEnabled()` 实际调用 `xlnextxaml/model/fm/CellEditFMUI.getfEditModeEnabled()` 与 `getfOverrideFormulaBarVisuallyEnabled()`；`MainRenderPageFragment.checkAndSetFormulaBarVisibility()` 初始化公式栏、取得 RichEditBox 与 AirspaceLayerHost、设置焦点监听；`fInCellEditMode()` 读取公式栏编辑状态。`FormulaBarCancelEnterPanelHelper.handleEditModeChanged()` 刷新按钮绘制。`shouldShowFormulaBarInBottom()` 根据小屏与设备条件判断位置。以上是 S2 UI 编辑模式接线，不证明公式引擎覆盖范围或重算正确。

对 Muyon 的具体启发：选中态与编辑态分开；单元格编辑明确取消/确认，不把焦点变化视为提交；手机可折叠底部公式栏，平板保留更大可视范围；公式文本、显示值、缓存值和重算状态必须分别记录。上述交互建议为我们的设计推断，并非声称本次已运行验证 Microsoft Excel。

补充证据：`ms/excel-edit-bytecode.json`（36 条定向方法记录）。


# WPS / Acrobat APK 静态取证与 Muyon 公共文档能力启示

核查：2026-10-22，云端静态分析。未安装或运行 APK，未调用厂商后端，未登录、付费或更改 Muyon 仓库。本文是研究证据，不是兼容性验收，也不授权复制专有代码。

## 1. 样本、身份与覆盖边界

|样本|包名/版本|完整 APK SHA-256|大小|
|---|---|---|---|
|base(11).apk|com.adobe.reader / 26.9.2.50367 / 1932150367|3e27d178ec1b06d833395cf258851e4da4ab5a147e3b15b7caa3011d6536834c|93,179,990 B|
|base(12).apk|cn.wps.moffice_eng / 26.10.0 / 2000|274d52dffcde6bf35489f9341a5598d60e21f5da1cf3a78f6b15861df5a1f9fc|174,746,541 B|

来源：[Acrobat 用户文件](https://drive.google.com/file/d/1TtwHs01lMyLbY5RM1vdBGDeV4kwoYhDS/view)、[WPS 用户文件](https://drive.google.com/file/d/1Qnk_w94Ps_8DZZRXYTjn5xXxcD9wamZC/view)。两个 ZIP CRC 检查均未发现错误。这只确认所下载 ZIP 内部校验一致，不证明签名有效或应用安全。

- Acrobat 提取证书 SHA-256：b6dd0562256487fcd6c98cde137858ef50d9adb9f9cd2f1ca58c5357efdf0faf，证书 subject 自述 Adobe Systems Incorporated。
- WPS 提取证书 SHA-256：643990878d3ca83952a5be5f3e58d9f8bb6cdc57bf0f228700212071c68db3d7，subject 自述 KSO Agent / Zhuhai Kingsoft Office Software Co.,Ltd。
- 未与可信官方发布证书独立比对，未做完整 APK 签名密码学验证。包名、版本和证书自述不等于官方真实性确认。
- Acrobat manifest 根节点明确 `requiredSplitTypes="base__abi,base__density"`；当前仅有 base APK，包内无 .so。因此这是不完整安装集，不能凭本次样本评估完整本地渲染引擎。
- WPS 样本含 arm64-v8a 的 52 个 .so 和 22 个 DEX；manifest 未见 requiredSplitTypes 或 split-required 元数据。只能说当前包含这些代码，不能据此保证无需运行时组件或下载。

## 2. Acrobat：把文件操作建模为任务，而不是按钮完成

### 2.1 确认的静态调用证据

1. `classes3.dex` 的 `com.adobe.libs.creationservice.apis.CRHeadlessPDFExportAPI.c(...)` 实际构造导出任务、调用 SenseiRequest、等待提交结果、轮询状态，再读取输出下载 URL。方法内分别出现 PDF/PPTX 输出类型和成功、提交失败、轮询失败、空下载 URL 的分支。
   - 支持结论：这一具体 headless 导出分支有云服务依赖及异步任务状态，不是仅 UI 字符串。
   - 不支持结论：不能推广为全部 PDF 导出都在线、某订阅必然可用、或用户当前账户有权益；没有执行过请求。
2. `classes6.dex` 的 `com.adobe.reader.services.saveACopy.ARSaveACopyService.z(...)` 读取原始 DOCUMENT_SOURCE 和目标 cloud source，通过操作工厂选择复制实现，注册 account removed / connector unlinked 监听。
3. 同类 `onOperationCompleted(...)` 与 `onOperationFailed(...)` 分别更新 `AROutboxTransferManager`；另有 `ARSaveACopyUploadFailedException` 保存 cloud-task result。静态结构显示“开始复制”“上传失败”“完成”是分开的结果。
   - 支持结论：本地/云来源及目标、传输任务、结果回执值得分层。
   - 不支持结论：尚未验证崩溃原子性、幂等性、所有 connector 的恢复行为或并发覆盖策略。

### 2.2 Manifest 与资源证据，不能当运行验收

- 主 AdobeReader 接收 PDF；DOCX preview、CreatePDF、MultiDoc assistant、workspace share 是不同的 alias。Word/PPT/Excel MIME 进入创建 PDF 或共享空间，不等于完整原格式编辑器。
- `com.adobe.reader.open.AROpenIntentEditPDFActivity`alias 在样本 manifest 中 enabled=false，显示入口能力可能受配置控制；不能据名称认定当前可用。
- 资源 `IDS_EXPORT_PDF_STARTED` 表示导出稍后通知完成；`IDS_KW_SOURCE_RENAME_CONFLICT_ERROR` 表示同名文件冲突；`IDS_NBA_SAVE_A_COPY_DESCRIPTION` 表示副本可保存另一位置或云端。
- 订阅资源包括 paywall export、购买 premium、恢复购买失败、不同 Adobe ID 已购买等。它们证明产品存在授权/恢复购买流程，不证明具体当前收费清单或地区价格。

## 3. WPS：格式路由和本地能力边界

已确认的包结构：
- manifest 为 DOC/DOCX、PPT/PPTX、XLS/XLSX、PDF、ODF、部分宏格式声明 MIME 入口；存在独立 `cn.wps.doc2pdf_activity`、`excel2pic_activity`、`ppt2pic_activity`、`pdf2word_activity`、`pdf_edit_activity`、`pdf_fill_form_activity` 等 alias。
- MIME 声明只证明能够接收这些意图，不能证明宏能执行、编辑保真、格式无损或当前已解锁。
- 本地库包括 libkwopdf.so、libfileformat.so、libdoc_encrypt.so、libfreetype-jni.so、libwcdb.so、libflutter.so / libapp.so。存在 Flutter 组件不等于整个应用或编辑引擎采用 Flutter。
- libdoc_encrypt.so 有 JNI 导出 `Java_cn_wps_securedoc_DocEncrypt_native_1encrypt` / `native_1decrypt`；libkwopdf.so 含大量 PDF 相关符号。仅确认对应接口/符号存在，不承诺支持哪些算法、权限、格式或性能。

### 3.1 保存链：实际调用而非名称推测

`classes6.dex` / `cn.wps.moffice.writer.io.FileSaveProcess`：

- `e(TextDocument, String, String, IFileOp, SecurityMode)` 创建带 `.save` 后缀的暂存文件，根据目标路径取得 FileFormat，调用 TextDocument.x1 进行序列化，再通过 IFileOp.b 搬移。
- 在暂存及搬移后查询 exists()/length()；针对文件不存在或为空有失败分支。故“返回成功后再检查产物”确实存在，不能仅凭操作返回值上报成功。
- `a(...)` 实例化 WordWriter 或带 ProviderInfo 的 WordWriter；说明格式序列化不是单纯把界面文字另存。
- `FileSaveBasic.d(...)` 经 SavePathManager 选择 NewApiFileOperator / NormalFileOperator；`h(...)` 调用保存及 Backup；`b(...)` 有临时路径、在线安全加密及搬移；`i(...)` 把授权路径操作器交给 FileSaveProcess。
- `classes7.dex` / SaveAsCommand 明确 onSaveAsCancel / onSaveFail / onSaveSuccess 回调；未将用户点击保存直接视为完成。

保守结论：WPS Writer 具有文档模型、格式序列化、路径权限适配、备份和输出验证分层。没有进行故障注入，不能声称 fsync、同卷原子 rename、跨 provider 原子提交、版本 CAS、完整回滚已经得到验证。本次也未验证 WordWriter 的全部 OOXML 保真行为。

### 3.2 渲染导出与授权是不同模块

- `classes7.dex` / `writer.service.export.KTextPdfExporter.exportPage(...)` 创建 KCanvas 后调用 PageService.render；close(...) 经 KPdfDocument 写出，cancel(...) 清理 exporter。这是实际本地页渲染导出调用链，但并未实测字体/公式/批注是否正确。
- `classes3.dex` / KPdfExporterLoader.a() 通过 WriterAuxLibsClassLoader / loadClass 加载 KPdfExporter。抽象加载器并不证明本次需要联网下载，其具体装载路径未深追。
- `classes3.dex` / presentation.control.ExportPdfInner 有 renderPdfPageByPage、取消状态与 Result；支持逐页导出与取消的架构判断，不证明 Android 设备上的正确性或性能。
- `classes4.dex` / ScanPicToPdfExportPrivilege.i(...) 经 ServiceManager 取得 IVasPrivilegeAssembly、创建 CheckParamsBuilder 并调用 check；普通用户分支包含 OCR PDF、高清和去水印的不同参数及支付引导。是实际权限检查调用，不能据此写成所有扫描导出付费，也不确定当前地区、账号或套餐规则。

### 3.3 必须保留能力不足，而非宣传“全面 Office”

样本资源中有以下精确标识：

- `et_include_unsupported_function`：不支持函数的结果不能正常显示。
- `et_loadDocumentFileStrictOpenXMLUnSupportedError`：Strict Open XML 打开不支持提示。
- `et_loadDocumentFileUnsupportedEncryptionError`：不支持某加密方法。
- `writer_revision_unsupportedRevisionSubDocument`：部分修订不能编辑。
- `writer_comment_penkit_unsupported_message`：特定 Pencil Engine 手绘批注当前设备不能编辑。
- `documentmanager_cloud_file_conflict_rename` / `public_cooperate_version_conflict`：保留两个 / 版本冲突。

这是应用包含相应错误/限制处理文案的证据，不能反推本样本当前必然触发每一种限制；对 Muyon 的启示是按“格式 × 操作 × 特性 × 引擎版本”发布能力，而非只列四个格式图标。

## 4. 对 Muyon 的可实施设计启示（建议，不是已有功能）

1. 将 DocumentAccess/Revision 与引擎分开：engine 不自行获取任意文件；由授权 scope 颁发一个版本的读句柄和受限输出位置。临时文件、缩略图、OCR、索引、预览、导出都同 scope。
2. 统一 Job 状态：prepared → running → output_created → validated → committed；failed / cancelled / outcome_unknown 是独立终态。远端导出只提交成功时不能显示“文件已保存”。
3. 渲染、结构化编辑、原格式保存、云转换、授权检查分开能力标记。UI 看到“DOCX可打开”不应自动解锁全文重写或保存覆盖。
4. 保存副本优先；目标版本以 hash/revision 做 CAS。临时写后关闭并重新打开解析、核对内容与结构、生成预览差异，最后提交新版本。云 provider 不支持原子替换时明确降级为创建新文件，不伪装原子覆盖。
5. 保存验证至少区分：容器有效、结构有效、文本/数据语义、版式预览、未支持特性保留。WPS 的 exists/length 只是最低层检查，Muyon 不应停在这里。
6. Agent 采用有类型的操作命令，不把文件内文字当指令。建议 replace_text_range、set_cell_formula、update_slide_text、add_pdf_annotation 等命令必须指明 documentId/revision/anchor/expectedValue/operationId；执行失败不自动改成有损整文件转换。
7. “取消”只表示停止后续工作或请求取消，不能保证撤回已上传内容、已写版本或费用。提交后回滚应另建一个可审计版本。
8. 密码、宏、外部链接、嵌入对象与脚本采取阻断/保留不执行策略；Office 页码和文字位置可能随字体/重排改变，应保留结构锚点+原文摘要+版本，不仅截图坐标。

## 5. 未完成验证与下一步

- 两 APK 的官方发布真实性及完整签名验证未完成；Acrobat 的 ABI/density split 缺失。
- 没有运行 APK、设备性能/触控/编辑测试，也没有用真实文件做 Word/PPT/Excel/PDF round-trip。
- 没有证明某厂商实现可合法嵌入 Muyon。这里只研究设计及架构，不复制专有代码、私有 API 或私有协议。
- 不因静态证据就决定收费 SDK；应由统一接口后面的候选引擎分别对许可、部署、格式保真、离线、成本、安全沙箱做专项验收。
- 用户扩大到“后台较全面 Office、Agent 编辑”的目标可以保留，但应以可验证子集逐步交付，未支持特性必须阻断或明确降级，不静默丢失。

复查定位：同目录 base11/base12 的 .json（身份）、.manifest.xml、.focused.json（DEX类/方法/调用摘录）、.strings.xml（资源）以及 inspect_wps_adobe.py（可复现静态索引）构成本次取证辅助产物；它们不是应用源代码复用材料。方法调用索引每方法最多记录180条调用/字符串，因此大方法结论仅覆盖已读片段，不冒称完整控制流证明。
