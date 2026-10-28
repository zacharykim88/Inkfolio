# InkFolio D21

Reading cards for KOReader, with sleep screens, screenshots, reading statistics, and optional weather.

D21 builds on D19. It adds a consistent set of monochrome weather icons and a choice of Simplified Chinese or American English. The public version remains 1.2.0, dated October 23, 2026. This is a development build, not a new release.

[简体中文](README.md)

## Install or update

Replace `2-inkfolio.lua` in KOReader's `patches` folder, then fully exit and restart KOReader. Keep the fonts installed with D19. No additional icon or language files are needed. Your settings, reading records, book matches, and weather cache are kept.

If you are upgrading from v1.0.0, remove the old `2-book-receipt-shortcut-and-lockscreen.lua` before installing this patch. Do not keep both patches enabled.

## Choose a language

Open **Tools → InkFolio → 语言 → English (United States)**. To switch back, choose **Tools → InkFolio → Language → 简体中文**.

The selection is saved immediately. InkFolio reopens its settings in the new language without restarting KOReader. KOReader's own language setting stays the same.

English covers reading cards, settings, prompts, help, About, release notes, diagnostics, weather conditions, and location names. Dates use U.S. order, such as **Oct 28, 2026**. Reading time appears as **2h 3m**, and large word counts use forms such as **25k words**. Book titles, authors, chapters, descriptions from online sources, and your own text stay in their original language. KOReader's shared folder picker and keyboard follow KOReader's language.

## Choose weather text or icons

Open **Tools → InkFolio → Content → Header → Weather Display**, then choose **Text** or **Icons**. Text is the default.

All four styles share 12 original, monochrome line icons: clear, partly cloudy, cloudy, showers, rain, thunderstorms, snow, rain and snow, hail, fog, haze, and dust. Icons scale with the card and adapt to white or dark gray backgrounds. Unrecognized or mixed conditions stay as text. Cities, dates, day labels, and temperatures remain visible. Temperatures stay in Celsius, matching the weather source.

Changing the display mode uses your existing cache and does not trigger a network request. Loading and error messages stay as text; an old condition icon is never shown in their place.

Select today's weather, tomorrow's weather, and the date independently under **Header**. Cover can show one forecast at a time. The other styles can show both. Forecasts come from China's National Meteorological Center and support the locations listed in the location menu. Adding English does not add a different weather provider or international location search.

## Customize the card

Open **Tools → InkFolio → Appearance**. Choose **Receipt**, **Pixel**, **Modern**, or **Cover**. Adjust the preview, then choose **Save** to apply your changes. **Cancel** or Back discards unsaved changes. Tap the preview for a full-screen view; tap again to return.

Cover shows the book's cover behind a reading card. Card width, card font size, cover background, and card background are separate controls. The card background can be **Auto**, **White**, or **Dark Gray**. Auto samples the area just outside the card: an average grayscale value of 150 or higher uses a #333333 background with white text; a lower value uses white with black text.

Features that Cover does not display are disabled in its settings. Your selections are kept for the other styles. D20's separate Paper experiment is not included in this D19-based build.

## Reading statistics and goals

Use **Content → Reading Progress** to choose the additional progress rows. **Content → Reading Summary** lets you select up to two summaries and two charts. Period summaries can show **Time + Words** or **Time + Pages**. All-time summaries use time and pages.

**Reading Goals** supports daily, weekly, or monthly targets for reading time or words. In English, enter time in whole minutes and word targets in whole thousands: **25** means **25,000 words**. Chinese uses ten-thousands, so **2.5** represents the same target. Switching languages does not change the stored target.

Time and pages come from KOReader reading statistics. Word counts track extractable text viewed since InkFolio began recording; each Chinese character counts as one word, while English is counted by word. Text is counted once per wake session. Counts reflect text you moved through, not confirmation that you read every word. Open **About Reading Stats** for details about missing records, periods, and chart symbols.

## Book information and online updates

InkFolio can fetch Douban ratings, show monthly book rankings, and let you review uncertain matches. Use **Online Services → Update Information** to refresh. While reading, this updates the current book and weather. From the library, it scans the library folder and completes missing book information.

Automatic weather updates are due after six hours. Failed book updates wait at least 30 minutes, with up to three automatic attempts per book per day. Complete book records are reused. Canceling a task pauses its module until the next wake. InkFolio never turns on Wi-Fi automatically.

Use **Update Status** to inspect sources and recent updates. **Developer Options → Diagnostics** can export a redacted report. Full error text stays on the device.

## Compatibility and validation

The public v1.2.0 was tested on Kobo Sage. D21 has passed software tests and visual checks at five screen sizes, but still needs testing on a real Sage.

Kindle and PocketBook require a working KOReader installation; custom sleep screens depend on device support. Android can use previews and screenshots with supported official KOReader builds, but InkFolio cannot replace Android's lock screen. F-Droid builds do not support the user patches this project needs. These platforms have not been tested on real devices.

Run software checks with:

```sh
KOREADER_RUNTIME=/path/to/koreader python3 run_checks.py
```

Tests use KOReader's native widgets, fonts, image renderer, and SQLite. They do not contact weather or book services. See [VALIDATION.md](VALIDATION.md) for this build's results and limits.

## Credits and license

Design and development: zacharykim88. Development assistance: OpenAI Codex.

Based on Estela-Zelin84/KOReader_Book-Receipt, with upstream credits to u/hundredpercentcocoa and omer-faruq/koreader-user-patches.

Code and original weather artwork: GPL-3.0. Fonts retain their own licenses. Keep the font license notices included with the original package. The embedded English catalog is mirrored in `localization/en-US.json` for review; that JSON is not a runtime dependency.
