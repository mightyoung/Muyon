# UI-4b planning port 接续验收

日期：2026-10-09。任务仅为 [UI-4b](UI-4b.md)，基线 `cd7dfb7f6c23802003d290b630bc7d1de0057e02`；不包含 UI-3b/UI-4a 合并、REG-4a 合并或发布。

## 接续与实现

复用既存 `/tmp/ui-4b-planning-port`、`task/ui-4b-planning-port` 的 22 个暂存文件（2368 行）；主目录和该 worktree 的未暂存 macOS xcconfig/Podfile 均保留。远端 develop 与基线一致，远端无同名任务分支/旧 CI。

统一 `UiPlanningPort`、真实宿主 request、guide metadata/空实现、自动/显式入口与去重、当前授权模型 Provider、共享 validator/renderer、三路事件及公共 fixture preview 已接入。生产默认关闭；本地小模型没有接入，不自动换模式。

## 独审与修复

独立 reviewer 对原暂存差分提出：超时子任务残留、显式规划缓存不完整回答、业务回执无法重新打开、surface/CAS 版本混淆、重规划重复预算及 CI 覆盖疑问。本轮补齐：

- 超时取消内部子任务，发送前核当前 planning 会话；重启丢失会话时拒绝发送，禁止把内部规划续跑成普通聊天。
- 无回答不缓存；最终回答变化时重新规划。完整回答相同且版本相同的自动/显式请求仍共用一次调用。
- 宿主任务事件持久记录 operation→child task；从该子任务真实 ToolRegistry 回执恢复，读取不执行动作。
- 使用 `planRevision` 表示 surface 版本，保留独立 CAS 保存计数。
- 每个规划子任务保存开始预算；后续重规划累计原任务及各子任务增量，不重置额度；存在未结束规划时拒绝新增尝试。
- `ci.yml` 本来通过 `scripts/ci.sh` 跑全宿主测试；另在 `ui-preview.yml` 增加显式宿主 planning/Store 测试步骤，方便与浏览器模拟证据区分。

全宿主回归另外暴露说明长度、禁用 planning 的事件顺序及 320px/200% 文本溢出，已修复；关闭 planning 时保留原事件流程。

Ruling：同一 task 在最终回答改变后不复用初步显式规划结果，以保证完整本次问答；代价是最终回答变化时多一次规划。重启/超时内部规划必须重新由父回答发起，不续用失效确认卡。

## 已运行证据

- 本轮实际 RED：超时任务未取消、回执恢复 unknown、最终问答未重新规划、CAS 与 plan revision 不同、累计预算、内部规划普通续跑；对应修复后已通过。原接续实现的初始 RED 历史未重新认证，不声称所有既存代码在本轮重新编写。
- planning harness/events + 实际生产授权回归：19/19；额外真实宿主关闭/重开回执恢复：1/1。
- 公共 preview：11/11。两模式同 fixture 的编辑、比较、导航、来源均通过；一次本地测量 intelligent 543μs、motivation 554μs，均无联网、成本 0。这只是 fixture 延迟，不代表真实模型效果。
- `muyon_module_api`：38/38；`muyon_ui`：253/253。
- 全 workspace `flutter analyze --no-pub`：无问题。
- `flutter build web --no-pub --release`：成功，输出 `apps/muyon_ui_preview/build/web`（不入库、未部署）。
- 全宿主串行回归：1153 通过、3 跳过；随后补充目标回归 19/19 与真实重开回执 1/1。首次并发全宿主运行曾失败：本任务事件/说明/布局回归已修复，夹具目录竞争导致的 SQLite 打开失败在串行运行消失，未把失败忽略为通过。精确提交 CI 在交付中记录。

原始测试日志只留 `/tmp/ui4b-*.log`，不入库。

## 未测与依赖

- REG-4a 尚未合并，真实 V2 询价适配联调未测；当前业务证据是已有宿主 SQLite Store qty10→12、实际确认及回执。
- 未读真实 key、未调用付费 API；在线真实模型效果和本地小模型效果均未测。
- Web 公开合成 fixture 与真实宿主测试分列；未部署受控云 URL，未声称云浏览器验收或原生/实机全部通过。原生/实机仍归 R-1-AI-UI-final。
