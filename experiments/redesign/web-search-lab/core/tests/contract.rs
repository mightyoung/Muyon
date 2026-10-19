use muyon_web_search_lab::*;
#[test]
fn official_search_payload_is_independent_and_does_not_leak_localization_or_history() {
    assert_eq!(
        request("DeepSeek site:example.org", 10).unwrap(),
        parse(br#"{"query":"DeepSeek site:example.org","count":10,"need_content":false}"#).unwrap()
    );
}
#[test]
fn unicode_query_and_count_bounds_are_not_truncated() {
    assert!(request(&"🔎".repeat(128), 1).is_ok());
    assert!(request(&"汉".repeat(128), 50).is_ok());
    for q in ["".into(), " \n\t".into(), "🔎".repeat(129)] {
        assert!(request(&q, 10).is_err());
    }
    for n in [0, 51, u64::MAX] {
        assert!(request("query", n).is_err());
    }
}
use muyon_web_search_lab::deepseek::DeepSeek;
fn nonempty() -> Json {
    parse(include_bytes!("../../fixtures/nonempty.json")).unwrap()
}
fn put(j: &mut Json, k: &str, v: Json) {
    if let Json::Object(m) = j {
        m.insert(k.into(), v);
    }
}
#[test]
fn null_metadata_decimal_and_unknown_authority_preserve_source_truth() {
    let rows = DeepSeek
        .decode(include_bytes!("../../fixtures/nonempty.json"), 10)
        .unwrap();
    let m = rows[0].object().unwrap();
    assert_eq!(m["rerank_score"], string("2.4"));
    assert_eq!(m["authority"], Json::Number("-1".into()));
    assert_eq!(m["url"], string("https://example.org/source"));
    assert_eq!(m["rank"], Json::Number("1".into()));
    for k in ["site_name", "site_icon", "date"] {
        assert!(!m.contains_key(k));
    }
    assert!(DeepSeek
        .decode(br#"{"results":[]}"#, 10)
        .unwrap()
        .is_empty());
}
#[test]
fn malformed_or_wrong_type_is_never_an_empty_success() {
    for raw in [
        b"<html>bad</html>".as_slice(),
        br#"{}"#,
        br#"{"results":null}"#,
        br#"{"results":{}}"#,
        br#"{"results":[{}]}"#,
        br#"{"results":[],"results":[]}"#,
    ] {
        assert!(DeepSeek.decode(raw, 10).is_err());
    }
    for (key, value) in [
        ("rerank_score", string("2.4")),
        ("rerank_score", Json::Number("4".into())),
        ("authority", Json::Number("5".into())),
        ("authority", Json::Number("1.5".into())),
        ("date", string("2026-02-30T00:00:00Z")),
        ("date", string("yesterday")),
        ("site_icon", Json::Bool(false)),
        ("url", string("https://user:pass@example.org")),
        ("url", string("javascript:alert(1)")),
        ("content", string("unexpected full page")),
    ] {
        let mut raw = nonempty();
        if let Json::Object(m) = &mut raw {
            if let Json::Array(rows) = m.get_mut("results").unwrap() {
                put(&mut rows[0], key, value)
            }
        }
        assert!(
            DeepSeek.decode(raw.encode().as_bytes(), 10).is_err(),
            "{key}"
        );
    }
}
#[test]
fn explicit_price_currency_and_fixed_https_endpoint() {
    assert_eq!(
        DeepSeek.endpoint(),
        "https://api.deepseek.com/v1/tools/search"
    );
    assert_eq!(
        DeepSeek.price("USD").unwrap(),
        Money {
            currency: "USD".into(),
            micros: 750
        }
    );
    assert_eq!(
        DeepSeek.price("CNY").unwrap(),
        Money {
            currency: "CNY".into(),
            micros: 5000
        }
    );
    assert!(DeepSeek.price("EUR").is_err());
    assert!(!SearchConfig::default().enabled);
}
