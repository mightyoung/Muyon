# Muyon 公共 Office 与 Agent 文件编辑研究 v2.0

核查日期：2026-10-22；执行位置：云端。此报告是 PDF 研究 v1.1 的新增扩展，不覆盖旧结论。目标按用户最新要求扩展为：前台易读、可批注和适量直接编辑；后台具备逐步扩展的 Office 文档生成、结构化编辑、校验和导出能力，Agent 经受控工具使用。不是“把几个 APK 的编辑器搬进 Muyon”。

## 1. 当前完成与证据等级

已从用户指定 Drive 目录读取并完整下载 5 个新 APK，静态读取 Manifest、资源、DEX 和本地库目录，计算 SHA-256 并做 ZIP CRC 检查。未安装、未运行 APK、未调用厂商内部 API、未使用凭据、未购买 SDK、未改 Muyon 代码；未进行设备体验、格式往返或真实编辑实验。因此以下借鉴点是静态结构和官方文档支持的设计建议，不是 Muyon 已实现能力。

来源目录：https://drive.google.com/drive/folders/1ifCHLvXiRAThyWUyCb6FbP8CfvKjnrVi

证据分层：A 官方原始文档；B 样本二进制可定位结构/方法；C 本研究的工程推断；U 运行/许可/保真仍未知。原始 APK 的证书主题和指纹只用于样本识别；未与可信官方发布证书逐一比对，也未以 apksigner 完成密码学验签，不宣称官方原包。ZIP 完整不等于安全可信，也不等于 split 安装集完整。

## 2. 产品借鉴应如何收敛

- Microsoft 三应用：学习“共享 Office 基础设施 + 格式专用编辑核心”，不是所有 MIME 都由一个内核编辑。Manifest 的 CrossSellHandler 会接收其他格式作跨应用转接，不能把它当本包全格式支持证据。
- WPS：学习统一入口、格式路由与共享存储，但不可把拥有同名菜单等同于离线/免费/完整能力。
- Acrobat：将阅读、批注、内容编辑、导出、云协作拆成独立能力和授权状态。此样本 base APK 明确依赖 ABI/density split，缺失部分使渲染内核覆盖不完整。
- Flexcil/Zotero：沿用上一报告的原文锚点、选择/笔模式、摘录回跳、跨文档引用、批注持久化；科研文献元数据与判断留在业务层。

Microsoft 官方移动帮助对屏幕尺寸/产品/计划有不同口径，应按具体 app 和设备核验，不能承诺所有平板免费编辑。Adobe 官方将 PDF 文字图片编辑列为订阅能力。WPS 安卓官方说明可查看/编辑文档，但产品宣传不能证明每项功能都免费、离线或与此 APK 一致。
来源：
- https://support.microsoft.com/en-us/office/foundations-experiences/microsoft-365-mobile-apps
- https://support.microsoft.com/en-us/microsoft-365-activation-licensing/mobile/what-you-can-do-in-the-microsoft-365-apps-on-mobile-devices-with-a-microsoft-365-subscription
- https://www.adobe.com/devnet-docs/acrobat/android/en/editpdf.html
- https://www.wps.com/office/android/

## 3. 公共层架构：文件引擎不是科研专属，也不是全盘权限

保留现有设计术语，扩展而不替换：
1. DocumentAccess / Revision：有范围的文件句柄、版本/hash、MIME嗅探、读写授权、来源和保留策略。业务 scope 同时覆盖文件、缩略图、OCR、索引、临时文件、导出和 Agent 上下文；群组成员/agent 不因“公共组件”获得其他项目文件。
2. Reader / Selection：手机/平板阅读与选择，原版式和抽取文本两种视图明确区分；布局预览不能冒称可回写原文件。
3. Anchor：通用身份加格式专用定位；必须绑 revision。PDF 页/页面box/旋转/坐标/文本片段，DOCX part+段落/书签+quote，PPTX slideId+shapeId+文本范围，XLSX sheetId+范围/命名区域。页号、shape序号、行号均不能单独作跨版本稳定ID；变更后的锚点重定位须带置信与失效状态。
4. AnnotationStore / Export：共同批注模型（高亮/墨迹/评论/区域）与原生格式注释不同，先侧车存储，按 adapter 导入导出。PDF标准批注、扁平化、DOCX comments/tracked changes、PPT notes/comments、Excel notes/threaded comments分别声明支持程度，不能一概称“双向同步”。
5. DocumentEngine adapter：inspect、extract、render、edit、recalculate、validate、export分开，返回能力表与降级理由。不把文件后缀或一个支持列表当成所有操作均可用。
6. AgentDocumentService：typed工具只拿scope file handle，不能任意路径、任意下载URL、通用shell或无限权限。底层重型引擎可在隔离后台，Android不需要塞入完整桌面Office，也不改变既有Kotlin/Rust接口边界。

