# One MCP identity

Three channels converge into one outlet: a visual shorthand for organizing multiple tools behind one deliberate connection. The mark is original project artwork, not the official MCP or OpenAI identity.

- `one-mcp-icon.svg`: editable vector app icon, 256-unit grid.
- `one-mcp-icon.png`: 1024 px transparent PNG.
- `one-mcp-mark.svg`: monochrome mark for light surfaces.
- `one-mcp-mark-light.svg`: mint/white mark for dark surfaces.
- `../../Resources/AppIcon.icns`: bundled macOS icon, PNG-backed representations through 1024 px.
- `../../Resources/AppIcon.iconset`: 16/32/128/256/512 pt icons at 1× and 2×.

Palette: ink `#142330`, mint `#65D9CA`, white `#F4FAFA`. Keep the mark upright, preserve proportions, and leave clear space. Do not add dots, gradients, shadows or extra rings. The menu bar intentionally uses a monochrome template version; macOS handles its appearance.

App packaging copies the checked-in ICNS and declares `CFBundleIconFile=AppIcon`. The sidebar uses the equivalent SwiftUI vector paths. The standard About panel inherits the packaged app icon. App builds need no image-generation software. To regenerate raster assets after editing the SVG, maintainers can run `python3 scripts/regenerate-brand.py` with Inkscape and Pillow installed. Changes to vector geometry must also be mirrored in `BrandMark.swift`.

Validation: PNG dimensions/transparency, ICNS representations, plist and packaging references were checked on Linux; light/dark 16–128 px previews were inspected. Actual Finder/Dock/About rendering requires a native macOS build and was not tested here. No license change is implied by these assets.
