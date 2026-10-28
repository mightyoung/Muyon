package com.mightyoung.muyon.study

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONObject
import kotlinx.coroutines.delay

@Composable fun ScheduleScreen(state:JSONObject,dispatch:(JSONObject)->Unit,onBack:()->Unit,onPublish:()->Unit){
    val proposal=state.items("proposals").lastOrNull()
    Page("整体计划","近期28天细排，远期按周评估；考试日期保持不变",actions={TextButton(onClick=onBack){Text("返回")};Button(onClick={dispatch(planningRequest(state))}){Text("重新评估")}}){
        if(proposal!=null){
            Panel("调整建议 · 尚未生效"){
                Text(proposal.optString("reason"));Text("原安排 ${state.items("schedule").size} 段 → 建议 ${proposal.items("blocks").size} 段")
                if(proposal.optLong("baseRevision")!=state.optLong("revision"))Text("依据已变化，请重新评估",color=MaterialTheme.colorScheme.error)
                Button(onClick={dispatch(obj("op" to "confirm","id" to proposal.getString("id")))},enabled=proposal.optLong("baseRevision")==state.optLong("revision")){Text("确认应用这份建议")}
            }
            proposal.items("extensions").forEach{e->Panel("延期建议 · ${e.optString("title")}"){Text("${dateText(e.optLong("oldDue"))} → ${dateText(e.optLong("newDue"))}");Text("确认整体方案后同步更新该目标／任务日期。")}}
            proposal.items("forecast").forEach{f->Panel("目标评估 · ${f.optString("title")}"){Text(if(f.optLong("expectedFinish")>0)"预计完成 ${dateText(f.optLong("expectedFinish"))}" else "尚无法安排完成");if(f.optInt("gap")>0)Text("仍缺 ${f.optInt("gap")} 分钟",color=MaterialTheme.colorScheme.error)}}
            proposal.items("unassigned").forEach{u->Panel("时间缺口 · ${u.optString("title")}"){Text("尚缺 ${u.optInt("minutes")} 分钟：${u.optString("reason")}");if(u.optBoolean("exam"))Text("考试日期未推迟，请调整投入或学习范围。")}}
            proposal.items("minimumGaps").forEach{u->Text("最低学习量缺口：${u.optString("title")} 尚缺 ${u.optInt("minutes")} 分钟",color=MaterialTheme.colorScheme.error)}
            Text("建议安排",style=MaterialTheme.typography.titleLarge)
            proposal.items("blocks").forEach{b->Panel(b.optString("title")){Text("${dateText(b.optLong("start"))} — ${dateText(b.optLong("end")).takeLast(5)}");if(b.optBoolean("late"))Text("超过原任务截止时间，确认即接受该安排",color=MaterialTheme.colorScheme.error)}}
            if(proposal.items("stages").isNotEmpty()){Text("远期周预算",style=MaterialTheme.typography.titleLarge);proposal.items("stages").take(52).forEach{s->Text("${dateText(s.optLong("weekStart")).take(10)} 起 · ${s.optString("title")} ${s.optInt("minutes")} 分钟")};Text("远期容量包含尚未同步日历范围的估算，后续会动态核对。")}
        }
        Text("当前已确认安排",style=MaterialTheme.typography.titleLarge)
        if(state.items("schedule").isEmpty())Empty("还没有已确认安排。先新增任务并检查固定时段。")
        state.items("schedule").forEach{b->Panel(b.optString("title")){Text("${dateText(b.optLong("start"))} — ${dateText(b.optLong("end")).takeLast(5)}");TextButton(onClick={dispatch(obj("op" to "lock_block","id" to b.getString("id"),"locked" to !b.optBoolean("locked")))}){Text(if(b.optBoolean("locked"))"已锁定 · 点击解锁" else "锁定这个时段")}}}
        Row{TextButton(onClick={dispatch(obj("op" to "undo"))}){Text("撤销最近本地调整")};TextButton(onClick=onPublish){Text("发布到 Google")}}
        Text("撤销本地调整不会自动删除已经发布的外部日历事件。",style=MaterialTheme.typography.bodySmall)
    }
}

