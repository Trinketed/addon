#!/usr/bin/env python3
"""Convert ArenaBlackBox SavedVariables to TrinketedHistoryDB format with eventLog.

Usage:
    python3 convert_blackbox.py input.lua [output.lua]

If output is omitted, writes to input-converted.lua
"""

import sys
import re
import json
import zlib

# ─── LibDeflate EncodeForPrint ─────────────────────────────────────────────
CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"


def encode_for_print(data: bytes) -> str:
    """Replicate LibDeflate:EncodeForPrint — base64-like with custom alphabet."""
    result = []
    i = 0
    n = len(data)
    while i + 2 < n:
        cache = data[i] + (data[i + 1] << 8) + (data[i + 2] << 16)
        result.append(CHARSET[cache & 0x3F])
        result.append(CHARSET[(cache >> 6) & 0x3F])
        result.append(CHARSET[(cache >> 12) & 0x3F])
        result.append(CHARSET[(cache >> 18) & 0x3F])
        i += 3
    remaining = n - i
    if remaining > 0:
        cache = 0
        for j in range(remaining):
            cache += data[i + j] << (8 * j)
        cache_bitlen = remaining * 8
        while cache_bitlen > 0:
            result.append(CHARSET[cache & 0x3F])
            cache >>= 6
            cache_bitlen -= 6
    return "".join(result)


# ─── Event type codes (must match EventRecorder.lua) ──────────────────────
E = {
    "damage": 1, "heal": 2, "miss": 3, "cast_start": 4, "cast_success": 5,
    "cast_fail": 6, "unit_state": 7, "aura_applied": 8, "aura_removed": 9,
    "aura_refresh": 10, "aura_dose": 11, "aura_break": 12, "interrupt": 13,
    "dispel": 14, "extra_attacks": 15, "aura_snapshot": 16, "death": 17,
    "summon": 18, "energize": 19, "drain": 20, "absorb": 21, "steal": 22,
    "loss_of_control": 23, "target_change": 24,
}

DMG_SUBTYPES = {
    "direct": 1, "periodic": 2, "auto_melee": 3, "auto_ranged": 4,
    "shield": 5, "split": 6, "env": 7,
}

HEAL_SUBTYPES = {"direct": 1, "periodic": 2}

MISS_SUBTYPES = {"swing": 1, "spell": 2, "range": 3, "spell_periodic": 4}

MISS_TYPE_CODES = {
    "ABSORB": 1, "BLOCK": 2, "DEFLECT": 3, "DODGE": 4, "EVADE": 5,
    "IMMUNE": 6, "MISS": 7, "PARRY": 8, "REFLECT": 9, "RESIST": 10,
}

FAIL_REASON_CODES = {
    "Interrupted": 1, "Another action is in progress": 2,
    "Not yet recovered": 3, "Out of range": 4,
    "Target not in line of sight": 5, "Not enough mana": 6,
    "Not enough energy": 7, "Not enough rage": 8,
    "No target": 9, "Invalid target": 10,
    "Target is friendly": 11, "Target is hostile": 12,
    "You are facing the wrong way": 13, "Spell is not ready yet": 14,
    "Target is dead": 15, "Nothing to dispel": 16,
    "Can't do that while stunned": 17, "Can't do that while silenced": 18,
    "Can't do that while incapacitated": 19, "Can't do that while feared": 20,
    "Can't do that while moving": 21, "Must be behind target": 22,
    "A more powerful spell is already active": 23, "Item is not ready yet": 24,
    "Not enough focus": 25,
}

DR_CAT_CODES = {
    "incapacitate": 1, "stun": 2, "fear": 3, "root": 4, "disorient": 5,
    "silence": 6, "disarm": 7, "horror": 8, "scatter": 9,
    "random_stun": 10, "random_root": 11, "mind_control": 12,
    "kidney_shot": 13, "death_coil": 14, "unstable_affliction": 15,
    "counterattack": 16, "chastise": 17, "opener_stun": 18,
    "cyclone": 19, "charge": 20,
}

AURA_TYPE_CODES = {"BUFF": 1, "DEBUFF": 2}