## 4. 四格式分阶段能力

| 格式 | 第一批可评测的前台/后台范围 | 后续全面能力方向 | 明确不可直接承诺 |
|---|---|---|---|
| DOCX | 原版式预览、目录/查找、摘录/评论；后台模板生成、指定段落/run替换、基本样式和简单表格 | 节/页眉页脚、引用/脚注、修订、复杂表格、跨文档合并 | DOC旧格式无损编辑；文本替换保留所有run样式；复杂域、公式、嵌入对象、签名和修订不丢失 |
| PPTX | 幻灯片预览、备注、对象选择；指定shape文字替换、图片替换、受限版式生成 | 图表、主题/母版、对象排版、讲稿、批量重组 | SmartArt、动画、视频/音频、字体替换后仍像素一致；整段text赋值不改变原分段样式 |
| XLSX | 工作表/区域阅读、单元格值与公式分别显示；类型化单元格/区域编辑、基础样式和验证 | 受支持公式重算、表格/图表、透视和数据分析生成、受控多表变换 | 写入公式即计算完成；缓存值即最新；宏、外部数据刷新、任意函数/数据模型兼容 |
| PDF | 分页/缩放/搜索/选择、标准批注/表单候选、侧车批注与导出副本 | 页面组织、OCR、受控文字/图片编辑、受评测转换 | PDF天然等同Word；OCR真值；签名后修改仍有效；涂黑矩形等于安全删密；转Office保真 |

以上不是把第一批功能预先标成已实现。首阶段选择可回归验证的窄编辑操作；全面能力通过引擎适配和能力证据扩展，而不是承诺单一库覆盖所有Office功能。旧二进制 DOC/PPT/XLS 首先只读/隔离转换，转换副本带保真告警，不静默覆盖源文件。

## 5. Agent 的真实编辑闭环（建议）

受控工具族：document.inspect / read / render / propose_patch / apply_patch_to_copy / validate / compare / commit_revision / export / rollback。每次包含 scopeId、fileId、baseRevision、operationId、幂等key及结构化操作列表；模型输出不直接变成shell或任意SDK脚本。

流程：
1. 读身份与capabilities，检查源版本、风险清单、可用字体和权限；模型看到的文档内容是数据，不是授权指令。
2. Agent输出结构化修改计划，如“将第3张指定shape标题改为…”，并明确未改区域不变量。替换目标必须带原文/hash前置条件，多匹配不可猜测。
3. 隔离作业对不可变原件副本执行；无网络、无宏、无外链刷新、无宿主凭据；限制CPU/内存/展开大小/页数/递归/超时。
4. 保存候选文件，重新打开并做结构、语义和渲染检查；Excel单独报告公式重算和缓存状态；对比未授权区域，不能仅“文件能打开”便通过。
5. 展示变更摘要、前后页/slide/区域预览、风险和遗漏。根据用户请求和既有权限决策：普通副本创建可沿已授权任务进行，覆盖源文件/对外分享/上传第三方/成本等按具体授权执行，不能一律后台静默。
6. compare-and-swap 检查 baseRevision，原子发布新版本；先durable blob再事务更新revision指针。对象存储不假装有POSIX rename，使用不可变对象+数据库指针；恢复记录覆盖崩溃窗口。
7. 交付文件及验证报告、引擎/版本/font集、输入输出hash、可回查anchors。取消只是停止请求：取消、写入、验证、发布、回滚状态分别记录。重复提交不产生重复写，失败保持原件不变。

建议状态：queued / inspecting / preparing / applying / validating / awaiting_review / committed / failed / cancelled / conflict。后台完成、格式验证通过、视觉人工验收、同步成功必须不同字段。用户改了源文件则conflict，保留候选副本待重基，不最后写入者覆盖。

## 6. 引擎候选与许可证边界（研究，不选型）

