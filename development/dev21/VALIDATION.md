# D21 validation / 验证记录

Baseline: D19. Build: `weather-icons-en-us-20261028-dev21`. Public version and release date stay at 1.2.0 / 2026-10-23. D20 Paper is not included.

## Software checks

- KOReader v2026.07.1 native Linux emulator: **8,966 passed, 0 failed**, all 72 test processes exited successfully.
- Screen sizes: 600×800, 758×1024, 1072×1448, 1440×1920, and 1920×1440.
- Complete existing weather, theme, cover, interaction, layout, statistics, migration, and network suites.
- Localization suite: 40 test groups per size, plus a fresh English startup at 1440×1920. Checks menus and help, all four native skin layouts with text/icons and one/two-day forecasts, true menu rebuild through native TouchMenu, English dialogs with KOReader set to Chinese, saved settings, unchanged parser tokens and station IDs, raw forecast reuse, word-goal conversion, source/user text preservation, icon scaling, unknown conditions, loading/errors, both card palettes, minimum cover width, and maximum cover font scale.
- Additional KOReader v2025.04 native compatibility run at 1440×1920: **40 passed, 0 failed** for the localization suite.
- LuaJIT bytecode compilation passed. The source SHA256 is recorded in validation-results.json and matches the delivered patch.

## Review and visual inspection

Reviewed the final diff against D19. Shared weather widgets/artwork serve all four skins, and source tokens and data identifiers stay in their original language. Artwork and the English catalog are embedded in the single patch; there are no new network endpoints, recurring tasks, or external installation dependencies. Changing language preserves content/color choices, saved targets, cached forecasts, and KOReader's global language.

Inspected native screenshots of English Receipt, Pixel, Modern, and Cover, including low resolution, portrait/landscape, one/two-day forecasts, white/dark gray cards, compact appearance controls, and the rebuilt English settings menu. Verified all twelve icons in both palettes. Corrected backend-dependent SVG cropping by scaling the complete rendered image, and removed duplicate summary units.

The 753-entry English catalog was edited for American spelling and native-app vocabulary. Menu labels, prompts, help pages, About, release notes, diagnostics, weather conditions, and location display names are covered. User text and book/source content are not translated. Shared KOReader components such as the system folder picker and keyboard keep KOReader's language. Weather remains in Celsius.

## Limits / 实机状态

These are native software/emulator checks, not device acceptance. Kobo Sage sleep/wake, e-ink refresh quality, perceived icon weight, and real-device readability still require user testing. No new live weather or Douban requests were made for validation. No formal Release was created.
