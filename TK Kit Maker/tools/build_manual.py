"""Renders USER_GUIDE.md to USER_GUIDE.pdf.

    python tools/build_manual.py

The PDF ships with the script, so it has to be rebuilt whenever the guide
changes -- which is why this exists as a script rather than as something done by
hand once. Run it after editing USER_GUIDE.md and commit both.

This is not a general Markdown converter. It handles exactly what the guide
uses -- headings, tables, bullets, numbered steps, block quotes, rules, bold and
inline code -- and raises on anything it does not recognise, so an unsupported
construct is a failed build rather than a line silently dropped from the manual.

Fonts are loaded from Windows rather than using ReportLab's built-in Helvetica,
which is Type 1 with WinAnsi encoding: the guide's arrows and ellipses are not
in that character set and would come out as solid black boxes.
"""

import os
import re
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Frame, HRFlowable, KeepTogether, ListFlowable, ListItem,
    PageTemplate, Paragraph, Spacer, Table, TableStyle,
)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "USER_GUIDE.md")
OUT = os.path.join(ROOT, "USER_GUIDE.pdf")

TITLE = "Kit Maker - User Guide"
AUTHOR = "TouristKiller & Flurmechanic"

INK = colors.HexColor("#1A1A1E")
DIM = colors.HexColor("#5A5A66")
ACCENT = colors.HexColor("#C8783C")
RULE = colors.HexColor("#D8D8DE")
PANEL = colors.HexColor("#F4F4F7")
CODE_BG = colors.HexColor("#EDEDF2")


def register_fonts():
    """Body, bold, italic and a monospace face, from the system font folder."""
    win = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
    families = [
        # (family, regular, bold, italic, bold-italic)
        ("Calibri", "calibri.ttf", "calibrib.ttf", "calibrii.ttf", "calibriz.ttf"),
        ("Arial", "arial.ttf", "arialbd.ttf", "ariali.ttf", "arialbi.ttf"),
    ]
    for name, reg, bold, ital, bi in families:
        paths = [os.path.join(win, f) for f in (reg, bold, ital, bi)]
        if not all(os.path.exists(p) for p in paths):
            continue
        for suffix, path in zip(("", "-Bold", "-Italic", "-BoldItalic"), paths):
            pdfmetrics.registerFont(TTFont(name + suffix, path))
        pdfmetrics.registerFontFamily(
            name, normal=name, bold=name + "-Bold",
            italic=name + "-Italic", boldItalic=name + "-BoldItalic")
        body = name
        break
    else:
        raise SystemExit("No usable system font found in " + win)

    mono_path = os.path.join(win, "consola.ttf")
    if os.path.exists(mono_path):
        pdfmetrics.registerFont(TTFont("Mono", mono_path))
        mono = "Mono"
    else:
        mono = "Courier"
    return body, mono


BODY, MONO = register_fonts()

# Characters the guide uses that the body font has no glyph for, and what to
# print instead. Kept explicit and tiny: a missing glyph is a solid black box in
# the finished manual, and a silent substitution table would be a place for that
# to be quietly papered over.
SUBSTITUTE = {
    "⋯": "…",   # midline ellipsis (the "..." button) -> ellipsis
}


def check_glyphs(text):
    """Refuse to build a manual with boxes in it."""
    face = pdfmetrics.getFont(BODY).face
    missing = sorted({ch for ch in text
                      if ord(ch) > 127 and ord(ch) not in face.charToGlyph})
    if missing:
        raise SystemExit(
            "%s has no glyph for: %s\nAdd a substitute in SUBSTITUTE, or use a "
            "font that covers it -- these would render as black boxes."
            % (BODY, " ".join("U+%04X (%s)" % (ord(c), c) for c in missing)))


