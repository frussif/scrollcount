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
    - Per-player setinfo persistence: scrollmode, scrollhud ("x y")
    - Tracking console summary (/trackscroll) with distributions and combos
    - Robust finalize window (re-arms on each step), no task leaks
    - Optimized HUD building (precomputed frame indices, minimized float ops)
*/

#define PLUGIN  "Scroll Counter"
#define VERSION "1.7"
#define AUTHOR  "Copilot"

// ----------------- Config -----------------
const Float:JUMP_WINDOW       = 0.20;   // seconds to accumulate scroll steps
const FOG_COOLDOWN_FRAMES     = 6;      // ignore jump if grounded >= 6 frames before press
const TASK_FINALIZE_BASE      = 42420;  // base for per-player finalize task id
const HUD_CHANNEL_HEADER      = 4;      // header line channel
const HUD_CHANNEL_TIMELINE    = 5;      // timeline line channel
const Float:HUD_HOLD          = 5.0;    // seconds to keep HUD visible

// Mode 4 layout
const BOX_COUNT               = 10;     // number of boxes shown in the timeline
const Float:ROW_LEFT_SHIFT    = 0.05;   // small left shift to visually align under header

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

new bool:wasAirborneBeforeScroll[33]; // any jump in sequence happened while airborne (prev frame off ground)

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
reset_tracking(id) {
    isTracking[id] = false;

    jumpCount[id] = 0;
    triggerIndex[id] = 0;
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
        fogStats[id][i]         = 0;
        triggerStats[id][i]     = 0;
        currentFogCombo[id][i]  = 0;
        maxFogCombo[id][i]      = 0;
        currentScrollCombo[id][i] = 0;
        maxScrollCombo[id][i]     = 0;
    }

    // No dangling finalize task
    remove_task(taskid_final(id));
}

init_player_settings(id) {
    scrollMode[id] = 1;
    hudX[id] = 0.50;
    hudY[id] = 0.50;

    // Read persisted settings
    new modeStr[8], hudStr[32];
    get_user_info(id, "scrollmode", modeStr, charsmax(modeStr));
    get_user_info(id, "scrollhud",  hudStr,  charsmax(hudStr));

    if (modeStr[0]) {
        new m = str_to_num(modeStr);
        if (m >= 0 && m <= 4) scrollMode[id] = m;
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

        client_print(id, print_console, "^nScroll timing distribution:");
        for (new i = 0; i < 10; i++) {
            if (triggerStats[id][i] > 0) {
                new Float:pct = (triggerStats[id][i] * 100.0) / total;
                client_print(id, print_console, "Step %d: %d (%.1f%%) (best streak: %dx)",
                             i + 1, triggerStats[id][i], pct, maxScrollCombo[id][i]);
            }
        }

        client_print(id, print_console, "Avg steps/scroll: %.1f", avgScrolls);
        client_print(id, print_console, "Avg duration/scroll: %.1f ms", avgDuration);

        client_print(id, print_console, "^nFOG distribution:");
        new totalFogFrames = 0;
        for (new i = 0; i < 10; i++) totalFogFrames += fogStats[id][i];
        if (totalFogFrames > 0) {
            for (new i = 0; i < 10; i++) {
                if (fogStats[id][i] > 0) {
                    new Float:fogPct = (fogStats[id][i] * 100.0) / totalFogFrames;
                    client_print(id, print_console, "FOG %d: %d (%.1f%%) (best streak: %dx)",
                                 i + 1, fogStats[id][i], fogPct, maxFogCombo[id][i]);
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
    if (mode < 0 || mode > 4) {
        client_print(id, print_chat, "[ScrollCount] Usage: scrollcount 0(off),1,2,3,4(timeline)");
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
            lastJumpTime[id]= now;

            scrollStartTime[id] = now;
            scrollEndTime[id]   = now;
            scrollTimes[id][0]  = now;
            frameIndices[id][0] = floatround(now * 100.0); // cache frame index @100 fps

            if (pev(id, pev_flags) & FL_ONGROUND)
                triggerIndex[id] = 1;

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

            if (triggerIndex[id] == 0 && (pev(id, pev_flags) & FL_ONGROUND))
                triggerIndex[id] = jumpCount[id];

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
    // Mode 4: header + timeline below with slight left alignment
	if (scrollMode[id] == 4) {
		// Header color (same as mode 1)
		new r, g, b;
		if (triggerIndex[id] <= 2)      { r = 0;   g = 255; b = 0;   }
		else if (triggerIndex[id] <= 4) { r = 255; g = 165; b = 0;   }
		else                            { r = 255; g = 0;   b = 0;   }

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
		new Float:rowX = hudX[id] - 0.04;   // small left shift
		new Float:rowY = hudY[id] + 0.015;  // just below header

		set_hudmessage(0, 200, 255, rowX, rowY, 0, 0.0, HUD_HOLD, 0.0, 0.0, HUD_CHANNEL_TIMELINE);
		show_hudmessage(id, "%s", timeline);
		return;
	}

    // Modes 1–3
    new r, g, b;
    if (triggerIndex[id] <= 2)      { r = 0;   g = 255; b = 0;   }
    else if (triggerIndex[id] <= 4) { r = 255; g = 165; b = 0;   }
    else                            { r = 255; g = 0;   b = 0;   }

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