A. 结构化库：python-docx、python-pptx、openpyxl，或Java Apache POI。适合受限对象编辑和生成，不是完整Office排版/计算引擎。前三者官方许可证MIT/Expat（需保留声明），POI需按Apache许可及实际依赖清单检查；不能仅依库名给整个应用许可结论。
- python-pptx官方示例明确某些text快捷赋值会删除原段落结构，设计应使用定向run级操作并验证。
- openpyxl官方明确不计算公式；data_only读取的是缓存，shape可能在打开保存后丢失；VBA保留选项并不支持编辑/执行VBA。故复杂原件应先筛查并拒绝未经验证的往返。
- POI有自己的公式求值器但并非Excel全部语义；修改依赖单元格后需要更新缓存，外部工作簿处理须隔离。
来源：https://github.com/python-openxml/python-docx/blob/master/LICENSE ，https://github.com/scanny/python-pptx/blob/master/LICENSE ，https://openpyxl.readthedocs.io/en/stable/ ，https://poi.apache.org/legal.html ，https://python-pptx.readthedocs.io/en/latest/user/quickstart.html ，https://openpyxl.readthedocs.io/en/stable/tutorial.html ，https://openpyxl.readthedocs.io/en/stable/simple_formulae.html ，https://poi.apache.org/components/spreadsheet/eval.html

B. LibreOffice后台引擎：官方有headless、格式转换、独立UserInstallation、UNO文档加载属性等接口，适合更宽的导入/排版/导出评测。headless不是安全沙箱；需要禁宏/外链、独立profile、进程隔离、超时和可复现字体。源码/发行包包含多种许可，不简单写“LGPL所以任意嵌入”；应固定版本逐组件核许可证和分发义务。复杂OOXML往返仍需验证。
来源：https://help.libreoffice.org/latest/en-US/text/shared/guide/start_parameters.html ，https://api.libreoffice.org/docs/idl/ref/servicecom_1_1sun_1_1star_1_1document_1_1MediaDescriptor.html ，https://www.libreoffice.org/licenses/

C. ONLYOFFICE Document Builder：官方有DOCX/XLSX/PPTX/PDF创建编辑转换、CLI/API/语言绑定。当前安装文档写明免费版输出带水印，去除限制/全部功能需商业许可。不能以ONLYOFFICE某仓库开源推断此SDK免费可商用，也不默认采购；待许可、资源和保真对照后再决定。
来源：https://api.onlyoffice.com/docs/document-builder/get-started/overview ，https://api.onlyoffice.com/docs/document-builder/get-started/installing

D. PDF引擎：沿先前PDF报告候选比较，独立核阅读/批注/表单/内容编辑/删密功能。不要因Zotero源码开源就复制其商用渲染依赖，不从Acrobat/WPS二进制抽取闭源库复用。

## 7. 必须覆盖的风险和验收样本

- DOCX：双栏、多节、页眉页脚、脚注/域、中文西文字体、公式、嵌套表格、现有评论/修订、隐藏文字、图片和OLE。
- PPTX：母版/theme、组合对象、旋转裁剪、讲稿、chart/SmartArt、动画媒体、替换字体后溢出。
- XLSX：合并单元格、日期/时区/1900与1904系统、数值精度、区域设置、共享/数组/动态公式、cached values、命名范围、图表、透视、验证/保护、外部链接、VBA和敏感隐藏sheet。
- PDF：双栏公式表格、扫描页、页旋转/CropBox、批注/表单、加密和签名。OCR confidence必须保留；编辑已签名文件应警告并输出副本，不声称签名仍有效。
- 安全：ZIP bomb、XML实体、路径穿越、超大图片/字体、解析器崩溃、递归嵌入、嵌入JS/宏、DDE/OLE、公式外联、文档提示注入、恶意URL。禁自动加载外部资源与远程模板；不复用进程用户profile。POI官方也明确解析复杂恶意文件可能耗尽内存/长时运行，应额外隔离，库自身检查不完备。
来源：https://poi.apache.org/security.html

每个支持项至少留：原始sample hash、预期变更、未改不变量、引擎版本、写前/写后render、结构验证、语义diff、重算状态、失败日志。分级为“只读可用/抽取可用/受限编辑已验/完整保真未承诺/不支持”。本报告未执行这些实验，不能给通过数。

## 8. 稳定任务拆解（归入 MIG-26，避免重复）

