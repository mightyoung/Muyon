import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:muspace_module_api/muspace_module_api.dart';
import 'package:uuid/uuid.dart';
import 'tool_registry.dart';

class AssistantConversation {
  AssistantConversation(this.id,this.title,this.scope,this.createdAt);
  final String id,title;
  final AssistantScope scope;
  final DateTime createdAt;
}

class AssistantMessage {
  AssistantMessage(this.id,this.conversationId,this.role,this.content,this.createdAt,this.references);
  final String id,conversationId,role,content;
  final DateTime createdAt;
  final List<ObjectRef> references;
}

class PersonalMemory {
  PersonalMemory(this.id,this.content,this.source,this.updatedAt,this.expiresAt);
  final String id,content,source;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  bool get isExpired=>expiresAt!=null&&!DateTime.now().toUtc().isBefore(expiresAt!);
}

class FoundationNotification {
  FoundationNotification(this.id,this.title,this.body,this.taskId,this.read,this.createdAt);
  final String id,title,body;
  final String? taskId;
  final bool read;
  final DateTime createdAt;
}

enum PersonalTaskState { queued, waitingConfirmation, running, succeeded, failed, cancelled, paused, interrupted }

class PersonalTask {
  PersonalTask(Map<String,Object?> payload):payload=freezeJsonMap(payload);
  final Map<String,Object?> payload;
  String get id=>payload['executionId'] as String;
  String get conversationId=>payload['conversationId'] as String;
  String get prompt=>payload['prompt'] as String;
  PersonalTaskState get state=>PersonalTaskState.values.byName(payload['state'] as String);
  String get stage=>payload['stage'] as String;
  String? get error=>payload['error'] as String?;
  String? get waitingFor=>payload['waitingFor'] as String?;
  String? get waitReason=>waitingFor;
  String get deviceId=>executionDeviceId;
  String? get summary=>payload['summary'] as String?;
  List<ObjectRef> get objectRefs=>[for(final r in payload['references'] as List? ?? const [])objectRefFromJson(Map<String,Object?>.from(r as Map))];
  String get executionDeviceId=>payload['executionDeviceId'] as String;
  String? get profileId=>(payload['profile'] as Map?)?['id'] as String?;
  String? get previousAttemptId=>payload['previousAttemptId'] as String?;
  AssistantScope get scope=>AssistantScope.fromJson(Map<String,Object?>.from(payload['scope'] as Map));
  DateTime get updatedAt=>DateTime.parse(payload['updatedAt'] as String);
  bool get terminal=>[PersonalTaskState.succeeded,PersonalTaskState.failed,PersonalTaskState.cancelled,PersonalTaskState.paused,PersonalTaskState.interrupted].contains(state);
  PersonalTask copy(Map<String,Object?> changes)=>PersonalTask({...payload,...changes,'updatedAt':DateTime.now().toUtc().toIso8601String()});
}

