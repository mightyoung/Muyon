# 活动入口切换与 Flutter/Dart 退役约束

只读基线：PR101 head214b4031deb38ca7dfd35ee86396089eb48157d5，develop0ab2c4f667681b9aacb017f8cd2eea6f576cf78e。
本材料只提案，未改 CI/源码/required checks，未合入或重跑。当前 legacy CI39822618984 coverage2395<2401、两文件2+4 hit减少仍是失败；产品39822618778成功不能抵消它。拒绝的coverage artifact不再下载。

用户授权新架构替代 Flutter/Dart，不要求旧数据迁移，但未授权清除用户文件。优先停止新增旧业务维护；完整旧源码、测试、oracle、失败证据需有不可变历史入口。新数据库可空，不复用旧authority/grant/receipt，不凭空推导旧Unknown成功。原两Unknown和¥0.002620不变。

新活动目标仅原生 Android+Rust，不承诺Electron生产、macOS/Windows新包或旧询价/报价全功能等价。Electron目录desktop-mock明确NOT_CONNECTED；已有core-port desktop-adapter只是受限真实Rust进程试验，不代表完整生产桌面。Android设备/实机视觉/公开Reader/Group执行/localDraft verifiedfalse及真实收费调用门槛均保留。

旧包ID com.mightyoung.muyon；新包ID com.mightyoung.muyon.product。新Service存储filesDir/muyon-product-v2/business-v2.sqlite。保持分离；切入口不卸载旧包、不删除旧库/用户目录，不改变签名承诺。

六个旧workflow是ci.yml、verify.yml、ui-preview.yml、reg4c-verification.yml、android-min26.yml、package-artifacts.yml。独立Laya四项必须从Flutter前序step抽出，保持无用户.env/凭据/网络/付费依赖；测试内临时合成env文件是fixture，不是用户配置读取。

生产Rust依赖experiments/redesign/{rust-agent-host-lab,core-agent-lab,web-search-lab}/core三个path，不得连同experiments删除。Dart oracle需固定历史源码及依赖/样本指纹，不能把历史输出冒充新模型或全部Unicode等价。Office后继只接受Rust服务/引擎，Python实验工具保历史而非生产执行器。

模型与包体不能因入口变化丢失验证：保留当前六资产集合(五model/config+生成dictionary)、固定URL/hash/size、所有许可notice、双ABI/16KiB ELF和ZIP对齐、native exactSHA和生成binding逐字节cmp、online及clean offline build+instrumentation compile+lint。当前无已授权APK发布/新增存储预算，不上传或散发含模型APK。原模型/许可声明不等于下游分发批准；未知总APK上限须明确未知，不能编造一个放行阈值。
