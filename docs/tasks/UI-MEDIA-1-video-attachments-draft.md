# UI-MEDIA-1 对话视频附件卡片（建议正式编号，待复核派发）

用户明确需求：消息内直接播放/暂停/拖动进度，全屏后回原消息保留播放位置，下载/另存为与真实成功/失败状态，跨重启附件引用，本地文件离线播放。原附图仅样式参考，本轮没有查看，不描述像素。独立任务，不挤掉UI4c/Agent修复；此文件不是已实现功能。

## 已查现状与依赖

基线0b64cfa；host及模块pubspec没有video_player/media_kit/chewie或视频播放器依赖，未发现现成播放器。FileGateway.freeze已有受控本地文件快照、拒符号链接、512MiB/10000文件限制；不是视频阅读/另存API。file_picker13.1.0/path_provider2.1.6已在host。KnowledgePreview当前是文档阅读，知识服务已注册文件不能直接声称支持视频。个人FoundationRepository messages有ObjectRef列表，没有视频附件元数据；设备ChatMessage/ChatBackend只有text body和文本发送，不能把设备聊天当个人会话库。

形式建议：UI-MEDIA-1独立媒体能力 + 两种会话薄适配，不新建第三会话库。首片个人助手卡片/附件持久；设备聊天适配另作UI-MEDIA-1b并复用原传输确认/去重，不能隐式新增设备媒体协议。若用户要求两者同时覆盖，仍拆两片，先稳定媒体store/player port。UI2a ArtifactRef/返回模式可复用但知识文件注册不能强行接视频；与UI4c同assistant_page必须串行，媒体服务/卡片/测试可独立准备。

## 建议文件与接口（尚未创建）

platform/message_media_store.dart：现有host文件owner下注册MediaAttachmentRef(attachmentId,ownerConversationId,ownerMessageId,contentDigest,mime,state)，持久关系及播放positionMs。真实文件在host受控目录，消息只存ref，不存任意路径/远程URL指令。使用已有DB投影或正式增量migration；版本开工重新占用，不改schema1～12。

services/media/video_playback_port.dart：统一加载受控ref、play/pause/seek/state/position/dispose；native与Web适配分开。screens/chat/video_message_card.dart、screens/video_fullscreen_page.dart：共用一个controller或host保存并接续同ref/position，全屏返回不跳到开头、不造成双音轨。个人助手adapter和设备聊天adapter必须各自使用真实owner，不让peer(messageId)串至个人conversation。

platform/media_export.dart：用户明确选目标才导出实际文件，沿已有文件/导出确认机制；成功必须有文件落盘/浏览器实际触发结果，取消/权限拒绝/缺文件/磁盘失败明确呈现，不直接把“按钮点击”叫下载成功。本地已落盘附件离线播放；移走/损坏文件显示不可用并保留消息，不删历史。

## 平台依赖门禁

先做播放器可行性只读官方支持核对+小公共样例spike：Android、macOS、Windows解码/seek/全屏生命周期分别验；Web公开样例/browser policy/CORS/下载另验。不凭Flutter跨平台推断三端支持，不选择未经核实的播放器，不安装新依赖/原生二进制。具体库、许可、原生构建链与安装范围选定后再交批准动作。

远程媒体先走现有外传/网络授权与目的地校验，禁止无授权自动fetch、redirect扩目的地、远端跟踪/上传本地视频；缓存不生成新授权，导出只处理当前已验证ref。不得绕开OutboundLedger/HostChannel/原设备确认。不自动将视频发给模型/转录服务；字幕/转码/视频理解不在首片。

## TDD与验收（未运行）

host：registered_local_video_survives_restart_and_offline、unregistered_path_ref_is_rejected、missing_or_changed_file_is_explicit；真实文件ref与owner跨重开一致。

widget：inline_play_pause_seek_updates_actual_player_state、fullscreen_returns_same_message_and_position、only_one_controller_plays_after_return、download_cancel_failure_success_are_truthful、disposed_card_releases_player_once；不用假的“isPlaying=true”界面替代真实端侧解码验收。

安全：remote_fetch_without_authority_is_blocked、redirect_destination_requires_current_authority、media_does_not_enter_model_payload_implicitly、new_peer_message_does_not_cross_owner。

公共Web：390/1440与320/200%字号/浅深色、按钮≥48、键盘焦点、实际公开视频播放/seek/全屏返回/下载；明确模拟附件owner，不公开产品视频。原生三端使用相同公共媒体并记录实际编解码容器/OS/硬件/SDK/源码SHA；支持/失败/未验矩阵逐端写，不把Web通过算Windows通过。

建议依赖顺序：UI4c准备继续；UI-MEDIA-1播放器/附件port spike与安全测试可并行；UI4c释放assistant_page后接消息卡；已有媒体core验证后UI-MEDIA-1b设备适配。最终独审、全量门禁、task分支精确CI；不自行合develop/main。

待具体决定：首批是否个人助手+设备聊天都覆盖（建议先个人、后独立设备适配）；选定播放器/原生依赖与许可后是否批准安装；可用受控Web承载和逐端设备证据。下载、全屏、离线、重启持久是已明确需求，不重复要求用户确认这些功能。
