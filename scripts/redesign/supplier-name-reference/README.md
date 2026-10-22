# M05 固定 Dart 名称参考 oracle

这是离线测试适配器和真实观测报告，不是业务 DTO/schema 生成器或 Rust 实现。`oracle.dart` 直接 import 未变的产品 `values.dart` 与 `entities.dart`，调用 `normalizeText(input, 'name', 200, required: true)` 和 `Supplier.fromJson`；Python只读固定git对象、校验源字节、准备package映射、比较独立M04预期，不实现trim/NFC/XML/长度规则。

产品固定 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`；M04 fixture固定 `8c5995515fa14ca3592a1c33c71afb4e4c1e5def`。通过git对象读取三个JSON，不写M04目录、不改其golden:null或not_run/planned状态。运行前必须三个直接产品依赖 values/entities/inquiry 与固定产品源逐字相同；记录每个文件SHA256。使用已经缓存的 `unorm_dart 0.3.1`，记录lib文件哈希及包自声明Unicode8.0；无pub/install/network。

复现（仓库根目录）：

```sh
python3 scripts/redesign/supplier-name-reference/run_reference.py \
  --fixture-sha 8c5995515fa14ca3592a1c33c71afb4e4c1e5def \
  --evidence-dir /workspace/reports/redesign-m05-reference-20261014 \
  --output scripts/redesign/supplier-name-reference/reference-observations.json
```

可通过`--dart`和`--unorm`明确指定已经可用的SDK/缓存；版本、源码与依赖哈希均记录。临时package_config仅映射已缓存unorm，无workspace pub resolve。CI=true、XDG_CONFIG_HOME=/workspace/sdk-config、PUB_CACHE=/workspace/pub-cache；移除运行子进程的MUYON_EVAL_REAL。原始命令stdout/stderr、invocations/package_config仅在外仓evidence目录；仓库仅安全普通合成规范值及非正文错误原因。当前固定M04没有secret/canary输入，safe_output只用于这些普通名称向量；任何未来敏感fixture须另行审查输出许可，不能将此适配器当credential classifier。

## 覆盖层级与观测

[reference-observations.json](reference-observations.json) 保留54个case各自actual_status及细分entry。32 normalizer向量pass；16入口比较中14 partial、2 not_run；6 planned状态仍not_run。共47次真实调用，其中39次对应固定独立预期，零差异；另8次raw normalizer观测不冒称完整入口通过。

- 32次声明的normalizer入口验证Chinese/NFC/非NFKC、200/201码点、raw2000/2001仅领域层、XML前检查、合法/孤立surrogate等。raw2001可在此函数合法，不表示2000入口guard通过。
- 6个完整Supplier payload（false/zero/null/array/object/缺name）实际调用Supplier.fromJson；另以M04中文正向输入构造完整合法Supplier字段作1次补充正例。正例仅比较name值，不证明工具dispatch、scope、CAS或写入。
- 8个入口的raw字符串追加直接normalizeText观测；旧form pretrim/controller、private `_validateArguments`、工具schema、新Rust raw guard均未调用，相关entry仍not_run。不复制pretrim或private guard来制造通过。
- 两patch与6state向量未运行：稳定意图、新intent同值revision+1、重复零写、过期CAS、scope、只读receipt、unknown均不由函数级结果证明。分类/授权也没有执行证明。

非空验证以固定M04正/负向量为准：实际接收与拒绝均须出现，另检查NFC组合、201码点拒绝、VT边缘拒绝、合法surrogate pair接受和孤立surrogate拒绝；结果缺项/多项、重复ID、错误source或预期差异使运行失败。未添加镜像实现的测试。

JSON记录产品/设计/fixture fullSHA、三fixture哈希、实际工具版本、实际命令与exit、源码/adapter/driver哈希、每case/entry及安全输出。`oracle_worktree_base_sha`是运行当时HEAD（本次bc5b2c3），不是最终M05提交；最终实现fullSHA随交付给出，adapter/driver内容哈希可独立核对。raw日志不纳入repo。

Rust目标全部not_run；两端Unicode等价未证明，M03仍blocked_contract。32 pass是实际Dart函数参考结果，不关闭52主case、A00 29分类子case、M04整入口或任何新架构runtime门禁。
