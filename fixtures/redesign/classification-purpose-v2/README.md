# classification-purpose-v2：I03当前用途表示派生

29个原case、77个原variant保持一一对应；原 [classification-v1](../classification-v1/README.md) 字节和not_run历史未修改。14规则proposed_unfrozen、52主case及29wholecase仍not_run。

`purpose-records.json`只是fixture表示，不是产品DTO/schema。每条stimulus仅复制v1已有输入区块；oracle只投影原current-purpose材料资格，非当前not_applicable，action_result另栏，资格不授dispatch/grant。未从expected补缺失stimulus，未将runtime actual复制成golden。派生本身不执行分类。

唯一实验DUT是 [admission/routing接缝](../../../experiments/redesign/d01a-contract/README.md)。它调用后才对独立v1期望比较，最大证据为partial_experimental；转换/模板/留存/重放/新尝试等不足分支not_run。实际credential扫描、完整分类、Unicode/来源真实性、权限/消费/出站/库/回执及M03均未证明。

`manifest.json`绑定原输入哈希，SHA256SUMS仅完整性检查，不是runtime acceptance。可在本目录运行 `sha256sum -c SHA256SUMS`；独立复跑driver不应写此目录。
