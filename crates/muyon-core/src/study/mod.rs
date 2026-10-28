//! Personal study domain. One SQLite owner; models only propose changes.
mod papers;
mod scheduler;
use crate::sqlite::Db;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

pub type Result<T> = std::result::Result<T, String>;
const COLLECTIONS: &[&str] = &[
    "goals",
    "tasks",
    "resources",
    "projects",
    "bom",
    "versions",
    "inbox",
    "papers",
    "attempts",
    "schedule",
    "calendar",
    "sessions",
    "history",
];
pub struct StudyStore {
    db: Db,
}
fn initial() -> Value {
    let mut v = json!({"format":"muyon-study","schema":1,"revision":0,"settings":{"windows":[{"days":[1,2,3,4,5],"start":"20:00","end":"22:00"},{"days":[6,7],"start":"14:00","end":"18:00"}],"dailyMax":240},"proposals":[],"sync":{}});
    for k in COLLECTIONS {
        v[*k] = json!([]);
    }
    v
}
pub(crate) fn arr<'a>(v: &'a Value, k: &str) -> Result<&'a Vec<Value>> {
    v[k].as_array().ok_or_else(|| format!("无效列表：{k}"))
}
pub(crate) fn text<'a>(v: &'a Value, k: &str) -> Result<&'a str> {
    v[k].as_str()
        .filter(|s| !s.trim().is_empty() && s.len() <= 20000)
        .ok_or_else(|| format!("缺少或无效字段：{k}"))
}
pub(crate) fn number(v: &Value, k: &str, default: i64) -> i64 {
    v[k].as_i64().unwrap_or(default)
}
fn put(v: &mut Value, kind: &str, value: Value) -> Result<()> {
    let id = text(&value, "id")?.to_string();
    let a = v[kind].as_array_mut().ok_or("无效集合")?;
    if let Some(i) = a.iter().position(|x| x["id"] == id) {
        a[i] = value;
    } else {
        a.push(value);
    }
    Ok(())
}
pub(crate) fn questions(p: &Value) -> Vec<&Value> {
    p["sections"]
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|s| s["questions"].as_array().into_iter().flatten())
        .collect()
}
impl StudyStore {
    pub fn open(path: &str) -> Result<Self> {
        let db = Db::open(path, false, true)?;
        db.query("PRAGMA journal_mode=WAL", &[])?;
        db.exec("PRAGMA synchronous=FULL", &[])?;
        db.exec("CREATE TABLE IF NOT EXISTS study_state(id INTEGER PRIMARY KEY CHECK(id=1),schema_version INTEGER NOT NULL,payload TEXT NOT NULL)",&[])?;
        db.exec(
            "INSERT OR IGNORE INTO study_state VALUES(1,1,?)",
            &[&initial().to_string()],
        )?;
        let s = Self { db };
        s.load()?;
        Ok(s)
    }
    fn load(&self) -> Result<Value> {
        let r = self.db.query(
            "SELECT schema_version,payload FROM study_state WHERE id=1",
            &[],
        )?;
        if r.len() != 1 || r[0][0].as_deref() != Some("1") {
            return Err("不支持的数据版本".into());
        }
        let v: Value =
            serde_json::from_str(r[0][1].as_deref().ok_or("数据缺失")?).map_err(|_| "数据损坏")?;
        validate_state(&v)?;
        Ok(v)
    }
    pub fn command(&self, c: Value) -> Result<Value> {
        let op = text(&c, "op")?;
        if op == "snapshot" || op == "export" {
            return self.load();
        }
        let tx = self.db.transaction()?;
        let mut v = self.load()?;
        let rev = v["revision"].as_u64().ok_or("无效修订")?;
        if let Some(expected) = c["expectedRevision"].as_u64() {
            if expected != rev {
                return Err("数据已变化，请刷新后重试".into());
            }
        }
        let result = match op {
            "upsert" => {
                let kind = text(&c, "kind")?;
                if ![
                    "goals",
                    "tasks",
                    "resources",
                    "projects",
                    "bom",
                    "versions",
                    "inbox",
                ]
                .contains(&kind)
                {
                    return Err("不允许写入该集合".into());
                }
                let mut item = c["value"].clone();
                if !item.is_object() {
                    return Err("无效对象".into());
                }
                if item["id"].as_str().is_none_or(str::is_empty) {
                    item["id"] = json!(format!("{kind}-{}", rev + 1));
                }
                validate_item(kind, &item)?;
                if kind == "goals" {
                    if let Some(old) = arr(&v, "goals")?.iter().find(|g| g["id"] == item["id"]) {
                        if old["exam"] == true
                            && (item["due"] != old["due"] || item["exam"] != true)
                        {
                            return Err("考试日期是固定约束，不能在普通编辑中改变".into());
                        }
                    }
                }
                // A completed prerequisite is real progress, never inferred from time blocks.
                if kind == "tasks" && item["status"] == "done" {
                    item["remaining"] = json!(0);
                }
                put(&mut v, kind, item.clone())?;
                item
            }
            "delete" => {
                let kind = text(&c, "kind")?;
                let id = text(&c, "id")?;
                if ![
                    "goals",
                    "tasks",
                    "resources",
                    "projects",
                    "bom",
                    "versions",
                    "inbox",
                ]
                .contains(&kind)
                {
                    return Err("无效集合".into());
                }
                v[kind]
                    .as_array_mut()
                    .ok_or("无效列表")?
                    .retain(|x| x["id"] != id);
                json!({"deleted":id})
            }
            "settings" => {
                validate_settings(&c["value"])?;
                v["settings"] = c["value"].clone();
                json!({"saved":true})
            }
            "import_tasks" => {
                let items = c["tasks"]
                    .as_array()
                    .filter(|a| a.len() <= 5000)
                    .ok_or("最多导入5000个任务")?;
                for item in items {
                    validate_item("tasks", item)?;
                    if !arr(&v, "tasks")?.iter().any(|x| x["id"] == item["id"]) {
                        put(&mut v, "tasks", item.clone())?;
                    }
                }
                json!({"imported":items.len()})
            }
            "apply_suggestions" => {
                if c["expectedRevision"].as_u64() != Some(rev) {
                    return Err("建议已过时，请重新整理".into());
                }
                let items = c["tasks"]
                    .as_array()
                    .filter(|a| a.len() <= 200)
                    .ok_or("建议任务无效")?;
                for item in items {
                    validate_item("tasks", item)?;
                    let mut item = item.clone();
                    if item["status"] == "done" {
                        item["remaining"] = json!(0);
                    }
                    put(&mut v, "tasks", item)?;
                }
                json!({"applied":items.len()})
            }
            "import_papers" => papers::import(&mut v, &c["papers"])?,
            "start_attempt" | "answer" | "submit" | "commentary" | "attempt_position" => {
                papers::command(&mut v, &c)?
            }
            "propose" => {
                let mut p = scheduler::propose(&v, &c)?;
                p["baseRevision"] = json!(rev + 1);
                p["id"] = json!(format!("plan-{}", rev + 1));
                v["proposals"] = json!([p.clone()]);
                p
            }
            "lock_block" => {
                let id = text(&c, "id")?;
                let b = v["schedule"]
                    .as_array_mut()
                    .unwrap()
                    .iter_mut()
                    .find(|b| b["id"] == id)
                    .ok_or("时间块不存在")?;
                b["locked"] = json!(c["locked"].as_bool().ok_or("缺少锁定状态")?);
                json!({"saved":true})
            }
            "confirm" => {
                let id = text(&c, "id")?;
                let p = arr(&v, "proposals")?
                    .iter()
                    .find(|x| x["id"] == id)
                    .cloned()
                    .ok_or("建议不存在")?;
                if p["baseRevision"].as_u64() != Some(rev) {
                    return Err("建议已过时，请重新生成".into());
                }
                let history = json!({"id":format!("history-{}",rev+1),"before":v["schedule"],"beforeStages":v["stages"],"deadlineChanges":p["extensions"],"after":p["blocks"],"reason":p["reason"],"revision":rev+1});
                v["history"].as_array_mut().unwrap().push(history);
                v["schedule"] = p["blocks"].clone();
                v["stages"] = p["stages"].clone();
                if let Some(extensions) = p["extensions"].as_array() {
                    for e in extensions {
                        let kind = text(e, "kind")?;
                        let id = text(e, "id")?;
                        if !["goals", "tasks"].contains(&kind) {
                            return Err("延期建议类型无效".into());
                        }
                        if let Some(item) = v[kind]
                            .as_array_mut()
                            .unwrap()
                            .iter_mut()
                            .find(|x| x["id"] == id)
                        {
                            if item["exam"] == true {
                                return Err("考试不能延期".into());
                            }
                            item["due"] = e["newDue"].clone();
                        }
                    }
                }
                v["proposals"] = json!([]);
                json!({"confirmed":true})
            }
            "undo" => {
                let h = v["history"]
                    .as_array_mut()
                    .unwrap()
                    .pop()
                    .ok_or("没有可撤销的调整")?;
                v["schedule"] = h["before"].clone();
                v["stages"] = h.get("beforeStages").filter(|x| x.is_array()).cloned().unwrap_or_else(|| json!([]));
                if let Some(changes) = h["deadlineChanges"].as_array() {
                    for e in changes {
                        let kind = e["kind"].as_str().unwrap_or("");
                        if !["goals", "tasks"].contains(&kind) { continue; }
                        if let Some(item) = v[kind].as_array_mut().unwrap().iter_mut().find(|x| x["id"] == e["id"]) {
                            if item["due"] == e["newDue"] { item["due"] = e["oldDue"].clone(); }
                        }
                    }
                }
                v["proposals"] = json!([]);
                json!({"undone":true})
            }
            "calendar_sync" => {
                let events = c["events"]
                    .as_array()
                    .filter(|a| a.len() <= 20000)
                    .ok_or("日历数据过多或无效")?;
                for e in events {
                    if number(e, "end", 0) <= number(e, "start", 0) {
                        return Err("日历时间无效".into());
                    }
                }
                v["calendar"] = json!(events);
                v["sync"]["calendar"] = json!({"at":c["now"],"status":"synced"});
                json!({"count":events.len()})
            }
            "maimemo_sync" => {
                v["sync"]["maimemo"] =
                    json!({"at":c["now"],"status":"synced","progress":c["progress"]});
                json!({"synced":true})
            }
            "sync_error" => {
                let provider = text(&c, "provider")?;
                if !["calendar", "drive", "maimemo"].contains(&provider) {
                    return Err("未知服务".into());
                }
                v["sync"][provider]["error"] = c["error"].clone();
                v["sync"][provider]["status"] = json!("failed");
                json!({"saved":true})
            }
            "session" => {
                let mut x = c["value"].clone();
                x["id"] = json!(format!("session-{}", rev + 1));
                put(&mut v, "sessions", x.clone())?;
                x
            }
            "restore" => {
                let mut backup = c["backup"].clone();
                validate_state(&backup)?;
                backup["proposals"] = json!([]);
                v = backup;
                json!({"restored":true})
            }
            _ => return Err("未知操作".into()),
        };
        v["revision"] = json!(rev
            .max(v["revision"].as_u64().unwrap_or(rev))
            .checked_add(1)
            .ok_or("修订号溢出")?);
        let raw = v.to_string();
        if raw.len() > 24 * 1024 * 1024 {
            return Err("数据超过24MB，请归档题包".into());
        }
        self.db
            .exec("UPDATE study_state SET payload=? WHERE id=1", &[&raw])?;
        tx.commit()?;
        Ok(result)
    }
}
fn validate_item(kind: &str, x: &Value) -> Result<()> {
    let id = text(x, "id")?;
    if id.len() > 200 {
        return Err("ID过长".into());
    }
    if kind == "inbox" {
        text(x, "text")?;
    } else {
        text(x, "title")?;
    }
    if kind == "tasks" {
        if !x["due"].is_null() && x["due"].as_i64().is_none_or(|d| d <= 0) {
            return Err("截止时间无效".into());
        }
        if !x["priority"].is_null() && x["priority"].as_i64().is_none_or(|d| !(1..=5).contains(&d))
        {
            return Err("优先级须为1至5".into());
        }
        for key in ["minutes", "remaining"] {
            if !x[key].is_null() && x[key].as_i64().is_none_or(|n| !(0..=100000).contains(&n)) {
                return Err("任务时长必须为0至100000分钟".into());
            }
        }
        if x["depends"]
            .as_array()
            .is_some_and(|a| a.iter().any(|d| d == id))
        {
            return Err("任务不能依赖自身".into());
        }
    }
    if kind == "goals" && x["exam"] == true && x["due"].as_i64().is_none_or(|d| d <= 0) {
        return Err("考试必须填写有效日期".into());
    }
    if kind == "resources" && x["type"] == "video" {
        let u = text(x, "url")?;
        if !u.starts_with("https://") && !u.starts_with("http://") {
            return Err("视频链接须为HTTP(S)地址".into());
        }
    }
    Ok(())
}
fn validate_state(v: &Value) -> Result<()> {
    if v["format"] != "muyon-study"
        || v["schema"] != 1
        || v["revision"].as_u64().is_none_or(|r| r >= 9007199254740990)
    {
        return Err("不是兼容的学习备份".into());
    }
    for k in COLLECTIONS {
        let a = arr(v, k)?;
        if a.len() > 20000 {
            return Err("记录过多".into());
        }
        if [
            "goals",
            "tasks",
            "resources",
            "projects",
            "bom",
            "versions",
            "inbox",
        ]
        .contains(k)
        {
            for x in a {
                validate_item(k, x)?;
            }
        }
    }
    if !v["settings"].is_object() || !v["sync"].is_object() || !v["proposals"].is_array() {
        return Err("备份结构不完整".into());
    }
    validate_settings(&v["settings"])?;
    Ok(())
}
fn validate_settings(v: &Value) -> Result<()> {
    let time = |s: &str| -> Result<i64> {
        let parts: Vec<&str> = s.split(':').collect();
        if parts.len() != 2 {
            return Err("时间格式应为HH:mm".into());
        }
        let h = parts[0].parse::<i64>().map_err(|_| "小时无效")?;
        let m = parts[1].parse::<i64>().map_err(|_| "分钟无效")?;
        if !(0..24).contains(&h) || !(0..60).contains(&m) {
            return Err("时间超出范围".into());
        }
        Ok(h * 60 + m)
    };
    for w in arr(v, "windows")? {
        if time(text(w, "end")?)? <= time(text(w, "start")?)? {
            return Err("结束时间应晚于开始".into());
        }
        for d in arr(w, "days")? {
            if d.as_i64().is_none_or(|d| !(1..=7).contains(&d)) {
                return Err("星期无效".into());
            }
        }
    }
    if !(15..=1440).contains(&number(v, "dailyMax", 240)) {
        return Err("每日安排上限无效".into());
    }
    Ok(())
}
pub fn content_id(prefix: &str, content: &str) -> String {
    format!(
        "{prefix}-{}",
        Sha256::digest(content.as_bytes())
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>()
    )
}
