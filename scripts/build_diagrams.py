#!/usr/bin/env python3
"""Build the docs diagrams.

Each diagram is described once below and written twice:
  docs/diagrams/<name>.excalidraw  editable source; open it at https://excalidraw.com
  docs/diagrams/<name>.svg         rendered copy that GitHub shows inline

Run from the repository root: python3 scripts/build_diagrams.py
"""

import hashlib
import json
import os
from xml.sax.saxutils import escape

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "docs", "diagrams")

# Excalidraw's own palette, so the source and the SVG match.
COLORS = {
    "blue": "#a5d8ff",
    "green": "#b2f2bb",
    "yellow": "#ffec99",
    "red": "#ffc9c9",
    "violet": "#d0bfff",
    "gray": "#e9ecef",
    "white": "#ffffff",
    "none": "transparent",
}
STROKE = "#1e1e1e"
MUTED = "#495057"
FONT_SIZE = 16
LINE_HEIGHT = 1.25
SVG_FONT = "'Segoe UI', -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif"


def seed(*parts):
    return int(hashlib.md5("|".join(map(str, parts)).encode()).hexdigest()[:8], 16)


class Diagram:
    def __init__(self, name, title):
        self.name = name
        self.title = title
        self.nodes = {}
        self.order = []
        self.edges = []
        self.notes = []

    def box(self, key, x, y, w, h, text, color="white", shape="rectangle", dashed=False, size=FONT_SIZE, bold_first=False):
        self.nodes[key] = dict(key=key, x=x, y=y, w=w, h=h, text=text, color=color,
                               shape=shape, dashed=dashed, size=size, bold_first=bold_first)
        self.order.append(key)

    def group(self, key, x, y, w, h, label, color="gray"):
        """A large dashed frame with its label in the top-left corner."""
        self.nodes[key] = dict(key=key, x=x, y=y, w=w, h=h, text="", color=color, shape="frame",
                               dashed=True, size=FONT_SIZE, label=label, bold_first=False)
        self.order.insert(0, key)

    def arrow(self, a, b, label="", start="auto", end="auto", dashed=False, via=None):
        self.edges.append(dict(a=a, b=b, label=label, start=start, end=end, dashed=dashed, via=via or []))

    def note(self, x, y, text, size=14, color=MUTED, align="left"):
        self.notes.append(dict(x=x, y=y, text=text, size=size, color=color, align=align))

    # Geometry ---------------------------------------------------------------

    def port(self, key, side):
        """A point on a box edge. `side` is a name, or (name, fraction along that edge)."""
        n = self.nodes[key]
        frac = 0.5
        if isinstance(side, tuple):
            side, frac = side
        if side in ("top", "bottom"):
            x = n["x"] + n["w"] * frac
            return (x, n["y"] if side == "top" else n["y"] + n["h"])
        y = n["y"] + n["h"] * frac
        return (n["x"] if side == "left" else n["x"] + n["w"], y)

    def auto_sides(self, a, b):
        na, nb = self.nodes[a], self.nodes[b]
        ax, ay = na["x"] + na["w"] / 2, na["y"] + na["h"] / 2
        bx, by = nb["x"] + nb["w"] / 2, nb["y"] + nb["h"] / 2
        dx, dy = bx - ax, by - ay
        if abs(dy) * 1.2 >= abs(dx):
            return ("bottom", "top") if dy > 0 else ("top", "bottom")
        return ("right", "left") if dx > 0 else ("left", "right")

    def edge_points(self, e):
        s_auto, e_auto = self.auto_sides(e["a"], e["b"])
        start = self.port(e["a"], s_auto if e["start"] == "auto" else e["start"])
        end = self.port(e["b"], e_auto if e["end"] == "auto" else e["end"])
        return [start] + [tuple(p) for p in e["via"]] + [end]

    def bounds(self):
        xs, ys = [], []
        for n in self.nodes.values():
            xs += [n["x"], n["x"] + n["w"]]
            ys += [n["y"], n["y"] + n["h"]]
        for t in self.notes:
            lines = t["text"].split("\n")
            xs += [t["x"], t["x"] + max(len(l) for l in lines) * t["size"] * 0.55]
            ys += [t["y"], t["y"] + len(lines) * t["size"] * LINE_HEIGHT]
        return min(xs), min(ys), max(xs), max(ys)

    # Excalidraw -------------------------------------------------------------

    def to_excalidraw(self):
        elements = []
        ids = {}

        def base(kind, eid, x, y, w, h, **extra):
            el = {
                "id": eid, "type": kind, "x": x, "y": y, "width": w, "height": h,
                "angle": 0, "strokeColor": STROKE, "backgroundColor": "transparent",
                "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
                "roughness": 1, "opacity": 100, "groupIds": [], "frameId": None,
                "roundness": None, "seed": seed(self.name, eid), "version": 1,
                "versionNonce": seed(self.name, eid, "n"), "isDeleted": False,
                "boundElements": [], "updated": 1, "link": None, "locked": False,
            }
            el.update(extra)
            return el

        def text_el(eid, x, y, w, h, text, size, container=None, align="center", color=STROKE):
            return base("text", eid, x, y, w, h, strokeColor=color, text=text, originalText=text,
                        fontSize=size, fontFamily=5, textAlign=align,
                        verticalAlign="middle" if container else "top",
                        containerId=container, lineHeight=LINE_HEIGHT, autoResize=True)

        for key in self.order:
            n = self.nodes[key]
            eid = f"node-{key}"
            ids[key] = eid
            if n["shape"] == "frame":
                el = base("rectangle", eid, n["x"], n["y"], n["w"], n["h"],
                          backgroundColor=COLORS[n["color"]], strokeStyle="dashed",
                          strokeWidth=1, roundness={"type": 3}, opacity=60)
                elements.append(el)
                lid = f"label-{key}"
                elements.append(text_el(lid, n["x"] + 14, n["y"] + 10, n["w"] - 28, 22,
                                        n["label"], 18, align="left", color=MUTED))
                continue
            kind = "diamond" if n["shape"] == "diamond" else ("ellipse" if n["shape"] == "pill" else "rectangle")
            el = base(kind, eid, n["x"], n["y"], n["w"], n["h"],
                      backgroundColor=COLORS[n["color"]],
                      strokeStyle="dashed" if n["dashed"] else "solid",
                      roundness={"type": 3} if kind == "rectangle" else {"type": 2})
            tid = f"text-{key}"
            el["boundElements"].append({"type": "text", "id": tid})
            elements.append(el)
            lines = n["text"].split("\n")
            th = len(lines) * n["size"] * LINE_HEIGHT
            elements.append(text_el(tid, n["x"] + 8, n["y"] + (n["h"] - th) / 2, n["w"] - 16, th,
                                    n["text"], n["size"], container=eid))

        for i, e in enumerate(self.edges):
            pts = self.edge_points(e)
            x0, y0 = pts[0]
            aid = f"edge-{i}"
            rel = [[px - x0, py - y0] for px, py in pts]
            xs = [p[0] for p in rel]
            ys = [p[1] for p in rel]
            el = base("arrow", aid, x0, y0, max(xs) - min(xs), max(ys) - min(ys),
                      points=rel, startArrowhead=None, endArrowhead="arrow",
                      strokeStyle="dashed" if e["dashed"] else "solid",
                      roundness={"type": 2} if len(pts) == 2 else None,
                      startBinding={"elementId": ids[e["a"]], "focus": 0, "gap": 4},
                      endBinding={"elementId": ids[e["b"]], "focus": 0, "gap": 4},
                      lastCommittedPoint=None, elbowed=False)
            for side in (e["a"], e["b"]):
                for el2 in elements:
                    if el2["id"] == ids[side]:
                        el2["boundElements"].append({"type": "arrow", "id": aid})
            if e["label"]:
                lid = f"edge-label-{i}"
                el["boundElements"].append({"type": "text", "id": lid})
                mx, my = self.label_point(pts)
                lines = e["label"].split("\n")
                w = max(len(l) for l in lines) * 14 * 0.55
                h = len(lines) * 14 * LINE_HEIGHT
                t = text_el(lid, mx - w / 2, my - h / 2, w, h, e["label"], 14, container=aid, color=MUTED)
                elements.append(el)
                elements.append(t)
            else:
                elements.append(el)

        for i, t in enumerate(self.notes):
            lines = t["text"].split("\n")
            w = max(len(l) for l in lines) * t["size"] * 0.55
            h = len(lines) * t["size"] * LINE_HEIGHT
            elements.append(text_el(f"note-{i}", t["x"], t["y"], w, h, t["text"], t["size"],
                                    align=t["align"], color=t["color"]))

        return {
            "type": "excalidraw",
            "version": 2,
            "source": "https://github.com/Zman2087/enough",
            "elements": elements,
            "appState": {"gridSize": 20, "viewBackgroundColor": "#ffffff"},
            "files": {},
        }

    # SVG --------------------------------------------------------------------

    @staticmethod
    def label_point(pts):
        # Middle of the longest segment, so labels sit on a straight run.
        best = max(range(len(pts) - 1), key=lambda i: abs(pts[i + 1][0] - pts[i][0]) + abs(pts[i + 1][1] - pts[i][1]))
        (x1, y1), (x2, y2) = pts[best], pts[best + 1]
        return (x1 + x2) / 2, (y1 + y2) / 2

    def svg_text(self, x, y, text, size, anchor="middle", color=STROKE, weight="normal", bold_first=False):
        lines = text.split("\n")
        lh = size * LINE_HEIGHT
        top = y - (len(lines) - 1) * lh / 2
        out = []
        for i, line in enumerate(lines):
            w = "600" if (bold_first and i == 0) else weight
            out.append(
                f'<text x="{x:.1f}" y="{top + i * lh:.1f}" font-size="{size}" font-weight="{w}" '
                f'text-anchor="{anchor}" dominant-baseline="central" fill="{color}">{escape(line)}</text>'
            )
        return "\n".join(out)

    def to_svg(self):
        pad = 40
        x0, y0, x1, y1 = self.bounds()
        title_h = 56
        width = x1 - x0 + pad * 2
        height = y1 - y0 + pad * 2 + title_h
        ox, oy = pad - x0, pad - y0 + title_h
        parts = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{height:.0f}" '
            f'viewBox="0 0 {width:.0f} {height:.0f}" font-family="{SVG_FONT}">',
            "<defs>",
            f'<marker id="arrow" viewBox="0 0 12 12" refX="11" refY="6" markerWidth="10" markerHeight="10" orient="auto-start-reverse">'
            f'<path d="M1,1 L11,6 L1,11" fill="none" stroke="{STROKE}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></marker>',
            "</defs>",
            f'<rect width="100%" height="100%" fill="#ffffff"/>',
            self.svg_text(pad, pad + 6, self.title, 22, anchor="start", weight="600"),
            f'<g transform="translate({ox:.1f},{oy:.1f})">',
        ]
        for key in self.order:
            n = self.nodes[key]
            fill = COLORS[n["color"]]
            dash = ' stroke-dasharray="8 6"' if n["dashed"] else ""
            if n["shape"] == "frame":
                parts.append(
                    f'<rect x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" height="{n["h"]}" rx="14" '
                    f'fill="{fill}" fill-opacity="0.45" stroke="{MUTED}" stroke-width="1.2" stroke-dasharray="8 6"/>'
                )
                parts.append(self.svg_text(n["x"] + 16, n["y"] + 22, n["label"], 17, anchor="start", color=MUTED, weight="600"))
                continue
            cx, cy = n["x"] + n["w"] / 2, n["y"] + n["h"] / 2
            if n["shape"] == "diamond":
                pts = f'{cx},{n["y"]} {n["x"] + n["w"]},{cy} {cx},{n["y"] + n["h"]} {n["x"]},{cy}'
                parts.append(f'<polygon points="{pts}" fill="{fill}" stroke="{STROKE}" stroke-width="2" stroke-linejoin="round"{dash}/>')
            elif n["shape"] == "pill":
                parts.append(
                    f'<rect x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" height="{n["h"]}" rx="{n["h"] / 2}" '
                    f'fill="{fill}" stroke="{STROKE}" stroke-width="2"{dash}/>'
                )
            else:
                parts.append(
                    f'<rect x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" height="{n["h"]}" rx="10" '
                    f'fill="{fill}" stroke="{STROKE}" stroke-width="2"{dash}/>'
                )
            parts.append(self.svg_text(cx, cy, n["text"], n["size"], bold_first=n["bold_first"]))
        for e in self.edges:
            pts = self.edge_points(e)
            d = " ".join(f"{'M' if i == 0 else 'L'}{x:.1f},{y:.1f}" for i, (x, y) in enumerate(pts))
            dash = ' stroke-dasharray="7 6"' if e["dashed"] else ""
            parts.append(f'<path d="{d}" fill="none" stroke="{STROKE}" stroke-width="2" '
                         f'stroke-linejoin="round" marker-end="url(#arrow)"{dash}/>')
            if e["label"]:
                mx, my = self.label_point(pts)
                lines = e["label"].split("\n")
                w = max(len(l) for l in lines) * 14 * 0.56 + 12
                h = len(lines) * 14 * LINE_HEIGHT + 6
                parts.append(f'<rect x="{mx - w / 2:.1f}" y="{my - h / 2:.1f}" width="{w:.1f}" height="{h:.1f}" rx="5" fill="#ffffff"/>')
                parts.append(self.svg_text(mx, my, e["label"], 14, color=MUTED))
        for t in self.notes:
            lines = t["text"].split("\n")
            lh = t["size"] * LINE_HEIGHT
            for i, line in enumerate(lines):
                parts.append(
                    f'<text x="{t["x"]}" y="{t["y"] + lh / 2 + i * lh:.1f}" font-size="{t["size"]}" '
                    f'dominant-baseline="central" fill="{t["color"]}">{escape(line)}</text>'
                )
        parts.append("</g></svg>")
        return "\n".join(parts) + "\n"


