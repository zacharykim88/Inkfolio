# InkFolio 开发修订

2026-10-25 · 以 D18 为基线；正式版本仍为 v1.2.0，尚未发布。

外观调整界面删除预览下方的说明文字；下方选项使用 KOReader 原生按钮的文字测量、触摸留白和标准行距，保留现有字号与全部控件，把节省的高度用于扩大预览。四种皮肤共用此布局。

Sage 竖屏软件测量：选项区高度777→555像素，预览696×928→915×1221像素，字号保持原样。其他分辨率的变化见 `appearance-comparison.json`。

## 安装与验证

完全退出 KOReader，将 `2-inkfolio.lua` 覆盖到 `koreader/patches/` 同名文件，再重新启动。

相关检查2350项通过、0项失败；20组尺寸对比通过。已查看四种皮肤、低分辨率、Sage竖屏与横屏的真实组件渲染，检查文字无截断、控件无越界及实际点击保存、手动数值输入、全屏预览。当前修改待 Kobo Sage 实机确认。

```sh
KOREADER_RUNTIME=/absolute/path/to/koreader python3 run_checks-dev16.py
```

继续复用针对性检查入口；完整回归入口仍为 `run_checks.py`。`tests/measure_appearance.lua` 可在配置独立 `KO_HOME`、`MEASURE_LABEL` 和 `INK_SOURCE` 后输出外观尺寸。
