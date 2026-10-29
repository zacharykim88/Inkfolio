# English UI catalog

The runtime catalog is embedded in `2-inkfolio.lua`, keeping installation to one patch file. `en-US.json` is an exact review snapshot of that catalog. Update the source catalog first and regenerate this snapshot after changing English text.

Use American spelling: canceled, gray, and license. Menu labels use title case; messages and weather conditions use sentence case. Prefer clear actions such as Save, Cancel, Reset, Search, Remove Match, and Update Information. Reading cards use short labels such as Progress, Est. Words Read, This Session, and Time Left. Use Douban Monthly Rankings for the source's ranked book list.

Translate complete sentences where English word order differs. Never translate book metadata, user input, remote parser field names, source category identifiers, station codes, filenames, or settings keys. Translate cached weather conditions when displaying them, preserving the original Chinese forecast cache. Missing or mixed conditions keep their original text instead of receiving an invented icon.

Config labels resolve in the current language at access time. Persisted targets and display settings remain independent of language. Changing a language rebuilds only InkFolio's settings and updates its three existing gesture action IDs.