@Composable fun TodayAvailabilityDialog(settings:JSONObject,onDismiss:()->Unit,onSave:(JSONObject)->Unit){
    var date by rememberSaveable{mutableStateOf(java.time.LocalDate.now().toString())};var start by rememberSaveable{mutableStateOf("20:00")};var end by rememberSaveable{mutableStateOf("21:00")};var unavailable by rememberSaveable{mutableStateOf(false)};var error by remember{mutableStateOf("")}
    AlertDialog(onDismissRequest=onDismiss,title={Text("当天可用时间")},text={Column(verticalArrangement=Arrangement.spacedBy(8.dp)){
        Field("日期 yyyy-MM-dd",date,{date=it});Row{Checkbox(unavailable,{unavailable=it});Text("当天没有可用时间",Modifier.padding(top=12.dp))}
        if(!unavailable){Field("开始 HH:mm",start,{start=it});Field("结束 HH:mm",end,{end=it})};Text("只替换这一天的常用时段，日历忙碌仍会扣除。保存后生成调整建议。");if(error.isNotBlank())Text(error,color=MaterialTheme.colorScheme.error)
    }},confirmButton={TextButton(onClick={try{java.time.LocalDate.parse(date);if(!unavailable)require(java.time.LocalTime.parse(end)>java.time.LocalTime.parse(start));val all=JSONArray();settings.items("overrides").filter{it.optString("date")!=date}.forEach{all.put(it)};all.put(obj("date" to date,"start" to start,"end" to end,"unavailable" to unavailable));onSave(JSONObject(settings.toString()).put("overrides",all))}catch(_:Exception){error="日期或时间格式有误"}}){Text("保存并评估")}},dismissButton={TextButton(onClick=onDismiss){Text("取消")}})
}
@Composable fun TaskDetail(t:JSONObject,state:JSONObject,onDismiss:()->Unit,onEdit:()->Unit,onDone:()->Unit,onLink:()->Unit,onProgress:(JSONObject)->Unit,onDelete:()->Unit,onOpen:(JSONObject)->Unit){
    var remaining by remember(t.toString()){mutableStateOf(t.optInt("remaining",t.optInt("minutes",30)).toString())}
    AlertDialog(onDismissRequest=onDismiss,title={Text(t.optString("title"))},text={Column(Modifier.heightIn(max=460.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(10.dp)){
        Text(taskSubtitle(t));Text(t.optString("notes"));if(t.optString("location").isNotBlank())Text("地点／工具：${t.optString("location")}")
        Field("实际剩余分钟",remaining,{remaining=it})
        TextButton(onClick={remaining.toIntOrNull()?.takeIf{it>=0}?.let{onProgress(JSONObject(t.toString()).put("remaining",it).put("status",if(it==0)"done" else "doing"))}}){Text("更新进度")}
        t.optJSONArray("resources")?.objects()?.forEach{link->val r=state.items("resources").find{it.optString("id")==link.optString("id")};if(r!=null){TextButton(onClick={onOpen(r)}){Text("打开 ${r.optString("title")}")};Text(link.optString("note"))}else Text("关联资源已删除")}
        val deps=t.optJSONArray("depends");if(deps!=null&&deps.length()>0)Text("前置："+(0 until deps.length()).map{val id=deps.optString(it);state.items("tasks").find{it.optString("id")==id}?.optString("title")?:"已删除任务"}.joinToString("、"))
        TextButton(onClick=onLink){Text("关联资源与前置任务")};TextButton(onClick=onEdit){Text("编辑任务")};TextButton(onClick=onDelete){Text("删除任务")}
    }},confirmButton={TextButton(onClick=onDone){Text(if(t.optString("status")=="done")"重新打开" else "标记完成")}},dismissButton={TextButton(onClick=onDismiss){Text("关闭")}})
}
@Composable fun TaskLinks(task:JSONObject,state:JSONObject,onDismiss:()->Unit,onSave:(JSONObject)->Unit){
    val selected=remember{mutableStateMapOf<String,Boolean>().also{m->task.optJSONArray("resources")?.objects()?.forEach{m[it.optString("id")]=true}}}
    val notes=remember{mutableStateMapOf<String,String>().also{m->task.optJSONArray("resources")?.objects()?.forEach{m[it.optString("id")]=it.optString("note")}}}
    val deps=remember{mutableStateMapOf<String,Boolean>().also{m->task.optJSONArray("depends")?.let{a->repeat(a.length()){m[a.optString(it)]=true}}}}
    AlertDialog(onDismissRequest=onDismiss,title={Text("资源与前置步骤")},text={Column(Modifier.heightIn(max=480.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)){
        Text("学习资源",style=MaterialTheme.typography.titleMedium)
        state.items("resources").forEach{r->val id=r.getString("id");Row(Modifier.clickable{selected[id]=selected[id]!=true}){Checkbox(selected[id]==true,{selected[id]=it});Text(r.optString("title"),Modifier.padding(top=12.dp))};if(selected[id]==true)Field("本任务的页码／章节／操作要求",notes[id].orEmpty(),{notes[id]=it})}
        if(state.items("resources").isEmpty())Text("先在学习资源中上传文件或添加视频链接。")
        Text("前置任务",style=MaterialTheme.typography.titleMedium)
        state.items("tasks").filter{it.optString("id")!=task.optString("id")}.forEach{t->val id=t.getString("id");Row{Checkbox(deps[id]==true,{deps[id]=it});Text(t.optString("title"),Modifier.padding(top=12.dp))}}
    }},confirmButton={TextButton(onClick={val resources=JSONArray();selected.filterValues{it}.forEach{(id,_)->resources.put(obj("id" to id,"note" to notes[id].orEmpty()))};val dependencies=JSONArray(deps.filterValues{it}.keys.toList());onSave(JSONObject(task.toString()).put("resources",resources).put("depends",dependencies))}){Text("保存关联")}},dismissButton={TextButton(onClick=onDismiss){Text("取消")}})
}
@Composable fun AttemptScreen(attempt:JSONObject,state:JSONObject,dispatch:(JSONObject)->Unit,onAi:(String,String?)->Unit,onBack:()->Unit,wrongOnly:Boolean=false){
    val paper=state.items("papers").find{it.optString("id")==attempt.optString("paper")}
    if(paper==null){Page("题包缺失",actions={TextButton(onClick=onBack){Text("返回")}}){Empty("原题包不存在，作答记录仍保留。")};return}
    val all=paper.items("sections").flatMap{it.items("questions")}
    val wrong=attempt.optJSONObject("result")?.optJSONArray("wrong")
    val qs=if(wrongOnly)all.filter{q->wrong!=null&&(0 until wrong.length()).any{wrong.optString(it)==q.optString("id")}}else all
    var index by rememberSaveable(attempt.optString("id"),wrongOnly){mutableIntStateOf((if(wrongOnly)0 else attempt.optInt("index")).coerceIn(0,(qs.size-1).coerceAtLeast(0)))}
    var now by remember{mutableLongStateOf(System.currentTimeMillis())}
    val active=attempt.optString("status")=="active"
    LaunchedEffect(attempt.optString("id"),active){while(active){delay(1000);now=System.currentTimeMillis();if(attempt.optLong("deadline")>0&&now>=attempt.optLong("deadline")){dispatch(obj("op" to "submit","attempt" to attempt.getString("id"),"now" to now));break}}}
    Page(paper.optString("shortTitle",paper.optString("title")),"${index+1} / ${qs.size} 题 · ${if(active)"作答自动保存" else "已交卷"}",actions={TextButton(onClick=onBack){Text("返回")};if(active)TextButton(onClick={dispatch(obj("op" to "submit","attempt" to attempt.getString("id"),"now" to now))}){Text("交卷")}}){
        if(attempt.optLong("deadline")>0&&active)Text("剩余 ${((attempt.optLong("deadline")-now).coerceAtLeast(0)/1000)/60} 分钟 · 退出后继续计时",color=MaterialTheme.colorScheme.primary)
        if(!active){Panel("本次结果"){Text(resultText(attempt.optJSONObject("result")));TextButton(onClick={onAi("请按题目与实际作答提供AI辅助点评；未提供标准答案时明确不确定，不虚构标准分。题目：${paper.toString().take(14000)}\n作答：${attempt.optJSONObject("answers")}",attempt.getString("id"))}){Text("请求 AI 辅助点评")}}
            attempt.optJSONObject("commentary")?.let{Panel("AI 辅助评价"){Text(it.optString("text"))}}
        }
        if(qs.isEmpty())Empty("该题包仅有参考材料，没有可作答题目。")
        else{val q=qs[index];val qid=q.getString("id")
            key(attempt.optString("id"),qid){
                var answer by rememberSaveable{mutableStateOf(attempt.optJSONObject("answers")?.optString(qid).orEmpty())}
                fun save(s:String){answer=s;dispatch(obj("op" to "answer","attempt" to attempt.getString("id"),"question" to qid,"value" to s,"index" to index,"now" to System.currentTimeMillis()))}
                if(q.optString("passage").isNotBlank())Panel("阅读材料"){Text(q.optString("passage"))}
                Panel("第 ${q.optString("label",(index+1).toString())} 题"){Text(q.optString("stem"));if(q.optString("promptNote").isNotBlank())Text(q.optString("promptNote"))
                    if(q.optString("type") in listOf("choice","multiple","boolean"))q.items("options").forEach{o->val letter=o.optString("key");Row(Modifier.fillMaxWidth().then(if(active)Modifier.clickable{save(if(q.optString("type")=="multiple"){if(answer.contains(letter))answer.replace(letter,"")else answer+letter}else letter)}else Modifier)){
                        RadioButton(answer.contains(letter),onClick=if(active)({save(if(q.optString("type")=="multiple"){if(answer.contains(letter))answer.replace(letter,"")else answer+letter}else letter)})else null);Text("$letter. ${o.optString("text")}",Modifier.padding(top=12.dp))
                    }}else OutlinedTextField(answer,{save(it)},label={Text("我的作答")},minLines=5,readOnly=!active,modifier=Modifier.fillMaxWidth())
                    if(!active){Text("我的答案：${answer.ifBlank{"未作答"}}");Text("标准答案：${q.optString("answer",q.optString("correctAnswer","未提供"))}");if(q.optString("explanation").isNotBlank())Text("解析：${q.optString("explanation")}")}
                }
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween){TextButton(onClick={index--;if(active)dispatch(obj("op" to "attempt_position","attempt" to attempt.getString("id"),"index" to index))},enabled=index>0){Text("上一题")};TextButton(onClick={index++;if(active)dispatch(obj("op" to "attempt_position","attempt" to attempt.getString("id"),"index" to index))},enabled=index<qs.lastIndex){Text("下一题")}}
            }
        }
        paper.items("sections").filter{it.optString("kind")=="reference"}.forEach{s->Panel(s.optString("title","参考材料")){Text(s.optString("referenceText"))}}
    }
}
@Composable fun SettingsScreen(settings:JSONObject,state:JSONObject,onImport:(String)->Unit,onExport:()->Unit,onGoogle:()->Unit,onMaimemo:()->Unit,onPublish:()->Unit,onDriveBackup:()->Unit,onDriveFiles:()->Unit,onKey:(String)->Unit,onWindows:()->Unit,onDark:()->Unit){
    val context=androidx.compose.ui.platform.LocalContext.current
    var settingNotice by remember{mutableStateOf("")}
    Page("我的","本地优先 · 连接与数据由你掌握"){
        if(settingNotice.isNotBlank())Text(settingNotice)
        Panel("学习安排"){TextButton(onClick=onWindows){Text("每周固定时段与每日上限")};TextButton(onClick=onDark){Text(if(settings.optBoolean("dark"))"切换浅色" else "切换深色")};TextButton(onClick={context.startActivity(android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE,context.packageName))}){Text("到期提醒通知设置")}}
        Panel("Google Calendar 与云盘"){
            Text("读取账号全部可访问日历的近期事件；网络失败保留缓存。Google 登录需要配置本应用包名与签名对应的 OAuth 客户端。",style=MaterialTheme.typography.bodySmall)
            TextButton(onClick=onGoogle){Text("连接／刷新全部日历")};TextButton(onClick=onPublish){Text("发布已确认时间块")}
            TextButton(onClick=onDriveFiles){Text("查看已授权云盘文件")};TextButton(onClick=onDriveBackup){Text("备份到 Google Drive")}
            state.optJSONObject("sync")?.optJSONObject("calendar")?.let{Text("日历更新：${dateText(it.optLong("at"))} · ${it.optString("status")}");if(it.optString("error").isNotBlank())Text(it.optString("error"),color=MaterialTheme.colorScheme.error)}
            TextButton(onClick={com.mightyoung.muyon.study.adapters.BackgroundSync.disable(context);settingNotice="已关闭后台读取；手动同步仍可使用。"}){Text("关闭后台同步")}
        }
        Panel("墨墨背单词"){
            TextButton(onClick={onKey("maimemo")}){Text("配置墨墨 API Token")};TextButton(onClick=onMaimemo){Text("同步今日进度")}
            Text("需在墨墨开启自动同步并当日打开 App；失败不视为未完成。",style=MaterialTheme.typography.bodySmall)
            state.optJSONObject("sync")?.optJSONObject("maimemo")?.let{Text("${dateText(it.optLong("at"))} · ${it.optString("status")}");if(it.optString("error").isNotBlank())Text(it.optString("error"),color=MaterialTheme.colorScheme.error)}
        }
        Panel("智能驱动与语音"){
            TextButton(onClick={onKey("deepseek")}){Text("配置 DeepSeek API Key")};TextButton(onClick={onKey("model")}){Text("配置模型名称")}
            Text("中文语音模型已随安装包内置。识别在本机；AI 整理与点评会发送你主动选择的文字。",style=MaterialTheme.typography.bodySmall)
        }
        Panel("备份与恢复"){TextButton(onClick=onExport){Text("导出完整备份 ZIP")};TextButton(onClick={onImport("restore")}){Text("恢复本地备份")};Text("备份含上传附件和作答记录，不含账号密钥。",style=MaterialTheme.typography.bodySmall)}
        Panel("关于"){Text("木易学习 1.0 · Muyon 本地学习与项目执行");Text("提醒仅用于到期事项。系统通知权限、省电策略和设备重启会影响投递，需在手机上检查。",style=MaterialTheme.typography.bodySmall)}
    }
}
@Composable fun KeyDialog(name:String,onDismiss:()->Unit,onSave:(String)->Unit){var value by rememberSaveable{mutableStateOf("")};AlertDialog(onDismissRequest=onDismiss,title={Text(if(name=="model")"模型名称" else "配置凭据")},text={Column{Text("留空保存会清除该项。密钥不写入备份或日志。");OutlinedTextField(value,{value=it},label={Text(if(name=="model")"例如 deepseek-chat" else "粘贴 API Key／Token")},visualTransformation=if(name=="model")androidx.compose.ui.text.input.VisualTransformation.None else PasswordVisualTransformation(),modifier=Modifier.fillMaxWidth())}},confirmButton={TextButton(onClick={onSave(value.trim())}){Text("保存")}},dismissButton={TextButton(onClick=onDismiss){Text("取消")}})}
@Composable fun WindowsDialog(settings:JSONObject,onDismiss:()->Unit,onSave:(JSONObject)->Unit){
    val old=settings.items("windows");var weekdayStart by rememberSaveable{mutableStateOf(old.getOrNull(0)?.optString("start")?:"20:00")};var weekdayEnd by rememberSaveable{mutableStateOf(old.getOrNull(0)?.optString("end")?:"22:00")}
    var weekendStart by rememberSaveable{mutableStateOf(old.getOrNull(1)?.optString("start")?:"14:00")};var weekendEnd by rememberSaveable{mutableStateOf(old.getOrNull(1)?.optString("end")?:"18:00")};var max by rememberSaveable{mutableStateOf(settings.optInt("dailyMax",240).toString())};var error by remember{mutableStateOf("")}
    AlertDialog(onDismissRequest=onDismiss,title={Text("固定可用时段")},text={Column(Modifier.heightIn(max=420.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)){
        Text("作为优先安排时段，日历忙碌时间会被扣除。时间采用24小时制。")
        Field("周一至周五开始 HH:mm",weekdayStart,{weekdayStart=it});Field("周一至周五结束 HH:mm",weekdayEnd,{weekdayEnd=it});Field("周末开始 HH:mm",weekendStart,{weekendStart=it});Field("周末结束 HH:mm",weekendEnd,{weekendEnd=it});Field("每日最多安排分钟",max,{max=it});if(error.isNotBlank())Text(error,color=MaterialTheme.colorScheme.error)
    }},confirmButton={TextButton(onClick={try{require(java.time.LocalTime.parse(weekdayEnd)>java.time.LocalTime.parse(weekdayStart));require(java.time.LocalTime.parse(weekendEnd)>java.time.LocalTime.parse(weekendStart));val n=max.toInt();require(n in 15..1440);val windows=JSONArray().put(obj("days" to JSONArray(listOf(1,2,3,4,5)),"start" to weekdayStart,"end" to weekdayEnd)).put(obj("days" to JSONArray(listOf(6,7)),"start" to weekendStart,"end" to weekendEnd));onSave(JSONObject(settings.toString()).put("windows",windows).put("dailyMax",n))}catch(_:Exception){error="请检查时间先后与每日分钟（15—1440）"}}){Text("保存")}},dismissButton={TextButton(onClick=onDismiss){Text("取消")}})
}
