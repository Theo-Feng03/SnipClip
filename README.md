# SnipClip

SnipClip is a macOS clipboard manager combined with a Snipaste-inspired screenshot capture and annotation tool.

It's a personal fork built on top of [Clipy](https://github.com/Clipy/Clipy) (MIT licensed) — the clipboard-history engine is Clipy's, and the `Snip/` module (region capture, annotation, pin-to-screen) is original code written for this fork, since Snipaste itself is closed-source.

---

__Requirement__: macOS 13 Ventura or later

### Development Environment
* macOS 26 Tahoe
* Xcode 26.5

### How to Build
1. Open `SnipClip.xcodeproj` in Xcode.
2. Build the `SnipClip` scheme. Code signing is ad-hoc by default (see `Configurations/CodeSigning.xcconfig`), so no developer account is required for local builds.

### Features
- Clipboard history, snippets, and preferences: inherited from Clipy.
- Region screenshot capture (default hotkey: Fn+F1), annotation (shapes, text, mosaic, border), and pin-to-screen: see `Clipy/Snip/`.
- Snip defaults (hotkey, default tool/color/line width, border) are configurable in Preferences → Snip.

### Licence
MIT — see [LICENSE](./LICENSE) and [LICENSE_CLIPMENU](./LICENSE_CLIPMENU) (Clipy is itself a fork of ClipMenu).

Icons are placeholder art generated from SF Symbols pending real design.
