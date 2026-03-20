#!/usr/bin/env python3
"""Decode a TrinketedHistory gameLog string and pretty-print the JSON."""

import sys
import zlib
import json

# LibDeflate EncodeForPrint alphabet: a-z A-Z 0-9 ( )
CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
CHAR_TO_6BIT = {c: i for i, c in enumerate(CHARSET)}


def decode_for_print(encoded: str) -> bytes:
    """Reverse LibDeflate:EncodeForPrint — base64-like with custom alphabet."""
    result = bytearray()
    i = 0
    n = len(encoded)
    while i + 3 < n:
        b1 = CHAR_TO_6BIT[encoded[i]]
        b2 = CHAR_TO_6BIT[encoded[i + 1]]
        b3 = CHAR_TO_6BIT[encoded[i + 2]]
        b4 = CHAR_TO_6BIT[encoded[i + 3]]
        # 4 x 6-bit values → 3 bytes (24 bits)
        cache = b1 + b2 * 64 + b3 * 4096 + b4 * 262144
        result.append(cache & 0xFF)
        result.append((cache >> 8) & 0xFF)
        result.append((cache >> 16) & 0xFF)
        i += 4

    # Handle remaining 1-3 characters
    if i < n:
        cache = 0
        cache_bitlen = 0
        remaining = n - i
        for j in range(remaining):
            cache += CHAR_TO_6BIT[encoded[i + j]] << (6 * j)
            cache_bitlen += 6
        while cache_bitlen >= 8:
            result.append(cache & 0xFF)
            cache >>= 8
            cache_bitlen -= 8

    return bytes(result)


def main():
    if len(sys.argv) > 1:
        data = sys.argv[1]
    else:
        data = sys.stdin.read().strip()

    compressed = decode_for_print(data)
    json_str = zlib.decompress(compressed)
    parsed = json.loads(json_str)

    # Summary
    event_count = parsed.get("eventCount", len(parsed.get("events", [])))
    print(f"=== Game Log v{parsed.get('v', '?')} — {event_count} events ===\n")

    # Initial state
    initial = parsed.get("initialState", {})
    if initial:
        print(f"Snapshot timestamp: {initial.get('timestamp', 'N/A')}")
        players = initial.get("players", {})
        print(f"Players ({len(players)}):")
        for guid, info in players.items():
            print(f"  [{info.get('team', '?')}] {info.get('name', '?')} "
                  f"({info.get('class', '?')}) "
                  f"HP: {info.get('health', 0)}/{info.get('healthMax', 0)} "
                  f"Power: {info.get('power', 0)}/{info.get('powerMax', 0)}")
        print()

    # First/last few events
    events = parsed.get("events", [])
    preview = 10
    if events:
        print(f"First {min(preview, len(events))} events:")
        for ev in events[:preview]:
            ts = ev[0] if ev else "?"
            subevent = ev[1] if len(ev) > 1 else "?"
            src = ev[4] if len(ev) > 4 else ""
            dst = ev[8] if len(ev) > 8 else ""
            spell = ev[12] if len(ev) > 12 else ""
            print(f"  {ts}  {subevent:<35} {src or ''} → {dst or ''}  {spell or ''}")

        if len(events) > preview:
            print(f"  ... ({len(events) - preview} more events)")
            print(f"\nLast {min(preview, len(events))} events:")
            for ev in events[-preview:]:
                ts = ev[0] if ev else "?"
                subevent = ev[1] if len(ev) > 1 else "?"
                src = ev[4] if len(ev) > 4 else ""
                dst = ev[8] if len(ev) > 8 else ""
                spell = ev[12] if len(ev) > 12 else ""
                print(f"  {ts}  {subevent:<35} {src or ''} → {dst or ''}  {spell or ''}")

    # Dump full JSON with --json flag
    if "--json" in sys.argv:
        print("\n=== Full JSON ===")
        print(json.dumps(parsed, indent=2))


if __name__ == "__main__":
    main()