# Diagrams --------------------------------------------------------------------

def architecture():
    d = Diagram("architecture", "Enough: system architecture")
    d.group("device", 0, 0, 1180, 700, "iPhone (everything here stays on the device)")
    d.group("app", 30, 50, 520, 330, "Enough.app  (SwiftUI shell)", color="blue")
    d.box("shell", 60, 100, 220, 110, "App shell\nContentView, Settings,\ncount ring, overlays", "white", bold_first=True)
    d.box("model", 300, 100, 220, 110, "FeedModel\nstate, cap, route,\ncommands to the page", "white", bold_first=True)
    d.box("bridge", 60, 262, 460, 100, "WKWebView + message bridge\nloads instagram.com only, injects the\nbundled script, receives page messages", "white", bold_first=True)

    d.group("page", 600, 50, 550, 330, "Page context (inside the web view)", color="yellow")
    d.box("filter", 630, 100, 240, 110, "filter.js + hide.css\nbundled in the app,\nnever downloaded", "white", bold_first=True)
    d.box("rules", 890, 100, 230, 110, "What it does\nhides Reels, suggestions\ncollapses seen posts\nkeeps ads visible", "white", size=15, bold_first=True)
    d.box("ig", 630, 240, 490, 110, "instagram.com (mobile site)\nyou sign in on Meta's own page;\nthe app never sees the password", "red", bold_first=True)

    d.group("engine", 30, 410, 760, 190, "FilterEngine  (Swift package, shared and unit-tested)", color="green")
    d.box("nav", 60, 460, 160, 110, "NavigationPolicy\nmain frame:\ninstagram.com only", "white", size=15, bold_first=True)
    d.box("cap", 240, 460, 160, 110, "CapPolicy\nwhich pages\nthe cap blocks", "white", size=15, bold_first=True)
    d.box("usage", 420, 460, 160, 110, "UsageStore\nDayBoundary\ncount + reset", "white", size=15, bold_first=True)
    d.box("sel", 600, 460, 170, 110, "SelectorValidator\nremote rules are\ndata, never script", "white", size=15, bold_first=True)

    d.box("group", 830, 440, 320, 140, "App Group storage\nsettings JSON\ntoday's post shortcodes\n(deleted at the reset time)", "violet", bold_first=True)

    d.arrow("shell", "model", "", start="right", end="left")
    d.arrow("model", "bridge", "commands", start="bottom", end=("top", 0.76))
    d.arrow("bridge", "filter", "inject at\ndocument start", start=("right", 0.3), end="left", via=[(575, 273), (575, 155)])
    d.arrow("filter", "ig", "observes &\nrestyles", start="bottom", end=("top", 0.245))
    d.arrow("ig", "bridge", "page messages: postViewed, route, ready, caughtUp", start=("bottom", 0.1), end=("bottom", 0.8), dashed=True, via=[(679, 395), (428, 395)])
    d.arrow("usage", "group", "read / write", start="bottom", end="bottom", via=[(500, 640), (990, 640)])
    d.arrow("bridge", "nav", "every navigation", start=("bottom", 0.17), end="top")
    return d


