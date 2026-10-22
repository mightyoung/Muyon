//! Verified independent Search JSON contract; intentionally no Fetch/model tools.
use crate::*;
pub struct DeepSeek;
impl SearchProvider for DeepSeek {
    fn id(&self) -> &str {
        "deepseek-search"
    }
    fn endpoint(&self) -> &str {
        "https://api.deepseek.com/v1/tools/search"
    }
    fn price(&self, currency: &str) -> Result<Money> {
        let micros = match currency {
            "USD" => 750,
            "CNY" => 5000,
            _ => return Err("search_currency_unsupported".into()),
        };
        Ok(Money {
            currency: currency.into(),
            micros,
        })
    }
    fn encode(&self, q: &str, count: u64) -> Result<Json> {
        request(q, count)
    }
    fn decode(&self, body: &[u8], count: u64) -> Result<Vec<Json>> {
        let raw = parse(body).map_err(|_| "search_response_invalid")?;
        let results = raw
            .object()
            .map_err(|_| "search_response_invalid")?
            .get("results")
            .ok_or("search_response_invalid")?
            .array()
            .map_err(|_| "search_response_invalid")?;
        if results.len() > count as usize || results.len() > 50 {
            return Err("search_response_invalid".into());
        }
        let mut out = Vec::new();
        for (rank, r) in results.iter().enumerate() {
            let m = r.object().map_err(|_| "search_response_invalid")?;
            let mut row = std::collections::BTreeMap::new();
            // Preserve every supported returned string, including snippet and
            // summary, under bounded schema; never truncate or synthesize dates.
            for k in ["title", "url", "snippet", "summary", "content"] {
                let s = m
                    .get(k)
                    .ok_or("search_response_invalid")?
                    .string()
                    .map_err(|_| "search_response_invalid")?;
                if s.len() > 4096 {
                    return Err("search_projection_limit".into());
                }
                row.insert(k.into(), string(s));
            }
            if !url(row["url"].string()?) || row["content"] != string("") {
                return Err("search_response_invalid".into());
            }
            for k in ["site_name", "site_icon", "date"] {
                match m.get(k).ok_or("search_response_invalid")? {
                    Json::Null => (),
                    Json::String(s) if s.len() <= 4096 => {
                        if (k == "site_icon" && !s.is_empty() && !url(s))
                            || (k == "date" && !utc_date(s))
                        {
                            return Err("search_response_invalid".into());
                        }
                        row.insert(k.into(), string(s));
                    }
                    _ => return Err("search_response_invalid".into()),
                }
            }
            let Json::Number(score) = m.get("rerank_score").ok_or("search_response_invalid")?
            else {
                return Err("search_response_invalid".into());
            };
            let n = score
                .parse::<f64>()
                .map_err(|_| "search_response_invalid")?;
            if !n.is_finite() || !(0.0..=3.0).contains(&n) {
                return Err("search_response_invalid".into());
            }
            // Existing registered schema has no float/null dialect. Retain exact
            // numeric spelling as a string, and omit only actual nullable fields.
            row.insert("rerank_score".into(), string(score));
            let Json::Number(authority) = m.get("authority").ok_or("search_response_invalid")?
            else {
                return Err("search_response_invalid".into());
            };
            let a = authority
                .parse::<i64>()
                .map_err(|_| "search_response_invalid")?;
            if !(-1..=4).contains(&a) || authority.contains(['.', 'e', 'E']) {
                return Err("search_response_invalid".into());
            }
            row.insert("authority".into(), Json::Number(authority.clone()));
            row.insert("rank".into(), Json::Number((rank + 1).to_string()));
            out.push(Json::Object(row));
        }
        Ok(out)
    }
}
// Muyon supported-link subset; these values are never fetched by this adapter.
fn url(s: &str) -> bool {
    if s.len() > 4096 || s.chars().any(|c| c.is_control() || c.is_whitespace()) || s.contains('\\')
    {
        return false;
    }
    let Some(rest) = s
        .strip_prefix("https://")
        .or_else(|| s.strip_prefix("http://"))
    else {
        return false;
    };
    let host = rest.split(['/', '?', '#']).next().unwrap_or("");
    !host.is_empty() && !host.contains('@')
}
fn utc_date(s: &str) -> bool {
    let Some(base) = s.strip_suffix('Z').or_else(|| s.strip_suffix("+00:00")) else {
        return false;
    };
    let b = base.as_bytes();
    if b.len() < 19
        || b[4] != b'-'
        || b[7] != b'-'
        || b[10] != b'T'
        || b[13] != b':'
        || b[16] != b':'
    {
        return false;
    }
    if [0..4, 5..7, 8..10, 11..13, 14..16, 17..19]
        .iter()
        .any(|r| !b[r.clone()].iter().all(u8::is_ascii_digit))
    {
        return false;
    }
    let num = |r: std::ops::Range<usize>| {
        std::str::from_utf8(&b[r])
            .ok()
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(u32::MAX)
    };
    let y = num(0..4);
    let m = num(5..7);
    let d = num(8..10);
    let days = match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) {
                29
            } else {
                28
            }
        }
        _ => 0,
    };
    y > 0
        && d > 0
        && d <= days
        && num(11..13) < 24
        && num(14..16) < 60
        && num(17..19) <= 60
        && (b.len() == 19
            || (b.len() > 20 && b[19] == b'.' && b[20..].iter().all(u8::is_ascii_digit)))
}
