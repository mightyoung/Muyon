# Windows 体验包：手动工作流准备

本交付只新增 `.github/workflows/windows-experience-package.yml` 和本说明，复用已审查的
`scripts/package_artifacts/package.py`。不修改 main、产品代码、依赖锁、原有工作流，
不 dispatch、不安装依赖、不使用业务库、模型或凭据。

任务基线 `ab5506c30d16269c31d8ac7f1cf7a7358214a5da` 的
[普通 Ubuntu CI](https://github.com/mightyoung/Muyon/actions/runs/38207019029) 成功，
这不是 Windows 构建证据，更不是最终体验候选。最终候选须由唯一集成者在窄屏与
披露修复完成、组合门禁通过后指定完整 SHA；工作流没有默认产品 SHA。

## 手动入口与最小授权

工作流仅 `workflow_dispatch`，固定标准 `windows-2022`，60 分钟上限，
仅 `contents: read`。所有 actions 固定完整 SHA；源码与工作流工具独立 checkout，
关闭凭据持久化，并分别核对完整 HEAD。输入通过环境变量校验，不直接插入 shell。

截至本次只读核验，仓库 public，默认 main 只有 verify.yml，Windows 新入口尚未登记；
现有六个已注册工作流没有 Windows 构建。先由唯一集成者安排默认分支独立登记，
复用打包脚本也须在所选工作流提交存在；本分支不执行该登记。
随后确认一次构建及一日产物存储额度、公开下载范围，才可在 Actions 选择这个入口，
填写最终候选 SHA 并勾选 `artifact_storage_approved`。未勾选即在准备工具链前失败。
该字段是操作者确认，不是账单或预算的独立证明。

仓库读取/推送权限可查；Actions permissions REST 查询返回 403，未据此声称全局
策略已允许运行，也未扩大权限。账户剩余额度与存储预算未取得证据。
[GitHub 官方费用说明](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
说明 public 仓库标准托管 runner 计算免费，larger runner 不免费；产物存储共享额度，
超过额度可能计费。未知不等于必定付费，一日保留也不是费用硬上限。
public 仓库 Actions artifacts 可被登录且有读取权限的其他用户下载，不能称私密分发。

## 包与依赖

运行时解析现有锁定 workspace 依赖（`--enforce-lockfile`），用 Flutter 3.47.5
构建完整 Windows Release bundle；不传 `dart-define`、不注入模型 key、不新建凭据。
Windows 工程已固定 ONNX Runtime 1.23.0、`USE_SYSTEM_ONNXRUNTIME=OFF`。
未来真实构建可能由现有插件/CMake 构建钩子下载这个既有原生运行库、Flutter SDK
及锁定依赖；这是网络下载与构建已有依赖，不能称完全离线，也没有在本任务执行。
若 runner 缺 Visual Studio/WebView 等构建前提，构建必须失败，不能现场加装系统依赖
或生成替代包；另报具体缺项。这里没有额外模型权重下载步骤。

复用打包脚本要求 exe、Flutter DLL、data 与全部递归产物存在，拒绝链接/reparse
point/路径越界和常见 `.env`、keys、日志、keystore 等路径，并验证未签名。
仅上传 ZIP 与 manifest，保留一天，不上传 rawlogs、源码、缓存或环境文件。
manifest 包含源码/工作流 SHA、run ID/attempt、OS/架构、工具版本、签名方式、
包大小及 SHA256。路径黑名单不是内容无秘密证明：最终候选资源及真实产物仍需核验，
不得包含密钥或真实用户数据。完整 ZIP 的 DLL/data 不能拆掉只发 exe。
无 Authenticode，不能承诺 Windows SmartScreen 信任或所有机器具备所需运行库。

应用已有 Windows FlutterSecureStorage 系统凭据路径和应用内 endpoint/model/key
配置入口；这里只是静态确认，没有输入或读取真实凭据。新数据库呈现偏好默认
textOnly；已存在持久偏好可能不同，不重置用户设置。体验时从隔离新工作区开始，
未验收的 AIUI、模型披露新接线与本地导出恢复边界按最终候选说明提示，不默认开启。

## 验证等级与本次检查

构建、启动、交互分别记录。未来构建通过后还要核对 ZIP/manifest 哈希、完整 SHA、
工具版本和签名；构建成功仅证明可打包。真实 Windows 启动及日常交互尚未执行，
不能称稳定可用版本。启动验证须在已授权 Windows 环境、隔离合成工作区进行，
不安装用户电脑，不用真实业务库、不调用真实模型。

本次离线复跑现有打包测试 26/26；原生工具输出是替身，不是 Windows 构建。
另用现有 PyYAML 做 workflow 结构、固定 action SHA、权限、输入、上传范围和保留期
检查，用 bash 对各 run 段做语法检查及 SHA/授权输入正反例验证。
未安装 actionlint，未宣称做过它的专用检查；未触发 Actions、未生成真实 exe/ZIP。
原始校验日志保留在仓库外。