def launch():
    d = Diagram("launch-sequence", "Launch: from tap to a usable feed")
    xs = [0, 230, 460, 690, 920]
    w, h = 200, 120
    d.box("tap", xs[0], 0, w, h, "1. App starts\nFeedHost builds the\none WKWebView", "blue", bold_first=True)
    d.box("cookies", xs[1], 0, w, h, "2. Session check\ncookie names only;\nvalues never read", "blue", bold_first=True)
    d.box("load", xs[2], 0, w, h, "3. Load\nhome feed  (signed in)\nlogin page (signed out)", "blue", bold_first=True)
    d.box("inject", xs[3], 0, w, h, "4. Document start\nboot payload, cap state,\nfilter.js, hide.css", "yellow", bold_first=True)
    d.box("ready", xs[4], 0, w, h, "5. Page has layout\nfilter.js posts\n{ type: \"ready\" }", "yellow", bold_first=True)
    d.box("shown", xs[4], 200, w, h, "6. Launch screen hides\n~1.5 s on a warm start", "green", bold_first=True)
    d.box("fallback", 330, 200, 440, h, "Fallback\nif \"ready\" never arrives, the launch screen\nstill hides after 3 s; the full page load can\ntake 20 s, which is why we don't wait for it", "gray", dashed=True, bold_first=True)
    for a, b in [("tap", "cookies"), ("cookies", "load"), ("load", "inject"), ("inject", "ready")]:
        d.arrow(a, b, start="right", end="left")
    d.arrow("ready", "shown", start="bottom", end="top")
    d.arrow("fallback", "shown", "3 s timer", start="right", end="left", dashed=True)
    return d


