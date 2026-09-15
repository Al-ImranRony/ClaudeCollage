# Licenses — content rights in Caroullage

Step 06 phase 6.6 (App Review guideline 5.2, content rights). Everything the
app ships that it did not author, and the terms it ships under. Kept in the
repo so the answer to "is that licensed?" is a file, not a memory.

| What | Where in the repo | Licence | Notes |
|---|---|---|---|
| Sample photography and video loops on Home's showcase (~24 photos, 3 loops) | `Caroullage/Resources/SampleContent/` | [Pexels License](https://www.pexels.com/license/) — free for commercial use, attribution not required | Per-file photographer credits and source URLs in `SampleContent/ATTRIBUTION.md`. No recognisable public figure; model-released lifestyle stock, chosen for exactly that reason. |
| Sticker glyphs (all packs) | `Caroullage/Resources/Stickers/*.json` reference SF Symbol names | Apple's [SF Symbols licence](https://developer.apple.com/sf-symbols/) — usable as-is in apps for Apple platforms | No symbol is exported outside the app except rendered into the user's own collage, which the licence permits; none is used as a logo or app icon. |
| Typefaces offered in the text style sheet (System, Helvetica, Avenir, Georgia…) | Resolved at runtime by name; `Caroullage/Resources/Fonts/` is empty | Bundled with iOS — Apple's platform fonts, licensed to apps on the platform | Nothing is embedded. `TextStyleSheet.fontPreview` falls back to the system font when a name is absent. |
| Template geometry (`Templates/`, `CarouselTemplates/`) | `Caroullage/Resources/` | Authored for Caroullage | Original work; the JSON describes zones, not art. |
| App icon | `Tools/IconGenerator/main.swift` | Authored for Caroullage | Drawn in code; no third-party mark. |
| Third-party SDKs | — | — | None. `project.yml` declares no packages; the privacy manifest is the app's own. |

If a future asset arrives with a licence that requires attribution, add the
attribution text to this folder and a row above.