- DOC-01 文档身份与scope：基于DocumentAccess/Revision明确文件/缓存/OCR/索引/导出同域隔离、不可变版本与授权矩阵。验收：跨项目/群组访问拒绝、撤权后缓存不可见。
- DOC-02 格式探测与安全检查：真实MIME、OOXML部件/宏/外链/嵌入物、大小限额和降级报告。验收：危险样本拒绝/隔离且原件不变。
- DOC-03 统一Reader/Selection/Anchor：四格式adapter和revision绑定，原版式/文本视图区分，失效锚点不猜测。依赖01/02。
- DOC-04 批注与导出：侧车批注、原生能力矩阵、可编辑与扁平导出区别、回跳/未知状态。依赖03。
- DOC-05 引擎评测与许可ADR：固定版本/许可证/依赖/字体/资源上限，比较结构化库、隔离LibreOffice、可选商业引擎；输出决策而非直接引入。无需先购买。
- DOC-06 Agent typed工具：inspect/read/render/propose/apply-copy/validate/commit/export/rollback，schema、scope、幂等、取消与冲突合同；文档内容不可发放权限。依赖01/02；可先做中性接口设计。
- DOC-07 四格式受限编辑与保真基线：格式专用最小操作、结构/视觉/公式/批注回归语料，保留NOT_RUN和失败。引擎未定前不编造实现。
- DOC-08 安全保存/版本/回滚：不可变候选、CAS、事务指针、失败恢复、保存副本、审计回执，取消≠回滚。依赖01/06。
- DOC-09 前台编辑预览交互：黑白主背景沿现UI定稿，变更卡/风险卡/差异预览/确认/版本入口，能力不可用时解释而非假按钮。与现MIG16/17等接口任务关联，不重复造全套UI票。
- DOC-10 全面Office能力扩展：分格式逐项引入高级对象、重算/排版、批量生成，只有通过保真/许可门槛才升级能力标签。不是首阶段必须全部完成。

当前可以继续：研究、设计、接口与评测计划。引擎引入/生产代码/真实作业应沿原授权与依赖复审推进；商业SDK采购、云文件传输、持久凭据和新增费用仍需明确决定。无需现在让用户在未经评测的技术名词间盲选。

## 附录 A：五个APK样本身份清单

下列证书指纹是DER证书SHA-256，不是APK指纹。证书主题自报不构成厂商认证。全部ZIP CRC通过；官方来源与密码学验签尚未确认。

### Microsoft Excel / base8.apk
- Drive：https://drive.google.com/file/d/1JIKKYdSLE4LiGBavTSelMA-UUYglivPP/view
- 包：com.microsoft.office.excel；版本：16.0.20228.20090（2006247667）；min/target SDK：33/35。
- 大小：141475483 bytes；SHA-256：7186fff1adf48ad19c15221e2ca0b554e8529abf298d5ebbbbb82f5ff6633eed。
- 证书SHA-256：b925136f3ea7c0a1951690a1ab313910da81f40994a85342ec622888f1287051；主题：Common Name: Microsoft Corporation Third Party Marketplace (Do Not Trust), Organizational Unit: Android Marketplace Signing for Microsoft Office, Organization: Microsoft Corporation, Locality: Redmond, State/Province: Washington, Country: US。

### Microsoft Word / base9.apk
- Drive：https://drive.google.com/file/d/1zgM5FZxKFzJOV2tJEuokvirWnF2jFpJh/view
- 包：com.microsoft.office.word；版本：16.0.20228.20090（2006247667）；min/target SDK：33/35。
- 大小：147334769 bytes；SHA-256：2a0f936cf6ba6cc77f2398f2cd063f428d4c610bcea57c69a0d9e94d35739111。
- 证书SHA-256：b925136f3ea7c0a1951690a1ab313910da81f40994a85342ec622888f1287051；主题：Common Name: Microsoft Corporation Third Party Marketplace (Do Not Trust), Organizational Unit: Android Marketplace Signing for Microsoft Office, Organization: Microsoft Corporation, Locality: Redmond, State/Province: Washington, Country: US。