def counting():
    d = Diagram("post-counting", "How a post is counted (or not)")
    cx = 330
    d.box("enter", cx - 140, 0, 280, 70, "A post enters the page\n(MutationObserver)", "blue", bold_first=True)
    d.box("isad", cx - 120, 110, 240, 110, "Ad?\n\"Ad\" / \"Sponsored\" label\nor ad tracking link", "yellow", shape="diamond", size=14, bold_first=True)
    d.box("keep", cx + 220, 125, 260, 80, "Keep visible, never count\n(Personal build: collapse it)", "green", bold_first=True)
    d.box("isfollow", cx - 120, 260, 240, 110, "Suggested?\nhas its own Follow button,\nor a Reel", "yellow", shape="diamond", size=14, bold_first=True)
    d.box("hide", cx + 220, 275, 260, 80, "Hide it\n(not counted)", "red", bold_first=True)
    d.box("seen", cx - 120, 410, 240, 110, "Seen earlier today?\nshortcode in the\nApp Group list", "yellow", shape="diamond", size=14, bold_first=True)
    d.box("collapse", cx + 220, 425, 260, 80, "Collapse it\n(counted already)", "gray", bold_first=True)
    d.box("watch", cx - 140, 560, 280, 80, "Watch it\nIntersectionObserver, 50% visible", "blue", bold_first=True)
    d.box("capq", cx - 120, 680, 240, 110, "Cap reached?", "yellow", shape="diamond", size=15, bold_first=True)
    d.box("stop", cx + 220, 695, 260, 80, "Do nothing\n(the count stops at the cap)", "gray", bold_first=True)
    d.box("record", cx - 140, 830, 280, 90, "Count it once\npostViewed(permalink) →\nUsageStore.record", "green", bold_first=True)
    d.arrow("enter", "isad")
    d.arrow("isad", "keep", "yes", start="right", end="left")
    d.arrow("isad", "isfollow", "no")
    d.arrow("isfollow", "hide", "yes", start="right", end="left")
    d.arrow("isfollow", "seen", "no")
    d.arrow("seen", "collapse", "yes", start="right", end="left")
    d.arrow("seen", "watch", "no")
    d.arrow("watch", "capq", "≥ 50% on screen")
    d.arrow("capq", "stop", "yes", start="right", end="left")
    d.arrow("capq", "record", "no")
    return d


