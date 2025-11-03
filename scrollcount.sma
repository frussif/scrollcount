#include <amxmodx>
#include <fakemeta>

/*
    Scroll Counter
    - Airborne filtering (ignore walk-jumps)
    - 6-frame ground cooldown
    - Modes:
        0: Off
        1: Steps [trigger]
        2: Duration ms
        3: Intervals ms (+ total)
        4: Header + timeline boxes [x]/[0] with slight left alignment
        5: Timing/Consistency Analysis (NEW)
    - Per-player setinfo persistence: scrollmode, scrollhud ("x y")
    - Tracking console summary (/trackscroll) with distributions and combos
    - Robust finalize window (re-arms on each step), no task leaks
    - Optimized HUD building (precomputed frame indices, minimized float ops)
*/

#define PLUGIN  "Scroll Counter"
#define VERSION "1.7"
#define AUTHOR  "Copilot"

// ----------------- Config -----------------
const Float:JUMP_WINDOW       = 0.20;     // seconds to accumulate scroll steps
const FOG_COOLDOWN_FRAMES     = 6;        // ignore jump if grounded >= 6 frames before press
const TASK_FINALIZE_BASE      = 42420;    // base for per-player finalize task id
const HUD_CHANNEL_HEADER      = 4;        // header line channel
const HUD_CHANNEL_TIMELINE    = 5;        // timeline line channel
const Float:HUD_HOLD          = 5.0;      // seconds to keep HUD visible

// Mode 4 layout
const BOX_COUNT               = 10;       // number of boxes shown in the timeline
const Float:ROW_LEFT_SHIFT    = 0.05;     // small left shift to visually align under header

// ----------------- Mode 5 Constants and Names -----------------
#define MAX_MODE5_CATEGORIES 6

// Timing Indices
#define TIMING_PERFECT_IDX      0
#define TIMING_GOOD_T3_IDX      1
#define TIMING_EARLY_T4_IDX     2 // Scrolling a little early
#define TIMING_TOO_EARLY_IDX    3 // Trigger >= 5, Fog <= 2
#define TIMING_TOO_LATE_IDX     4 // Trigger 1-4, Fog >= 3
#define TIMING_TERRIBLE_IDX     5 // Trigger >= 5, Fog >= 3

// Consistency Indices
#define CONSIST_PERFECT_IDX     0
#define CONSIST_TERRIBLE_R_IDX  1 // twoFrameGapsCount >= 3 (Rhythm)
#define CONSIST_GOOD_PCT_IDX    2 // density_pct >= 60.0
#define CONSIST_GOOD_INCON_IDX  3 // density_pct >= 40.0
#define CONSIST_BAD_SCROLL_IDX  4 // density_pct >= 30.0
#define CONSIST_TERRIBLE_S_IDX  5 // density_pct < 30.0 (Percentage)

// Global string arrays for console output names (CONCISE FORMAT)
new const g_sTimingNames[MAX_MODE5_CATEGORIES][] = {
    "Perfect Timing", 
    "Good Timing",
    "Scrolling a little early",
    "Scrolling too early",
    "Scrolling too late", 
    "Terrible scroll"
};

new const g_sConsistNames[MAX_MODE5_CATEGORIES][] = {
    "Perfect Consistency", 
    "Terrible Consistency", // Index 1: Rhythm-based
    "Good Consistency",
    "Good, slightly inconsistent", 
    "Bad Scroll",
    "Terrible Scroll"       // Index 5: Percentage-based
};

// ----------------- State -----------------
new jumpCount[33];
new triggerIndex[33];
new Float:lastJumpTime[33];
new bool:timerActive[33];

new Float:scrollStartTime[33];
new Float:scrollEndTime[33];
new Float:scrollTimes[33][32];     // timestamps
new frameIndices[33][32];          // cached frame indices (int) for scrollTimes

new bool:isTracking[33];
new triggerStats[33][10];

new totalJumpsTracked[33];
new totalScrollsTracked[33];
new Float:totalDurationTracked[33];

new g_iFog[33];             // consecutive frames on ground
new bool:g_isOldGround[33]; // previous frame ground state
new fogStats[33][10];

new currentFogCombo[33][10];
new maxFogCombo[33][10];

new currentScrollCombo[33][10];
new maxScrollCombo[33][10];

new Float:hudX[33];
new Float:hudY[33];
new scrollMode[33];
new triggerFog[33]; // NEW: FOG value at the moment the trigger jump occurred

