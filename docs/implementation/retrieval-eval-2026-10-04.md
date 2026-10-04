# 检索评测 2026-10-04

数字来自 `apps/muyon/test/retrieval_eval/retrieval_eval_test.dart` 这一次运行。语料是可再分发的合成中文、英文和中英混合短文，含 1–2 字中文、中英混排和近重复。没有使用外部模型。

重跑：

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
  NO_PROXY=localhost,127.0.0.1,::1 \
  flutter test --no-pub --timeout 120s apps/muyon/test/retrieval_eval/retrieval_eval_test.dart
```

| 策略 | recall@1 | recall@5 | recall@10 | MRR | 索引字节 | 建索引 ms | 查询均值 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| current（cjk-bigram-latin-v1 + 单字扫描） | 0.779 | 0.976 | 1.000 | 1.000 | 40960 | 37.5 | 0.659 |
| fts-bigram-only（同一分词器，没有单字扫描） | 0.767 | 0.917 | 0.917 | 0.917 | 40960 | 25.0 | 0.174 |
| unigram（单字 + 拉丁词） | 0.779 | 0.976 | 1.000 | 1.000 | 32768 | 31.9 | 0.157 |
| hybrid（current 与 unigram 的 RRF，k=60） | 0.779 | 0.976 | 1.000 | 1.000 | 73728 | 70.5 | 0.816 |
| vector | not measured — needs real model | | | | | |

查询「泵」的 recall@5：current 0.714；fts-bigram-only 0.000；unigram 0.714；hybrid 0.714。

保持当前检索（cjk-bigram-latin-v1，外加已有的单字扫描）。unigram 的 recall@5 只高 0.000，recall@10 只高 0.000，不值得为这个增益再维持一套索引。

这 18 篇短文上的建索引时间受 SQLite 启动影响，不能外推到大库。策略取舍以 recall、MRR 和索引字节为准。

向量检索没有测量：环境变量 `MUYON_EMBEDDING_ENDPOINT` 未配置，不能用真实模型冒充数字。
