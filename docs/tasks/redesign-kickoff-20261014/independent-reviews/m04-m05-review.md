# M04/M05非作者独立复审与实际复跑

M04固定 `8c5995515fa14ca3592a1c33c71afb4e4c1e5def`、M05固定 `962daee22c2ee2108440d9b30f2fcf7a88948f40`；共同base `bc5b2c37a98bfa417c0f35f5383b76dfb03be85a`。固定设计58fe与已审M02 2fd/D01a99/D03a40为语义依据。仅固定源码/合成fixture/函数级实际运行，不重复A00盘点，不安装/pub，不触碰真实数据/credential/model/Android/设备。

## 结论与C/I

**C=0。M04可接为离线语义fixture输入；M05可接为真实固定Dart函数级参考证据。** 独立复跑exit0：47次真实调用，39独立预期对照，32pass/14partial/8not_run，0差异；逐case及逐entry观测与提交报告完全相同。它们不是完整API/UI/CAS/状态成功或新架构Runtime门禁通过。

- **I-01：未跑lane明确保留。** private `_validateArguments`、工具schema/dispatch、真实旧controller/pretrim、新Rust raw2000 guard都没有调用；14入口partial不是14完整入口通过。两patch入口和6状态仍not_run。CAS、scope、同值新intent+1、重复零写、只读receipt、unknown、分类/授权/当前实际值credential检查均无执行证明，不能以函数32pass关闭这些工程门禁。
- **I-02：Unicode等价与M03仍blocked。** 真实环境Dart3.13.4 stable linux_x64，缓存unorm_dart0.3.1包声明Unicode8.0且lib字节哈希匹配原报告。这是依赖事实，32名称样本不证明全部Unicode域或Rust/Android/双传输等价。M03仍须已协调D01a/D03a、固定oracle差分范围/版本及SPIKE-01真实Android加载与选型证据；不得因两库名NFC而冻结。
- **I-03：golden采纳须与执行层级绑定。** M04三个顶层golden及54个case golden仍null；32domain/16entry原not_run，6state原planned。M05比较的是独立`proposed_semantics`，实际输出可成为经此非作者核验的函数层参考输入，但不能静默把M04整入口/状态改PASS或把54局部记录加到52主号。A00 29分类case保持not_run。

没有发现源事实/已定目标冲突、镜像normalize实现或秘密回显问题。未来新增secret/canary或调用完整入口必须另审safe_output/日志许可；当前适配器只适用已审普通合成名称，不能推广成凭据分类器。

## 真实调用与独立负对照

`oracle.dart`直接import固定原产品values.dart/entities.dart，通过entities/inquiry循环依赖加载原实现；调用`normalizeText(input,'name',200,required:true)`及`Supplier.fromJson`。Python只读git对象、输入构造配方及预期字面值，不实现trim/NFC/XML/领域限长。三直接产品文件与固定01e56cc逐字相同且哈希匹配提交报告。

47调用细分：32名称normalizer；6完整Supplier负payload；1普通中文完整Supplier补充正例；8入口raw-normalizer追加观测。前39次有独立M04预期并零差异，后8次标observed_only，不冒完整入口执行。接受/拒绝均实际出现：中文、NFC组合/非NFKC、200/201码点、XML前trim、VT/FF/NUL、孤立surrogate/合法pair，raw2001直接领域可合法与工具guard未跑分层准确。

独立负对照仅在外仓隔离副本：

1. 临时改变values.dart字节而不改行为，原driver先报`source differs from product pin`、exit1，未进入Dart；随后恢复固定源码。证明固定源漂移保护实际生效。
2. 在外仓对象store建立独立负对照fixture提交`0ae260e14e08428e2c640518b1f2c24bc9c5cbd7`，只把NFC组合预期改成明显错误的合成字符串；输入与产品实现未改。原driver真实跑47调用，exit1、1mismatch、M04-NAME-nfc-compose明确fail，其余正常。没有回写或调整作者M04预期掩盖差异。

负对照是本复审检测能力证据，不属于作者实现或原M04新版本，不可纳入正常golden/成功计数。

## 原字节执行、输出隔离与证据

M05 driver限制`--output`必须位于其HERE目录、raw evidence必须仓库外；直接给作者worktree的外仓output会被拒绝。为遵守用户“不改作者/committed observations、新外仓输出”要求，本审查创建仅共享读取git对象的外仓isolated clone，取962原字节脚本及固定产品三源保持路径布局，HEAD固定962；fixtures从8c固定git对象读取。脚本没有改写。正常独立output为：

`/workspace/reports/redesign-m04-m05-independent-20261014/oracle-copy/scripts/redesign/supplier-name-reference/independent-observations.json`

原始stdout/stderr、invocations/package_config在本报告目录的`rerun-raw/`；source漂移/错误预期控制另留外仓子目录。没有修改作者提交中的reference-observations.json。正常复跑与原报告仅路径/命令及运行HEAD背景等provenance不同；case/entry、summary、版本、依赖/源码/fixture/adapter/driver哈希逐项相同。

环境固定CI=true、PUB_CACHE=/workspace/pub-cache、XDG_CONFIG_HOME=/workspace/sdk-config，子进程明确移除MUYON_EVAL_REAL。只使用已有SDK和缓存，零网络安装、零模型/外部发送。原日志没有进入仓库；当前全部输入普通合成、无真实秘密/credential canary。

## 范围和后续采纳

相对bc5b，M04恰6新增文件、M05恰5新增文件；`git diff --check`通过。M04 SHA256SUMS覆盖README与3JSON的4项全部通过；54case唯一且分32/16/6，状态及null golden准确。作者M04/M05工作树均干净；原分支、产品、M01/原书/ADR、其他worktree未修改。

B可登记本固定SHA非作者终态并接收函数层参考证据，继续安排未跑lane的真实可信入口/隔离库与状态runner。reference数据不证明本机动作actual-value credential检查、grant或风险准入，name=none不授权；unreviewed外发与credential正文边界仍沿已审澄清。保持Dart函数层pass、partial/observed_only、not_run及跨端not_proven四种证据范围，不能将尚未运行程序记完成。

机器证据`proof.json`；可复现核验/负对照`check.py`；正常观测与原始日志路径如上。没有剩余阻断本次输入/函数参考采纳的问题，I项仍阻止扩大完成声明或M03冻结。
