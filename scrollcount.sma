#include <amxmodx>
#include <fakemeta>

#define PLUGIN  "Scroll Counter"
#define VERSION "1.0"
#define AUTHOR  "Copilot"

new jumpCount[33];
new triggerIndex[33];
new Float:lastJumpTime[33];
new bool:timerActive[33];
new Float:scrollStartTime[33];
new Float:scrollEndTime[33];
new Float:scrollTimes[33][32];

new bool:isTracking[33];
new perfectCount[33];
new goodCount[33];
new badCount[33];

// Tracking totals for averages
new totalJumpsTracked[33];
new totalScrollsTracked[33];
new Float:totalDurationTracked[33];

// FOG tracking
new g_iFog[33];             // Current FOG count
new bool:g_isOldGround[33]; // Was player on ground last frame
new fogStats[33][10];       // FOG statistics for summary

// HUD position for each player
new Float:hudX[33];
new Float:hudY[33];
new scrollMode[33];

const Float:JUMP_WINDOW = 0.2;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    register_forward(FM_CmdStart, "fw_CmdStart");
    register_forward(FM_PlayerPreThink, "fw_PlayerPreThink");

    // Track scroll commands
    register_clcmd("say /trackscroll", "cmd_trackscroll");
    register_clcmd("say_team /trackscroll", "cmd_trackscroll");
    register_concmd("scrollcount", "cmd_scrollcount");
    register_concmd("scrollcounthud", "cmd_scrollcounthud");
}

reset_tracking(id) {
    isTracking[id] = false;
    perfectCount[id] = 0;
    goodCount[id] = 0;
    badCount[id] = 0;
    jumpCount[id] = 0;
    triggerIndex[id] = 0;
    timerActive[id] = false;
    lastJumpTime[id] = 0.0;
    scrollStartTime[id] = 0.0;
    scrollEndTime[id] = 0.0;
    
    // Reset average tracking
    totalJumpsTracked[id] = 0;
    totalScrollsTracked[id] = 0;
    totalDurationTracked[id] = 0.0;
    
    // Reset FOG tracking
    g_iFog[id] = 0;
    g_isOldGround[id] = false;
    for (new i = 0; i < 10; i++) {
        fogStats[id][i] = 0;
    }
}

init_player_settings(id) {
    // Default settings
    scrollMode[id] = 1;
    hudX[id] = 0.5;
    hudY[id] = 0.5;

    // Read setinfo values
    new mode[8], hud[32];
    get_user_info(id, "scrollmode", mode, charsmax(mode));
    get_user_info(id, "scrollhud", hud, charsmax(hud));

    // Set scroll mode
    if (mode[0]) {
        new m = str_to_num(mode);
        if (m >= 0 && m <= 3) {
            scrollMode[id] = m;
        }
    }

    // Set HUD position
    new xStr[16], yStr[16];
    if (parse(hud, xStr, charsmax(xStr), yStr, charsmax(yStr)) == 2) {
        new Float:x = str_to_float(xStr);
        new Float:y = str_to_float(yStr);
        hudX[id] = (x < 0.0) ? 0.0 : ((x > 1.0) ? 1.0 : x);
        hudY[id] = (y < 0.0) ? 0.0 : ((y > 1.0) ? 1.0 : y);
    }
}

public client_connect(id) {
    reset_tracking(id);
    init_player_settings(id);
}

public client_disconnected(id) {
    reset_tracking(id);
}

