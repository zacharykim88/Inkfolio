# D22 validation / 验证记录

Build: `weather-position-about-fix-20261028-dev22`. D22 fixes D21 device feedback while retaining the D19 feature baseline. Public version/date remain 1.2.0 / 2026-10-23.

## Reproduction and cause

The device photo reports `2-inkfolio.lua:1858: bad argument #1 to 'ipairs' (table expected, got nil)` when opening About in English. D21 produces the same error at the same line when the native emulator's `Device:hasDPad()` returns false. Two localization checks failed before the fix.

Native ButtonTable always creates `buttons_layout`; it sets the separate focus-navigation `layout` only on devices with a D-pad. D21 iterated the optional focus-navigation table to translate Close. D22 iterates the actual native button list instead. There is no exception suppression or empty-list fallback. The shared correction covers About, release notes, statistics help, diagnostics, and export previews.

## Software checks

- KOReader v2026.07.1 native Linux emulator: **9,266 passed, 0 failed**, all **78** test processes successful.
- Five sizes: 600×800, 758×1024, 1072×1448, 1440×1920, 1920×1440.
- Complete weather, theme, cover, interaction, layout, statistics, migration, and network suites.
- Localization suite: **45 groups**, run with and without a D-pad at all five sizes, plus fresh English startup in both input profiles at 1440×1920. The selected language is saved and reread before loading the patch.
- About opened repeatedly through native TouchMenu in Chinese and English. All English information viewers opened using native widgets with no D-pad focus layout. Close still works with KOReader set to Chinese.
- Weather positions were recorded during native painting for both languages, with and without a city name, and left/center/right alignment. Checks verify city/day text comes first, the icon precedes the temperature, and content stays in its column. Existing four-skin, single/two-day, palette, loading, error, and unknown-condition checks still pass.
- Language option is exactly `English`; the stored `en_US` key is unchanged.
- Additional KOReader v2025.04 run at 1440×1920, no D-pad and saved English: **45 passed, 0 failed**.
- LuaJIT bytecode compilation passed. The report records the final source SHA256.

## Review and visuals

Reviewed the D21-to-D22 diff. Production changes are confined to the build label, weather widget ordering and measurement, the shared TextViewer button list, and the English display name. Settings keys, cached weather, translations, and the D19 card palette remain compatible.

Inspected native Chinese single-day weather, English two-day weather, Cover and its deep-gray card, compact appearance controls, and the English About dialog in the no-D-pad profile. The icon now replaces only the condition: city/day → icon → temperature. There are no new runtime files, network requests, or dependencies.

## Device status / 实机状态

D21's real-device About failure is reproduced and fixed in the matching native input profile. D22 still needs the user's Kobo Sage retest. Software/emulator checks do not establish real-device acceptance.