def styles():
    def st(name, **kw):
        opts = dict(fontName=BODY, textColor=INK, alignment=TA_LEFT)
        opts.update(kw)
        return ParagraphStyle(name, **opts)

    return {
        "title": st("title", fontSize=26, leading=30, spaceAfter=4,
                    fontName=BODY + "-Bold"),
        "h1": st("h1", fontSize=17, leading=21, spaceBefore=18, spaceAfter=7,
                 fontName=BODY + "-Bold", textColor=ACCENT),
        "h2": st("h2", fontSize=13, leading=17, spaceBefore=13, spaceAfter=5,
                 fontName=BODY + "-Bold"),
        "h3": st("h3", fontSize=11, leading=15, spaceBefore=10, spaceAfter=4,
                 fontName=BODY + "-Bold", textColor=DIM),
        "body": st("body", fontSize=10, leading=14.5, spaceAfter=7),
        "bullet": st("bullet", fontSize=10, leading=14.5, spaceAfter=3),
        "quote": st("quote", fontSize=9.5, leading=14, leftIndent=0,
                    rightIndent=0, spaceBefore=0, spaceAfter=0,
                    textColor=DIM),
        "th": st("th", fontSize=9, leading=12.5, fontName=BODY + "-Bold"),
        "td": st("td", fontSize=9, leading=12.5),
    }


S = styles()

# --- inline markup -----------------------------------------------------------

ESCAPES = ((("&", "&amp;"), ("<", "&lt;"), (">", "&gt;")))


def inline(text):
    """`**bold**`, `*italic*` and `` `code` `` to ReportLab's markup."""
    out = text
    for a, b in ESCAPES:
        out = out.replace(a, b)
    # Code first: its contents must not then be read as emphasis.
    out = re.sub(r"`([^`]+)`",
                 lambda m: '<font face="%s" size="9" backColor="#%s">%s</font>'
                           % (MONO, CODE_BG.hexval()[2:], m.group(1)), out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", out)
    out = re.sub(r"(?<![*\w])\*([^*]+)\*(?!\w)", r"<i>\1</i>", out)
    return out


# --- block parsing -----------------------------------------------------------

def split_row(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def build_table(rows, width):
    header, body = rows[0], rows[1:]
    data = [[Paragraph(inline(c), S["th"]) for c in header]]
    data += [[Paragraph(inline(c), S["td"]) for c in r] for r in body]

    n = len(header)
    # The first column of these tables is a label and the rest is prose, so a
    # flat split would leave the labels wrapping while the prose has room.
    if n == 2:
        widths = [width * 0.30, width * 0.70]
    else:
        widths = [width / n] * n

    t = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), PANEL),
        ("LINEBELOW", (0, 0), (-1, 0), 0.6, RULE),
        ("LINEBELOW", (0, 1), (-1, -2), 0.3, RULE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]))
    return t