# ─── Lua SavedVariables parser ────────────────────────────────────────────
class LuaParser:
    """Minimal parser for WoW SavedVariables Lua tables."""

    def __init__(self, text):
        self.text = text
        self.pos = 0
        self.length = len(text)

    def skip_ws(self):
        while self.pos < self.length and self.text[self.pos] in ' \t\n\r':
            self.pos += 1
        # Skip Lua comments
        if self.pos < self.length - 1 and self.text[self.pos:self.pos + 2] == '--':
            while self.pos < self.length and self.text[self.pos] != '\n':
                self.pos += 1
            self.skip_ws()

    def peek(self):
        self.skip_ws()
        return self.text[self.pos] if self.pos < self.length else ''

    def expect(self, ch):
        self.skip_ws()
        if self.pos < self.length and self.text[self.pos] == ch:
            self.pos += 1
            return True
        return False

    def parse_value(self):
        self.skip_ws()
        if self.pos >= self.length:
            return None
        ch = self.text[self.pos]
        if ch == '{':
            return self.parse_table()
        elif ch == '"':
            return self.parse_string()
        elif ch == '-' or ch.isdigit():
            return self.parse_number()
        elif self.text[self.pos:self.pos + 4] == 'true':
            self.pos += 4
            return True
        elif self.text[self.pos:self.pos + 5] == 'false':
            self.pos += 5
            return False
        elif self.text[self.pos:self.pos + 3] == 'nil':
            self.pos += 3
            return None
        else:
            raise ValueError(f"Unexpected char '{ch}' at pos {self.pos}: ...{self.text[self.pos:self.pos+20]}...")

    def parse_string(self):
        self.pos += 1  # skip opening "
        result = []
        while self.pos < self.length:
            ch = self.text[self.pos]
            if ch == '\\':
                self.pos += 1
                esc = self.text[self.pos]
                if esc == 'n':
                    result.append('\n')
                elif esc == 't':
                    result.append('\t')
                elif esc == '"':
                    result.append('"')
                elif esc == '\\':
                    result.append('\\')
                else:
                    result.append(esc)
                self.pos += 1
            elif ch == '"':
                self.pos += 1
                return ''.join(result)
            else:
                result.append(ch)
                self.pos += 1
        return ''.join(result)

    def parse_number(self):
        start = self.pos
        if self.text[self.pos] == '-':
            self.pos += 1
        while self.pos < self.length and (self.text[self.pos].isdigit() or self.text[self.pos] == '.'):
            self.pos += 1
        # Handle scientific notation
        if self.pos < self.length and self.text[self.pos] in 'eE':
            self.pos += 1
            if self.pos < self.length and self.text[self.pos] in '+-':
                self.pos += 1
            while self.pos < self.length and self.text[self.pos].isdigit():
                self.pos += 1
        s = self.text[start:self.pos]
        return float(s) if '.' in s or 'e' in s or 'E' in s else int(s)

    def parse_table(self):
        self.pos += 1  # skip {
        self.skip_ws()

        # Detect if array or dict by peeking
        entries = []
        dict_entries = {}
        is_dict = False
        idx = 1

        while self.peek() != '}':
            if self.peek() == '':
                break

            # Check for [key] = val or ["key"] = val
            if self.text[self.pos] == '[':
                is_dict = True
                self.pos += 1  # skip [
                key = self.parse_value()
                self.skip_ws()
                self.expect(']')
                self.skip_ws()
                self.expect('=')
                val = self.parse_value()
                dict_entries[key] = val
            else:
                # Array element
                val = self.parse_value()
                entries.append(val)

            self.skip_ws()
            self.expect(',')  # optional trailing comma

        self.expect('}')

        if is_dict:
            # Merge any positional entries (shouldn't happen but just in case)
            return dict_entries
        return entries


def parse_lua_savedvars(text):
    """Parse 'ArenaBlackBoxDB = { ... }' and return the dict."""
    # Skip the assignment
    m = re.search(r'ArenaBlackBoxDB\s*=\s*', text)
    if not m:
        raise ValueError("Could not find ArenaBlackBoxDB assignment")
    parser = LuaParser(text)
    parser.pos = m.end()
    return parser.parse_value()


