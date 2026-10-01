# Clip 📎

A sleek, minimalistic macOS clipboard manager built with **Swift**, **SwiftUI**, and **AppKit**. Designed with pure minimalism and Apple's **Liquid Glass** aesthetic.

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue?style=flat-square)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## ✨ Philosophy & Design

When you press **`⇧⌘V` (Shift + Cmd + V)**, Clip opens **only** a clean, distraction-free liquid glass list of your recent clipboard items:
- **Zero Clutter**: No search bars, no category tabs, no clue banners, no side panels, and no complicated menus.
- **Liquid Glass Aesthetic**: Native frosted translucency (`NSVisualEffectView` HUD vibrancy), subtle specular glass border, and soft ambient drop shadows.
- **Configurable History Limit**: Keeps recent copied items (default 30, customizable up to 100 in Settings) with automatic deduplication.
- **Effortless Paste**:
  - Click any item, or navigate with `↑` / `↓` and hit `Return` to paste directly into your active app.
  - Press `Esc` or click outside to dismiss.
- **Dedicated Settings Window (`⌘,`)**:
  - Right-click the menubar icon to open Settings.
  - Adjust history limit (10–100 items), toggle auto-paste, enable sound effects, configure palette width and height presets, set text preview line count, or clear history.
- **Autorun on Boot**: Automatically runs when your Mac turns on via macOS `SMAppService` and `LaunchAgent`.
- **Menubar Companion**: Lives unobtrusively in your status bar (`paperclip` icon) with quick access to launch settings, preferences, and quit.

---

## ⌨️ How to Use

| Interaction | Action |
| :--- | :--- |
| **`⇧ ⌘ V`** (`Shift + Cmd + V`) | **Open clipboard list anywhere** |
| **`↑` / `↓`** | Move selection up and down |
| **`Return` / `Enter`** | Paste selected item into active application and close |
| **Click** | Click any item to paste it directly |
| **`Esc`** | Dismiss list |

---

## 🚀 Quick Start

### 1. Build and Run
From the `Clip` directory:
```bash
make run
```
or:
```bash
./scripts/build_app.sh --run
```

### 2. Install to Applications
To install `Clip.app` into `~/Applications`:
```bash
make install
```

### 3. Open in Xcode
```bash
open Package.swift
```

---

## 🏗️ Architecture

```
Clip/
├── Package.swift               # Swift Package manifest (macOS 13+)
├── Makefile                    # Build & run helpers
├── scripts/
│   ├── build_app.sh            # Release build & app bundle script
│   └── generate_icon.swift     # Liquid glass AppIcon generator
└── Sources/Clip/
    ├── main.swift              # App entry point
    ├── App/
    │   └── AppDelegate.swift   # Status bar item & window controller
    ├── Models/
    │   ├── ClipItem.swift      # Model for text, images, code, colors
    │   └── ClipboardManager.swift # 30-item clipboard monitor & persistence
    ├── Services/
    │   ├── HotkeyManager.swift # Carbon RegisterEventHotKey for ⇧⌘V
    │   ├── LaunchAtLoginManager.swift # SMAppService & LaunchAgent autorun
    │   └── PasteHelper.swift   # CGEvent direct paste into target app
    └── UI/
        ├── FloatingPanel.swift # Frameless liquid glass NSPanel
        ├── ClipboardListView.swift # Pure, minimal list of clipboard items
        └── LiquidGlassModifiers.swift # Frosted glass shaders and borders
```

---

## 📄 License
MIT License.
