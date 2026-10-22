# Independent static review

Reviewer: separate read-only agent `document_contract_review`, no shared
implementation responsibility, scoped to code/spec and existing contracts.

## Initial review: d038bab674b9f871fedc8de77e5f0c4b9590b571

No statically confirmed compile defect or authorization bypass found.

P2: generation loop simultaneously changed epoch, so rejection could be due to
epoch alone. Split invalid generation=0 and stale epoch. Nonzero lease generation
must be checked against the real host table, not equated to grant generation.

P2: PDF user-space region could be outside known crop. For visible selection,
reject outside crop; otherwise explicitly declare potentially invisible objects.
Structural validation alone was not classified as an authorization vulnerability.

Coverage gap: all PDF unknowns removed together; separate individual unknown
page/rotation/crop/coordinates. Add invalid crop, valid normalized region and
all rotations. All Rust tests/format checks NOT_RUN due missing toolchain.

## Follow-up review: 3e168cfc1676772c360dfd8ac33a9551a60a592b

Reviewer's conclusion (translated only for formatting):

> 此前 P2 和所列覆盖缺口均静态关闭。region 明确为 visible selection；
> 已知 user-space crop 检查四侧包含，有限数和尺寸校验先执行。测试覆盖
> 越界拒绝及等于 crop 边界接受；generation=0 与 epoch mismatch 已分离；
> 四个未知字段、非法 crop、合法 normalized region 和四种 rotation 已覆盖。
>
> 未发现此次修复引入新的静态编译、权限或逻辑问题。实际权限交集、当前
> lease 和字节交付时原子复核仍需未来可信 host 实现，不能据此声称真实
> 读取或撤权集成已经验收。
>
> 代码静态复审通过；发布验收继续 HOLD，仅因缺少 Rust 工具链下的编译、
> 测试和格式检查证据。状态维持 NOT_RUN。

Reviewer did not modify files, use network, install tools, commit or push.
The author checked the actual corrective diff and preserved raw NOT_RUN logs.
This is a static contract review, not an engine/security/runtime acceptance.
