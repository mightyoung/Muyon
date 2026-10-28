# GPT Image 图标资源

按用户要求，应用自有图标由内置 GPT Image 图像生成工具逐个生成，原始 PNG 未重绘、裁切或改写。实际文件在 `apps/study_android/app/src/main/res/drawable-nodpi/`，文件名、字节数及 SHA-256 见同目录文档 `study-icon-assets.json`。

桌面图标 `gpt_launcher.png`：暖纸色背景、赤陶色打开的书与嫩芽；五个导航图标为 `gpt_today`、`gpt_learning`、`gpt_projects`、`gpt_inbox`、`gpt_profile`。操作图标为 `gpt_add`、`gpt_voice`、`gpt_import`，通知使用透明背景的白色 `gpt_reminder`。Compose 仅按原图 alpha 轮廓进行主题着色及布局缩放，以适应亮暗模式。

## Launcher prompt

Use case: logo-brand. Create ONE finished Android launcher icon for a personal Chinese learning, planning and DIY app called Muyon Study. No lettering. Square 1024 image, warm ivory #F4F1EA background extending edge to edge, a single elegant terracotta #A84B27 open notebook whose central fold subtly forms a sprouting leaf. Quiet editorial stationery aesthetic, simple geometric silhouette, flat colors, generously centered inside middle 60 percent so Android adaptive masks do not cut it. Crisp rounded strokes, no gradients, shadows, photoreal texture, mockup, border, text or watermark. This is the actual app icon asset.

## Navigation prompt template

Use case: logo-brand. Produce ONE standalone finished UI icon, SUBJECT. A unified quiet editorial stationery icon family for Muyon Study. Monochrome terracotta #A84B27 only, flat generous rounded continuous strokes with uniform weight approximately 48 pixels on a 1024 square. Recognizable at 24dp. Icon centered, occupies about 66 percent of image width and height, ample transparent margin, perfectly isolated on genuinely transparent background. No words, letters, numerals, label, border, enclosing badge, drop shadow, gradient, texture, mockup, extra illustration or watermark. Single crisp symbol only. Actual Android navigation asset, not a presentation sheet.

SUBJECT values:

- today: a small calendar page with a single check mark, representing today's plan
- learning: a simple open book, representing learning
- projects: a small cube with a simple short wrench alongside, representing DIY projects
- inbox: an inbox tray with a single downward arrow, representing captured inputs
- profile: a head and shoulders outline, representing personal settings

## Action prompt template

Use case: logo-brand. ONE actual Android action icon: SUBJECT. Match a quiet editorial stationery icon family. Flat monochrome terracotta #A84B27 unless white was explicitly specified. Simple confident rounded silhouette and strokes, centered on a genuinely transparent square, occupying 66 percent with generous empty margin. Legible at 24dp, approximately 48px stroke weight on a 1024 image. No text, letters, numerals, labels, enclosing tile, texture, gradients, shadow, mockup or watermark. One icon asset only.

SUBJECT values:

- add: a simple plus sign with round stroke ends
- voice: a simple standing microphone with its short stand
- import: a simple document outline with a downward arrow
- reminder: a simple solid white bell silhouette with transparent cutouts, white color only instead of terracotta
