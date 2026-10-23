# InkFolio

**v1.2.0 · 2026-10-23**

为 KOReader 提供阅读信息卡，展示封面、豆瓣评分、阅读进度、阅读统计、阅读目标和豆瓣月榜，支持休眠显示与截图。

[下载完整安装包](https://github.com/zacharykim88/Inkfolio/releases/download/v1.2.0/InkFolio-v1.2.0.zip) · [更新日志](CHANGELOG.md)

## 功能

- **阅读字数**：从可提取的正文记录翻阅字数，按日汇总，查看周／月字数柱状图；本书估算已读字数和本次唤醒翻阅字数分别展示。
- **阅读统计**：自定义组合今日、本周、本月及本书／全局累计数据；时长、页数、字数按对应统计口径显示，趋势图最多同时选择两项。
- **阅读目标**：按日、周、月设置时长或字数目标，查看当前量、目标量和完成比例。
- **UI皮肤**：小票、像素、现代三种风格共用功能与设置，支持实时预览，可调整宽度、字号、比例和背景。
- **图书与榜单**：自动／手动获取豆瓣评分，支持候选确认、重新检索、版本／分册均分及来源查询；豆瓣月榜支持分类选择与锁屏时离线轮换。
- **操作与反馈**：支持手势调用、截图及脱敏诊断导出。

## 三种皮肤预览

以下为本版本使用 KOReader 原生组件和随包字体生成的**软件渲染预览**，使用同组示例数据与示意封面，**不是实机截图**。

| 小票 | 像素 | 现代 |
| --- | --- | --- |
| ![小票皮肤软件渲染预览](docs/previews/v1.2.0/classic.png) | ![像素皮肤软件渲染预览](docs/previews/v1.2.0/pixel.png) | ![现代皮肤软件渲染预览](docs/previews/v1.2.0/modern.png) |

以实际勾选的模块及设备分辨率排版；示例中的“已记录”表示现有记录不完整，详情可在“阅读摘要 → 统计说明”查看。[历史版本实机截图](https://github.com/zacharykim88/Inkfolio/tree/v1.1.0/docs/screenshots/v1.1.0)仅用于查看旧版，不代表当前界面。

## 兼容性：安装前请看

InkFolio 是 **KOReader 用户补丁**，需先有可以正常运行的 KOReader，不能直接安装到阅读器原生系统。

| 设备／安装版本 | 使用范围与验证情况 |
| --- | --- |
| Kobo Sage | D08 功能基线已通过用户实机验证；正式包只更新版本和已确认文案。 |
| Kindle、PocketBook | 尚未经实机验证。需先安装 KOReader；休眠显示取决于设备的平台支持。 |
| Android 手机及安卓电纸书 | 使用 [KOReader 官方 GitHub 安装包](https://github.com/koreader/koreader/releases)，可尝试信息卡预览与截图；本项目不能替换 Android 系统锁屏，尚未经实机验证。 |
| F-Droid 版 KOReader | 不执行本项目所需的用户补丁，无法使用。 |
| 其他设备 | 需支持 KOReader 用户补丁；尚未经实机验证。 |

休眠显示能力由 KOReader 和设备决定，不能仅凭品牌判断。阅读统计依赖 KOReader 内置阅读统计插件；图书信息及榜单获取还受网络与豆瓣页面可用性影响。

## 首次安装

1. 下载 **InkFolio-v1.2.0.zip** 并解压。不要使用 GitHub 自动生成的 Source code 包代替完整安装包。
2. 完全退出 KOReader，将 `2-inkfolio.lua` 放入 KOReader 数据目录下的 `patches/`；没有该目录则创建。
3. 将包内 `fonts/` 合并至 KOReader 的 `fonts/`，保留原有字体，不要替换整个目录。
4. 重新启动 KOReader，在 **工具 → InkFolio → 关于** 核对 **v1.2.0**。
5. 按需设置书库目录、显示内容、阅读目标及 UI皮肤；支持的平台可开启“启用休眠显示”。

Kobo 数据目录通常是 `.adds/koreader`，Kindle 通常是 `koreader`。Android 使用实际 KOReader 数据目录，需授予相应存储权限。

## 已安装用户升级

1. 完全退出 KOReader，备份原补丁及设置；补丁备份请放到 `patches/` 之外。
2. 用新 `2-inkfolio.lua` 覆盖同名文件，同一功能只保留一份补丁。
3. **合并随包 `fonts/`**。从 v1.1.0 升级时需要新增的像素字体。
4. 保留 `settings.reader.lua`、`settings/read_receipt_v2_db.lua`、已有的 `settings/read_receipt_v2_words.lua` 及 KOReader 阅读统计数据库，勿清空设置和缓存。
5. 完全重启，在“关于”核对版本。

**仅 v1.0.0 用户**：先删除旧补丁 `2-book-receipt-shortcut-and-lockscreen.lua`，再安装新文件。现有设置与阅读记录继续使用，已移除模块的旧选项会清理。

## 常用设置

- **显示内容**：选择封面、评分、进度、摘要、月榜和底部文字等。
- **阅读摘要**：数字摘要与趋势图各最多两项，独立选择；周期数字可选择“时长＋字数”或“时长＋页数”。本书／全局累计继续显示时长和页数。
- **阅读目标**：选择日、周、月及统计类型；字数目标使用万字，支持一位小数。
- **外观调整**：切换皮肤并实时预览；宽度、字号、比例可用按钮或手动输入，保存后生效，取消不保留草稿。
- **联网设置**：选择书库目录、更新信息、查看来源与处理待确认图书。常规自动及主页批量获取跳过已完成、待确认和暂不采用的书籍。
- **豆瓣月榜**：选择分类与离线轮换；按缓存规则联网更新，锁屏轮换不需要重新联网，预览和截图不换组。
- **开发者选项**：进度弹窗、复现记录与诊断导出；新用户的进度弹窗和复现记录默认关闭。

新用户默认黑色背景，首次显示时按设备分辨率适配整体比例；已有用户的外观设置保留。后续增加模块或长内容时，可在外观调整中查看并调整比例。

## 字数与历史数据

中文每字、英文每单词计一字，不计标点和空白。实际记录来自可提取正文，同次唤醒内同一内容去重，跨书汇总；下次唤醒或重启开始新会话。它表示翻阅量，不保证文字已被完整阅读。

本书“估算已读”由全书字数乘阅读位置得到，不参与周期字数或目标统计。周期字数从 InkFolio 开始记录时累计，安装前缺失日期不补录；不能把缺失数据当成零。

时长和页数读取 KOReader 阅读统计，可包含其保留的安装前历史。详细口径、图表符号及当前统计状态见 **显示内容 → 阅读摘要 → 统计说明**。

## 反馈问题

可在开发者选项开启复现记录，重现问题后预览并导出脱敏诊断信息。反馈时提供设备型号、KOReader 版本、InkFolio 版本、复现步骤和截图；不要公开原始设置数据库、个人书籍正文或未经脱敏的日志。

## 字体、许可与致谢

完整包附香萃打字机体 W40、缝合像素字体及原始授权文件；现代皮肤使用 KOReader 自带 Noto Sans 与中文回退字体。详情见 [FONT-SOURCES.md](FONT-SOURCES.md)。代码采用 GPL-3.0，见 [COPYING](COPYING)；保留原有版权声明。

开发与设计：zacharykim88。开发辅助：OpenAI Codex。

上游：[Estela-Zelin84/KOReader_Book-Receipt](https://github.com/Estela-Zelin84/KOReader_Book-Receipt)、u/hundredpercentcocoa、[omer-faruq/koreader-user-patches](https://github.com/omer-faruq/koreader-user-patches)。

推荐：[墨享 · InkShare](https://github.com/zacharykim88/inkshare.koplugin)——分享 KOReader 截图。

验证范围见 [VALIDATION.md](VALIDATION.md)。
