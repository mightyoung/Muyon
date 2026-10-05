# 检索评测 2026-10-05

数字来自 `apps/muyon/test/retrieval_eval/retrieval_eval_test.dart` 这一次运行，共 300 篇。语料：可再分发的合成语料。`retrieval-eval-2026-10-04.md` 是 18 篇短文的历史结果，本文件不改写它。文档正文不会写入本报告。

重跑并写回本文件。普通 `flutter test` 不带 `MUYON_WRITE_EVAL_REPORT=1`，因此不会改这个文件：

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
  NO_PROXY=localhost,127.0.0.1,::1 \
  MUYON_WRITE_EVAL_REPORT=1 \
  flutter test --no-pub --timeout 120s apps/muyon/test/retrieval_eval/retrieval_eval_test.dart
```

可选：`MUYON_EVAL_CORPUS_DIR` 指向含 `queries.json` 与 `docs/<id>.txt` 的本地目录。`MUYON_EMBEDDING_ENDPOINT` 只改变下面的向量说明；这次运行不发送文档正文。

| 策略 | recall@1 | recall@5 | recall@10 | MRR | 索引字节 | 建索引 ms | 查询均值 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| current（cjk-bigram-latin-v1 + 单字扫描） | 0.678 | 0.889 | 0.961 | 1.000 | 335872 | 750.5 | 1.379 |
| fts-bigram-only（同一分词器，没有单字扫描） | 0.662 | 0.808 | 0.830 | 0.857 | 335872 | 641.0 | 0.374 |
| unigram（单字 + 拉丁词） | 0.678 | 0.889 | 0.961 | 1.000 | 270336 | 558.2 | 0.430 |
| hybrid（current 与 unigram 的 RRF，k=60） | 0.678 | 0.889 | 0.961 | 1.000 | 606208 | 1312.1 | 1.809 |
| vector | not measured — needs real model | | | | | |

查询「泵」的 recall@5：current 0.714；fts-bigram-only 0.000；unigram 0.714；hybrid 0.714。

保持当前检索（cjk-bigram-latin-v1，外加已有的单字扫描）。unigram 的 recall@5 只高 0.000，recall@10 只高 0.000，不值得为这个增益再维持一套索引。

这 300 篇上的建索引时间受 SQLite 启动和机器负载影响，不能外推到用户的真实文库。策略取舍以 recall、MRR 和索引字节为准。

向量：not measured — needs real model
