# LAN 威胁模型（D1）

传输使用系统 TLS 1.3（`dart:io` `SecureSocket`）和 P-256 自签证书。证书由 `basic_utils` 生成，签名是 SHA-256/ECDSA。没有自研分组密码。私钥只经 `LanSecretStore` 交给宿主，宿主使用 `flutter_secure_storage`。

发现包可以带指纹，但指纹、设备名和同一局域网都不构成信任。信任只来自用户把本机算出的指纹与对方屏幕上的核对码或二维码内容比对之后调用 `confirmPeer`。

| 威胁 | 处理 | 自动测试 |
|---|---|---|
| 中间人替换证书 | 发送方只接受已配对指纹；对端证书不符则握手失败，不写收件箱 | `lan_trust_test` mitm |
| 冒用设备名 | 发现到的同名设备没有已验证指纹，发送在连接前拒绝 | `lan_trust_test` discovery |
| 重放已送达的消息 | nonce 与 message id 在读正文前占用；重复请求返回 409，不产生第二份文件 | `lan_trust_test` replay |
| 降级到明文 | 只绑定 TLS；明文 HTTP 无法完成握手，收件箱保持为空 | `lan_trust_test` plaintext |
| 设备被盗后撤销 | 撤销后未配对，正文接受前返回 401；撤销身份不能再次配对 | `lan_trust_test` revoked |
| 核对码输错 | 不写入信任集合 | `lan_trust_test` wrong code |

未覆盖：真实两台设备、证书在安全存储中的平台级提取测试、超过 4096 条之后被挤出的旧 nonce 重放。这些在报告中标为未验证。