new bool:wasAirborneBeforeScroll[33]; // any jump in sequence happened while airborne (prev frame off ground)

// NEW: Mode 5 tracking arrays
new timingStats[33][10];
new maxTimingCombo[33][10];
new currentTimingCombo[33][10];

new consistencyStats[33][10];
new maxConsistencyCombo[33][10];
new currentConsistencyCombo[33][10];

// ----------------- Helpers -----------------
stock taskid_final(id) { return TASK_FINALIZE_BASE + id; }

stock clamp01f(Float:x) {
    if (x < 0.0) return 0.0;
    if (x > 1.0) return 1.0;
    return x;
}

// ----------------- AMXX -----------------
public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    register_forward(FM_CmdStart,      "fw_CmdStart");
    register_forward(FM_PlayerPreThink,"fw_PlayerPreThink");

    register_clcmd("say /trackscroll",      "cmd_trackscroll");
    register_clcmd("say_team /trackscroll", "cmd_trackscroll");
    register_concmd("scrollcount",          "cmd_scrollcount");
    register_concmd("scrollcounthud",       "cmd_scrollcounthud");
}

// ----------------- Init/reset -----------------
public reset_tracking(id) {
    isTracking[id] = false;

    jumpCount[id] = 0;
    triggerIndex[id] = 0;
    triggerFog[id] = 0; // NEW: Reset FOG index
    timerActive[id] = false;

    lastJumpTime[id] = 0.0;
    scrollStartTime[id] = 0.0;
    scrollEndTime[id]   = 0.0;

    totalJumpsTracked[id]   = 0;
    totalScrollsTracked[id] = 0;
    totalDurationTracked[id] = 0.0;

    g_iFog[id]        = 0;
    g_isOldGround[id] = false;

    wasAirborneBeforeScroll[id] = false;

    for (new i = 0; i < 10; i++) {
        fogStats[id][i]          = 0;
        triggerStats[id][i]      = 0;
        currentFogCombo[id][i]   = 0;
        maxFogCombo[id][i]       = 0;
        currentScrollCombo[id][i] = 0;
        maxScrollCombo[id][i]      = 0;
        
        // NEW: Reset Mode 5 stats
        timingStats[id][i]            = 0;
        currentTimingCombo[id][i]     = 0;
        maxTimingCombo[id][i]         = 0;

        consistencyStats[id][i]       = 0;
        currentConsistencyCombo[id][i] = 0;
        maxConsistencyCombo[id][i]     = 0;
    }

    // No dangling finalize task
    remove_task(taskid_final(id));
}

public init_player_settings(id) {
    scrollMode[id] = 1;
    hudX[id] = 0.50;
    hudY[id] = 0.50;

    // Read persisted settings
    new modeStr[8], hudStr[32];
    get_user_info(id, "scrollmode", modeStr, charsmax(modeStr));
    get_user_info(id, "scrollhud",  hudStr,  charsmax(hudStr));

    if (modeStr[0]) {
        new m = str_to_num(modeStr);
        // UPDATED: Allow mode 5
        if (m >= 0 && m <= 5) scrollMode[id] = m;
    }

    if (hudStr[0]) {
        new xStr[16], yStr[16];
        if (parse(hudStr, xStr, charsmax(xStr), yStr, charsmax(yStr)) == 2) {
            new Float:px = str_to_float(xStr);
            new Float:py = str_to_float(yStr);
            hudX[id] = clamp01f(px);
            hudY[id] = clamp01f(py);
        }
    }
}

public client_connect(id)       { reset_tracking(id); init_player_settings(id); }
public client_disconnected(id)  { reset_tracking(id); }

