# c804 产品构建与恢复后最小运行独审

固定生产源：`c8044174a37fdc0e4d807307f81fc56a7cc74232`，含 PR102 祖先
`4cbc9b053542dab65cf44f5bfbe98c0df49d56f6`。工作树生产源码无增量。
本阶段源码、构建、恢复后限定 smoke 及准备材料无阻断性/Important 问题；
Library 保存另有真实认证阻断，不能计为交付完成。仅写本报告，未操作设备、
修改源码、运行模型、重跑构建或调用 Library。

- 新 clean 构建日志终态成功：3m36s，78任务中77执行/1已最新，含完整主程序、
  androidTest 与 lint。已检查 native/binding 比较和签名终态，并独立重跑当前
  未修改的 package_gate.py、model_package_gate.py，均 exit0/PASS。
- 实际产品 APK 430153912字节，SHA256
  `bf54a74d7df4d0f2f48d59be7d9608d26f813b1d20494d8e7538218b49ff6841`。
  构建输出、准备目录副本及设备 installed base.apk 的记录相同。
  原始源码 androidTest APK 已恢复为
  `6ee990276d9dc2729287a883d491cd4659c61bb410dfd686f4f8e408bc4b8c3f`；
  含外部 probe 的测试 APK 独立保存，不冒充原始测试产物。
- 新运行日志有11个不同测试 status0，无失败/遗漏：Shell6、Reader合成fixture4、
  实际 Service health1，OK(11 tests)，96.77s，正常终态 code -1。
  不能把 Reader 的 synthetic host/PDF 回调计为生产 ReaderHost/授权桥接验收。
- 实际 health 日志为新 native 身份
  `c8044174a37fdc0e4d807307f81fc56a7cc74232:192689c72a496283f788e341516b179893824efef62f8bc113c220616cbbdda5`，
  synthetic=false，Service PID3468；configured=false，chat/search transport_bound=false。
  probe 仍仅调用 health、agent_availability。生产 Service verified=false 及持久化
  unavailable 门保留，未凭源码接线打开能力。无消息/搜索/推理动作被选择；这不是
  全设备网络抓包证明，也不验证模型推理、Office/Bot全流程或生产持久化权限链。

## 系统异常及运行限定

保留的启动日志明确是 com.android.systemui 与 android.process.media 的 ANR，
时间早于20:06:55的产品启动。拒收 PNG/XML 未当成交付图；不能宣称全程无 ANR、
无中断冷启动或稳定性验收，也不能据此归咎为产品 ANR。普通可见 Wait 一次后恢复，
未接受权限提示或修改安全设置。初始化后 null-root 层级读取失败亦保留；随后只读
确认真实空工作台状态，没有因不确定结果再次初始化。新菜单开关、Back 回 Launcher、
重入 Status:ok3031ms 均有原始记录。708570结果未继承为本次证据。

独立目视主页面/菜单两张新产品截图：无 ANR/权限覆盖，无虚构会话。Pillow完整解码
和原图/准备副本逐字节比较均通过，尺寸1080×1920；元数据为API26、x86_64、420dpi、
字号1.0、暗色系统主题。两图 SHA256：

- main-empty-confirmed：`5cd45dfe28a1da95268c5f049de6ab91299e2fecbd755c3e98ef018afb2982fe`
- menu-open-actual：`79a667ba49ceea72d4212e099b59cbf1b992752374aa55ead1bff63911902430`

## 准备材料及 Library 阻断

准备的许可证 ZIP 47379字节，SHA256
`dd47422ea8823d215cebd63b0f3c01a31d352e9083b65c6c414e869c02b4c878`。
独立检查其不含 APK，11份原 APK NOTICE 逐字节相等；更正来源说明已标明当前 c804。
最终小包补入 model-manifest 及 source-SHA/LFS/完整转换日志证据，自包含范围已补齐。
准备清单仅为这份新 APK、小许可证包及两张新 PNG，不包含旧708 APK或大型重复 ZIP。
这证明材料准备及资格范围，不等同于远端保存。

唯一一次 Library helper 尝试在 hosted apps tools/list 发现阶段因 HTTP401 退出；
stdout为空，无 prepare/transfer/finalize 成功返回或确认的 Library ID。
父线程明确未重试、未换直连或公开站点路线。故本次 Library 上传/保存是认证阻断，
不是成功或未知已提交结果；需有认证的执行环境/授权恢复后再决定下一动作。
本独审未重读远端、未创建上传、未配置凭据，不能宣称已外发或交付。

补充：纯证据提交3606107a7481e0040d54a2c04d2187a302ac5c22不改变固定生产源。
原始构建/运行日志的空白与进度输出引起的 diff--check 告警保留，不改原日志；
不能把此类告警计为生产源码格式缺陷，也不能笼统宣称全部证据 diffcheck 无告警。
