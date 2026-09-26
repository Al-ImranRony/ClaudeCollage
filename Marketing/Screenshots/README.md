# App Store screenshots

Generated, not authored: `Tools/screenshots.sh` runs `AppStoreScreenshotUITests` on
each device and language, exports the captures, and `Tools/ScreenshotFramer` sets
each one under its caption from `captions.json` at the device's exact pixel size.
The PNGs are gitignored; regenerate before an upload. v1 is iPhone-only, so App
Store Connect asks for the 6.9" iPhone set and no iPad screenshots.

    Tools/screenshots.sh                       # iPhone 16 Pro Max (6.9"), all 11 languages
    LANGUAGES="en" Tools/screenshots.sh "iPhone 16 Pro Max"

Scenes (`-ScreenshotMode` fills the editors with the bundled sample photography):

| # | Scene | Route |
|---|---|---|
| 1 | Carousel editor, frames filled | Start Editing → Carousel → Matched → Create |
| 2 | Hexagon shape collage | Home → Shapes |
| 3 | Template gallery | Collage tab |
| 4 | Video collage, clips playing | Home → Video |
| 5 | Video collage, timeline expanded | ↑ chevron |
| 6 | Home showcase | Home |

A caption may carry an explicit line break (`\n`) where a language's natural break is
not a space (the CJK strings do). Chrome that is still English in a localized
screenshot — a nav title, a tool name — is a UIKit literal not yet in the String
Catalog (`docs/step-06-account-gated.md`, phase 6.4); regenerate after that pass.

The brief's fifth scene — the subject lift before/after — needs Vision, which the
simulator does not run. Capture it on a device: run the same test from Xcode on an
iPhone, then lift a subject by hand and screenshot; the framer takes any PNG.
Scene 6 stands in until then.
