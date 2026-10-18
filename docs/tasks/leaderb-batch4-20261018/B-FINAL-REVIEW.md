# F2 正式Rust CI：独立原件重审

结论：**F2正式Rust CI范围 C0，无Critical/Important新增发现。** 本次读取并重审F2自己的927个文件，没有用F的run或A旧产物认证新source。整套merge保持draft；本报告不是最终合入授权，也不声称关闭Claude其余补证项。

固定F2 `3f1be180bb009a91e659c113ba5b1916e5360332`，tree `30ccb7d1ceda6fe66baeee0266ce961a57fd3e2e`；[CI39097184291](https://github.com/mightyoung/Muyon/actions/runs/39097184291)。completed/success、五job全steps成功由父/root API确认；本review独立审实际下载原件 `/workspace/batch4/evidence/ci/f2/downloads/{core,plugin,host,native,http}/`，未新查API/构建/改源码。

## 本次重新核验的实际内容

- 五个gate-verdict source=精确F2、tree一致、command exit0、accepted/source_inputs_unchanged true；五份source-manifest同SHA `615f5df19d0d5e42910a3a5cfd273ccf96c21725a01e6fd4e3758e01568c4437`。每份2751个tracked file hash独立逐项匹配本地clean F2。
- 每job的classifier.log实际37方法/Ran37/OK，非只信job summary。
- core115/plugin22/host59 behavior.log与verdict raw SHA相符，用F2实际full.rust combined逐group/name/status/summary重判通过；原107/22/48用例此前静态保留检查仍成立。
- core process26、wire18、harness6+7，逐方法重新分类通过，raw SHA相符。
- broad legacy17所有身份/编译/退出记录有效；physical17实际日志含RUST_WIRE_ARGS_ACK_OBSERVED、`PRETERMINAL_PHYSICAL_EFFECT`精确1!=0失败、单目标单失败、无setup timeout。没有仅凭可接受confirmation分支regex推断物理效果敏感性。
- precise legacy16各name/target/needles与F2 CONTRACTS一致，各baseline0+精确目标ok；mutant101，raw hash、清理记录及F2 exact panic source位置/语义重新判通过。旧F反向结果没有拿来替代本次执行。
- native3的三baseline/三mutant重新运行F2实际oracle；原始目标/marker/左右值/reach/计数、compile exit0、自然cleanup与raw hash均符合。source_before/source_after等于F2，fixture/host hash匹配；执行文件before/after字典相等且非空，gate所引用summary hash一致。
- HTTP7身份/目标/needles与F2 MUTANTS完全一致；每baseline0、实际target ok；每mutant101且目标FAILED和具体语义断言匹配；原始hash/无timeout/无forced cleanup/无live residual检查通过。

## Scoped integrity与限制

Full core/plugin/host分别14/7/14个baseline manifest条目，与远端binary-integrity.log同路径逐条OK、无缺项；native为自身before/after seal。CI下载没有这些已清理/未上传的Linux二进制，本review核远端执行时封存证据，未声称本地取得并重hash它们。

HTTP7仍明确outer_baseline_executables/not_recorded/verified:null，不抬升成不存在的外层baseline完整性证据；其实际编译/精确反向执行已经从新原件成立。

产物：`audit_ci_f2.py`实际运行exit0；`F2-FINAL-CI-AUDIT.json`为本次结果；`F2-FINAL-CI-RAW-SHA256.json`为本次927个原件hash索引。F的报告、audit与raw索引原样保留。

## 当前整套边界

Android PR新selector、实际producers/APK/generic CI与A exactF2全套由父/root及另一reviewer另验，不由本RustCI推断。旧F A通过、A r1环境噪声失败、初次PR selector失败均保持原source/原失败身份。

父/root转达Claude d25/2f独立审查：I01/I07的formal gate缺口由本轮对应修复与实际CI范围覆盖；I02默认并行数十次统计尚未做；I03静态双fsync事实与机制注入实验不等于写次数/时延量化数据；I04旧script状态HTTP重开推断尚待最小复现；I05真实begin后/IO中SIGKILL补证未完成。本review不将后二者未经复现的推断写成已确认产品漏洞，也不以当前绿色声称它们关闭。父/root保持draft，先ABC当前验收收尾，再有界补证/新会话交接；没有本review新增writer、改产品或改design/memory owner内容。

本次无审批拒绝，未执行commit/push/merge；CI范围通过，整套结论仍pending。
