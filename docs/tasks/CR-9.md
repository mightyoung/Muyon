# CR-9 GB-6 特征测试的独立审查（ChatGPT 6 Pro，线上只读）

执行：ChatGPT 线上 · 只读 GitHub · 结果贴给用户，leader A 入库为 `docs/reviews/2026-10-11-gb6-test-review.md`

## 审什么
grokbot 在云端写的特征测试（本机没有 Flutter，靠 CI 迭代）：分支 `task/gb-6-dispatch-turn-characterization-rest` 提交 `0a08689` 的两个文件 `apps/muyon/test/gb6_dispatch_characterization_test.dart`、`apps/muyon/test/gb6_model_turn_characterization_test.dart`。目的：在拆分 `apps/muyon/lib/assistant/agent_dispatch.dart`、`agent_model_turn.dart` 之前，把缺口 G6～G14 的行为钉死。缺口定义见 [GB-4 清单](https://github.com/mightyoung/Muyon/blob/review/gb-2-research-write-contracts/docs/reviews/2026-10-11-dispatch-turn-characterization.md) 第 3、4 节。

## 逐条回答（每个缺口一节，附 `文件:行`）
1. 这个测试断言的是不是 GB-4 描述的那条行为？有没有断言错对象、或者只断言了「不抛异常」这类空洞结果？
2. 它能抓住哪个变异？请具体写「把 lib 哪一行改成什么，这个测试会失败」；如果你认为它**抓不住**任何合理变异（例如断言与被测分支无关、夹具绕过了被测代码），明确指出。
3. 夹具是否走了真实生产路径，还是用替身绕过了关键分支？替身是否改变了被测行为？
4. 有没有依赖时间、顺序、全局状态等可能导致时好时坏的写法？
5. 测试有没有把**疑似错误的现状行为**固定下来？如果有，列出来（这类应该先确认行为是否正确，而不是钉死）。

## 输出
第一行结论：可直接合入 / 修改后合入 / 需重写。然后按 G6～G14 逐条；最后列「建议 leader A 本机必做的变异清单」（每条一行：文件:行 → 改成什么 → 期望失败的测试名）。只写在代码里确认过的结论，推测标「推测」。
