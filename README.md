# StickitToTheMax

Lightweight native macOS app for pinning color-coded to-do stickies, pictures, and freehand drawings directly to your desktop wallpaper.

🌐 **Website & Interactive Preview:** [flup-repo.github.io/StickitToTheMax](https://flup-repo.github.io/StickitToTheMax/)

![StickitToTheMax stickies, freehand wallpaper drawings, and picture sticky pinned to macOS wallpaper](assets/hero.jpg)

## Download & Install (v1.0.1)

**[Download StickitToTheMax-1.0.1.dmg](https://github.com/flup-repo/StickitToTheMax/releases/download/v1.0.1/StickitToTheMax-1.0.1.dmg)** *(macOS 13+)* · [All Releases](https://github.com/flup-repo/StickitToTheMax/releases/tag/v1.0.1)

1. Download **`StickitToTheMax-1.0.1.dmg`** using the link above.
2. Double-click the `.dmg` file and drag **StickitToTheMax.app** into your **Applications** folder.
3. Launch **StickitToTheMax** from Applications — look for the note icon in your macOS menu bar.
4. *(Optional)* Click the menu bar icon to enable **Launch at Login** and **Automatically Check for Updates** (or use **Check for Updates…** anytime to download & install the latest DMG automatically).

> **First-launch note:** Because this open-source build is ad-hoc signed, macOS Gatekeeper may ask for confirmation on first open. Right-click **StickitToTheMax.app** in Applications → **Open**, or run `xattr -cr /Applications/StickitToTheMax.app` in Terminal.

## Features (v1.0.1)

- **True wallpaper pinning**: Uses `CGWindowLevelForKey(.desktopIconWindow) + 1` with `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle` so stickies and drawings always stay strictly behind normal app windows, across all Spaces, and during Mission Control / **Show Desktop**.
- **Featherweight native macOS**: Pure Swift & AppKit with zero third-party dependencies (~15–25 MB RAM, ~0% idle CPU, no Dock icon clutter).
- **Color-coded to-do stickies**: Inline editable top titles, 6 pastel palettes (Yellow, Blue, Green, Pink, Purple, Orange), and quick category presets (`Work`, `Personal`, `Ideas`, `Urgent`, `Errands`).
- **Mark as done**: Click the checkmark (`✓`) in any sticky's header to cross out the title and text with strikethrough and subtle dimming, or clear all done stickies in one click from the menu bar.
- **Freehand wallpaper drawing (`⌥⇧D`)**:
  - Toggle Drawing Mode from anywhere with **Option + Shift + D** (or from the menu bar).
  - Smooth freehand **Pen (`P`)** with 8 colors and resizable tip (`2–24 pt`, slider or `[` / `]`).
  - **Stroke Eraser (`E`)** to swipe away individual strokes, plus **Undo (`⌘Z`)** and **Clear All**.
  - Drawings stay pinned to your wallpaper as crisp vector strokes and pass clicks straight through once you exit Drawing Mode (`Esc` or **Done**).
- **Picture stickies**:
  - Pin any image from disk (**New Picture Sticky…** / `⌘I`) or straight from your clipboard (**Paste Picture Sticky**).
  - Resizes smoothly from any corner while preserving aspect ratio (down to `190×140` or up to `1200×1200`), with editable title, color header, and automatic local image storage.
- **Multi-select & group actions**:
  - Drag a marquee selection box on the wallpaper or `⌘+Click` stickies to move, resize, and adjust font sizes (`⌘+`, `⌘-`, `⌘0`) together.
- **Monitor-switch layout preservation**:
  - Switching between an external display and your built-in MacBook screen uniformly scales and fits all stickies and drawings together so order and arrow alignment stay intact, and restores your exact original layout when plugging back in.
- **In-app updates, Launch at Login & automatic persistence**:
  - Click **Check for Updates…** in the menu bar to automatically download and install the latest GitHub Release `.dmg`, or enable **Automatically Check for Updates** to stay updated in the background.
  - Toggle **Launch at Login** directly from the menu bar via native `SMAppService`.
  - Stickies, drawings, and imported pictures save automatically to `~/Library/Application Support/StickitToTheMax/`.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌥⇧D` | Toggle Drawing Mode (global) |
| `P` / `E` | Switch between Pen and Stroke Eraser (in Drawing Mode) |
| `[` / `]` | Decrease / increase pen or eraser size (in Drawing Mode) |
| `⌘Z` | Undo last draw or erase (in Drawing Mode) |
| `⌘+` / `⌘-` / `⌘0` | Increase / decrease / reset sticky font size |
| `⌘+Click` or Wallpaper Drag | Multi-select stickies |
| `Esc` | Exit Drawing Mode or clear selection |

## Build from Source (Developers)

Requires macOS 13+ and Swift / Xcode Command Line Tools.

```bash
# Run unit tests
swift test

# Build release .app bundle
./scripts/bundle.sh

# Build release .dmg installer
./scripts/create-dmg.sh

# Launch the app
open build/StickitToTheMax.app
```
