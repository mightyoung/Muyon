# WorkBuddy 2.6.1 发现索引
| ID | 发现 | 等级 | 证据文件 |
|---|---|---|---|
| F01 | 签名 v2、DN Tencent、证书 SHA-256 2b4500… | A | evidence/snippets/01-signature.txt |
| F02 | 版本/SDK/ABI | A | evidence/snippets/02-badging.txt |
| F03 | 组件清单（单 MainActivity + 腾讯 SDK） | A | evidence/snippets/03-components.txt |
| F04 | adjustResize | A | evidence/snippets/04-mainactivity-flags.txt |
| F05 | Flutter + 原生库清单（editor_sdk_ffi、ImSDK、rive…） | A | evidence/snippets/05-native-libs.txt |
| F06 | Sheet/Page 标识（未混淆残留） | A-线索 | evidence/snippets/06-dart-widget-name-clues.txt |
| F07 | 路由/接口路径线索 | A-线索 | evidence/snippets/07-route-path-clues.txt |
| F08 | 图标清单（Tab/输入/状态/工具/产物） | A | evidence/snippets/08-icon-inventory.txt |
| F09 | 字体清单 | A | evidence/snippets/09-fonts.txt |
| F10 | 包内附带技术评估文档摘录 | A | evidence/snippets/10-bundled-tech-eval-excerpt.md |
| F11 | UI 文案命中表（56/57） | A-线索 | evidence/snippets/11-ui-string-clues.tsv |
| F12 | 疑似密钥/配置位置（未读取） | A | evidence/snippets/12-key-material-locations.txt |
| V01 | 图标拼图（资源渲染，非截图） | A | evidence/visual/icon-sheet.png |
| V02 | 空态/失败明暗插图 | A | evidence/visual/empty-error-light-dark.png |
| V03 | 登录海报明暗 | A | evidence/visual/login_hero_*_poster.png |
| F13 | blutter 运行记录 | — | evidence/snippets/13-blutter-run.txt |
| F14 | TextStyle 常量（字号、行高、字重） | A | evidence/snippets/14-textstyle-consts.tsv |
| F15 | 间距和圆角常量 | A | evidence/snippets/15-spacing-radius.txt |
| F16 | 颜色常量（灰阶、青绿、深色候选） | A/D | evidence/snippets/16-color-consts.txt |
| F17 | 枚举状态线索（发送对账、管线、过期、权限、流式滚动、消息块） | A-线索 | evidence/snippets/17-enum-state-clues.txt |
| F18 | 带参数的路由模式 | A-线索 | evidence/snippets/18-route-patterns.txt |
