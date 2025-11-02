# 🎯 ScrollCount AMXX Plugin

A Counter-Strike 1.6 AMX Mod X plugin that tracks bunnyhopping efficiency by monitoring scroll patterns and Frames on Ground (FOG).

**Download:** [scrollcount.amxx](https://github.com/frussif/scrollcount/raw/refs/heads/main/scrollcount.amxx)  
Add `scrollcount.amxx` to `plugins.ini`, otherwise it won't work.

Yes, it's AI slop.

---

## 🧭 Command Overview

| Command | Description | Link |
|--------|-------------|------|
| `say /trackscroll` | Starts or stops scroll tracking and shows stats | [See example output](#-example-stats-output) |
| `scrollcount <mode>` | Sets display mode for scroll tracking | [See scrollcount modes](#️-scrollcount-mode) |
| `scrollcounthud <x> <y>` | Sets HUD position (preset or custom) | [See HUD options](#️-scrollcounthud-x-y) |
| `setinfo scrollmode "<mode>"` | Saves display mode setting | [See save settings](#-save-settings) |
| `setinfo scrollhud "<x> <y>"` | Saves HUD position | [See save settings](#-save-settings) |

---

## ⚙️ `scrollcount <mode>`

Toggles or sets the display mode.  
Displays:
- The **number of scroll steps** per jump
- The **exact scroll step** that triggered the jump in brackets `[]`

| Mode | Description |
|------|-------------|
| 0    | Off (no HUD shown) |
| 1    | On (shows scroll count + step that triggers jump) |
| 2    | Adds total duration in milliseconds |
| 3    | Adds intervals between each scroll step |
| 4    | Adds a timeline of 10 frames, starting with first scroll step, `[x]` (+jump landed in frame) and `[0]` (no +jump in frame). Ideally you'd want to register a +jump in every frame for a consistent FOG 1 BHOP, realistically speaking you're more likely to hit every other frame like `[x][0][x][0][x]` |
---

## 🖥️ `scrollcounthud <x> <y>`

Sets the HUD position.

### Presets:
- `scrollcounthud 1` → Center  
- `scrollcounthud 2` → Left  
- `scrollcounthud 3` → Right  

### Custom coordinates:
```bash
scrollcounthud 0.4 0.6
```

---

## 💾 Save Settings

To persist your settings across sessions:

```bash
setinfo scrollmode "3"
setinfo scrollhud "0.4 0.6"
```

---

## 🌟 Features

- Tracks scroll step counts for bunnyhopping
- Shows the exact scroll step that triggers the jump
- Monitors Frames on Ground (FOG) for jump timing analysis
- **Detailed Step Timing Distribution:** Tracks and displays the distribution of jumps for each scroll step (1–10) that successfully triggered a jump. Also tracks the **maximum consecutive combo** achieved for each step.
- **FOG Combo Tracking:** Tracks and displays the distribution of Frames on Ground (FOG 1–10) and the **maximum consecutive combo** achieved for each FOG value.
- Real-time HUD display with customizable position
- Detailed statistics including scroll counts and FOG distribution
- Average scroll duration tracking

---

## 📊 Example Stats Output

This is the output shown when using `say /trackscroll`:

```
*** ScrollCount Summary ***
Total Jumps: 30
Average Steps per Scroll: 7.3
Average Duration per Scroll: 136.0ms

Distribution for Scroll Timing:
Step 1: 4 (13.3%) (3x)  <-- (3x) is the max combo for Step 1
Step 2: 7 (23.3%) (5x)  <-- (5x) is the max combo for Step 2
Step 3: 10 (33.3%) (4x)
Step 4: 5 (16.7%) (2x)
Step 5: 4 (13.3%) (1x)

Frames On Ground Distribution:
FOG 1: 5 (33.3%) (4x)
FOG 2: 4 (26.6%) (3x)
FOG 3: 5 (33.3%) (2x)
```

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
