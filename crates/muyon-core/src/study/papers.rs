use super::*;
pub fn import(v: &mut Value, input: &Value) -> Result<Value> {
    let list = if input.is_array() {
        input.clone()
    } else {
        json!([input])
    };
    let papers = list
        .as_array()
        .filter(|a| a.len() <= 200)
        .ok_or("题包无效或超过200套")?;
    let mut added = 0;
    for p in papers {
        text(p, "id")?;
        text(p, "title")?;
        let qs = questions(p);
        if qs.len() > 5000 || p["sections"].as_array().is_none() {
            return Err("题包章节无效或题目过多".into());
        }
        let mut seen = std::collections::BTreeSet::new();
        for q in qs {
            let id = text(q, "id")?;
            text(q, "stem")?;
            if !seen.insert(id) {
                return Err("重复题目ID".into());
            }
            if !["choice", "text", "multiple", "boolean", "blank"]
                .contains(&q["type"].as_str().unwrap_or(""))
            {
                return Err("不支持的题型".into());
            }
        }
        if let Some(old) = arr(v, "papers")?.iter().find(|x| x["id"] == p["id"]) {
            if old != p {
                return Err("题包ID已存在且内容变化，请修改题包ID以保留历史作答".into());
            }
        } else {
            put(v, "papers", p.clone())?;
            added += 1;
        }
    }
    Ok(json!({"imported":added}))
}
pub fn command(v: &mut Value, c: &Value) -> Result<Value> {
    if c["op"] == "start_attempt" {
        let p = arr(v, "papers")?
            .iter()
            .find(|x| x["id"] == c["paper"])
            .ok_or("题包不存在")?;
        let now = c["now"].as_i64().ok_or("缺少开始时间")?;
        let a = json!({"id":format!("attempt-{}",number(v,"revision",0)+1),"paper":p["id"],"paperDigest":content_id("paper",&p.to_string()),"mode":c["mode"],"started":now,"deadline":if c["mode"]=="exam"{p["suggestedMinutes"].as_i64().map(|m|now+m*60000)}else{None},"status":"active","index":0,"answers":{},"marked":[],"result":null});
        put(v, "attempts", a.clone())?;
        return Ok(a);
    }
    let id = text(c, "attempt")?;
    let i = arr(v, "attempts")?
        .iter()
        .position(|x| x["id"] == id)
        .ok_or("练习不存在")?;
    let a = v["attempts"][i].clone();
    let p = arr(v, "papers")?
        .iter()
        .find(|x| x["id"] == a["paper"])
        .cloned()
        .ok_or("原题包缺失")?;
    if c["op"] == "commentary" {
        text(c, "text")?;
        v["attempts"][i]["commentary"] = json!({"source":"AI","text":c["text"]});
        return Ok(v["attempts"][i].clone());
    }
    if a["status"] != "active" {
        return Err("该次练习已经交卷".into());
    }
    if c["op"] == "attempt_position" {
        let index = number(c, "index", 0);
        if index < 0 || index >= questions(&p).len() as i64 {
            return Err("题目位置无效".into());
        }
        v["attempts"][i]["index"] = json!(index);
        return Ok(v["attempts"][i].clone());
    }
    if c["op"] == "answer" {
        let qid = text(c, "question")?;
        if !questions(&p).iter().any(|q| q["id"] == qid) {
            return Err("题目不属于该次练习".into());
        }
        let answer = c["value"]
            .as_str()
            .filter(|s| s.len() <= 20000)
            .ok_or("答案过长")?;
        if let (Some(deadline), Some(now)) = (a["deadline"].as_i64(), c["now"].as_i64()) {
            if now > deadline {
                return Err("考试已到时，请交卷".into());
            }
        }
        v["attempts"][i]["answers"][qid] = json!(answer);
        v["attempts"][i]["index"] =
            json!(number(c, "index", 0).clamp(0, questions(&p).len().saturating_sub(1) as i64));
        return Ok(v["attempts"][i].clone());
    }
    let mut correct = 0;
    let mut pending = 0;
    let mut wrong = Vec::new();
    let mut score = 0.0;
    let mut total = 0.0;
    for q in questions(&p) {
        let key = q["answer"].as_str().or_else(|| q["correctAnswer"].as_str());
        if let Some(key) = key.filter(|s| !s.trim().is_empty()) {
            if q["type"] == "text" {
                pending += 1;
                continue;
            }
            let points = q["points"].as_f64().unwrap_or(1.0);
            total += points;
            let given = a["answers"][q["id"].as_str().unwrap()]
                .as_str()
                .unwrap_or("");
            let normalize = |s: &str| s.trim().to_uppercase().replace([' ', ',', '，'], "");
            let ok = if q["type"] == "multiple" {
                let mut g: Vec<char> = normalize(given).chars().collect();
                g.sort();
                g.dedup();
                let mut k: Vec<char> = normalize(key).chars().collect();
                k.sort();
                k.dedup();
                g == k
            } else {
                normalize(given) == normalize(key)
            };
            if ok {
                correct += 1;
                score += points;
            } else {
                wrong.push(q["id"].clone());
            }
        } else {
            pending += 1;
        }
    }
    let result = json!({"correct":correct,"wrong":wrong,"pending":pending,"score":score,"total":total,"source":"standard-key"});
    v["attempts"][i]["status"] = json!("submitted");
    v["attempts"][i]["finished"] = c["now"].clone();
    v["attempts"][i]["result"] = result.clone();
    Ok(result)
}