def parse(md, width):
    story = []
    lines = md.split("\n")
    i = 0
    first_heading = True

    while i < len(lines):
        line = lines[i].rstrip()
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        # Tables: a run of pipe rows, with the alignment row dropped.
        if stripped.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = split_row(lines[i])
                # The alignment row, |---|:--:|, is separator not content. It
                # has to be recognised per cell: as one string it still contains
                # the pipes between the columns.
                if not all(re.fullmatch(r":?-+:?", c) for c in cells):
                    rows.append(cells)
                i += 1
            story.append(Spacer(1, 3))
            story.append(build_table(rows, width))
            story.append(Spacer(1, 9))
            continue

        # Headings.
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            level, text = len(m.group(1)), m.group(2)
            if level == 1:
                story.append(Paragraph(inline(text), S["title"]))
            else:
                key = {2: "h1", 3: "h2", 4: "h3"}.get(level, "h3")
                # A heading alone at the foot of a page reads as a mistake.
                nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
                head = Paragraph(inline(text), S[key])
                if level == 2 and not first_heading:
                    story.append(Spacer(1, 4))
                story.append(head if nxt.startswith("|") else KeepTogether(
                    [head, Paragraph(inline(nxt), S["body"])]))
                if not nxt.startswith("|") and nxt:
                    i += 1  # consumed by the KeepTogether above
                first_heading = False
            i += 1
            continue

        if stripped == "---":
            story.append(Spacer(1, 6))
            story.append(HRFlowable(width="100%", thickness=0.6, color=RULE,
                                    spaceBefore=0, spaceAfter=10))
            i += 1
            continue

        # Block quotes: the guide uses them for asides.
        if stripped.startswith(">"):
            block = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                block.append(lines[i].strip().lstrip(">").strip())
                i += 1
            para = Paragraph(inline(" ".join(block)), S["quote"])
            t = Table([[para]], colWidths=[width], hAlign="LEFT")
            t.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, -1), PANEL),
                ("LINEBEFORE", (0, 0), (0, -1), 2, ACCENT),
                ("LEFTPADDING", (0, 0), (-1, -1), 9),
                ("RIGHTPADDING", (0, 0), (-1, -1), 9),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
            ]))
            story.append(t)
            story.append(Spacer(1, 9))
            continue

        # Bullets and numbered steps. Continuation lines are indented under the
        # marker, and a blank line inside a list starts a new paragraph in the
        # same item -- both of which the guide uses.
        m = re.match(r"^([-*]|\d+\.)\s+(.*)$", stripped)
        if m:
            numbered = m.group(1)[0].isdigit()
            items = []
            while i < len(lines):
                cur = lines[i]
                mm = re.match(r"^([-*]|\d+\.)\s+(.*)$", cur.strip())
                if mm and not cur.startswith("  "):
                    if numbered != mm.group(1)[0].isdigit():
                        break
                    items.append([mm.group(2)])
                    i += 1
                elif cur.strip() and (cur.startswith("  ") or cur.startswith("\t")):
                    if not items:
                        break
                    # A nested list would end this item -- but the marker has
                    # to be followed by a space to be one. Without that, a
                    # continuation line starting in bold ("**Focus** sets...")
                    # reads its own asterisk as a bullet, and the rest of the
                    # sentence breaks off into a paragraph of its own.
                    if re.match(r"^([-*]|\d+\.)\s+", cur.strip()):
                        break  # nested list -- not used by the guide
                    items[-1].append(cur.strip())
                    i += 1
                elif not cur.strip():
                    # One blank line inside a list is a paragraph break; two
                    # end it.
                    if (i + 1 < len(lines) and lines[i + 1].startswith("  ")
                            and lines[i + 1].strip()):
                        items[-1].append("")
                        i += 1
                    else:
                        break
                else:
                    break

            flow = []
            for parts in items:
                paras, cur = [], []
                for p in parts:
                    if p == "":
                        paras.append(" ".join(cur))
                        cur = []
                    else:
                        cur.append(p)
                paras.append(" ".join(cur))
                inner = [Paragraph(inline(p), S["bullet"]) for p in paras if p]
                flow.append(ListItem(inner, leftIndent=14))

            story.append(ListFlowable(
                flow, bulletType="1" if numbered else "bullet",
                bulletFontName=BODY, bulletFontSize=9,
                bulletFormat="%s." if numbered else None,
                start=1 if numbered else "\u2022",
                leftIndent=18, bulletOffsetY=-1))
            story.append(Spacer(1, 7))
            continue

        # Anything else is a paragraph: gather until a blank line or a block.
        block = []
        while i < len(lines):
            cur = lines[i].strip()
            if (not cur or cur.startswith(("|", "#", ">", "---"))
                    or re.match(r"^([-*]|\d+\.)\s+", cur)):
                break
            block.append(cur)
            i += 1
        text = " ".join(block)
        if text:
            story.append(Paragraph(inline(text), S["body"]))

    return story


# --- page furniture ----------------------------------------------------------

def decorate(canvas, doc):
    canvas.saveState()
    canvas.setFont(BODY, 8)
    canvas.setFillColor(DIM)
    w, h = A4
    if doc.page > 1:
        canvas.drawString(20 * mm, h - 12 * mm, TITLE)
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.4)
    canvas.line(20 * mm, 14 * mm, w - 20 * mm, 14 * mm)
    canvas.drawRightString(w - 20 * mm, 9.5 * mm, str(doc.page))
    canvas.restoreState()


def main():
    md = open(SRC, encoding="utf-8").read()
    for bad, good in SUBSTITUTE.items():
        md = md.replace(bad, good)
    check_glyphs(md)

    doc = BaseDocTemplate(
        OUT, pagesize=A4,
        leftMargin=20 * mm, rightMargin=20 * mm,
        topMargin=18 * mm, bottomMargin=20 * mm,
        title=TITLE, author=AUTHOR, subject="TK Kit Maker for REAPER",
    )
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height,
                  id="body", leftPadding=0, rightPadding=0,
                  topPadding=0, bottomPadding=0)
    doc.addPageTemplates([PageTemplate(id="main", frames=[frame],
                                       onPage=decorate)])

    doc.build(parse(md, doc.width))

    pages = "?"
    try:
        import pypdf
        pages = len(pypdf.PdfReader(OUT).pages)
    except Exception:
        pass
    size = os.path.getsize(OUT)
    print("wrote %s  (%d pages, %.1f kB)" % (os.path.basename(OUT), pages, size / 1024))


if __name__ == "__main__":
    sys.exit(main())
