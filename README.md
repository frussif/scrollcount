# 🎯 ScrollCount AMXX Plugin

A Counter-Strike 1.6 AMX Mod X plugin that tracks bunnyhopping efficiency by monitoring scroll patterns and Frames on Ground (FOG).

---

## ⚙️ Commands

### `scrollcount <mode>`

Toggles or sets the display mode.

| Mode | Description                                               |
|------|-----------------------------------------------------------|
| 0    | Off (no HUD shown)                                        |
| 1    | On (shows scroll count + step that triggers jump)         |
| 2    | Adds total duration in milliseconds                       |
| 3    | Adds intervals between each scroll                        |

---

### `scrollcounthud <x> <y>`

Sets the HUD position.

#### Presets:
- `scrollcounthud 1` → Center  
- `scrollcounthud 2` → Left  
- `scrollcounthud 3` → Right  

#### Custom coordinates:
```bash
scrollcounthud 0.4 0.6
```

---

### 💾 Save Settings

```bash
setinfo scrollmode "3"
setinfo scrollhud "0.4 0.6"
```

---

## 🌟 Features

- Tracks scroll step counts for bunnyhopping
- Monitors Frames on Ground (FOG) for jump timing analysis
- Quality indicators for scroll patterns:
  - **Perfect**: 1–2 steps
  - **Good**: 3–4 steps
  - **Bad**: 5+ steps
- Real-time HUD display with customizable position
- Detailed statistics including scroll counts and FOG distribution
- Average scroll duration tracking

---

## 🧩 Additional Commands

- `say /trackscroll` — Start/stop tracking scrolls and show statistics
- `scrollcount <mode>` — Set display mode (0=off, 1=on, 2=duration, 3=intervals)
- `scrollcounthud <x> <y>` — Set HUD position

---

## 📦 Installation

1. Copy `scrollcount.amxx` to your `addons/amxmodx/plugins` folder  
2. Add `scrollcount.amxx` to your `plugins.ini`

---

## 🛠️ Building

1. Make sure you have AMXX Compiler installed  
2. Compile `scrollcount.sma` using the AMXX Compiler  
3. Copy the generated `.amxx` file to your plugins folder

---

## 📋 Requirements

- AMX Mod X **1.8.2** or higher  
- Counter-Strike **1.6**
