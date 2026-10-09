# 手动打包基础设施集成复审（PR #6）

2026-10-09；候选 `107ca439547a01c4ac37e218e059de0a508a0309`，
PR https://github.com/mightyoung/Muyon/pull/6，基线 develop
`01404ae472451f55af5baa6ce76c95af72b0cbfc`。
本轮最新用户授权允许审查通过后合 develop，覆盖原任务“不合并”的限制；
仅合手动基础设施，不 dispatch、不改 main、不部署、不改变分发范围或权限。

非作者 `/root/review_grok7` 完整只读复审四文件，无确定阻断。
核对 workflow_dispatch 单平台、完整 SHA 经 env 校验、工具/源码独立 checkout
与 HEAD 核验、persist-credentials=false、contents:read、actions 固定完整 SHA；
只上传包/manifest 三天。路径逐段过滤，Windows 拒 symlink/reparse/resolve 越界；
macOS 正常 bundle 链接保留。manifest 明确来源、架构、版本、签名、大小与 SHA-256。

集成执行者在 /tmp 的精确候选副本重新运行
`python3 -m unittest discover -s scripts/package_artifacts -p 'test_*.py' -v`：
26 tests，OK；git diff --check 通过。原始输出不入仓库。
当前无 actionlint，不能声称本轮重跑 YAML 专用检查；原交付记 actionlint 1.7.7
通过，独立审查另逐行核实了 workflow。测试的原生工具输出为替身，真实 Windows
ZIP 逐项成员和字节有核对，不能代替三端原生构建与安装。

三端构建/安装/签名、ditto 权限与链接保真、实际产物内容扫描仍未执行。
路径过滤不证明包内容无秘密或真实用户数据。首次构建、预算及默认分支登记
依旧另行处理；public Actions artifacts 下载范围未改。PR 保持草稿，不开启自动合并。
