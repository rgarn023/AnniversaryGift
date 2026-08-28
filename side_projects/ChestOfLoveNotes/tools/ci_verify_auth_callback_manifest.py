#!/usr/bin/env python3
"""Verify a packaged Android manifest exposes the OAuth callback route.

v77 shipped an AAB whose manifest had lost the auth callback intent filter even
though source injection looked successful. The build must fail rather than
upload an artifact when that happens again, so this validator is run against
the FINAL packaged manifests of both the APK and the AAB.

Two input formats are supported:

  aapt  the text tree from `aapt dump xmltree <apk> AndroidManifest.xml`
  xml   real XML, e.g. `bundletool dump manifest --bundle=<aab>`

Both are reduced to the same element tree and checked structurally: the
VIEW/DEFAULT/BROWSABLE filter and its scheme/host must belong to the callback
Activity itself, not merely appear somewhere in the manifest.
"""
from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET

ACTIVITY = "com.charoitegames.chestoflovenotes.securestorage.AuthCallbackActivity"
SCHEME = "com.charoitegames.chestoflovenotes"
HOST = "auth-callback"
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


class Node:
    def __init__(self, tag: str) -> None:
        self.tag = tag
        self.attrs: dict[str, str] = {}
        self.children: list["Node"] = []

    def find_all(self, tag: str) -> list["Node"]:
        found = []
        stack = list(self.children)
        while stack:
            node = stack.pop()
            if node.tag == tag:
                found.append(node)
            stack.extend(node.children)
        return found


# `A: android:name(0x01010003)="value" (Raw: "value")` or a typed scalar such as
# `A: android:exported(0x01010010)=(type 0x12)0xffffffff`.
_ELEMENT = re.compile(r"^(\s*)E: ([^ ]+)")
_ATTR = re.compile(r'^\s*A: (?:android:)?([A-Za-z0-9_]+)(?:\(0x[0-9a-f]+\))?=(.*)$')
_TYPED = re.compile(r"^\(type (0x[0-9a-f]+)\)(0x[0-9a-f]+)")

# aapt attribute type codes: 0x12 is boolean, 0x10/0x11 are decimal/hex ints.
_TYPE_BOOLEAN = 0x12


def _attr_value(raw: str) -> str:
    raw = raw.strip()
    # Prefer the Raw form; aapt prints resolved and raw values for strings.
    m = re.search(r'\(Raw: "(.*)"\)\s*$', raw)
    if m:
        return m.group(1)
    if raw.startswith('"'):
        end = raw.find('"', 1)
        if end > 0:
            return raw[1:end]
    m = _TYPED.match(raw)
    if m:
        type_code, value = int(m.group(1), 16), int(m.group(2), 16)
        if type_code == _TYPE_BOOLEAN:
            # aapt renders booleans as 0xffffffff (true) / 0x0 (false).
            return "true" if value else "false"
        # Ints (launchMode and friends) must keep their value, not collapse to a
        # truthiness flag. Signed 32-bit, so wrap values above the positive range.
        if value >= 0x80000000:
            value -= 0x100000000
        return str(value)
    return raw


def parse_aapt_tree(text: str) -> Node:
    root = Node("#root")
    # (indent, node) stack; indentation encodes nesting depth in aapt output.
    stack: list[tuple[int, Node]] = [(-1, root)]
    for line in text.splitlines():
        m = _ELEMENT.match(line)
        if m:
            indent = len(m.group(1))
            node = Node(m.group(2))
            while stack and stack[-1][0] >= indent:
                stack.pop()
            stack[-1][1].children.append(node)
            stack.append((indent, node))
            continue
        m = _ATTR.match(line)
        if m and len(stack) > 1:
            stack[-1][1].attrs[m.group(1)] = _attr_value(m.group(2))
    return root


def parse_xml(text: str) -> Node:
    def convert(elem: ET.Element) -> Node:
        node = Node(elem.tag.split("}")[-1])
        for key, value in elem.attrib.items():
            name = key[len(ANDROID_NS):] if key.startswith(ANDROID_NS) else key.split("}")[-1]
            node.attrs[name] = value
        node.children = [convert(child) for child in elem]
        return node

    root = Node("#root")
    root.children.append(convert(ET.fromstring(text)))
    return root


def verify(root: Node, label: str) -> None:
    activities = [a for a in root.find_all("activity") if a.attrs.get("name") == ACTIVITY]
    if not activities:
        raise SystemExit(f"ERROR: {label} manifest is missing activity {ACTIVITY}")

    reasons = []
    for activity in activities:
        if activity.attrs.get("exported") != "true":
            reasons.append("activity is not android:exported=true")
            continue
        for filt in activity.find_all("intent-filter"):
            actions = {n.attrs.get("name") for n in filt.find_all("action")}
            cats = {n.attrs.get("name") for n in filt.find_all("category")}
            if "android.intent.action.VIEW" not in actions:
                continue
            if "android.intent.category.DEFAULT" not in cats:
                continue
            if "android.intent.category.BROWSABLE" not in cats:
                continue
            for data in filt.find_all("data"):
                if data.attrs.get("scheme") == SCHEME and data.attrs.get("host") == HOST:
                    print(
                        f"STRICT_AUTH_CALLBACK_OK ({label}): exported {ACTIVITY} "
                        f"owns VIEW/DEFAULT/BROWSABLE {SCHEME}://{HOST}"
                    )
                    return
        reasons.append(
            "activity is exported but has no VIEW/DEFAULT/BROWSABLE filter for "
            f"{SCHEME}://{HOST}"
        )
    raise SystemExit(f"ERROR: {label} manifest callback route invalid: {'; '.join(reasons)}")


# AuthCallbackActivity sends FLAG_ACTIVITY_CLEAR_TOP to bring the app forward.
# Against a "standard" launcher that tears down and recreates the Godot activity
# (a full app restart on return from Google) instead of resuming it, so report
# what the export template actually produced. Informational only: the callback
# still completes via the cold-start consumer either way.
_LAUNCH_MODES = {"0": "standard", "1": "singleTop", "2": "singleTask", "3": "singleInstance"}


def report_launcher(root: Node, label: str) -> None:
    for tag in ("activity", "activity-alias"):
        for node in root.find_all(tag):
            for filt in node.find_all("intent-filter"):
                actions = {n.attrs.get("name") for n in filt.find_all("action")}
                cats = {n.attrs.get("name") for n in filt.find_all("category")}
                if "android.intent.action.MAIN" not in actions:
                    continue
                if "android.intent.category.LAUNCHER" not in cats:
                    continue
                raw = node.attrs.get("launchMode", "0")
                mode = _LAUNCH_MODES.get(raw, "unknown(%s)" % raw)
                warn = "" if mode in ("singleTop", "singleTask", "singleInstance") else \
                    "  <-- CLEAR_TOP will recreate this activity (app restarts on auth return)"
                print("LAUNCHER_INFO (%s): %s <%s> launchMode=%s%s"
                      % (label, node.attrs.get("name", "?"), tag, mode, warn))
                return
    print("LAUNCHER_INFO (%s): no MAIN/LAUNCHER entry found" % label)


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: ci_verify_auth_callback_manifest.py <aapt|xml> <file> <label>")
    mode, path, label = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    root = parse_aapt_tree(text) if mode == "aapt" else parse_xml(text)
    verify(root, label)
    report_launcher(root, label)


if __name__ == "__main__":
    main()