# ─── Converter ────────────────────────────────────────────────────────────

class EventLogBuilder:
    """Convert a single ArenaBlackBox match to compact eventLog format."""

    def __init__(self, match):
        self.match = match
        self.guids = []
        self.guid_index = {}
        self.spell_dict = {}
        self.roster = {}
        self.events = []
        self.last_time_ms = 0

    def guid_idx(self, guid):
        if not guid:
            return 0
        if guid not in self.guid_index:
            self.guids.append(guid)
            self.guid_index[guid] = len(self.guids)
        return self.guid_index[guid]

    def record_spell(self, spell_id, spell_name):
        if spell_id and spell_id != 0 and spell_name and spell_id not in self.spell_dict:
            self.spell_dict[int(spell_id)] = spell_name

    def delta_time(self, t_sec):
        """Convert relative seconds to delta ms from previous event."""
        abs_ms = int(round(t_sec * 1000))
        # For first event, delta from match start (0)
        start_ms = int(round((self.match.get("startTime", 0) % 1) * 1000))
        if not self.events:
            self.last_time_ms = 0
        dt = abs_ms - self.last_time_ms
        self.last_time_ms = abs_ms
        return max(0, dt)

    def build_roster(self):
        roster_data = self.match.get("roster", {})
        for guid_str, info in roster_data.items():
            idx = self.guid_idx(guid_str)
            self.roster[idx] = {
                "n": info.get("name", ""),
                "c": info.get("class", ""),
                "r": info.get("race", ""),
                "s": info.get("spec", ""),
                "t": 0 if info.get("team") == "friendly" else 1,
            }

    def convert_event(self, ev):
        t = ev.get("t", 0)
        dt = self.delta_time(t)
        etype = ev.get("type", "")

        if etype == "damage":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            sub = DMG_SUBTYPES.get(ev.get("subtype", "direct"), 1)
            self.events.append([
                E["damage"], dt, src, dst, sid, sub,
                int(ev.get("amount", 0) or 0),
                int(ev.get("school", 0) or 0),
                int(ev.get("overkill", 0) or 0),
                int(ev.get("absorbed", 0) or 0),
                1 if ev.get("critical") else 0,
            ])

        elif etype == "heal":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            sub = HEAL_SUBTYPES.get(ev.get("subtype", "direct"), 1)
            self.events.append([
                E["heal"], dt, src, dst, sid, sub,
                int(ev.get("amount", 0) or 0),
                int(ev.get("overhealing", 0) or 0),
                int(ev.get("absorbed", 0) or 0),
                1 if ev.get("critical") else 0,
            ])

        elif etype == "miss":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            sub = MISS_SUBTYPES.get(ev.get("subtype", "spell"), 2)
            mt = MISS_TYPE_CODES.get(ev.get("missType", ""), 0)
            self.events.append([
                E["miss"], dt, src, dst, sid, sub, mt,
                int(ev.get("amountMissed", 0) or 0),
            ])

        elif etype == "cast_start":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            self.events.append([E["cast_start"], dt, src, dst, sid])

        elif etype == "cast_success":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            self.events.append([E["cast_success"], dt, src, dst, sid])

        elif etype == "cast_fail":
            src = self.guid_idx(ev.get("srcGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            fr = FAIL_REASON_CODES.get(ev.get("failReason", ""), 0)
            self.events.append([E["cast_fail"], dt, src, sid, fr])

        elif etype == "unit_state":
            gidx = self.guid_idx(ev.get("guid"))
            target_idx = self.guid_idx(ev.get("targetGUID")) if ev.get("targetGUID") else 0
            cast_sid = int(ev.get("castSpellID", 0) or 0)
            cast_end = int(ev.get("castEnd", 0) or 0)
            self.events.append([
                E["unit_state"], dt, gidx,
                int(ev.get("hp", 0) or 0),
                int(ev.get("hpMax", 0) or 0),
                int(ev.get("power", 0) or 0),
                int(ev.get("powerMax", 0) or 0),
                int(ev.get("powerType", 0) or 0),
                target_idx, cast_sid, cast_end,
            ])

        elif etype == "aura_applied":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            at = AURA_TYPE_CODES.get(ev.get("auraType", "DEBUFF"), 2)
            dr = DR_CAT_CODES.get(ev.get("dr", ""), 0)
            dur = int((ev.get("dur", 0) or 0) * 10)
            self.events.append([E["aura_applied"], dt, src, dst, sid, at, dr, dur])

        elif etype == "aura_removed":
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            at = AURA_TYPE_CODES.get(ev.get("auraType", "DEBUFF"), 2)
            self.events.append([E["aura_removed"], dt, dst, sid, at])

        elif etype == "aura_refresh":
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            self.events.append([E["aura_refresh"], dt, dst, sid])

        elif etype == "aura_dose":
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            self.events.append([E["aura_dose"], dt, dst, sid, int(ev.get("stacks", 1) or 1)])

        elif etype == "aura_break":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            esid = int(ev.get("extraSpellID", 0) or 0)
            if ev.get("extraSpell"):
                self.record_spell(esid, ev.get("extraSpell"))
            self.events.append([E["aura_break"], dt, src, dst, sid, esid])

        elif etype == "aura_snapshot":
            gidx = self.guid_idx(ev.get("guid"))
            row = [E["aura_snapshot"], dt, gidx]
            for aura in (ev.get("auras") or []):
                if not isinstance(aura, dict):
                    continue
                sid = int(aura.get("spellID", 0) or 0)
                self.record_spell(sid, aura.get("spell"))
                at = AURA_TYPE_CODES.get(aura.get("auraType", "BUFF"), 1)
                stacks = int(aura.get("stacks", 0) or 0)
                row.extend([sid, at, stacks])
            self.events.append(row)

        elif etype == "interrupt":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            esid = int(ev.get("extraSpellID", 0) or 0)
            if ev.get("extraSpell"):
                self.record_spell(esid, ev.get("extraSpell"))
            self.events.append([E["interrupt"], dt, src, dst, sid, esid])

        elif etype == "dispel":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            esid = int(ev.get("extraSpellID", 0) or 0)
            if ev.get("extraSpell"):
                self.record_spell(esid, ev.get("extraSpell"))
            at = AURA_TYPE_CODES.get(ev.get("auraType", "DEBUFF"), 2)
            self.events.append([E["dispel"], dt, src, dst, sid, esid, at])

        elif etype == "steal":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            esid = int(ev.get("extraSpellID", 0) or 0)
            if ev.get("extraSpell"):
                self.record_spell(esid, ev.get("extraSpell"))
            self.events.append([E["steal"], dt, src, dst, sid, esid])

        elif etype == "absorb":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            self.events.append([
                E["absorb"], dt, src, dst, sid,
                int(ev.get("amount", 0) or 0),
            ])

        elif etype == "energize":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            self.events.append([
                E["energize"], dt, src, dst, sid,
                int(ev.get("amount", 0) or 0),
                int(ev.get("powerType", 0) or 0),
            ])

        elif etype == "drain":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            self.events.append([
                E["drain"], dt, src, dst, sid,
                int(ev.get("amount", 0) or 0),
                int(ev.get("powerType", 0) or 0),
            ])

        elif etype == "death":
            dst = self.guid_idx(ev.get("dstGUID"))
            self.events.append([E["death"], dt, dst])

        elif etype == "summon":
            src = self.guid_idx(ev.get("srcGUID"))
            dst = self.guid_idx(ev.get("dstGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            self.events.append([E["summon"], dt, src, dst, sid])

        elif etype == "extra_attacks":
            src = self.guid_idx(ev.get("srcGUID"))
            sid = int(ev.get("spellID", 0) or 0)
            self.record_spell(sid, ev.get("spell"))
            self.events.append([
                E["extra_attacks"], dt, src, sid,
                int(ev.get("amount", 0) or 0),
            ])

        elif etype == "target_change":
            gidx = self.guid_idx(ev.get("guid"))
            tidx = self.guid_idx(ev.get("targetGUID")) if ev.get("targetGUID") else 0
            self.events.append([E["target_change"], dt, gidx, tidx])

        elif etype == "loss_of_control":
            loc_type = ev.get("locType", "")
            sid = int(ev.get("spellID", 0) or 0)
            dur = int((ev.get("duration", 0) or 0) * 1000)
            self.events.append([E["loss_of_control"], dt, loc_type, sid, dur])

        # Skip: gates_open, match_end, player_entered, cooldown_state, focus_change
        # (these are either metadata or can be derived)

    def build(self):
        self.build_roster()

        match_events = self.match.get("events", [])
        if isinstance(match_events, dict):
            match_events = list(match_events.values())

        # Sort by time
        match_events.sort(key=lambda e: e.get("t", 0) if isinstance(e, dict) else 0)

        for ev in match_events:
            if not isinstance(ev, dict):
                continue
            self.convert_event(ev)

        start_ms = int(round(self.match.get("startTime", 0) * 1000))

        # Convert spell_dict keys to strings for JSON
        spell_dict_str = {str(k): v for k, v in self.spell_dict.items()}

        # Convert roster keys to strings for JSON
        roster_str = {str(k): v for k, v in self.roster.items()}

        return {
            "v": 2,
            "startMs": start_ms,
            "guids": self.guids,
            "spells": spell_dict_str,
            "roster": roster_str,
            "events": self.events,
        }


def compress_eventlog(log_dict):
    """Compress eventLog dict → LibDeflate EncodeForPrint string."""
    json_str = json.dumps(log_dict, separators=(',', ':'))
    compressed = zlib.compress(json_str.encode('utf-8'), 9)
    return encode_for_print(compressed)


def lua_escape(s):
    """Escape a string for Lua."""
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r')


def write_trinketed_lua(matches, output_path):
    """Write matches in TrinketedHistoryDB format."""
    with open(output_path, 'w') as f:
        f.write('\nTrinketedHistoryDB = {\n')
        f.write('["settings"] = {\n["showTimestamp"] = true,\n["enableGameLog"] = true,\n},\n')
        f.write('["games"] = {\n')

        for i, match in enumerate(matches):
            m = match["meta"]
            el = match["eventLog"]

            f.write('{\n')
            f.write(f'["startTime"] = {m["startTime"]},\n')
            f.write(f'["endTime"] = {m["endTime"]},\n')
            f.write(f'["map"] = "{lua_escape(m["map"])}",\n')
            f.write(f'["result"] = "{m["result"]}",\n')
            f.write(f'["playerName"] = "{lua_escape(m["playerName"])}",\n')

            if m.get("bracket"):
                f.write(f'["bracket"] = "{m["bracket"]}",\n')
            if m.get("ratingBefore") is not None:
                f.write(f'["ratingBefore"] = {m["ratingBefore"]},\n')
            if m.get("ratingAfter") is not None:
                f.write(f'["ratingAfter"] = {m["ratingAfter"]},\n')
            if m.get("ratingChange") is not None:
                f.write(f'["ratingChange"] = {m["ratingChange"]},\n')

            # Friendly team
            f.write('["friendlyTeam"] = {\n')
            for p in m.get("friendlyTeam", []):
                f.write('{\n')
                f.write(f'["name"] = "{lua_escape(p["name"])}",\n')
                f.write(f'["class"] = "{lua_escape(p["class"])}",\n')
                if p.get("race"):
                    f.write(f'["race"] = "{lua_escape(p["race"])}",\n')
                if p.get("spec"):
                    f.write(f'["spec"] = "{lua_escape(p["spec"])}",\n')
                if p.get("ratingChange") is not None:
                    f.write(f'["ratingChange"] = {p["ratingChange"]},\n')
                f.write('},\n')
            f.write('},\n')

            # Enemy team
            f.write('["enemyTeam"] = {\n')
            for p in m.get("enemyTeam", []):
                f.write('{\n')
                f.write(f'["name"] = "{lua_escape(p["name"])}",\n')
                f.write(f'["class"] = "{lua_escape(p["class"])}",\n')
                if p.get("race"):
                    f.write(f'["race"] = "{lua_escape(p["race"])}",\n')
                if p.get("spec"):
                    f.write(f'["spec"] = "{lua_escape(p["spec"])}",\n')
                if p.get("ratingChange") is not None:
                    f.write(f'["ratingChange"] = {p["ratingChange"]},\n')
                f.write('},\n')
            f.write('},\n')

            # Enemy comp
            f.write('["enemyComp"] = {\n')
            for cls in m.get("enemyComp", []):
                f.write(f'"{lua_escape(cls)}",\n')
            f.write('},\n')

            # Event log
            f.write(f'["eventLog"] = "{lua_escape(el)}",\n')

            f.write('},\n')

        f.write('},\n')
        f.write('}\n')


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 convert_blackbox.py input.lua [output.lua]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else input_path.rsplit('.', 1)[0] + '-converted.lua'

    print(f"Reading {input_path}...")
    with open(input_path, 'r') as f:
        text = f.read()

    print("Parsing Lua SavedVariables...")
    db = parse_lua_savedvars(text)

    matches_raw = db.get("matches", [])
    if isinstance(matches_raw, dict):
        matches_raw = list(matches_raw.values())

    print(f"Found {len(matches_raw)} matches")

    converted = []
    total_events = 0
    total_json_bytes = 0
    total_encoded_bytes = 0

    for i, match in enumerate(matches_raw):
        if not isinstance(match, dict):
            continue

        builder = EventLogBuilder(match)
        log = builder.build()

        json_str = json.dumps(log, separators=(',', ':'))
        json_bytes = len(json_str)
        encoded = compress_eventlog(log)
        encoded_bytes = len(encoded)

        num_events = len(log["events"])
        total_events += num_events
        total_json_bytes += json_bytes
        total_encoded_bytes += encoded_bytes

        # Build roster info for teams
        roster = match.get("roster", {})
        friendly = []
        enemy = []
        enemy_classes = []
        player_name = match.get("playerName", "")

        for guid_str, info in roster.items():
            if not isinstance(info, dict):
                continue
            entry = {
                "name": info.get("name", ""),
                "class": info.get("class", ""),
                "race": info.get("race", ""),
                "spec": info.get("spec", ""),
            }
            rc = info.get("ratingChange")
            if rc is not None:
                entry["ratingChange"] = int(rc)
            if info.get("team") == "friendly":
                friendly.append(entry)
            else:
                enemy.append(entry)
                if info.get("class") and info["class"] not in enemy_classes:
                    enemy_classes.append(info["class"])

        bracket_val = match.get("bracket")
        bracket_str = f"{int(bracket_val)}v{int(bracket_val)}" if bracket_val else None

        meta = {
            "startTime": match.get("startTime", 0),
            "endTime": match.get("endTime", 0),
            "map": match.get("map", "Unknown"),
            "result": match.get("result", "LOSS"),
            "playerName": player_name,
            "bracket": bracket_str,
            "ratingBefore": match.get("ratingBefore"),
            "ratingAfter": match.get("ratingAfter"),
            "ratingChange": int(match.get("ratingAfter", 0) - match.get("ratingBefore", 0)) if match.get("ratingAfter") and match.get("ratingBefore") else None,
            "friendlyTeam": friendly,
            "enemyTeam": enemy,
            "enemyComp": enemy_classes,
        }

        converted.append({"meta": meta, "eventLog": encoded})

        result = match.get("result", "?")
        map_name = match.get("map", "?")[:20]
        print(f"  Match {i+1}: {result:4s} {map_name:<20s} {num_events:>6,} events → {json_bytes:>8,} JSON → {encoded_bytes:>7,} encoded")

    print(f"\nTotal: {total_events:,} events, {total_json_bytes:,} bytes JSON → {total_encoded_bytes:,} bytes encoded")
    print(f"Compression ratio: {total_json_bytes / max(1, total_encoded_bytes):.1f}x")

    print(f"\nWriting {output_path}...")
    write_trinketed_lua(converted, output_path)

    import os
    out_size = os.path.getsize(output_path)
    in_size = os.path.getsize(input_path)
    print(f"Input:  {in_size:>12,} bytes")
    print(f"Output: {out_size:>12,} bytes")
    print(f"Reduction: {(1 - out_size / in_size) * 100:.1f}%")
    print("Done!")


if __name__ == "__main__":
    main()
