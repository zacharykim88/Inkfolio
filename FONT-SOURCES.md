# 字体来源与授权

InkFolio v1.3.0 完整包仅分发当前皮肤所需的附加字体，未修改字体文件。代码采用 GPL-3.0；各字体继续遵循各自的 SIL Open Font License 1.1。

## 小票：香萃打字机体 W40

- 官方项目：[Miiiller/Xiangcui-Dazijiti](https://github.com/Miiiller/Xiangcui-Dazijiti)。
- 用于项目名和书名；其余文字使用 KOReader 原生无衬线字体。
- 随包文件：`fonts/Xiangcui-Dazijiti-main/香萃打字机体 W40.ttf`。
- 保留 `License.txt`、`UPSTREAM-README.md` 和上游思源宋体 `SourceHanSerif-LICENSE.txt`。
- 沿用已分发的原始字体；不在缺少内嵌版权字段的字体中自行补写声明。

## 像素：Fusion Pixel Font（缝合像素字体）

- 官方项目：[TakWolf/fusion-pixel-font](https://github.com/TakWolf/fusion-pixel-font)。
- 使用 2026.10.16 发布版、12px 比例宽度简体中文字体，中英文、数字和单位共用该字体。
- 文件：`fonts/fusion-pixel-12px-proportional-zh_hans.otf`。
- SHA256：`db40edf0cc1e446bfe1ce75d5abb4d7c499ace96379b8a0f5f761bd3de8335eb`。
- 保留官方来源记录 `FusionPixel-SOURCE.json`、主许可证及 `FusionPixel-Licenses/` 下的上游许可文件。

## 现代、封面与系统字体

现代和封面皮肤使用 KOReader 自带的 Noto Sans 及中文回退字体；封面英文书名使用自带 Noto Serif Italic。本包不重复分发 KOReader 系统字体，保留它们在 KOReader 中的原始授权。

## 升级说明

当前皮肤不再依赖 Cinzel Decorative 或 InkfolioMatrix，本包不再附带这两项字体。合并字体目录时不删除用户已安装的其他字体。

字体不改为 GPL，不单独出售，原作者署名不表示其为本项目背书。完整包内的 SHA256SUMS.txt 列出实际分发文件的校验值。