// ----------------- Commands -----------------
public cmd_trackscroll(id) {
    if (!isTracking[id]) {
        reset_tracking(id);
        isTracking[id] = true;
        client_print(id, print_chat,    "[ScrollCount] Tracking started");
        client_print(id, print_console, "*** ScrollCount: Tracking started ***");
    } else {
        isTracking[id] = false;
        client_print(id, print_chat,    "[ScrollCount] Tracking stopped. See console for summary.");

        new total = totalJumpsTracked[id];
        if (total == 0) {
            client_print(id, print_console, "*** ScrollCount: No jumps recorded ***");
            return PLUGIN_HANDLED;
        }

        new Float:avgScrolls  = totalScrollsTracked[id] / float(totalJumpsTracked[id]);
        new Float:avgDuration = (totalDurationTracked[id] * 1000.0) / totalJumpsTracked[id];

        client_print(id, print_console, "*** ScrollCount Summary ***");
        client_print(id, print_console, "Total Jumps: %d", total);

        // 1. Scroll timing distribution
        client_print(id, print_console, "^nScroll timing distribution:");
        for (new i = 0; i < 10; i++) {
            if (triggerStats[id][i] > 0) {
                new Float:pct = (triggerStats[id][i] * 100.0) / total;
                client_print(id, print_console, "Step %d: %d (%.1f%%) (Best streak: %dx)",
                             i + 1, triggerStats[id][i], pct, maxScrollCombo[id][i]);
            }
        }

        client_print(id, print_console, "Avg steps/scroll: %.1f", avgScrolls);
        client_print(id, print_console, "Avg duration/scroll: %.1f ms", avgDuration);
        
        // 2. FOG distribution
        client_print(id, print_console, "^nFOG distribution:");
        new totalFogFrames = 0;
        for (new i = 0; i < 10; i++) totalFogFrames += fogStats[id][i];
        if (totalFogFrames > 0) {
            for (new i = 0; i < 10; i++) {
                if (fogStats[id][i] > 0) {
                    new Float:fogPct = (fogStats[id][i] * 100.0) / totalFogFrames;
                    client_print(id, print_console, "FOG %d: %d (%.1f%%) (Best streak: %dx)",
                                 i + 1, fogStats[id][i], fogPct, maxFogCombo[id][i]);
                }
            }
        }
        
        // 3. Mode 5 Timing distribution
        client_print(id, print_console, "^nTiming distribution:");
        new totalTimingCount = 0;
        for (new i = 0; i < MAX_MODE5_CATEGORIES; i++) totalTimingCount += timingStats[id][i];
        
        if (totalTimingCount > 0) {
            // Print order for timing (0, 1, 2, 3, 4, 5) is fine as is
            for (new i = 0; i < MAX_MODE5_CATEGORIES; i++) {
                if (timingStats[id][i] > 0) {
                    new Float:pct = (timingStats[id][i] * 100.0) / totalTimingCount;
                    client_print(id, print_console, "%s: %d (%.1f%%) (Best streak: %dx)",
                                 g_sTimingNames[i], timingStats[id][i], pct, maxTimingCombo[id][i]);
                }
            }
        }

        // 4. Mode 5 Consistency distribution
        client_print(id, print_console, "^nConsistency distribution:");
        new totalConsistCount = 0;
        for (new i = 0; i < MAX_MODE5_CATEGORIES; i++) totalConsistCount += consistencyStats[id][i];

        if (totalConsistCount > 0) {
            // Custom print order: Good categories first, Terrible categories last
            new const printOrder[MAX_MODE5_CATEGORIES] = {
                CONSIST_PERFECT_IDX,    // 0: Perfect Consistency
                CONSIST_GOOD_PCT_IDX,   // 2: Good Consistency
                CONSIST_GOOD_INCON_IDX, // 3: Good, slightly inconsistent
                CONSIST_BAD_SCROLL_IDX, // 4: Bad Scroll
                CONSIST_TERRIBLE_R_IDX, // 1: Terrible Consistency (Rhythm)
                CONSIST_TERRIBLE_S_IDX  // 5: Terrible Scroll (Percentage)
            };

            for (new j = 0; j < MAX_MODE5_CATEGORIES; j++) {
                new i = printOrder[j]; // The actual index to look up
                if (consistencyStats[id][i] > 0) {
                    new Float:pct = (consistencyStats[id][i] * 100.0) / totalConsistCount;
                    client_print(id, print_console, "%s: %d (%.1f%%) (Best streak: %dx)",
                                 g_sConsistNames[i], consistencyStats[id][i], pct, maxConsistencyCombo[id][i]);
                }
            }
        }
    }
    return PLUGIN_HANDLED;
}

public cmd_scrollcount(id) {
    new arg[8];
    read_argv(1, arg, charsmax(arg));
    new mode = str_to_num(arg);
    // UPDATED: Allow mode 5
    if (mode < 0 || mode > 5) {
        client_print(id, print_chat, "[ScrollCount] Usage: scrollcount 0(off),1,2,3,4(timeline),5(analysis)");
        return PLUGIN_HANDLED;
    }
    scrollMode[id] = mode;

    // Persist to setinfo
    new modeStr[8];
    num_to_str(mode, modeStr, charsmax(modeStr));
    set_user_info(id, "scrollmode", modeStr);

    client_print(id, print_chat, "[ScrollCount] Mode %d activated.", mode);
    return PLUGIN_HANDLED;
}

