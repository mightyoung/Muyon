package com.mightyoung.muyon.study

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONArray
import org.json.JSONObject

val Terracotta=Color(0xFFA84B27)
val Paper=Color(0xFFF4F1EA)
val Ink=Color(0xFF2B2621)
@Composable fun StudyTheme(dark:Boolean=false,content: @Composable () -> Unit) {
    val colors=if(dark) darkColorScheme(primary=Color(0xFFE8946D),background=Color(0xFF1C1917),surface=Color(0xFF26221F),onSurface=Color(0xFFEFE9E1))
    else lightColorScheme(primary=Terracotta,background=Paper,surface=Color(0xFFFBF9F4),surfaceVariant=Color(0xFFECE7DD),onSurface=Ink,onBackground=Ink,outlineVariant=Color(0xFFE3DDD0))
    MaterialTheme(colorScheme=colors,typography=Typography(headlineLarge=androidx.compose.ui.text.TextStyle(fontFamily=FontFamily.Serif,fontSize=30.sp),headlineSmall=androidx.compose.ui.text.TextStyle(fontFamily=FontFamily.Serif,fontSize=24.sp)),content=content)
}
@OptIn(ExperimentalLayoutApi::class)
@Composable fun Page(title:String,subtitle:String="",actions:@Composable ()->Unit={},body:@Composable ColumnScope.()->Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=20.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        Text(title,style=MaterialTheme.typography.headlineLarge)
        if(subtitle.isNotBlank())Text(subtitle,color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.bodyMedium)
        FlowRow(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp),verticalArrangement=Arrangement.spacedBy(4.dp)){actions()}
        body();Spacer(Modifier.height(36.dp))
    }
}
@Composable fun Panel(title:String="",onClick:(()->Unit)?=null,content:@Composable ColumnScope.()->Unit) {
    OutlinedCard(modifier=Modifier.fillMaxWidth().then(if(onClick!=null)Modifier.clickable(onClick=onClick)else Modifier)){
        Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){
            if(title.isNotBlank())Text(title,style=MaterialTheme.typography.titleMedium)
            content()
        }
    }
}
@Composable fun Empty(message:String){Panel{Text(message,color=MaterialTheme.colorScheme.onSurfaceVariant)}}
@Composable fun Field(label:String,value:String,onChange:(String)->Unit,lines:Int=1){OutlinedTextField(value,onChange,label={Text(label)},modifier=Modifier.fillMaxWidth(),minLines=lines,singleLine=lines==1)}
@Composable fun Choice(label:String,options:List<Pair<String,String>>,selected:String,onSelect:(String)->Unit){
    Text(label,style=MaterialTheme.typography.labelLarge)
    Column(verticalArrangement=Arrangement.spacedBy(3.dp)){
        options.forEach{(id,title)->Row(Modifier.fillMaxWidth().clickable{onSelect(id)},horizontalArrangement=Arrangement.spacedBy(5.dp)){
            RadioButton(selected==id,onClick={onSelect(id)});Text(title,Modifier.padding(top=12.dp))
        }}
    }
}
@Composable fun Editor(title:String,fields:List<Pair<String,String>>,initial:JSONObject=JSONObject(),options:Map<String,List<Pair<String,String>>> =emptyMap(),onDismiss:()->Unit,onSave:(JSONObject)->Unit){
    val values=remember(initial.toString()){mutableStateMapOf<String,String>().also{m->fields.forEach{(k,_)->m[k]=when(k){"due"->dateText(initial.optLong(k));else->initial.optString(k,"")}}}}
    var error by remember{mutableStateOf("")}
    AlertDialog(onDismissRequest=onDismiss,title={Text(title)},text={Column(Modifier.heightIn(max=480.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(10.dp)){
        fields.forEach{(key,label)->
            if(options.containsKey(key)) Choice(label,options.getValue(key),values[key].orEmpty()){values[key]=it}
            else Field(label,values[key].orEmpty(),{values[key]=it},if(key in listOf("notes","text","instructions"))3 else 1)
        }
        if(error.isNotEmpty())Text(error,color=MaterialTheme.colorScheme.error)
    }},confirmButton={TextButton(onClick={try{
        val result=JSONObject(initial.toString());if(!result.has("id"))result.put("id",newId())
        values.forEach{(k,s)->when(k){
            "due"->if(s.isBlank())result.remove(k) else result.put(k,parseDate(s))
            "minutes","remaining","priority","minimum","quantity","price"->if(s.isNotBlank()){val n=s.toDoubleOrNull()?:error("$k 必须是数字");require(n>=0){"数值不能为负"};result.put(k,if(k=="price")n else n.toInt())}
            "exam"->result.put(k,s=="true")
            else->result.put(k,s)
        }}
        require(result.optString("title",result.optString("text")).isNotBlank()){ "请填写内容" }
        if(result.optBoolean("exam"))require(result.optLong("due")>0){"考试必须填写日期"}
        if(result.has("minutes")&&!initial.has("remaining"))result.put("remaining",result.getInt("minutes"))
        onSave(result)
    }catch(e:Exception){error=e.message?:"请检查输入"}}){Text("保存")}},dismissButton={TextButton(onClick=onDismiss){Text("取消")}})
}
fun taskSubtitle(t:JSONObject):String=listOfNotNull(
    "剩余 ${t.optInt("remaining",t.optInt("minutes",30))} 分钟",
    t.optLong("due").takeIf{it>0}?.let{"截止 ${dateText(it)}"},
    when(t.optString("status")){"done"->"已完成";"blocked"->"受阻";"paused"->"暂停";"doing"->"进行中";else->null}
).joinToString(" · ")
@Composable fun TaskCard(t:JSONObject,onOpen:()->Unit,onDone:()->Unit){Panel(onClick=onOpen){
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween){
        Column(Modifier.weight(1f)){Text(t.optString("title"),style=MaterialTheme.typography.titleMedium);Text(taskSubtitle(t),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        Checkbox(t.optString("status")=="done",onCheckedChange={onDone()})
    }
}}
@Composable fun ImportReview(title:String,summary:String,items:JSONArray,onConfirm:()->Unit,onDismiss:()->Unit,before:List<JSONObject> = emptyList()){AlertDialog(onDismissRequest=onDismiss,title={Text(title)},text={Column(Modifier.heightIn(max=430.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(10.dp)){
    Text(summary);items.objects().take(100).forEach{item->
        Text("• ${item.optString("title",item.optString("text","条目"))}")
        if(item.has("minutes"))Text(taskSubtitle(item),style=MaterialTheme.typography.bodySmall)
        val old=before.find{it.optString("id")==item.optString("id")}
        if(old!=null)listOf("title" to "内容","minutes" to "预计分钟","remaining" to "剩余分钟","due" to "截止","status" to "状态","goal" to "目标","priority" to "优先级","notes" to "说明","location" to "地点／工具").forEach{(k,label)->if(old.opt(k)?.toString()!=item.opt(k)?.toString()){val a=if(k=="due")dateText(old.optLong(k))else old.optString(k,"未设置");val b=if(k=="due")dateText(item.optLong(k))else item.optString(k,"未设置");Text("$label：$a → $b",style=MaterialTheme.typography.bodySmall)}}
        else if(before.isNotEmpty())Text("新增任务",style=MaterialTheme.typography.labelSmall)
    };if(items.length()>100)Text("另有 ${items.length()-100} 项")
}},confirmButton={TextButton(onClick=onConfirm){Text("确认导入")}},dismissButton={TextButton(onClick=onDismiss){Text("取消")}})}