/// One host database: conversations add context, execution_records remain the
/// sole execution authority. No parallel workspace/settings/device tables.
class FoundationRepository extends ChangeNotifier {
  FoundationRepository(this.database);
  final ManagedDatabase database;
  static final migration=ModuleMigration(version:2,id:'foundation-v2',definitionDigest:'foundation-v2',migrate:(db){
    db.execute('''
CREATE TABLE conversations(id TEXT PRIMARY KEY,title TEXT NOT NULL,scope_json TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
CREATE TABLE messages(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL REFERENCES conversations(id),role TEXT NOT NULL,content TEXT NOT NULL,references_json TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE INDEX messages_conversation ON messages(conversation_id,created_at);
CREATE TABLE memories(id TEXT PRIMARY KEY,content TEXT NOT NULL,source TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,expires_at TEXT);
CREATE TABLE notifications(id TEXT PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,task_id TEXT,read INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL);
''');
    installToolRegistrySchema(db);
  });
  String _id()=>const Uuid().v4();
  String _now()=>DateTime.now().toUtc().toIso8601String();
  List<AssistantConversation> conversations()=>[for(final r in database.raw.select('SELECT * FROM conversations ORDER BY updated_at DESC,rowid DESC'))
    AssistantConversation(r['id'] as String,r['title'] as String,AssistantScope.fromJson(Map<String,Object?>.from(jsonDecode(r['scope_json'] as String) as Map)),DateTime.parse(r['created_at'] as String))];
  AssistantConversation? conversation(String id) {
    for(final c in conversations()) {if(c.id==id)return c;}
    return null;
  }
  Future<AssistantConversation> createConversation({String title='主对话',AssistantScope scope=const AssistantScope.global()}) async {
    if(title.trim().isEmpty)throw ArgumentError('Conversation title required');
    final id=_id(),now=_now();
    await database.write((db)=>db.execute('INSERT INTO conversations VALUES(?,?,?,?,?)',[id,title.trim(),jsonEncode(scope.toJson()),now,now]));
    notifyListeners();return conversation(id)!;
  }
  List<AssistantMessage> messages(String conversationId)=>[for(final r in database.raw.select('SELECT * FROM messages WHERE conversation_id=? ORDER BY created_at,rowid',[conversationId]))
    AssistantMessage(r['id'] as String,conversationId,r['role'] as String,r['content'] as String,DateTime.parse(r['created_at'] as String),List.unmodifiable([for(final ref in jsonDecode(r['references_json'] as String) as List)objectRefFromJson(Map<String,Object?>.from(ref as Map))]))];
  Future<void> appendMessage(String conversationId,String role,String content,{List<ObjectRef> references=const []})async {
    if(!['user','assistant','tool','system'].contains(role)||content.trim().isEmpty)throw ArgumentError('Invalid message');
    await database.write((db){
      db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?)',[_id(),conversationId,role,content,jsonEncode(references.map((e)=>e.toJson()).toList()),_now()]);
      db.execute('UPDATE conversations SET updated_at=? WHERE id=?',[_now(),conversationId]);
    });notifyListeners();
  }
  List<PersonalMemory> memories({bool includeExpired=false})=>[for(final r in database.raw.select('SELECT * FROM memories ORDER BY updated_at DESC'))
    if(includeExpired||r['expires_at']==null||DateTime.now().toUtc().isBefore(DateTime.parse(r['expires_at'] as String)))
      PersonalMemory(r['id'] as String,r['content'] as String,r['source'] as String,DateTime.parse(r['updated_at'] as String),r['expires_at']==null?null:DateTime.parse(r['expires_at'] as String))];
  Future<String> saveMemory({String? id,required String content,required String source,DateTime? expiresAt})async {
    if(content.trim().isEmpty||source.trim().isEmpty)throw ArgumentError('Memory requires content and source');
    final key=id??_id(),now=_now();
    await database.write((db)=>db.execute('INSERT INTO memories VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET content=excluded.content,source=excluded.source,updated_at=excluded.updated_at,expires_at=excluded.expires_at',[key,content.trim(),source.trim(),now,now,expiresAt?.toUtc().toIso8601String()]));
    notifyListeners();return key;
  }
  Future<void> deleteMemory(String id)async {await database.write((db)=>db.execute('DELETE FROM memories WHERE id=?',[id]));notifyListeners();}
  List<FoundationNotification> notifications({bool unreadOnly=false})=>[for(final r in database.raw.select('SELECT * FROM notifications ${unreadOnly?'WHERE read=0':''} ORDER BY created_at DESC,rowid DESC'))
    FoundationNotification(r['id'] as String,r['title'] as String,r['body'] as String,r['task_id'] as String?,r['read']==1,DateTime.parse(r['created_at'] as String))];
  Future<void> notify({required String title,required String body,String? taskId})async {
    await database.write((db)=>db.execute('INSERT INTO notifications VALUES(?,?,?,?,0,?)',[_id(),title,body,taskId,_now()]));notifyListeners();
  }
  Future<void> markNotificationRead(String id)async {await database.write((db)=>db.execute('UPDATE notifications SET read=1 WHERE id=?',[id]));notifyListeners();}
  List<PersonalTask> tasks({String? conversationId})=>[for(final r in database.raw.select("SELECT payload FROM execution_records WHERE json_extract(payload,'\$.kind')='personal' ORDER BY rowid DESC"))
    if(conversationId==null||(jsonDecode(r['payload'] as String) as Map)['conversationId']==conversationId)
      PersonalTask(Map<String,Object?>.from(jsonDecode(r['payload'] as String) as Map))];
  PersonalTask? task(String id) {
    final r=database.raw.select("SELECT payload FROM execution_records WHERE id=? AND json_extract(payload,'\$.kind')='personal'",[id]);
    return r.isEmpty?null:PersonalTask(Map<String,Object?>.from(jsonDecode(r.first['payload'] as String) as Map));
  }
  Future<void> createTask(PersonalTask task)async {
    if(task.payload['kind']!='personal'||task.state!=PersonalTaskState.queued)throw ArgumentError('Invalid new task');
    await database.write((db)=>db.execute('INSERT INTO execution_records VALUES(?,?,?)',[task.id,task.state.name,jsonEncode(task.payload)]));notifyListeners();
  }
  Future<bool> updateTask(PersonalTask next,{Set<PersonalTaskState>? expected,bool Function()? canCommit,String? assistantAnswer,List<ObjectRef> references=const []})async {
    final result=await database.write((db){
      final current=task(next.id);
      if(current==null||current.terminal||(expected!=null&&!expected.contains(current.state))||(canCommit!=null&&!canCommit()))return false;
      if(current.conversationId!=next.conversationId||jsonEncode(current.scope.toJson())!=jsonEncode(next.scope.toJson()))throw StateError('Task scope changed');
      db.execute('UPDATE execution_records SET state=?,payload=? WHERE id=?',[next.state.name,jsonEncode(next.payload),next.id]);
      if(assistantAnswer!=null){
        if(next.state!=PersonalTaskState.succeeded)throw StateError('Answer requires success');
        db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?)',[_id(),next.conversationId,'assistant',assistantAnswer,jsonEncode(references.map((e)=>e.toJson()).toList()),_now()]);
        db.execute('UPDATE conversations SET updated_at=? WHERE id=?',[_now(),next.conversationId]);
      }
      return true;
    });if(result)notifyListeners();return result;
  }
  Future<void> recoverInterrupted()async {
    for(final task in tasks()){
      if([PersonalTaskState.queued,PersonalTaskState.running].contains(task.state)) {
        await updateTask(task.copy({'state':PersonalTaskState.interrupted.name,'stage':'interrupted','error':'应用中断；继续将创建新尝试并重新确认'}));
      }
    }
  }
}