def daily_cap():
    d = Diagram("daily-cap", "The daily cap: what changes when you hit it")
    d.box("under", 0, 60, 300, 170, "Under the cap\nfeed scrolls normally\nposts count once each\ncount ring fills up", "green", bold_first=True)
    d.box("at", 460, 0, 420, 290, "At the cap\nHome: posts replaced in place by\n\"You're done for today\"\nHeader, stories tray, tab bar keep working\nMessages, Search, Profile stay open\nAn opened post shows only that post\nStories and Reels: full-screen overlay\nNothing more is counted", "red", bold_first=True)
    d.box("caught", 0, 330, 300, 120, "All caught up\nevery post already seen;\nsame in-feed notice, no cap", "blue", bold_first=True)
    d.box("reset", 460, 350, 420, 100, "Reset time (default 4:00 AM)\nthe day's shortcode list is deleted", "violet", bold_first=True)
    d.arrow("under", "at", "count reaches\nthe cap", start="right", end="left", via=[(380, 145)])
    d.arrow("at", "reset", "", start="bottom", end="top")
    d.arrow("reset", "under", "new day", start="left", end=("right", 0.82), via=[(390, 400), (390, 199)])
    d.arrow("under", "caught", "nothing new", start="bottom", end="top", dashed=True)
    return d


def main():
    os.makedirs(OUT, exist_ok=True)
    for build in (architecture, launch, counting, daily_cap):
        d = build()
        with open(os.path.join(OUT, f"{d.name}.excalidraw"), "w") as f:
            json.dump(d.to_excalidraw(), f, indent=2)
            f.write("\n")
        with open(os.path.join(OUT, f"{d.name}.svg"), "w") as f:
            f.write(d.to_svg())
        print(f"wrote docs/diagrams/{d.name}.excalidraw and .svg")


if __name__ == "__main__":
    main()