### Microsoft PowerPoint / base10.apk
- Drive：https://drive.google.com/file/d/1SUlFVUhWqJLpqbAi8Rm5q2XBEtgQoCXQ/view
- 包：com.microsoft.office.powerpoint；版本：16.0.20228.20090（2006247667）；min/target SDK：33/35。
- 大小：135270154 bytes；SHA-256：6cf16fcc9ad78a319c82fccd742904423f805d8cacd369eefe1969e3b6688fc8。
- 证书SHA-256：b925136f3ea7c0a1951690a1ab313910da81f40994a85342ec622888f1287051；主题：Common Name: Microsoft Corporation Third Party Marketplace (Do Not Trust), Organizational Unit: Android Marketplace Signing for Microsoft Office, Organization: Microsoft Corporation, Locality: Redmond, State/Province: Washington, Country: US。

### Adobe Acrobat / base11.apk
- Drive：https://drive.google.com/file/d/1TtwHs01lMyLbY5RM1vdBGDeV4kwoYhDS/view
- 包：com.adobe.reader；版本：26.9.2.50367（1932150367）；min/target SDK：28/36。
- 大小：93179990 bytes；SHA-256：3e27d178ec1b06d833395cf258851e4da4ab5a147e3b15b7caa3011d6536834c。
- 证书SHA-256：b6dd0562256487fcd6c98cde137858ef50d9adb9f9cd2f1ca58c5357efdf0faf；主题：Common Name: Adobe Systems Incorporated, Organizational Unit: Adobe Reader, Organization: Adobe Systems Incorporated, Locality: San Jose, State/Province: California, Country: US。

### WPS Office / base12.apk
- Drive：https://drive.google.com/file/d/1Qnk_w94Ps_8DZZRXYTjn5xXxcD9wamZC/view
- 包：cn.wps.moffice_eng；版本：26.10.0（2000）；min/target SDK：24/37。
- 大小：174746541 bytes；SHA-256：274d52dffcde6bf35489f9341a5598d60e21f5da1cf3a78f6b15861df5a1f9fc。
- 证书SHA-256：643990878d3ca83952a5be5f3e58d9f8bb6cdc57bf0f228700212071c68db3d7；主题：Common Name: KSO Agent; Organizational Unit: MAPP; Organization: Zhuhai Kingsoft Office Software Co.,Ltd; Locality: Zhuhai; State/Province: Guangdong; Country: CN。

Microsoft三个样本证书主题含 Third Party Marketplace (Do Not Trust)，只记录身份边界，不单凭文字认定恶意。Manifest为CHINA渠道与此相符不等于验真通过。Acrobat base明确要求base__abi、base__density；当前未取得split，未知安装及完整native引擎。

## 附录 B：ChatGPT / Claude 官方路径核验


### OpenAI

1. 当前 ChatGPT Work 帮助文档明确支持创建、编辑文档/表格/演示，参考 DOCX/XLSX/PPTX 或 Google 文档模板，并要求用户指出需保留的公式、布局等。原生 Google Workspace 路线与桌面 Excel add-in 路线分开说明；该文档明确 PowerPoint 不包含在其 Work 桌面启动流程中。不能把“可生成 PPTX”写成“桌面 PowerPoint 插件已在此流程可用”。
来源：https://help.openai.com/en/articles/20001278-creating-and-editing-documents-spreadsheets-and-presentations-with-chatgpt-work

2. ChatGPT for Excel/Google Sheets 是表格宿主中的独立侧栏体验。官方提醒 VBA/宏等高级能力可能不完全支持，检查公式、引用和修改单元格，并先复制重要文件。它不支持我们承诺任意复杂工作簿无损往返。
来源：https://help.openai.com/en/articles/20001063-chatgpt-for-excel-and-google-sheets

3. 公开 Code Interpreter API 支持在沙箱中运行 Python、处理输入文件并生成文件。它证明可以构建“模型 + 计算容器 + 文件输出”方案，不证明 ChatGPT 所有 Office 功能均用某个 Python 库或同一执行链。
来源：https://developers.openai.com/api/docs/guides/tools-code-interpreter

4. 2025-07-17 ChatGPT agent 发布说明描述虚拟计算机、代码和可编辑产物，但页面现在标注发布帖已过时。因此只作为历史机制证据，不能作为当前功能/套餐/限额清单。
来源：https://openai.com/index/introducing-chatgpt-agent/

### Anthropic

5. Claude 官方文件能力公告发布于 2025-09-09，更新称 2025-10-21 进入付费计划正式可用；明确通过私有计算环境写代码、运行程序，交付 Excel、Word、PowerPoint、PDF 文件。此公告包含旧预览介绍，当前可用性仍应以当下帮助页核查，而非照搬历史套餐。
来源：https://claude.com/resources/articles/create-files
当前帮助：https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude

