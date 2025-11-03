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
| 5    | Scroll trainer, indicates scroll timing and scroll consistency, also shows up in /trackscroll output [click for specific info](https://github.com/frussif/scrollcount?tab=readme-ov-file#-timing-categories) |

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
- Scroll trainer

---

## 📊 Example Stats Output

This is the output shown when using `say /trackscroll`:

```

*** ScrollCount Summary ***
Total Jumps: 44

Scroll timing distribution:
Step 1: 2 (4.5%) (Best streak: 1x)
Step 2: 6 (13.6%) (Best streak: 2x)
Step 3: 20 (45.4%) (Best streak: 5x)
Step 4: 12 (27.2%) (Best streak: 3x)
Step 5: 4 (9.0%) (Best streak: 2x)
Avg steps/scroll: 5.1
Avg duration/scroll: 82.9 ms

FOG distribution:
FOG 1: 23 (52.2%) (Best streak: 6x)
FOG 2: 17 (38.6%) (Best streak: 3x)
FOG 3: 4 (9.0%) (Best streak: 2x)

Timing distribution:
Perfect Timing: 8 (18.1%) (Best streak: 2x)
Good Timing: 20 (45.4%) (Best streak: 5x)
Scrolling a little early: 12 (27.2%) (Best streak: 3x)
Scrolling too early: 4 (9.0%) (Best streak: 2x)

Consistency distribution:
Perfect Consistency: 7 (15.9%) (Best streak: 2x) 
Good Consistency: 17 (38.6%) (Best streak: 4x)
Good, slightly inconsistent: 20 (45.4%) (Best streak: 4x)
```
## ⏱ Timing Categories

| Category                 | Trigger Step (T) | FOG (F) | Basis                                                                 |
|--------------------------|------------------|--------|------------------------------------------------------------------------|
| Perfect Timing           | T ≤ 2            | F ≤ 2  | Ideal ground hit and setup.                                           |
| Good Timing              | T = 3            | F ≤ 2  | Hit the ground slightly later, but FOG timing was good.               |
| Scrolling a little early | T = 4            | F ≤ 2  | Hit the ground late; scroll likely started slightly too early.        |
| Scrolling too early      | T ≥ 5            | F ≤ 2  | Hit the ground very late; scroll started significantly too early.     |
| Scrolling too late       | T ≤ 4            | F ≥ 3  | High FOG means you waited too long on the ground before initiating the jump. |
| Terrible scroll          | T ≥ 5            | F ≥ 3  | Both the ground hit was late and the FOG timing was poor.             |

## 🎯 Consistency Categories

| Category                   | Condition                                                                 | Basis                                                                 |
|----------------------------|---------------------------------------------------------------------------|------------------------------------------------------------------------|
| Perfect Consistency        | Density ≥ 60.0% max of 1 consecutive frame missed ([x][x][0][x][0][x])           | Not actually 'Perfect' but the ideal situation considering human and hardware limitation. FOG 2 in the worst case scenario.|
| Good Consistency           | Density ≥ 60.0% and missed 2 consecutive frames ([x][x][0][0][x][x])                   | High input density, but not strictly perfect rhythm, slight chance of FOG 3. |
| Good, slightly inconsistent| Density ≥ 40.0%                                                           | Moderate input density, with noticeable missed frames, higher chance of FOG 3. |
| Bad Scroll                 | Density ≥ 30.0%                                                           | Low density, but inputs still covered a minimal amount of frames.     |
| Terrible Consistency       | ≥3 instances of two or more consecutive empty frames ([x][0][0][x]...)   | A rhythm-based failure, indicating frequent long pauses between inputs. |
| Terrible Scroll            | Density < 30.0%                                                           | Very low input density; many scroll frames were missed.               |

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
