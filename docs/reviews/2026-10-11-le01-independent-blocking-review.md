# LE01 独立复验：两个 Important 已动态复现，暂缓合入

固定作者HEAD `202e44afc793aba8f38d2fb4105aa6c656bbf8af`；RED `5f974f1eb3a567b1d775b2d7c4a00b0b356b50af`；任务6ab51ba6父为develop140a。原实现两提交仅module_api四文件+558/-1；完整分支另有LE-01任务文档21行。独立验证分支review/le01-independent-20261011，组合 `11cb1de08a4a84ba899fe798971f4f10e8c0ddd2`（OC15–20/WC-C候选f64d2c1 + 作者202e44a）；此候选未推远端、未合develop，不能冒称完整CI已绿。

读LE-01、CR17设计、固定f7c76fd ADR第3项v6.8/schema2、API源码及测试。以下补充动态证据支持父任务安排的独立静态审查，不用作者268通过替代边界验证。

## I1：构造后可把本机目标变成混合网络声明

位置：packages/muyon_module_api/lib/src/tool_registrar.dart:14、27、121–127。通用DestinationRule(localExport:true,fixedHosts:callerSet)保留可变Set引用。以空Set构造ExternalToolSpec(export)时校验通过、localExportRuleProblems为空；随后callerSet.add('changed.example')，同一spec固定hosts非空，声明成为禁止的混合规则。

最小回归首行：`I1 local export cannot become a mixed network rule after construction [E]`。Expected empty / Actual {'changed.example'}；正常编译和启动。named const localExport构造的空集合安全，但不能因此为通用构造放行。没有声称当前宿主已开放该功能或发生网络访问。

## I2：列表冻结没有冻结开放元素的值

位置：packages/muyon_module_api/lib/src/local_export.dart:57–59、64–83、102–108。ObjectRef与LocalExportExclusion均允许合法implements；List.unmodifiable只复制列表壳，保留元素身份。

独立MutableRef implements ObjectRef：准备后把objectId A→B、revision r1→r2、digest a…→c…，prepared.sources.single.toJson随之改变；首行 `I2 source element identity and revision stay frozen after preparation [E]`。独立MutableExclusion implements LocalExportExclusion：id n1→n2、reason no_binding→changed_reason，准备排除项随之改变；首行 `I2 exclusion element reason stays frozen after preparation [E]`。两条真实值快照断言失败，符合合法API输入，不依赖反射或修改作者产品。

三个最小回归合计0pass/3fail；完整可复制代码和复现命令见下文。临时测试仅独立worktree执行，随后删除；作者分支、产品源码、baseline均未改。Parent已请Leader A转Sonnet补修；本审查只提供证据，不修改作者分支。

## 原测试与任务逆变异

官方Flutter3.47.5 / Dart3.13.4，独立API全量268pass/0skip/0fail，strict analyze No issues found。首次本地启动因未复制根worktree原生SQLite缓存而下载被拒，未执行测试；补齐既有官方缓存后完整执行成功，不计为产品测试失败或成功用例。三个逆变异分别施加并恢复：

| 逆变异 | 真实失败第一行 / 结果 |
|---|---|
| 去掉能力缺失检查 | `capability a localExport target without the capability is refused [E]`，17pass/1fail |
| 允许localExport混网络规则 | `destination rule a local export cannot be mixed with a network rule [E]`，17pass/1fail |
| Uint8List输入不复制，仅建不可修改view | `preparation is deeply frozen a later change to the caller bytes does not reach the preparation [E]`，17pass/1fail，调用方改字节影响准备 |

变异全部编译/加载正常；恢复后18项契约测试全绿、git diff --exit-code及git status干净。旧250项与新增18项通过不否定上述未覆盖Important。

## 真实覆盖率与未执行范围

只对这次268项API全量的本地LCOV计量，**不是固定SHA八套合并测量**，不能与旧八套hit floor或whole-package百分比混比：

- API-only：36个加载文件、2022 hit / 2497 loaded DA；源库存37→38，新增local_export.dart。
- local_export.dart：44/46，遗漏58（const exclusion构造）、92（空format/MIME错误分支）；不排除、不忽略这些行。
- tool_registrar.dart：21/31，未命中14、23、33、37、62、176、189、192、199、205；API-only没有其他七套宿主消费者，不能把其21对旧八套22称为确定退化。
- 与原baseline DA指纹比较：所有原加载API文件只有实际改动tool_registrar漂移，26→31；新增local_export为46。原baseline门禁API2446/2320来自八套测量，当前局部新DA为2497；新分母与新库存确实存在，check.py的source_files/loaded_denominator严格检查会要求复测审核，不能直接接受。
- 原scripts/coverage/baseline.json逐字保留。两Important未修前不重置baseline、降要求或排除文件；不冒称已跑完整LE组合CI。修复交付后须按QUALITY-COVERAGE-current协议在最新develop固定组合跑完整八套、读源码库存/hash/逐文件DA及hit/uncovered，保留旧floor并审核实际分母，再正常集成。

非阻断建议记录：v1/v2测试名实际只构造v2；未覆盖坏manifestDigest/空format/MIME；List<int>越界值契约需定义。真实digest核算、序列化与宿主保存接线属于后续LE02/03范围，不夸称本任务完成。

结论：**需修改；LE01暂缓合入**。本发布分支仅增加审查文档，基于develop `fc9d73988ba20c2bda331614dfe8a16a83db165e`；未合develop，不携带LE01产品实现。OC15–20/WC-C的组合与合后CI均成功，但均不含LE01，不作为LE01放行证据。


## 作者复现：固定源码与预期冻结行为