public cmd_trackscroll(id) {
    if (!isTracking[id]) {
        // Start tracking
        reset_tracking(id);
        isTracking[id] = true;
        client_print(id, print_chat, "[ScrollCount] Started tracking scrolls");
        client_print(id, print_console, "*** ScrollCount: Started tracking scrolls ***");
    } else {
        // Stop tracking and show results
        isTracking[id] = false;
        
        new total = perfectCount[id] + goodCount[id] + badCount[id];
        if (total == 0) {
            client_print(id, print_chat, "[ScrollCount] No jumps recorded");
            client_print(id, print_console, "*** ScrollCount: No jumps recorded ***");
            return PLUGIN_HANDLED;
        }
        
        new Float:perfectPct = (perfectCount[id] * 100.0) / total;
        new Float:goodPct    = (goodCount[id]    * 100.0) / total;
        new Float:badPct     = (badCount[id]     * 100.0) / total;
        
        // Console output
        // Calculate averages
        new Float:avgScrolls = totalScrollsTracked[id] / float(totalJumpsTracked[id]);
        new Float:avgDuration = (totalDurationTracked[id] * 1000.0) / totalJumpsTracked[id];

        // Console output only
        client_print(id, print_console, "*** ScrollCount Summary ***");
        client_print(id, print_console, "Perfect (1-2 steps): %d (%.1f%%)", perfectCount[id], perfectPct);
        client_print(id, print_console, "Good (3-4 steps):    %d (%.1f%%)", goodCount[id],    goodPct);
        client_print(id, print_console, "Bad (5+ steps):      %d (%.1f%%)", badCount[id],     badPct);
        client_print(id, print_console, "Total Jumps: %d", total);
        client_print(id, print_console, "Average Scrolls: %.1f", avgScrolls);
        client_print(id, print_console, "Average Duration: %.1fms", avgDuration);
        
        // FOG Statistics
        client_print(id, print_console, "^nFrames On Ground Distribution:");
        for (new i = 0; i < 10; i++) {
            if (fogStats[id][i] > 0) {
                new Float:fogPct = (fogStats[id][i] * 100.0) / total;
                client_print(id, print_console, "FOG %d: %d (%.1f%%)", i, fogStats[id][i], fogPct);
            }
        }
    }
    
    return PLUGIN_HANDLED;
}

public cmd_scrollcount(id) {
    new arg[8];
    read_argv(1, arg, charsmax(arg));

    new mode = str_to_num(arg);
    if (mode < 0 || mode > 3) {
        client_print(id, print_chat, "[ScrollCount] Usage: scrollcount 0 (off), 1 (on), 2 (duration), 3 (intervals)");
        return PLUGIN_HANDLED;
    }

    scrollMode[id] = mode;
    client_print(id, print_chat, "[ScrollCount] Mode %d activated.", mode);
    return PLUGIN_HANDLED;
}

public cmd_scrollcounthud(id) {
    new arg1[16], arg2[16];
    read_argv(1, arg1, charsmax(arg1));
    read_argv(2, arg2, charsmax(arg2));

    if (equali(arg1, "1")) {
        hudX[id] = 0.5; hudY[id] = 0.5;
        client_print(id, print_chat, "[ScrollCount] HUD set to center.");
        return PLUGIN_HANDLED;
    } else if (equali(arg1, "2")) {
        hudX[id] = 0.4; hudY[id] = 0.6;
        client_print(id, print_chat, "[ScrollCount] HUD set to left.");
        return PLUGIN_HANDLED;
    } else if (equali(arg1, "3")) {
        hudX[id] = 0.6; hudY[id] = 0.6;
        client_print(id, print_chat, "[ScrollCount] HUD set to right.");
        return PLUGIN_HANDLED;
    }

    new Float:x = str_to_float(arg1);
    new Float:y = str_to_float(arg2);

    hudX[id] = (x < 0.0) ? 0.0 : ((x > 1.0) ? 1.0 : x);
    hudY[id] = (y < 0.0) ? 0.0 : ((y > 1.0) ? 1.0 : y);

    client_print(id, print_chat, "[ScrollCount] HUD set to X: %.2f, Y: %.2f", hudX[id], hudY[id]);
    return PLUGIN_HANDLED;
}



public fw_CmdStart(id, uc_handle, seed) {
    if (!is_user_alive(id)) {
        return FMRES_IGNORED;
    }

    static buttons;
    buttons = get_uc(uc_handle, UC_Buttons);

    if (buttons & IN_JUMP) {
        new Float:currentTime = get_gametime();

        if (!timerActive[id]) {
            // Start window
            timerActive[id] = true;
            jumpCount[id] = 1;
            triggerIndex[id] = 0;
            lastJumpTime[id] = currentTime;
            scrollStartTime[id] = currentTime;
            scrollEndTime[id] = currentTime;
            scrollTimes[id][0] = currentTime;

            // First scroll while grounded means normal jump (not bhop)
            if (pev(id, pev_flags) & FL_ONGROUND) {
                triggerIndex[id] = 1;
            }

            set_task(JUMP_WINDOW, "finalize_jump_count", id);
        } else if ((currentTime - lastJumpTime[id]) <= JUMP_WINDOW && jumpCount[id] < 32) {
            // Subsequent scrolls within window
            jumpCount[id]++;
            lastJumpTime[id] = currentTime;
            scrollEndTime[id] = currentTime;
            scrollTimes[id][jumpCount[id] - 1] = currentTime;

            // If still on ground when this scroll happens, it can be the trigger
            if (triggerIndex[id] == 0 && (pev(id, pev_flags) & FL_ONGROUND)) {
                triggerIndex[id] = jumpCount[id];
            }
        }
    }

    return FMRES_IGNORED;
}