public cmd_scrollcounthud(id) {
    new arg1[16], arg2[16];
    read_argv(1, arg1, charsmax(arg1));
    read_argv(2, arg2, charsmax(arg2));

    new Float:px = str_to_float(arg1);
    new Float:py = str_to_float(arg2);
    hudX[id] = clamp01f(px);
    hudY[id] = clamp01f(py);

    // Persist to setinfo as "x y"
    new hudStr[32];
    format(hudStr, charsmax(hudStr), "%.2f %.2f", hudX[id], hudY[id]);
    set_user_info(id, "scrollhud", hudStr);

    client_print(id, print_chat, "[ScrollCount] HUD set: X=%.2f, Y=%.2f", hudX[id], hudY[id]);
    return PLUGIN_HANDLED;
}

// ----------------- Core -----------------
public fw_CmdStart(id, uc_handle, seed) {
    if (!is_user_alive(id))
        return FMRES_IGNORED;

    static buttons;
    buttons = get_uc(uc_handle, UC_Buttons);

    if (buttons & IN_JUMP) {
        // Ignore if grounded too long before press
        if (g_iFog[id] >= FOG_COOLDOWN_FRAMES)
            return FMRES_IGNORED;

        // Mark airborne involvement (previous frame was off ground)
        if (!wasAirborneBeforeScroll[id] && !g_isOldGround[id])
            wasAirborneBeforeScroll[id] = true;

        new Float:now = get_gametime();

        if (!timerActive[id]) {
            // Start new sequence
            timerActive[id] = true;

            jumpCount[id]   = 1;
            triggerIndex[id]= 0;
            triggerFog[id] = 0; // Reset FOG for the new sequence
            lastJumpTime[id]= now;

            scrollStartTime[id] = now;
            scrollEndTime[id]   = now;
            scrollTimes[id][0]  = now;
            frameIndices[id][0] = floatround(now * 100.0); // cache frame index @100 fps

            if (pev(id, pev_flags) & FL_ONGROUND) {
                triggerIndex[id] = 1;
                triggerFog[id] = g_iFog[id]; // NEW: Capture FOG for trigger jump
            }

            // Arm finalize task; re-armed on each step
            remove_task(taskid_final(id));
            set_task(JUMP_WINDOW, "finalize_jump_count", taskid_final(id));
        } else if ((now - lastJumpTime[id]) <= JUMP_WINDOW && jumpCount[id] < 32) {
            // Add step and extend window
            new idx = jumpCount[id]; // next slot
            jumpCount[id]++;
            lastJumpTime[id] = now;
            scrollEndTime[id] = now;
            scrollTimes[id][idx]  = now;
            frameIndices[id][idx] = floatround(now * 100.0);

            if (triggerIndex[id] == 0 && (pev(id, pev_flags) & FL_ONGROUND)) {
                triggerIndex[id] = jumpCount[id];
                triggerFog[id] = g_iFog[id]; // NEW: Capture FOG for trigger jump
            }

            // Re-arm finalize relative to last step
            remove_task(taskid_final(id));
            set_task(JUMP_WINDOW, "finalize_jump_count", taskid_final(id));
        }
    }
    return FMRES_IGNORED;
}

