# Configuration runner 输入修复独审

固定源 `3a3614911dc183180686d1b68cb9367c792eeba2`，直接基线
`022389b4d1d6fbf1f1bd7eead59259774886170d`。独审通过，无阻断或Important。
完整源码diff仅原run-offline-checks.sh新增一条真实SetupDraftArchive.kt编译输入。
未改生产实现、编译参数、依赖版本、5项检查或断言；无需APK/设备/网络/上传动作。

原RED已读：exit1，确实缺SetupDraftArchive、ArchivedSetupEdits、RestoredBotSetupDraft。
这是缺编译输入的真实编译RED，不冒称运行期断言RED。原日志保留，不因修复追记为成功。

## 独立实际复跑

在该固定源码工作树运行原脚本，未替换为外部full-inputs脚本：

```sh
JAVA_HOME=/workspace/ui-shell-tools/jdk-17.0.21+9 \
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
PATH=/workspace/ui-shell-tools/jdk-17.0.21+9/bin:$PATH \
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/configuration/run-offline-checks.sh
```

独立结果 **exit0、5/5 PASS**，涵盖返回保留编辑、名称不授予权限、空白阻断前进、
unknown只查询原intent、不可用能力不被建议选中。4个Kotlin编译输入及runner共5文件运行前后SHA256一致。
原始stdout/stderr：`/workspace/ui-shell-tools/configuration-runner-20261022/INDEPENDENT-GREEN.log`；
退出码：同目录`INDEPENDENT-GREEN.exit`。bash -n及固定提交diff--check均通过。

ConfigurationChecks.kt逐字节等于基线，SHA256
`f80122817f8a32a3a28e3eb4e96c342c641bb27d306950f55aa95b50f060792d`。
修复后runner SHA256
`b158a2f243bc03a525e5f656d0368bb458f86a7409847846d8d81dff0937457f`。

另已检查父执行的相邻Bot日志：exit0、PASS17offlinechecks；这不是本人重跑的第二套测试。
本修复仅恢复原离线runner的依赖自足性，不代表新增产品功能、Android APK/设备或模型验收。
仅写本独审及授权的独立日志/退出码；未修改源码、构建APK、上传或提交。

独立raw log SHA256：`3c19ae190f1363573b4373823f96452cb482c1000bf4196b1e22ee82ce4b3177`。
