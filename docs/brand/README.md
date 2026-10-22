# One MCP identity

Three channels converge into one outlet: a visual shorthand for organizing multiple tools behind one deliberate connection. The mark is original project artwork, not the official MCP or OpenAI identity.

- `one-mcp-icon.svg`: editable vector app icon, 256-unit grid.
- `one-mcp-icon.png`: 1024 px transparent PNG.
- `one-mcp-mark.svg`: monochrome mark for light surfaces.
- `one-mcp-mark-light.svg`: mint/white mark for dark surfaces.
- `AppIcon.icns`: generated inside each app bundle by Apple `iconutil`, not hand-encoded or checked in.
- `../../Resources/AppIcon.iconset`: 16/32/128/256/512 pt icons at 1× and 2×.

Palette: ink `#142330`, mint `#65D9CA`, white `#F4FAFA`. Keep the mark upright, preserve proportions, and leave clear space. Do not add dots, gradients, shadows or extra rings. The menu bar intentionally uses a monochrome template version; macOS handles its appearance.

App packaging converts the checked-in iconset with Apple `iconutil`, validates every round-tripped size with `sips`, and declares `CFBundleIconFile=AppIcon`. The sidebar uses the equivalent SwiftUI vector paths. The standard About panel inherits the packaged app icon. App builds need no image-generation software. To regenerate raster assets after editing the SVG, maintainers can run `python3 scripts/regenerate-brand.py` with Inkscape and Pillow installed. Changes to vector geometry must also be mirrored in `BrandMark.swift`.

Validation: PNG dimensions/transparency, ICNS representations, plist and packaging references were checked on Linux; light/dark 16–128 px previews were inspected. Actual Finder/Dock/About rendering requires a native macOS build and was not tested here. No license change is implied by these assets.

2026-10-16 verification: all 11 embedded ICNS PNG representations (16 through1024 pixels, including Retina types) decoded successfully; byte lengths matched the ICNS container, and none contained red-dominant opaque pixels. The 1024-pixel image decoded through Pillow's ICNS reader matched the navy/mint design visually. No built `.app` was available in the Linux workspace. A reported red Finder/Dock thumbnail is therefore not explained by the checked-in icon bytes; its actual location/build must be observed before attributing it to caching or another executable. No cache deletion is recommended by this check.

2026-10-22 small-icon correction: the supplied system-list screenshot shows a corrupted colored app icon, not an in-app SF Symbol. The 16/32 px source PNGs are intact. The previous Python-built ICNS passed Pillow decoding, but that did not establish compatibility with native small-icon rendering. Removed that handpacked artifact and encoder; the macOS packaging path now generates and round-trips ICNS with Apple tools, failing the build if any standard/Retina size is absent or invalid. Existing artwork, vector sidebar and monochrome menu-bar mark are unchanged.

Reference: [Apple, Optimizing for High Resolution](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html).

Linux regression: `python3 scripts/check-app-icons.py` (Pillow required). This checks PNG decoding, exact dimensions, alpha and packaging contracts, not macOS rendering. Native iconutil/sips execution and system-list/Finder/About rendering remain untested in the cloud Linux environment. Rebuild the app to obtain the corrected icon package; an existing installed app is not changed. No cache deletion, bundle-ID change, or user-machine operation is performed.