public finalize_jump_count(id) {
    timerActive[id] = false;

    // Track quality when tracking is active
    if (isTracking[id]) {
        if (triggerIndex[id] == 1 || triggerIndex[id] == 2) {
            perfectCount[id]++;
        } else if (triggerIndex[id] == 3 || triggerIndex[id] == 4) {
            goodCount[id]++;
        } else {
            // 0 (no trigger detected as intended bhop) or 5+
            badCount[id]++;
        }
        
        // Track totals for averages
        totalJumpsTracked[id]++;
        totalScrollsTracked[id] += jumpCount[id];
        totalDurationTracked[id] += scrollEndTime[id] - scrollStartTime[id];
        
        // Frame tracking is handled in PlayerPreThink
    }

    // Show HUD display if mode is enabled
    if (scrollMode[id] > 0 && triggerIndex[id] > 1) {
        show_jump_count(id);
    }
}

public fw_PlayerPreThink(id) {
    if (!is_user_alive(id) || !isTracking[id]) {
        return FMRES_IGNORED;
    }

    new bool:isGround = bool:(pev(id, pev_flags) & FL_ONGROUND);
    
    if (isGround) {
        g_iFog[id]++;
    } else {
        if (g_isOldGround[id]) {
            // Player just left the ground, record FOG stat
            if (g_iFog[id] <= 10) { // Only record FOGs up to 10
                new fogIndex = min(g_iFog[id], 9);
                fogStats[id][fogIndex]++;
            }
        }
        g_iFog[id] = 0;
    }
    
    g_isOldGround[id] = isGround;
    return FMRES_IGNORED;
}

public show_jump_count(id) {
    new r, g, b;
    if (triggerIndex[id] == 1 || triggerIndex[id] == 2) {
        r = 0;   g = 255; b = 0;      // Green
    } else if (triggerIndex[id] == 3 || triggerIndex[id] == 4) {
        r = 255; g = 165; b = 0;      // Orange
    } else {
        r = 255; g = 0;   b = 0;      // Red
    }

    new message1[64], message2[128];
    format(message1, charsmax(message1), "%d [%d]", jumpCount[id], triggerIndex[id]);

    if (scrollMode[id] == 2) {
        new Float:duration = (scrollEndTime[id] - scrollStartTime[id]) * 1000.0;
        format(message2, charsmax(message2), "%dms", floatround(duration));
    } else if (scrollMode[id] == 3) {
        new len = 0;
        for (new i = 1; i < jumpCount[id]; i++) {
            new Float:interval = (scrollTimes[id][i] - scrollTimes[id][i - 1]) * 1000.0;
            new rounded = floatround(interval);
            if (i == triggerIndex[id] - 1) {
                len += format(message2[len], charsmax(message2) - len, "[%d]%s", rounded, (i < jumpCount[id] - 1) ? ", " : "");
            } else {
                len += format(message2[len], charsmax(message2) - len, "%d%s", rounded, (i < jumpCount[id] - 1) ? ", " : "");
            }
        }
        new Float:duration = (scrollEndTime[id] - scrollStartTime[id]) * 1000.0;
        format(message2[len], charsmax(message2) - len, " (%dms)", floatround(duration));
    } else {
        message2[0] = 0;
    }

    set_hudmessage(r, g, b, hudX[id], hudY[id], 0, 0.0, 5.0, 0.0, 0.0, 4);
    show_hudmessage(id, "%s%s%s", message1, (message2[0] ? "^n" : ""), message2);
}