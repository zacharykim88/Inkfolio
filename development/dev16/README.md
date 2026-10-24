# InkFolio 开发修订

2026-10-24 · 正式版本仍为 v1.2.0，尚未发布。

D15 已由用户确认 Kobo Sage 实机通过，自动配色正常。本次将封面卡片的纯黑底改为深灰底（#333333），自动与手动模式一致；设置名称更新为“深灰”，已有黑色设置直接沿用。卡片文字区域同步使用相同底色，保留浅色正文、辅助文字与进度条。

## 安装

完全退出 KOReader，将 `2-inkfolio.lua` 覆盖到 `koreader/patches/` 同名文件后重新启动。已有字体、设置及阅读数据保留。

## 验证

相关检查 2185 项通过、0 项失败；使用原生组件与字体检查五种分辨率、四种皮肤、自动及手动配色、预览、截图、休眠显示和设置保留。已查看原生画面；本次深灰效果待 Kobo Sage 实机确认。

```sh
KOREADER_RUNTIME=/absolute/path/to/koreader python3 run_checks-dev16.py
```

`run_checks.py` 保留完整回归入口；本次使用上面的针对性检查，报告位于 `validation-results.json`。
