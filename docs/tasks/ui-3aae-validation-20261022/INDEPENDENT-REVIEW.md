# 固定3aae构建及运行独审

固定源 `3aae195c088f1b943be897efc7d874974066d79a`，生产源码零增量。
本批限定范围内无阻断性/Important问题。仅写本报告，不操作设备、不改生产、
不运行模型、不提交或上传；未继承708/c804测试结果。

- 新native两ABI、binding生成/严格cmp退出0；clean离线assembleDebug、完整
  androidTest和lint成功2m28s，78任务77执行/1已最新；normal assemble另成功17s。
  package/model/signature gates终态通过。新实际APK430153964字节，SHA256
  `2f3b67f53e25085aecce68a433b96921691d3b187813544fc761f0f55113b8bd`，
  本地实际字节和设备installed base.apk记录一致。
- 独立解析原始instrumentation输出：14唯一方法全部code0，无失败/遗漏，
  与当前实际源码方法精确对应：Shell6、Reader4、普通Service health1、Bot3。
  OK(14 tests)，185.47s，正常终态code-1。不是仅接受validator的总计数字。
- 读取validator源码：它验证匹配build身份的健康记录、类别/唯一计数、装机APK及
  4份native哈希；不能由此推导未测试业务或宿主socket身份。独立只读复核正常
  local-workspace健康记录1条、Service PID4379、synthetic=false，身份为
  `3aae195c088f1b943be897efc7d874974066d79a:060e1e61224d6ca3c14452e8e34b929faff70a31bd2b03faa892863be2dd16ef`。
  实际availability configured=false，chat/search transport_bound=false。
  4条匹配的新Bot fixture记录，其装机APK与4个native哈希全部等于本次实际APK。

## 能力及fixture边界

Bot3使用真实Service/Runtime/生成绑定/native持久化API，无FakePort或ABI stub；
但只绑定debug/non-exported的:bot_native_acceptance服务，独立workspace及
filesDir/bot-native-acceptance-fixture根，UUID会话/项目。其verified=true仅属
该debug子类；普通ProductService默认localDraftPortVerifiedForBuild=false仍保留，
无intent/wire参数开放生产门。测试只终止经health PID和精确进程名核对的fixture。
因此证明隔离fixture的真实本地保存/CAS/取消/进程丢失恢复/原attempt fencing，
不证明普通生产Service持久化门开放或真实用户工作台全流程通过。
Reader4同样仍含合成PDF/host回调，不是生产ReaderHost/PFD授权或Office全链验收。
普通health探针仅两项只读调用，未配置provider、发消息、搜索或执行推理。

## 本轮UI、失败保留及环境限制

新安装唯一session返回Success，冷启5086ms、菜单显式关闭/Back、回Launcher和
重入2768ms都有新日志。初始化点击后首null-root读取失败保留；之后只读确认状态，
没有重发初始化。四张新PNG完整Pillow解码均通过，1080×1920；已目视新主页面及
菜单，无当前ANR/权限遮罩或虚构会话。当前22:00启动不可与旧19:57系统ANR混同。
是复用模拟器上的应用进程冷启，不是新设备启动/可靠性或完整视觉验收。

新启动同AVD占用退出和原PID34777复用事实保留；真实socket到宿主PID映射仍未核实。
fd符号链接PermissionError未提权或重读，不能宣称socket-PID所有权已验证。
可选rust版本探测遗漏taskenv导致readonly/home失败，保留且未重试；不计作版本PASS，
也不替代此前正确taskenv完成的真实构建。首模型runner参数错误exit2及许可证准备
计数错误亦保留，修正own runner后实际模型验证/准备结果单独记录，不改生产门槛。

许可证小ZIP47430字节，SHA256
`7c72dec0b2d0b407a28f78bd8135952c94b32fdfba9b85072e0079f540c88f06`，
独立核对11份原APK NOTICE逐字节一致，不含APK。本批仅准备材料，无Library/
helper/Drive调用或上传；不能宣称远端保存、交付、模型推理或全部UI开发完成。

补核PR85提交022389b4相对首父仅6份Markdown，无runtime源码变化；
本APK仍明确固定3aae，未冒称由较新提交重建。此文档更新不继承或改变本批运行结果。
