# InkFolio 开发修订

2026-10-24 · 正式版本仍为 v1.2.0，尚未发布。

按用户对上一修订灰度的反馈，封面卡片底色由 #333333 提亮至 #666666，自动与手动模式一致。进度条轨道同步调整为 #999999，以保持与卡片底色及白色已读部分的区分。原设置、文字、布局与自动检测规则保留。

## 安装与验证

完全退出 KOReader，将 `2-inkfolio.lua` 覆盖到 `koreader/patches/` 同名文件后重新启动。

相关检查2185项通过、0项失败；软件渲染检查通过，当前灰度效果待 Kobo Sage 实机确认。

```sh
KOREADER_RUNTIME=/absolute/path/to/koreader python3 run_checks-dev16.py
```

复用上一修订的针对性检查入口；完整回归入口仍为 `run_checks.py`。
