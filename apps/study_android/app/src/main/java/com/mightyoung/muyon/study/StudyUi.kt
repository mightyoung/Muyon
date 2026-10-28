package com.mightyoung.muyon.study

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

@OptIn(ExperimentalLayoutApi::class)
@Composable fun StudyUi(
    state:JSONObject,notice:String,busy:Boolean,voiceText:String?,dispatch:(JSONObject)->Unit,onNotice:(String)->Unit,
    onImport:(String)->Unit,onExport:()->Unit,onVoice:()->Unit,onVoiceDismiss:()->Unit,onMaimemo:()->Unit,
    onGoogle:()->Unit,onPublish:()->Unit,onDriveBackup:()->Unit,onDriveFiles:()->Unit,onDriveSelect:(JSONObject)->Unit,
    onAi:(String,String?)->Unit,onLoadSample:()->Unit,onSaveKey:(String,String)->Unit,
    preview:JSONObject?,onDismissPreview:()->Unit,onConfirmPreview:()->Unit
){
    val context=LocalContext.current
    var tab by rememberSaveable{mutableIntStateOf(0)}
    var section by rememberSaveable{mutableIntStateOf(0)}
    var edit by remember{mutableStateOf<Pair<String,JSONObject>?>(null)}
    var detail by remember{mutableStateOf<String?>(null)}
    var project by rememberSaveable{mutableStateOf<String?>(null)}
    var goal by rememberSaveable{mutableStateOf("")}
    var showSchedule by rememberSaveable{mutableStateOf(false)}
    var attemptId by rememberSaveable{mutableStateOf<String?>(null)}
    var wrongOnly by rememberSaveable{mutableStateOf(false)}
    var input by rememberSaveable{mutableStateOf("")}
    var keyEditor by remember{mutableStateOf<String?>(null)}
    var showWindows by remember{mutableStateOf(false)}
    var showTodayAvailability by remember{mutableStateOf(false)}
    var publishConfirm by remember{mutableStateOf(false)}
    var linkTask by remember{mutableStateOf<JSONObject?>(null)}
    var confirmDelete by remember{mutableStateOf<Pair<String,String>?>(null)}
    fun save(kind:String,value:JSONObject){dispatch(obj("op" to "upsert","kind" to kind,"value" to value));edit=null}
    fun done(t:JSONObject){val x=JSONObject(t.toString());val wasDone=x.optString("status")=="done";x.put("status",if(wasDone)"todo" else "done");x.put("remaining",if(wasDone)x.optInt("minutes",30)else 0);save("tasks",x)}
    val tasks=state.items("tasks")
    val settings=state.optJSONObject("settings")?:JSONObject()
    val dark=settings.optBoolean("dark",false)
    StudyTheme(dark){Scaffold(bottomBar={NavigationBar(containerColor=MaterialTheme.colorScheme.surface){
        listOf("今天","学习","项目","收件箱","我的").forEachIndexed{i,label->NavigationBarItem(colors=NavigationBarItemDefaults.colors(selectedIconColor=MaterialTheme.colorScheme.primary,selectedTextColor=MaterialTheme.colorScheme.primary,indicatorColor=MaterialTheme.colorScheme.secondaryContainer),selected=tab==i,onClick={tab=i;showSchedule=false;attemptId=null},icon={GeneratedIcon(listOf(R.drawable.gpt_today,R.drawable.gpt_learning,R.drawable.gpt_projects,R.drawable.gpt_inbox,R.drawable.gpt_profile)[i],null)},label={Text(label)})}
    }}){padding->Column(Modifier.padding(padding).fillMaxSize()){
        if(busy)LinearProgressIndicator(Modifier.fillMaxWidth())
        Text(notice,Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=6.dp),style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        val activeAttempt=state.items("attempts").find{it.optString("id")==attemptId}
        when{
            activeAttempt!=null->AttemptScreen(activeAttempt,state,dispatch,onAi,onBack={attemptId=null;wrongOnly=false},wrongOnly=wrongOnly)
            showSchedule->ScheduleScreen(state,dispatch,onBack={showSchedule=false},onPublish={publishConfirm=true})
            tab==0->Page("今天",LocalDate.now().toString(),actions={Button(onClick={edit="tasks" to obj("minutes" to 30,"priority" to 3,"status" to "todo","category" to "work")}){ActionLabel(R.drawable.gpt_add,"待办")};OutlinedButton(onClick={showSchedule=true}){Text("整体计划")};TextButton(onClick=onVoice){ActionLabel(R.drawable.gpt_voice,"语音")}}){
                val due=tasks.count{it.optString("status")!="done"&&it.optLong("due") in 1..(System.currentTimeMillis()+86400000)}
                Panel("今日概览"){Text("${tasks.count{it.optString("status")!="done"}} 项待办 · $due 项临近或已经到期");Text("按固定时段安排，变化先建议、确认后生效。",style=MaterialTheme.typography.bodySmall)}
                Row{TextButton(onClick={showTodayAvailability=true}){Text("调整今日空闲")};if(state.items("proposals").isNotEmpty())TextButton(onClick={showSchedule=true}){Text("查看待确认调整")}}
                val now=System.currentTimeMillis();val end=LocalDate.now().plusDays(1).atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
                val blocks=state.items("schedule").filter{it.optLong("end")>now&&it.optLong("start")<end}
                blocks.forEach{b->Panel(b.optString("title"),onClick={detail=b.optString("task")}){Text("${dateText(b.optLong("start"))} — ${dateText(b.optLong("end")).takeLast(5)}");Text("计划时间不代表已经完成",style=MaterialTheme.typography.bodySmall)}}
                if(blocks.isEmpty())Empty("今天尚无已确认安排。进入整体计划生成建议。")
                state.items("calendar").filter{it.optLong("end")>now&&it.optLong("start")<end}.sortedBy{it.optLong("start")}.forEach{e->Panel("日历 · ${e.optString("title")}"){Text("${dateText(e.optLong("start"))} · ${e.optString("name")}");Text(if(e.optBoolean("free"))"空闲事件" else "占用时间",style=MaterialTheme.typography.bodySmall)}}
                Text("待办事项",style=MaterialTheme.typography.titleLarge)
                tasks.filter{it.optString("status")!="done"}.sortedWith(compareBy<JSONObject>{it.optLong("due",Long.MAX_VALUE)}.thenBy{it.optInt("priority",3)}).forEach{t->TaskCard(t,{detail=t.getString("id")},{done(t)})}
                if(tasks.isEmpty())Empty("从一个待办、学习计划或语音输入开始。")
                state.optJSONObject("sync")?.optJSONObject("maimemo")?.let{m->Panel("墨墨背单词"){val p=m.optJSONObject("progress");Text("${p?.optInt("finished")?:0} / ${p?.optInt("total")?:0} 词 · ${dateText(m.optLong("at"))}");Text("显示上次同步数据，未打开墨墨初始化时可能不完整。",style=MaterialTheme.typography.bodySmall)}}
            }
            tab==1->Page("学习","目标、内容与实际进度分别记录",actions={TextButton(onClick={onImport("plan")}){ActionLabel(R.drawable.gpt_import,"导入计划")};TextButton(onClick={edit="goals" to obj("priority" to 3,"minimum" to 15)}){ActionLabel(R.drawable.gpt_add,"目标")}}){
                ScrollableTabRow(selectedTabIndex=section){listOf("任务","目标","资源","练习","错题").forEachIndexed{i,s->Tab(selected=section==i,onClick={section=i},text={Text(s)})}}
                when(section){
                    0->{Choice("目标筛选",listOf("" to "全部")+state.items("goals").map{it.getString("id") to it.optString("title")},goal){goal=it}
                        Button(onClick={edit="tasks" to obj("goal" to goal,"category" to "study","minutes" to 30,"priority" to 3,"status" to "todo")}){Text("新增学习任务")}
                        tasks.filter{goal.isBlank()||it.optString("goal")==goal}.forEach{t->TaskCard(t,{detail=t.getString("id")},{done(t)})}
                    }
                    1->{state.items("goals").forEach{g->val own=tasks.filter{it.optString("goal")==g.optString("id")};Panel(g.optString("title"),onClick={edit="goals" to g}){
                        Text("优先级 ${g.optInt("priority",3)} · ${if(g.optBoolean("exam"))"考试日期固定" else "目标日期可建议延期"}")
                        Text("${own.count{it.optString("status")=="done"}} / ${own.size} 项已完成 · 最低学习 ${g.optInt("minimum")} 分钟/天")
                        if(g.optLong("due")>0)Text(dateText(g.optLong("due")))
                        Text(g.optString("notes"));TextButton(onClick={goal=g.optString("id");section=0}){Text("查看任务")}
                        TextButton(onClick={val x=JSONObject(g.toString()).put("status",if(g.optString("status")=="paused")"active" else "paused");save("goals",x)}){Text(if(g.optString("status")=="paused")"恢复目标" else "暂停目标")}
                    }};if(state.items("goals").isEmpty())Empty("新增考试、课程或技能目标，再关联任务与资源。")}
                    2->{Row{Button(onClick={onImport("resource")}){ActionLabel(R.drawable.gpt_import,"上传资料／例程")};TextButton(onClick={edit="resources" to obj("type" to "video")}){ActionLabel(R.drawable.gpt_add,"视频链接")}}
                        state.items("resources").forEach{r->Panel(r.optString("title")){
                            Text(if(r.optString("type")=="video")r.optString("url") else "本地资源 · ${r.optLong("size")/1024} KB")
                            Text(r.optString("notes"));Text("关联 ${tasks.count{t->t.optJSONArray("resources")?.objects()?.any{it.optString("id")==r.optString("id")}==true}} 个任务",style=MaterialTheme.typography.bodySmall)
                            Row{TextButton(onClick={try{StudyFiles.openResource(context,r)}catch(e:Exception){onNotice(e.message?:"没有可用的文件查看器")}}){Text("打开")};TextButton(onClick={edit="resources" to r}){Text("编辑")};TextButton(onClick={confirmDelete="resources" to r.getString("id")}){Text("删除")}}
                        }};if(state.items("resources").isEmpty())Empty("上传教材或例程，或添加视频链接。")}
                    3->{Row{Button(onClick={onImport("paper")}){Text("导入题包")};TextButton(onClick=onLoadSample){Text("载入附件一")}}
                        state.items("attempts").filter{it.optString("status")=="active"}.forEach{a->Panel("继续练习",onClick={attemptId=a.getString("id")}){Text("${a.optString("mode")} · 第 ${a.optInt("index")+1} 题")}}
                        state.items("papers").forEach{p->Panel(p.optString("title")){
                            val count=p.items("sections").sumOf{it.optJSONArray("questions")?.length()?:0};Text("$count 题 · ${p.optString("subtitle")}")
                            Row{Button(onClick={dispatch(obj("op" to "start_attempt","paper" to p.getString("id"),"mode" to "practice","now" to System.currentTimeMillis()))}){Text("练习")};TextButton(onClick={dispatch(obj("op" to "start_attempt","paper" to p.getString("id"),"mode" to "exam","now" to System.currentTimeMillis()))}){Text("模拟考试")}}
                        }}
                        state.items("attempts").filter{it.optString("status")=="submitted"}.reversed().forEach{a->Panel("已交卷 · ${state.items("papers").find{it["id"]==a["paper"]}?.optString("title")}",onClick={attemptId=a.getString("id")}){Text(resultText(a.optJSONObject("result")))}}
                    }
                    4->{val wrong=state.items("attempts").filter{it.optJSONObject("result")?.optJSONArray("wrong")?.length()?.let{n->n>0}==true};if(wrong.isEmpty())Empty("有标准答案的练习交卷后，错题会出现在这里。")
                        wrong.forEach{a->Panel("错题复习",onClick={attemptId=a.getString("id");wrongOnly=true}){Text(resultText(a.optJSONObject("result")));Text("只查看本次错题、答案与解析")}}
                    }
                }
            }
            tab==2->{val p=state.items("projects").find{it.optString("id")==project}
                Page(p?.optString("title")?:"动手项目",p?.optString("notes")?:"物料、步骤与制作过程放在一起",actions={if(p==null)Button(onClick={edit="projects" to JSONObject()}){ActionLabel(R.drawable.gpt_add,"项目")}else{TextButton(onClick={project=null}){Text("返回")};TextButton(onClick={edit="projects" to p}){Text("编辑项目")}}}){
                    if(p==null){state.items("projects").forEach{item->Panel(item.optString("title"),onClick={project=item.getString("id")}){Text(item.optString("notes"));Text("${state.items("bom").count{it.optString("project")==item.optString("id")}} 项物料 · ${tasks.count{it.optString("project")==item.optString("id")}} 个步骤")}};if(state.items("projects").isEmpty())Empty("从一个你想做的小东西开始。")}
                    else{
                        FlowRow{Button(onClick={edit="tasks" to obj("project" to project,"category" to "diy","minutes" to 45,"status" to "todo")}){ActionLabel(R.drawable.gpt_add,"制作步骤")};TextButton(onClick={edit="bom" to obj("project" to project,"quantity" to 1,"price" to 0,"status" to "unordered")}){ActionLabel(R.drawable.gpt_add,"物料")};TextButton(onClick={edit="versions" to obj("project" to project)}){ActionLabel(R.drawable.gpt_add,"版本")}}
                        Text("制作步骤",style=MaterialTheme.typography.titleLarge);tasks.filter{it.optString("project")==project}.forEach{t->TaskCard(t,{detail=t.getString("id")},{done(t)})}
                        Text("BOM 与采购",style=MaterialTheme.typography.titleLarge)
                        state.items("bom").filter{it.optString("project")==project}.forEach{b->Panel(b.optString("title"),onClick={edit="bom" to b}){Text("${b.optString("spec")} × ${b.optInt("quantity",1)} · ¥${b.optDouble("price",0.0)}");Text(statusName(b.optString("status")));Text(b.optString("notes"))}}
                        Text("版本与制作记录",style=MaterialTheme.typography.titleLarge)
                        state.items("versions").filter{it.optString("project")==project}.forEach{r->Panel(r.optString("title"),onClick={edit="versions" to r}){Text(r.optString("notes"))}}
                    }
                }
            }
            tab==3->Page("收件箱","零碎输入先保存，计划修改先确认",actions={OutlinedButton(onClick=onVoice){Text("离线语音")}}){
                Field("今天要做什么，或刚刚完成了什么",input,{input=it},4)
                Row{Button(onClick={if(input.isNotBlank()){save("inbox",obj("id" to newId(),"text" to input,"created" to System.currentTimeMillis(),"status" to "unprocessed"));input=""}}){Text("保存输入")};TextButton(onClick={if(input.isNotBlank())onAi("北京时间 ${dateText(System.currentTimeMillis())}。请将以下输入整理为待确认任务；若是进度、困难或想法则说明而不虚构新任务：\n$input",null)}){Text("AI 整理建议")}}
                state.items("inbox").reversed().forEach{i->Panel(if(i.optString("status")=="processed")"已处理" else "待整理"){
                    Text(i.optString("text"));Row{TextButton(onClick={edit="tasks" to obj("title" to i.optString("text"),"minutes" to 30,"status" to "todo","sourceInput" to i.optString("id"))}){Text("转为任务")};TextButton(onClick={onAi("当前时间 ${dateText(System.currentTimeMillis())}。整理为待确认任务或说明进度含义：${i.optString("text")}",null)}){Text("AI 整理")};TextButton(onClick={save("inbox",JSONObject(i.toString()).put("status","processed"))}){Text("已处理")}}
                }}
            }
            else->SettingsScreen(settings,state,onImport,onExport,onGoogle,onMaimemo,onPublish={publishConfirm=true},onDriveBackup,onDriveFiles,
                onKey={keyEditor=it},onWindows={showWindows=true},onDark={dispatch(obj("op" to "settings","value" to JSONObject(settings.toString()).put("dark",!dark)))})
        }
        if(edit!=null){val(kind,value)=edit!!;val fields=editorFields(kind);val options=editorOptions(kind,state)
            Editor(when(kind){"tasks"->"编辑任务";"goals"->"学习目标";"resources"->"学习资源";"bom"->"物料与采购";"versions"->"版本／制作记录";else->"项目"},fields,value,options,onDismiss={edit=null},onSave={save(kind,it)})}
        val t=tasks.find{it.optString("id")==detail}
        if(t!=null)TaskDetail(t,state,onDismiss={detail=null},onEdit={edit="tasks" to t;detail=null},onDone={done(t)},onLink={linkTask=t;detail=null},onProgress={value->save("tasks",value)},onDelete={confirmDelete="tasks" to t.getString("id");detail=null},onOpen={r->try{StudyFiles.openResource(context,r)}catch(e:Exception){onNotice(e.message?:"无法打开")}})
        linkTask?.let{t->TaskLinks(t,state,onDismiss={linkTask=null},onSave={save("tasks",it);linkTask=null})}
        keyEditor?.let{name->KeyDialog(name,onDismiss={keyEditor=null},onSave={onSaveKey(name,it);keyEditor=null})}
        if(showWindows)WindowsDialog(settings,onDismiss={showWindows=false},onSave={dispatch(obj("op" to "settings","value" to it));showWindows=false})
        if(showTodayAvailability)TodayAvailabilityDialog(settings,onDismiss={showTodayAvailability=false},onSave={dispatch(obj("op" to "settings","value" to it));showTodayAvailability=false})
        if(publishConfirm)AlertDialog(onDismissRequest={publishConfirm=false},title={Text("发布已确认安排到 Google")},text={Text("将当前已确认的时间块发布到应用专用日历，并删除由本应用创建、未经手动修改的旧时间块。手动修改或发生冲突的事件会保留并报告。")},confirmButton={TextButton(onClick={publishConfirm=false;onPublish()}){Text("确认发布")}},dismissButton={TextButton(onClick={publishConfirm=false}){Text("取消")}})
        confirmDelete?.let{(kind,id)->AlertDialog(onDismissRequest={confirmDelete=null},title={Text("确认删除")},text={Text("删除本地条目；已有历史记录保留。")},confirmButton={TextButton(onClick={dispatch(obj("op" to "delete","kind" to kind,"id" to id));confirmDelete=null}){Text("删除")}},dismissButton={TextButton(onClick={confirmDelete=null}){Text("取消")}})}
        if(voiceText!=null){var transcript by remember(voiceText){mutableStateOf(voiceText)};AlertDialog(onDismissRequest=onVoiceDismiss,title={Text("离线中文语音")},text={Column{Text("按下后识别；确认文字再保存，录音不上传。");Field("识别结果，可修改",transcript.orEmpty(),{transcript=it},4)}},confirmButton={TextButton(onClick={if(!transcript.isNullOrBlank())save("inbox",obj("id" to newId(),"text" to transcript,"created" to System.currentTimeMillis(),"status" to "unprocessed"));onVoiceDismiss()}){Text("保存到收件箱")}},dismissButton={TextButton(onClick=onVoiceDismiss){Text("停止／取消")}})}
        preview?.let{p->if(p.optString("mode")=="drive"){
            AlertDialog(onDismissRequest=onDismissPreview,title={Text("云盘文件")},text={Column(Modifier.verticalScroll(rememberScrollState())){Text(p.optString("summary"));p.optJSONArray("items")?.objects()?.forEach{file->TextButton(onClick={onDriveSelect(file)}){Text("下载／导入 ${file.optString("name")}")}}}},confirmButton={TextButton(onClick=onDismissPreview){Text("关闭")}})
        }else ImportReview(p.optString("title"),p.optString("summary"),p.optJSONArray("items")?:JSONArray(),onConfirmPreview,onDismissPreview,if(p.optString("mode")=="suggestions")state.items("tasks")else emptyList())}
    }}}
}
fun resultText(r:JSONObject?):String=if(r==null)"尚未判分" else "正确 ${r.optInt("correct")} · 错误 ${r.optJSONArray("wrong")?.length()?:0} · 待判 ${r.optInt("pending")} · ${r.optDouble("score")}/${r.optDouble("total")} 分"
fun statusName(s:String)=mapOf("unordered" to "待采购","ordered" to "已下单","partial" to "部分到货","arrived" to "已到货","assembled" to "已装配")[s]?:s
fun editorFields(kind:String):List<Pair<String,String>> = when(kind){
    "tasks"->listOf("title" to "任务内容","minutes" to "预计总用时（分钟）","remaining" to "剩余用时（分钟）","due" to "截止日期 yyyy-MM-dd HH:mm，可留空","goal" to "所属学习目标","priority" to "优先级（1最高，5最低）","status" to "状态","notes" to "进度、困难或说明","location" to "地点／工具条件")
    "goals"->listOf("title" to "目标名称","exam" to "是否考试","due" to "考试／目标日期 yyyy-MM-dd","priority" to "优先级（1最高，5最低）","minimum" to "每日最低学习分钟","notes" to "目标要求与阶段说明")
    "resources"->listOf("title" to "资源名称","url" to "视频或资料链接","notes" to "章节／版本／环境说明")
    "bom"->listOf("title" to "物料名称","spec" to "型号与规格","quantity" to "数量","price" to "单价（元）","status" to "采购状态","url" to "采购链接","version" to "所属版本","notes" to "注意事项")
    else->listOf("title" to if(kind=="versions")"版本名称／记录标题" else "项目名称","notes" to "目标、说明或制作记录")
}
fun editorOptions(kind:String,state:JSONObject):Map<String,List<Pair<String,String>>> = when(kind){
    "tasks"->mapOf("status" to listOf("todo" to "待办","doing" to "进行中","done" to "已完成","blocked" to "受阻","paused" to "暂停"),"goal" to listOf("" to "不关联目标")+state.items("goals").map{it.getString("id") to it.optString("title")})
    "goals"->mapOf("exam" to listOf("false" to "普通目标（可建议延期）","true" to "考试（日期不可推迟）"))
    "bom"->mapOf("status" to listOf("unordered","ordered","partial","arrived","assembled").map{it to statusName(it)})
    else->emptyMap()
}
