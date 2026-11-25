# StickitToTheMax

Lightweight native macOS app for pinning to-do stickies directly to your desktop wallpaper.

![StickitToTheMax stickies pinned to macOS wallpaper](assets/hero.jpg)

## Why Swift + AppKit?

- **Minimal memory & CPU**: Pure native AppKit with zero third-party dependencies, no Electron/WebView overhead (~15–25 MB RAM, ~0% idle CPU).
- **True wallpaper pinning**: Uses `CGWindowLevelForKey(.desktopIconWindow) + 1` with `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle` so stickies stay strictly beneath normal application windows, remain visible across Spaces, and stay glued to the wallpaper during Mission Control / **Show Desktop**.

## MVP Features

- **Wallpaper-only stickies**: Always stay behind open app windows; visible whenever you view your desktop.
- **Top title per sticky**: Inline editable header (e.g. `Work`, `Personal`, `Ideas`).
- **Color coding**: 6 sticky colors (Yellow, Blue, Green, Pink, Purple, Orange) with quick category presets from the menu bar.
- **Mark as done**: Click the checkmark button (`✓`) in a sticky's header to cross out the title and text with strikethrough and subtle dimming.
- **Create, move, resize, delete**:
  - Drag the header bar to reposition on the wallpaper.
  - Resize from any edge/corner or via the bottom-right grip.
  - Click `+` on a sticky (or use the menu bar icon) to add new stickies.
  - Click `×` to delete a sticky (with confirmation when it has text), or clear all done stickies from the menu bar.
- **Automatic persistence**: Saved to `~/Library/Application Support/StickitToTheMax/stickies.json`.

## Build & Run

```bash
# Run unit tests
swift test

# Build release .app bundle
chmod +x scripts/bundle.sh
./scripts/bundle.sh

# Launch the app
open build/StickitToTheMax.app
```

To keep it running automatically on login, drag `build/StickitToTheMax.app` into `/Applications` and add it under **System Settings → General → Login Items**.