实测组合11cb1de的整个`packages/muyon_module_api`目录与固定作者202e44af逐字相同（完整git diff为空），三个回归正常编译/启动，不是模块缺失、框架错误或清理超时。下面代码是原实测代码的Dart格式化版本，仅调整排版；本次文档发布不重跑全量。

预期：通过声明校验之后，调用方修改原Set不得改变声明的网络边界；冻结的准备对象应保留当时的source六字段值及exclusion id/reason，合法接口实现的后续修改不得改变准备快照。不能只让named const localExport路径安全，或删除/放宽这些负例来使其通过。具体补修设计由作者决定。

以下从已有仓库根目录执行，使用新的独立detached worktree，不切换或修改作者当前分支。需现有Flutter3.47.5/Dart3.13.4与项目所需的官方原生依赖缓存；依赖启动失败不算这三个行为断言的复现。输出包含的fixture SHA值只用于验证冻结边界，真实内容摘要计算属于后续任务。

```bash
# 先取得本审查文档并提取下面唯一的Dart代码块。
git fetch origin review/le01-blocking-reproducer-20261011
python3 - <<'PY_REPRO'
from pathlib import Path
import subprocess
review = subprocess.check_output([
    'git', 'show',
    'FETCH_HEAD:docs/reviews/2026-10-11-le01-independent-blocking-review.md',
], text=True)
code = review.split('```dart\n', 1)[1].split('\n```', 1)[0] + '\n'
Path('../le01_independent_alias_probe_test.dart').write_text(code)
PY_REPRO

git fetch origin task/le-01-local-export-contract
git worktree add --detach ../le01-reproduce 202e44afc793aba8f38d2fb4105aa6c656bbf8af
cp ../le01_independent_alias_probe_test.dart ../le01-reproduce/packages/muyon_module_api/test/le01_independent_alias_probe_test.dart
cd ../le01-reproduce
flutter pub get
cd packages/muyon_module_api
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub test/le01_independent_alias_probe_test.dart
```

预期在固定202e44af上退出码为1，0pass/3fail；补修后应三个行为断言都通过，并继续通过原契约/网络兼容测试。不要把下面有意新增的三个失败混作作者原268项的失败。

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

class MutableRef implements ObjectRef {
  @override
  String moduleId = 'research';
  @override
  String objectType = 'project';
  @override
  String objectId = 'A';
  @override
  String? nativeProjectId = 'P';
  @override
  String? revisionRef = 'r1';
  @override
  String? contentDigest = 'a' * 64;
  @override
  Map<String, Object?> toJson() => ObjectRef(
    moduleId: moduleId,
    objectType: objectType,
    objectId: objectId,
    nativeProjectId: nativeProjectId,
    revisionRef: revisionRef,
    contentDigest: contentDigest,
  ).toJson();
}

class MutableExclusion implements LocalExportExclusion {
  @override
  String id = 'n1';
  @override
  String reason = 'no_binding';
}

LocalExportPreparation prepare({
  List<ObjectRef> sources = const [],
  List<LocalExportExclusion> exclusions = const [],
}) => LocalExportPreparation(
  kind: LocalExportKind.report,
  formatVersion: 'v1',
  mimeType: 'text/plain',
  generatedAt: DateTime.utc(2026),
  bytes: [1],
  sha256: 'a' * 64,
  sources: sources,
  dedupedObjectCount: 1,
  exclusions: exclusions,
  warnings: [],
  preparationVersion: 1,
  manifestDigest: 'b' * 64,
);
void main() {
  test(
    'I1 local export cannot become a mixed network rule after construction',
    () {
      final hosts = <String>{};
      final spec = ExternalToolSpec(
        name: 'export_probe',
        description: 'd',
        effect: ToolEffect.export,
        destination: DestinationRule(localExport: true, fixedHosts: hosts),
      );
      expect(localExportRuleProblems(spec.effect, spec.destination), isEmpty);
      hosts.add('changed.example');
      expect(spec.destination.fixedHosts, isEmpty);
    },
  );
  test(
    'I2 source element identity and revision stay frozen after preparation',
    () {
      final source = MutableRef();
      final before = source.toJson();
      final prepared = prepare(sources: [source]);
      source.objectId = 'B';
      source.revisionRef = 'r2';
      source.contentDigest = 'c' * 64;
      expect(prepared.sources.single.toJson(), before);
    },
  );
  test('I2 exclusion element reason stays frozen after preparation', () {
    final exclusion = MutableExclusion();
    final prepared = prepare(exclusions: [exclusion]);
    exclusion.id = 'n2';
    exclusion.reason = 'changed_reason';
    expect(
      [prepared.exclusions.single.id, prepared.exclusions.single.reason],
      ['n1', 'no_binding'],
    );
  });
}
```

## 原实测失败摘要（已去除本机绝对路径）

```text
00:00 +0 -1: I1 local export cannot become a mixed network rule after construction [E]
Expected: empty
Actual: Set:['changed.example']

00:00 +0 -2: I2 source element identity and revision stay frozen after preparation [E]
Expected objectId/revisionRef/contentDigest: A / r1 / aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Actual objectId/revisionRef/contentDigest: B / r2 / cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
moduleId=research, objectType=project, nativeProjectId=P在两边相同。

00:00 +0 -3: I2 exclusion element reason stays frozen after preparation [E]
Expected: ['n1', 'no_binding']
Actual: ['n2', 'changed_reason']

00:00 +0 -3: Some tests failed.
```

这是从实际失败输出摘录的断言摘要，原始日志不入仓库。本发布只验证文档、代码提取、source差异与Git引用，不再执行全量或改覆盖率baseline。