public finalize_jump_count(taskid) {
    new id = taskid - TASK_FINALIZE_BASE;
    if (id < 1 || id > 32) return;

    timerActive[id] = false;

    // Skip if no ground contact or never airborne
    if (triggerIndex[id] == 0 || !wasAirborneBeforeScroll[id]) {
        wasAirborneBeforeScroll[id] = false;
        // Clean sequence
        jumpCount[id] = 0;
        triggerIndex[id] = 0;
        triggerFog[id] = 0; // Clean triggerFog
        return;
    }

    // Tracking stats
    if (isTracking[id]) {
        new trigger = triggerIndex[id];
        new idx = trigger - 1;

        if (trigger > 0 && trigger <= 10) {
            for (new i = 0; i < 10; i++) {
                if (i == idx) {
                    currentScrollCombo[id][i]++;
                    if (currentScrollCombo[id][i] > maxScrollCombo[id][i])
                        maxScrollCombo[id][i] = currentScrollCombo[id][i];
                } else {
                    currentScrollCombo[id][i] = 0;
                }
            }
            triggerStats[id][idx]++;
        } else {
            for (new i = 0; i < 10; i++) currentScrollCombo[id][i] = 0;
        }

        totalJumpsTracked[id]++;
        totalScrollsTracked[id] += jumpCount[id];
        totalDurationTracked[id] += (scrollEndTime[id] - scrollStartTime[id]);
        
        // ----------------- NEW: Mode 5 Tracking Logic -----------------
        new fog = triggerFog[id];
        new timing_idx = -1;
        new consistency_idx = -1;
        
        // --- Timing Logic ---
        if (fog <= 2) {
            if (trigger >= 1 && trigger <= 2) {
                timing_idx = TIMING_PERFECT_IDX;
            } else if (trigger == 3) {
                timing_idx = TIMING_GOOD_T3_IDX;
            } else if (trigger == 4) {
                timing_idx = TIMING_EARLY_T4_IDX;
            } else { // trigger >= 5
                timing_idx = TIMING_TOO_EARLY_IDX;
            }
        } else { // fog >= 3 (FOG is bad)
            if (trigger >= 1 && trigger <= 4) {  
                timing_idx = TIMING_TOO_LATE_IDX;
            } else { // trigger >= 5
                timing_idx = TIMING_TERRIBLE_IDX;
            }
        }
        
        // Update Timing Stats and Combo
        if (timing_idx != -1 && timing_idx < MAX_MODE5_CATEGORIES) {
            timingStats[id][timing_idx]++;
            for (new i = 0; i < MAX_MODE5_CATEGORIES; i++) {
                if (i == timing_idx) {
                    currentTimingCombo[id][i]++;
                    if (currentTimingCombo[id][i] > maxTimingCombo[id][i])
                        maxTimingCombo[id][i] = currentTimingCombo[id][i];
                } else {
                    currentTimingCombo[id][i] = 0;
                }
            }
        }
        
        // --- Consistency Logic (Requires Frame Calculation) ---
        new totalFramesFilled = 0;
        new totalDurationFrames = 0;
        new consecutiveEmptyFrames = 0;
        new twoFrameGapsCount = 0;
        new bool:perfectRhythm = true;

        if (jumpCount[id] >= 2) {
            new baseFrame = frameIndices[id][0];
            new lastValidJumpIndex = jumpCount[id] - 1;
            new endFrame = frameIndices[id][lastValidJumpIndex];
            
            totalDurationFrames = endFrame - baseFrame + 1;

            new jumpIndex = 0;
            for (new f = 0; f < totalDurationFrames; f++) {
                new targetFrame = baseFrame + f;
                new found = 0;
                
                for (new i = jumpIndex; i <= lastValidJumpIndex; i++) {
                    new fi = frameIndices[id][i];
                    if (fi == targetFrame) { 
                        found = 1; 
                        jumpIndex = i + 1;
                        break;
                    } else if (fi > targetFrame) {
                        break; 
                    }
                }
                
                if (found) {
                    totalFramesFilled++;
                    if (f > 0 && consecutiveEmptyFrames != 1) { 
                        perfectRhythm = false;
                    }
                    consecutiveEmptyFrames = 0;
                } else {
                    consecutiveEmptyFrames++;
                    if (consecutiveEmptyFrames > 1) { 
                        perfectRhythm = false;
                    }
                    if (consecutiveEmptyFrames == 2) { 
                        twoFrameGapsCount++;
                    }
                }
            }
            
            if (consecutiveEmptyFrames >= 1) {
                  perfectRhythm = false;
            }
        } else {
            perfectRhythm = false;
        }
        
        new Float:density_pct = 0.0;
        if (totalDurationFrames > 0) {
            density_pct = (float(totalFramesFilled) * 100.0) / float(totalDurationFrames);
        }
        
        // --- Consistency Rating Logic ---
        if (twoFrameGapsCount >= 3) {  
            consistency_idx = CONSIST_TERRIBLE_R_IDX;
        } else if (perfectRhythm) { 
            consistency_idx = CONSIST_PERFECT_IDX;
        } else {
            if (density_pct >= 60.0) {  
                consistency_idx = CONSIST_GOOD_PCT_IDX;
            } else if (density_pct >= 40.0) {  
                consistency_idx = CONSIST_GOOD_INCON_IDX;
            } else if (density_pct >= 30.0) { 
                consistency_idx = CONSIST_BAD_SCROLL_IDX;
            } else { // < 30% density
                consistency_idx = CONSIST_TERRIBLE_S_IDX;
            }
        }
        
        // Update Consistency Stats and Combo
        if (consistency_idx != -1 && consistency_idx < MAX_MODE5_CATEGORIES) {
            consistencyStats[id][consistency_idx]++;
            for (new i = 0; i < MAX_MODE5_CATEGORIES; i++) {
                if (i == consistency_idx) {
                    currentConsistencyCombo[id][i]++;
                    if (currentConsistencyCombo[id][i] > maxConsistencyCombo[id][i])
                        maxConsistencyCombo[id][i] = currentConsistencyCombo[id][i];
                } else {
                    currentConsistencyCombo[id][i] = 0;
                }
            }
        }
        // ----------------- END NEW Mode 5 Tracking Logic -----------------
    }

    // Show HUD
    if (scrollMode[id] > 0 && triggerIndex[id] > 0)
        show_jump_count(id);

    // Reset airborne flag for next sequence; keep counts for HUD just displayed
    wasAirborneBeforeScroll[id] = false;
}