6. Anthropic 官方公开 anthropics/skills 仓库称文档技能为实际产品能力的参考，但同时声明公开实现与产品行为可能不同。DOCX/PPTX 示例区分新建与对现有 OOXML 包的定点修改；XLSX 示例涉及程序化处理与重算；PPTX 示例包含内容、渲染检查。这是公开示例证据，不是完整生产技术栈。不能将 python-docx/openpyxl/python-pptx 任意列表描述为两家厂商内部真实实现。
来源：https://github.com/anthropics/skills
公开示例：https://github.com/anthropics/skills/tree/main/skills/docx
https://github.com/anthropics/skills/tree/main/skills/pptx
https://github.com/anthropics/skills/tree/main/skills/xlsx

7. 重要许可边界：上述文档技能是 source-available，而非一般开源。DOCX LICENSE 包含复制、衍生及分发限制。不得把仓库整体按 Apache-2.0 引入 Muyon；公共设计经验可研究，代码、提示词、脚本或素材能否复用需独立许可审查。本研究未复制这些实现代码。
来源：https://github.com/anthropics/skills/blob/main/skills/docx/LICENSE.txt

8. Claude for Microsoft 365 官方页面单列 Excel、PowerPoint、Word、Outlook：宣称 Word 修订与评论、PPT 模板/原生图表、Excel 模型编辑，并强调可审阅修改。此为宿主插件产品能力，不能外推成 Android APK 内存在同一 Office 引擎，也不能证明任何复杂文件绝对保真。
来源：https://claude.com/claude-for-microsoft-365

9. Claude 公开 Code execution API 支持 Python/Bash 沙箱及文件操作；当前该页写明无出站网络、工作区作用域等。API 沙箱与 Claude 消费者产品、托管 Agent、Office 插件是不同产品表面，不应混用其联网/权限/生命周期规则。
来源：https://platform.claude.com/docs/en/agents-and-tools/tool-use/code-execution-tool

未查明：两家公司完整生产依赖锁定版本、所有文件的内部转换链、闭源保真算法、各宿主具体覆盖率。未测量：编辑成功率、兼容性、成本、Android 性能。公开声明不能当独立复现实验。


## 附录 C：静态取证摘要与定位

Microsoft：Word classes5.dex 的 SavePanePropertiesUI 注册 ManualSave/SaveAs/OpportunisticSaveAndUpload 事件并通过native完成回调通知；AutoSaveState有Unavailable，DocumentSaveDisabledReason有ReadOnly/NotSignedIn/InsufficientLicensePrivileges/SubscriptionRequired等。SaveToLocationAsync将目标位置、请求、完成分开。PPT classes5.dex 的 ConflictResolutionComponentUI 提供 GetCurrentLocalSlide/GetCurrentServerSlide、双方缩略图与OnConflictsResolved异步完成。适合自研状态/冲突预览，尚不证明原子保存或套餐规则。

WPS：classes6.dex 的 FileSaveProcess.e 生成.save临时文件、调用TextDocument.x1序列化、经IFileOp.b移动并核目标exists/length。FileSaveBasic分离备份、路径操作与SecurityMode。只能支持保存流程有这些步骤，不能证明所有文件原子保存、崩溃恢复或往返保真。

Acrobat：classes3.dex 的 CRHeadlessPDFExportAPI.c 实际构造云导出、SenseiRequest提交/轮询/输出下载；classes6.dex 的 ARSaveACopyService 根据源与目标connector选择操作并区分完成/失败Outbox结果，监听解绑/退出账号。此具体分支依赖服务端，不推广为所有转换都在线。

详细证据单独保留《Microsoft-Office静态取证》《WPS-Acrobat静态取证》。未把专有DEX、本地库或资源移入Muyon；复用应是自有接口/交互设计而非专有实现。

## 变更记录

v2.0（2026-10-22）：在已交付PDF研究v1.1之外新增五个办公类APK静态取证，纳入Word/PPT/Excel公共能力，并按用户追加要求研究后台较全面Office及Agent编辑。保留v1.1，不将新方案回填成历史已实施。SDK选择、设备验收、文件往返实验、完整Adobe split、官方签名信任链和商业许可均未完成。
