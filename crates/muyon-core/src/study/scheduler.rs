use super::*;
use std::collections::BTreeMap;
/// Daily minima get a first share; extra time follows priority and dependencies.
pub fn propose(v: &Value, c: &Value) -> Result<Value> {
    let now = number(c, "now", 0);
    let offset = number(c, "offsetMinutes", 480).clamp(-720, 840) * 60000;
    let window_key = if c["capacityWindows"].is_array() {
        "capacityWindows"
    } else {
        "windows"
    };
    let mut windows: Vec<(i64, i64)> = arr(c, window_key)?
        .iter()
        .filter_map(|w| {
            let s = number(w, "start", 0).max(now);
            let e = number(w, "end", 0);
            (e > s).then_some((s, e))
        })
        .collect();
    windows.sort();
    let last_day = windows
        .iter()
        .map(|(_, e)| (*e - 1 + offset).div_euclid(86400000))
        .max()
        .unwrap_or((now + offset).div_euclid(86400000));
    let first_day = (now + offset).div_euclid(86400000);
    let mut free: Vec<(i64, i64)> = Vec::new();
    for (s, e) in windows {
        if let Some(last) = free.last_mut() {
            if s <= last.1 {
                last.1 = last.1.max(e);
                continue;
            }
        }
        free.push((s, e));
    }
    let locked: Vec<Value> = arr(v, "schedule")?
        .iter()
        .filter(|b| {
            b["locked"] == true
                && number(b, "end", 0) > now
                && arr(v, "tasks")
                    .unwrap()
                    .iter()
                    .any(|t| t["id"] == b["task"] && t["status"] != "done")
        })
        .cloned()
        .collect();
    let mut busy = arr(v, "calendar")?.clone();
    busy.extend(c["busy"].as_array().cloned().unwrap_or_default());
    busy.extend(locked.clone());
    for b in busy {
        if b["free"] == true || b["managedUnmodified"] == true {
            continue;
        }
        let s = number(&b, "start", 0);
        let e = number(&b, "end", 0);
        free = free
            .into_iter()
            .flat_map(|(a, z)| {
                let mut r = vec![];
                if e <= a || s >= z {
                    r.push((a, z));
                } else {
                    if s > a {
                        r.push((a, s));
                    }
                    if e < z {
                        r.push((e, z));
                    }
                }
                r
            })
            .collect();
    }
    let goals = arr(v, "goals")?;
    let tasks: Vec<&Value> = arr(v, "tasks")?
        .iter()
        .filter(|t| {
            !matches!(t["status"].as_str(), Some("done" | "blocked" | "paused"))
                && !goals
                    .iter()
                    .any(|g| g["id"] == t["goal"] && g["status"] == "paused")
        })
        .collect();
    let goal = |t: &Value| {
        goals
            .iter()
            .find(|g| !t["goal"].is_null() && g["id"] == t["goal"])
    };
    let mut remaining: Vec<i64> = tasks
        .iter()
        .map(|t| {
            let reserved: i64 = locked
                .iter()
                .filter(|b| b["task"] == t["id"])
                .map(|b| (number(b, "end", 0) - number(b, "start", 0).max(now)).max(0) / 60000)
                .sum();
            (number(t, "remaining", number(t, "minutes", 30)) - reserved).max(0)
        })
        .collect();
    let mut finished: BTreeMap<String, i64> = arr(v, "tasks")?
        .iter()
        .filter(|t| t["status"] == "done")
        .filter_map(|t| Some((t["id"].as_str()?.into(), now)))
        .collect();
    let mut daily: BTreeMap<i64, i64> = BTreeMap::new();
    let mut shares: BTreeMap<(i64, String), i64> = BTreeMap::new();
    let mut blocks = locked.clone();
    for b in &locked {
        let day = (number(b, "start", 0) + offset).div_euclid(86400000);
        let minutes = (number(b, "end", 0) - number(b, "start", 0).max(now)).max(0) / 60000;
        *daily.entry(day).or_default() += minutes;
        if let Some((i, t)) = tasks.iter().enumerate().find(|(_, t)| t["id"] == b["task"]) {
            let gid = goal(t)
                .and_then(|g| g["id"].as_str())
                .unwrap_or("")
                .to_string();
            *shares.entry((day, gid)).or_default() += minutes;
            if remaining[i] == 0 {
                finished.insert(text(t, "id")?.into(), number(b, "end", now));
            }
        }
    }
    let cap = number(&v["settings"], "dailyMax", 240).clamp(15, 1440);
    for (start, end) in free {
        let mut cursor = start;
        while cursor < end {
            let day = (cursor + offset).div_euclid(86400000);
            let boundary = number(c, "detailedEnd", i64::MAX);
            let slot_end = end
                .min((day + 1) * 86400000 - offset)
                .min(if cursor < boundary {
                    boundary
                } else {
                    i64::MAX
                });
            let room = (cap - daily.get(&day).copied().unwrap_or(0)).max(0);
            if room == 0 {
                cursor = slot_end;
                continue;
            }
            let mut candidates = Vec::new();
            for (i, t) in tasks.iter().enumerate() {
                if remaining[i] == 0 {
                    continue;
                }
                let deps = t["depends"].as_array().cloned().unwrap_or_default();
                if deps.iter().any(|d| {
                    d.as_str()
                        .is_none_or(|s| finished.get(s).is_none_or(|at| *at > cursor))
                }) {
                    continue;
                }
                let g = goal(t);
                let deadline = if g.is_some_and(|x| x["exam"] == true) {
                    number(g.unwrap(), "due", i64::MAX).min(number(t, "due", i64::MAX))
                } else {
                    i64::MAX
                };
                let available = (slot_end.min(deadline) - cursor) / 60000;
                let chunk = number(t, "minChunk", 5).clamp(1, 120).min(remaining[i]);
                if available.min(room) < chunk {
                    continue;
                }
                let gid = g.and_then(|x| x["id"].as_str()).unwrap_or("").to_string();
                let minimum = g.map(|x| number(x, "minimum", 0)).unwrap_or(0).max(0);
                let deficit =
                    (minimum - shares.get(&(day, gid.clone())).copied().unwrap_or(0)).max(0);
                let priority = g
                    .map(|x| number(x, "priority", 3) * 10 + number(t, "priority", 3))
                    .unwrap_or(number(t, "priority", 3) * 10);
                let due = number(
                    t,
                    "due",
                    g.map(|x| number(x, "due", i64::MAX)).unwrap_or(i64::MAX),
                );
                candidates.push(((deficit == 0, priority, due, i), available, deficit, gid));
            }
            candidates.sort_by_key(|x| x.0);
            let Some(((_, _, _, i), available, deficit, gid)) = candidates.into_iter().next()
            else {
                cursor = slot_end;
                continue;
            };
            let t = tasks[i];
            let take = remaining[i]
                .min(available)
                .min(room)
                .min(90)
                .min(if deficit > 0 { deficit } else { i64::MAX });
            if take <= 0 {
                break;
            }
            let until = cursor + take * 60000;
            let soft_due = number(
                t,
                "due",
                goal(t)
                    .map(|g| number(g, "due", i64::MAX))
                    .unwrap_or(i64::MAX),
            );
            blocks.push(json!({"id":format!("block-{}-{}",number(v,"revision",0)+1,blocks.len()),"task":t["id"],"title":t["title"],"start":cursor,"end":until,"late":soft_due<until}));
            remaining[i] -= take;
            *daily.entry(day).or_default() += take;
            *shares.entry((day, gid)).or_default() += take;
            if remaining[i] == 0 {
                finished.insert(text(t, "id")?.into(), until);
            }
            cursor = until;
        }
    }
    let unscheduled:Vec<Value>=tasks.iter().enumerate().filter(|(i,_)|remaining[*i]>0).map(|(i,t)|json!({"task":t["id"],"title":t["title"],"minutes":remaining[i],"exam":goal(t).is_some_and(|g|g["exam"]==true),"reason":"剩余内容超过可用容量，或前置条件、考试日期尚无法满足"})).collect();
    let mut gaps = Vec::new();
    for day in first_day..=last_day.min(first_day + 730) {
        for g in goals {
            let gid = g["id"].as_str().unwrap_or("");
            let before = blocks
                .iter()
                .filter(|b| {
                    (number(b, "start", 0) + offset).div_euclid(86400000) < day
                        && tasks
                            .iter()
                            .any(|t| t["id"] == b["task"] && t["goal"] == g["id"])
                })
                .map(|b| (number(b, "end", 0) - number(b, "start", 0)) / 60000)
                .sum::<i64>();
            let total = tasks
                .iter()
                .filter(|t| t["goal"] == g["id"])
                .map(|t| number(t, "remaining", number(t, "minutes", 30)))
                .sum::<i64>();
            let min = number(g, "minimum", 0).min((total - before).max(0));
            let allocated = shares.get(&(day, gid.to_string())).copied().unwrap_or(0);
            if min > allocated
                && g["status"] != "paused"
                && tasks.iter().any(|t| t["goal"] == g["id"])
            {
                gaps.push(
                    json!({"goal":g["id"],"title":g["title"],"day":day,"minutes":min-allocated}),
                );
            }
        }
    }
    blocks.sort_by_key(|b| number(b, "start", 0));
    let mut extensions = Vec::new();
    let mut forecast = Vec::new();
    for g in goals {
        let finish = blocks
            .iter()
            .filter(|b| {
                tasks
                    .iter()
                    .any(|t| t["id"] == b["task"] && t["goal"] == g["id"])
            })
            .map(|b| number(b, "end", 0))
            .max()
            .unwrap_or(0);
        let gap: i64 = tasks
            .iter()
            .enumerate()
            .filter(|(_, t)| t["goal"] == g["id"])
            .map(|(i, _)| remaining[i])
            .sum();
        forecast.push(json!({"goal":g["id"],"title":g["title"],"due":g["due"],"expectedFinish":finish,"gap":gap,"exam":g["exam"]}));
        if g["exam"] != true && number(g, "due", i64::MAX) < finish {
            extensions.push(json!({"kind":"goals","id":g["id"],"title":g["title"],"oldDue":g["due"],"newDue":finish}));
        }
    }
    for t in &tasks {
        if goal(t).is_some_and(|g| g["exam"] == true) {
            continue;
        }
        let finish = blocks
            .iter()
            .filter(|b| b["task"] == t["id"])
            .map(|b| number(b, "end", 0))
            .max()
            .unwrap_or(0);
        if number(t, "due", i64::MAX) < finish {
            extensions.push(json!({"kind":"tasks","id":t["id"],"title":t["title"],"oldDue":t["due"],"newDue":finish}));
        }
    }
    let detailed_end = number(c, "detailedEnd", i64::MAX);
    let mut weeks: BTreeMap<(i64, String), i64> = BTreeMap::new();
    for b in &blocks {
        if number(b, "start", 0) >= detailed_end {
            let week = (number(b, "start", 0) + offset).div_euclid(7 * 86400000);
            let title = b["title"].as_str().unwrap_or("").to_string();
            *weeks.entry((week, title)).or_default() +=
                (number(b, "end", 0) - number(b, "start", 0)) / 60000;
        }
    }
    let stages:Vec<Value>=weeks.into_iter().map(|((week,title),minutes)|json!({"weekStart":week*7*86400000-offset,"title":title,"minutes":minutes})).collect();
    blocks.retain(|b| number(b, "start", 0) < detailed_end);
    Ok(
        json!({"blocks":blocks,"stages":stages,"forecast":forecast,"extensions":extensions,"unassigned":unscheduled,"minimumGaps":gaps,"before":v["schedule"],"reason":"按每日保底、优先级、固定时段、日历占用及依赖评估；保留锁定安排，远期按周汇总。日历缓存范围之外的容量为估算。","created":now}),
    )
}