public fw_PlayerPreThink(id) {
    if (!is_user_alive(id))
        return FMRES_IGNORED;

    new bool:isGround = bool:(pev(id, pev_flags) & FL_ONGROUND);

    if (isGround) {
        g_iFog[id]++; // consecutive ground frames
    } else {
        // Just left ground -> record fog stats on exit
        if (g_isOldGround[id]) {
            new currentFog = g_iFog[id];
            if (currentFog > 0 && currentFog <= 10) {
                new fogIndex = currentFog - 1;

                for (new i = 0; i < 10; i++) {
                    if (i == fogIndex) {
                        currentFogCombo[id][i]++;
                        if (currentFogCombo[id][i] > maxFogCombo[id][i])
                            maxFogCombo[id][i] = currentFogCombo[id][i];
                    } else {
                        currentFogCombo[id][i] = 0;
                    }
                }

                fogStats[id][fogIndex]++;
            } else {
                // reset combos if FOG exceeded tracked window
                for (new i = 0; i < 10; i++) currentFogCombo[id][i] = 0;
            }
        }
        g_iFog[id] = 0; // reset when airborne
    }

    g_isOldGround[id] = isGround;
    return FMRES_IGNORED;
}

// ----------------- HUD -----------------
public show_jump_count(id) {
// --- Mode 5: Timing and Consistency Analysis ---
if (scrollMode[id] == 5) {
    // Line 1: Timing Analysis
    new r1, g1, b1;
    new message1[64];
    new trigger = triggerIndex[id];
    new fog = triggerFog[id];
    
    // String buffer for the static timing message
    new timing_text[64];

    // --- Line 1: Timing Logic ---
    if (fog <= 2) {
        // FOG is good (1-2)
        if (trigger >= 1 && trigger <= 2) {
            r1 = 0; g1 = 255; b1 = 0; // Green
            format(timing_text, charsmax(timing_text), "Perfect Timing");
        } else if (trigger == 3) {
            r1 = 255; g1 = 165; b1 = 0; // Orange
            format(timing_text, charsmax(timing_text), "Good Timing");
        } else if (trigger == 4) {
            r1 = 255; g1 = 165; b1 = 0; // Orange
            format(timing_text, charsmax(timing_text), "Scrolling a little early");
        } else { // trigger >= 5
            r1 = 255; g1 = 0; b1 = 0; // Red
            format(timing_text, charsmax(timing_text), "Scrolling too early");
        }
    } else { // fog >= 3 (FOG is bad)
        r1 = 255; g1 = 0; b1 = 0; // Red
        
        if (trigger >= 1 && trigger <= 4) { 
            format(timing_text, charsmax(timing_text), "Scrolling too late");
        } else { // trigger >= 5
            format(timing_text, charsmax(timing_text), "Terrible scroll");
        }
    }
    
    // Line 1: Append the trigger step and total steps: [TriggerStep/TotalSteps]
    format(message1, charsmax(message1), "%s [%d/%d]", timing_text, trigger, jumpCount[id]);

    // Define the shifted X position
    new Float:rowX = hudX[id] - ROW_LEFT_SHIFT; 

    // Display Line 1 (Header Channel) - Shifted
    set_hudmessage(r1, g1, b1, rowX, hudY[id], 0, 0.0, HUD_HOLD, 0.0, 0.0, HUD_CHANNEL_HEADER);
    show_hudmessage(id, "%s", message1);

    // --- Line 2: Consistency Analysis (RHYTHM-BASED OVERRIDE) ---
    new totalFramesFilled = 0;
    new totalDurationFrames = 0;
    
    new consecutiveEmptyFrames = 0;
    new twoFrameGapsCount = 0;
    new bool:perfectRhythm = true;

    // Analysis requires at least two recorded jumps to define a duration/interval.
    if (jumpCount[id] >= 2) {
        // Analysis window now runs from the first jump up to the very last jump (inclusive).
        new baseFrame = frameIndices[id][0];
        new lastValidJumpIndex = jumpCount[id] - 1; // Index of the last jump
        new endFrame = frameIndices[id][lastValidJumpIndex];
        
        totalDurationFrames = endFrame - baseFrame + 1;

        new jumpIndex = 0;
        // Loop over the new valid duration
        for (new f = 0; f < totalDurationFrames; f++) {
            new targetFrame = baseFrame + f;
            new found = 0;
            
            // Search for jumps only up to the last valid index
            for (new i = jumpIndex; i <= lastValidJumpIndex; i++) {
                new fi = frameIndices[id][i];
                if (fi == targetFrame) { 
                    found = 1; 
                    jumpIndex = i + 1;
                    break;
                } else if (fi > targetFrame) {
                    break; 
                }
            }
            
            if (found) {
                totalFramesFilled++;
                
                // Perfect Rhythm check: If we had a jump, the previous frame MUST have been empty
                if (f > 0 && consecutiveEmptyFrames != 1) { 
                    perfectRhythm = false;
                }
                consecutiveEmptyFrames = 0; // RESET
            } else {
                consecutiveEmptyFrames++; // INCREMENT
                if (consecutiveEmptyFrames > 1) { 
                    perfectRhythm = false;
                }
                if (consecutiveEmptyFrames == 2) { 
                    twoFrameGapsCount++; // Count 2+ frame gaps
                }
            }
        }
        
        // Final check: If the last frame analyzed (endFrame) was empty, the rhythm wasn't perfect.
        if (consecutiveEmptyFrames >= 1) {
              perfectRhythm = false;
        }
    } else {
        // If jumpCount < 2, the scroll cannot be considered perfect rhythm.
        perfectRhythm = false;
    }
    
    new r2, g2, b2;
    new consistency_text[64];
    new Float:density_pct = 0.0;
    
    if (totalDurationFrames > 0) {
        density_pct = (float(totalFramesFilled) * 100.0) / float(totalDurationFrames);
    }
    
    // --- RATING LOGIC (RHYTHM TRUMPS DENSITY) ---
    
    // 1. Check for TERRIBLE RHYTHM (3 or more intervals of 2+ empty frames)
    if (twoFrameGapsCount >= 3) { 
        format(consistency_text, charsmax(consistency_text), "Terrible Consistency");
        r2 = 255; g2 = 0; b2 = 0; // Red
    // 2. Check for PERFECT RHYTHM (every other frame is +jump)
    } else if (perfectRhythm) { 
        format(consistency_text, charsmax(consistency_text), "Perfect Consistency");
        r2 = 0; g2 = 255; b2 = 0; // Green
    // 3. Fallback to percentage ratings for the middle ground (Corrected flow)
    } else {
        // Now using the remaining states for percentage logic
        if (density_pct >= 60.0) { 
            // 60%+ density, but not perfect rhythm
            format(consistency_text, charsmax(consistency_text), "Good Consistency");
            r2 = 255; g2 = 255; b2 = 0; // Yellow
        } else if (density_pct >= 40.0) { 
            // 40-60% density, and not perfect rhythm
            format(consistency_text, charsmax(consistency_text), "Good, slightly inconsistent");
            r2 = 255; g2 = 255; b2 = 0; // Yellow
        } else if (density_pct >= 30.0) { // 30-40% density
            // 30-40% density, and not perfect rhythm/terrible
            format(consistency_text, charsmax(consistency_text), "Bad Scroll");
            r2 = 255; g2 = 0; b2 = 0; // Red
        } else { // < 30% density
            // 0-30% density, and not terrible rhythm (less than 3 gaps)
            format(consistency_text, charsmax(consistency_text), "Terrible Scroll");
            r2 = 255; g2 = 0; b2 = 0; // Red
        }
    }


    // Append full frame data: [Y/Z frames] - This line is maintained to show the total frames.
    new append_buffer[32];
    format(append_buffer, charsmax(append_buffer), " [%d/%d]", totalFramesFilled, totalDurationFrames);

    new message2[96];
    format(message2, charsmax(message2), "%s%s", consistency_text, append_buffer);
    
    // Display Line 2 (Timeline Channel) below Line 1 - Shifted
    new Float:rowY = hudY[id] + 0.015;
    
    set_hudmessage(r2, g2, b2, rowX, rowY, 0, 0.0, HUD_HOLD, 0.0, 0.0, HUD_CHANNEL_TIMELINE);
    show_hudmessage(id, "%s", message2);
    
    return;
}
    // Mode 4: header + timeline below with slight left alignment
    if (scrollMode[id] == 4) {
        // Header color (same as mode 1-3 logic)
        new r, g, b;
        if (triggerIndex[id] <= 2)      { r = 0; g = 255; b = 0; }
        else if (triggerIndex[id] <= 4) { r = 255; g = 165; b = 0; }
        else                            { r = 255; g = 0; b = 0; }

        // Line 1: steps [trigger]
        new header[64];
        format(header, charsmax(header), "%d [%d]", jumpCount[id], triggerIndex[id]);

        // Draw header centered
        set_hudmessage(r, g, b, hudX[id], hudY[id], 0, 0.0, HUD_HOLD, 0.0, 0.0, HUD_CHANNEL_HEADER);
        show_hudmessage(id, "%s", header);

        // Build timeline string
        new timeline[128], len = 0;
        if (jumpCount[id] > 0) {
            new baseFrame = frameIndices[id][0];
            for (new f = 0; f < BOX_COUNT; f++) {
                new targetFrame = baseFrame + f;
                new found = 0;
                for (new i = 0; i < jumpCount[id]; i++) {
                    new fi = frameIndices[id][i];
                    if (fi == targetFrame) { found = 1; break; }
                    else if (fi > targetFrame) break;
                }
                len += format(timeline[len], charsmax(timeline) - len, found ? "[x]" : "[0]");
            }
        }

        // Line 2: timeline slightly left and below header
        new Float:rowX = hudX[id] - ROW_LEFT_SHIFT;    // small left shift (0.05)
        new Float:rowY = hudY[id] + 0.015;  // just below header

        set_hudmessage(0, 200, 255, rowX, rowY, 0, 0.0, HUD_HOLD, 0.0, 0.0, HUD_CHANNEL_TIMELINE);
        show_hudmessage(id, "%s", timeline);
        return;
    }

    // Modes 1–3
    new r, g, b;
    if (triggerIndex[id] <= 2)      { r = 0; g = 255; b = 0; }
    else if (triggerIndex[id] <= 4) { r = 255; g = 165; b = 0; }
    else                            { r = 255; g = 0; b = 0; }

    new message1[64], message2[128];
    format(message1, charsmax(message1), "%d [%d]", jumpCount[id], triggerIndex[id]);

    if (scrollMode[id] == 2) {
        new Float:duration = (scrollEndTime[id] - scrollStartTime[id]) * 1000.0;
        format(message2, charsmax(message2), "%dms", floatround(duration));
    } else if (scrollMode[id] == 3) {
        new len2 = 0;
        for (new i = 1; i < jumpCount[id]; i++) {
            new Float:interval = (scrollTimes[id][i] - scrollTimes[id][i - 1]) * 1000.0;
            new rounded = floatround(interval);
            len2 += format(message2[len2], charsmax(message2) - len2, "%d%s",
                           rounded, (i < jumpCount[id] - 1) ? ", " : "");
        }
        new Float:duration2 = (scrollEndTime[id] - scrollStartTime[id]) * 1000.0;
        format(message2[len2], charsmax(message2) - len2, " (%dms)", floatround(duration2));
    } else {
        message2[0] = 0;
    }

    set_hudmessage(r, g, b, hudX[id], hudY[id], 0, 0.0, HUD_HOLD, 0.0, 0.0, HUD_CHANNEL_HEADER);
    show_hudmessage(id, "%s%s%s", message1, (message2[0] ? "^n" : ""), message2);
}