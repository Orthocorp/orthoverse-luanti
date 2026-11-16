"""Add accented letters (French above all) and a few signs to the Midnight
font, drawn in its own 8 x 8 pixels.

    midnight_accents.py IN.ttf OUT.ttf [PREVIEW.png]

The font (Simon Holdsworth's TrueType of the Lords of Midnight lettering) has
only ASCII and the pound sign. Each new letter is its plain letter with an
accent drawn in the free rows above it: lower case letters are five pixels
high, leaving two rows (a gap, then the accent); capitals are seven high, so
an accented capital is drawn five rows high first (by hand, after the
font's own). The cedilla goes in the row below the line.
The pixels become squares on the font's 64-unit grid, merged into outlines.
"""
import sys

import pathops
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

PX = 64          # font units to a pixel
TOP = 7          # rows above the baseline (row 0 is the top; row 7 is below)
ROWS = 8

# The accents. Two rows (0 and 1, resting on the letter) read best at this
# size; the diaeresis is one row, with a gap below it
ACCENT = {
	"acute":      (".....##.", "....##.."),
	"grave":      ("..##....", "...##..."),
	"circumflex": ("...##...", "..#..#.."),
	"ring":       ("...##...", "..#..#.."),
	"tilde":      ("..##..#.", ".#..##.."),
	"diaeresis":  (".##..##.", "........"),
}

# Capitals pressed to five rows for an accent, drawn by hand from the font's
CAPS = {
	"A": ["..#####.", ".##...##", ".#######", ".##...##", ".###.###"],
	"E": [".#######", "..##...#", "..#####.", "..##...#", ".#######"],
	"I": ["..######", "....##..", "....##..", "....##..", "..######"],
	"O": ["..#####.", ".##...##", ".##...##", ".##...##", "..#####."],
	"U": [".###..##", "..##..##", ".##...##", ".##...##", "..#####."],
	"Y": [".###.###", "..##.##.", "...###..", "...##...", "...##..."],
	"N": [".###..##", ".####.##", ".##.####", ".##..###", ".##...##"],
}

# The new letters: the plain letter and its accents (and the same in capitals)
LETTERS = {}
for base, accs in {
	"a": "grave acute circumflex diaeresis ring",
	"e": "grave acute circumflex diaeresis",
	"i": "grave acute circumflex diaeresis",
	"o": "grave acute circumflex diaeresis",
	"u": "grave acute circumflex diaeresis",
	"y": "acute diaeresis",
	"n": "tilde",
}.items():
	for acc in accs.split():
		for b in (base, base.upper()):
			LETTERS.setdefault(b, []).append(acc)

import unicodedata


def char_for(base, acc):
	name = "LATIN %s LETTER %s WITH %s" % ("SMALL" if base.islower() else "CAPITAL", base.upper(),
		{"acute": "ACUTE", "grave": "GRAVE", "circumflex": "CIRCUMFLEX", "diaeresis": "DIAERESIS",
		 "ring": "RING ABOVE", "tilde": "TILDE"}[acc])
	try:
		return unicodedata.lookup(name)
	except KeyError:
		return None


# Drawn whole, 8 rows each (the last below the line)
DRAWN = {
	"æ": ["........", "........", ".###.##.", "...##..#", ".#######", "#..##...", ".###.###", "........"],
	"Æ": ["..######", ".##.#...", "##..#...", "#######.", "##..#...", "##..#...", "##..####", "........"],
	"œ": ["........", "........", ".##.###.", "#..##..#", "#..#####", "#..##...", ".##.####", "........"],
	"Œ": [".#######", "#..#....", "#..#....", "#..####.", "#..#....", "#..#....", ".#######", "........"],
	"ß": ["..####..", ".##..##.", ".##.##..", ".##..##.", ".##...##", ".##..##.", ".##.##..", "........"],
	"ø": ["........", "........", "..#####.", ".##..###", ".##.#.##", ".###..##", ".#####..", "........"],
	"Ø": ["...###.#", "..##.##.", ".##..###", ".##.#.##", ".###..##", "..##.##.", ".#.###..", "........"],
	"«": ["........", "........", "...#..#.", "..#..#..", ".#..#...", "..#..#..", "...#..#.", "........"],
	"»": ["........", "........", ".#..#...", "..#..#..", "...#..#.", "..#..#..", ".#..#...", "........"],
	"€": ["...####.", "..##....", "######..", ".##.....", "######..", "..##....", "...####.", "........"],
	"°": ["..###...", "..#.#...", "..###...", "........", "........", "........", "........", "........"],
	"·": ["........", "........", "........", "...##...", "...##...", "........", "........", "........"],
	"×": ["........", "........", ".##..##.", "..####..", "...##...", "..####..", ".##..##.", "........"],
}
# Copies of glyphs the font has, under other characters
COPY = {"’": "'", "‘": "'", "“": '"', "”": '"', "–": "-", " ": " ", "′": "'"}
# Copies turned half round
FLIP = {"¡": "!", "¿": "?"}


def bitmap(glyphset, gname):
	"""The glyph's 8 x 8 pixels, from its outline (even-odd, pixel centres)"""
	pen = RecordingPen()
	glyphset[gname].draw(pen)
	polys, poly = [], []
	for op, args in pen.value:
		if op == "moveTo":
			poly = [args[0]]
		elif op in ("lineTo", "qCurveTo", "curveTo"):
			poly.extend(args)
		elif op in ("closePath", "endPath"):
			polys.append(poly)
	rows = []
	for r in range(ROWS):
		y = (TOP - r) * PX - PX / 2
		row = ""
		for c in range(8):
			x, n = c * PX + PX / 2, 0
			for pg in polys:
				for i in range(len(pg)):
					(x1, y1), (x2, y2) = pg[i], pg[(i + 1) % len(pg)]
					if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
						n += 1
			row += "#" if n % 2 else "."
		rows.append(row)
	return rows


def accented(glyphset, cmap, base, acc):
	rows = bitmap(glyphset, cmap[ord(base)])
	if base.isupper():
		rows = ["........"] * 2 + CAPS[base] + rows[TOP:]
	elif base in "ij":
		rows = ["........"] * 2 + rows[2:]     # without its dot
	rows = list(rows)
	rows[0], rows[1] = ACCENT[acc]
	return rows


def cedilla(glyphset, cmap, base):
	rows = list(bitmap(glyphset, cmap[ord(base)]))
	rows[7] = "...##..."
	return rows


def outline(rows):
	"""The pixels as one merged outline (TrueType glyph)"""
	path = pathops.Path()
	for r, row in enumerate(rows):
		y0 = (TOP - r - 1) * PX
		c = 0
		while c < 8:
			if row[c] != "#":
				c += 1
				continue
			start = c
			while c < 8 and row[c] == "#":
				c += 1
			p = pathops.Path()
			p.moveTo(start * PX, y0)
			p.lineTo(start * PX, y0 + PX)
			p.lineTo(c * PX, y0 + PX)
			p.lineTo(c * PX, y0)
			p.close()
			path = pathops.op(path, p, pathops.PathOp.UNION)
	path.simplify(fix_winding=True)
	pen = TTGlyphPen(None)
	path.draw(pen)
	return pen.glyph()


def main(src, dst, preview=None):
	font = TTFont(src)
	cmap = font.getBestCmap()
	glyphset = font.getGlyphSet()
	new = {}
	for base, accs in LETTERS.items():
		for acc in accs:
			ch = char_for(base, acc)
			if ch:
				new[ch] = accented(glyphset, cmap, base, acc)
	new["ç"] = cedilla(glyphset, cmap, "c")
	new["Ç"] = cedilla(glyphset, cmap, "C")
	new.update(DRAWN)
	for ch, src_ch in FLIP.items():
		# (half a turn, kept on the line and one column to the right)
		body = [("." + r[::-1])[:8] for r in bitmap(glyphset, cmap[ord(src_ch)])[:TOP][::-1]]
		new[ch] = body + ["........"]
	for ch, src_ch in COPY.items():
		new[ch] = bitmap(glyphset, cmap[ord(src_ch)])

	glyf, hmtx = font["glyf"], font["hmtx"]
	added = {}
	for ch, rows in sorted(new.items()):
		if ord(ch) in cmap:
			continue
		gname = "uni%04X" % ord(ch)
		g = outline(rows) if any("#" in r for r in rows) else TTGlyphPen(None).glyph()
		glyf[gname] = g
		g.recalcBounds(glyf)
		hmtx[gname] = (512, getattr(g, "xMin", 0))
		added[ord(ch)] = gname
	# (the glyf table keeps the glyph order: setting a glyph added its name)
	order = glyf.glyphOrder
	font.setGlyphOrder(order)
	for t in font["cmap"].tables:
		if t.isUnicode():
			t.cmap.update(added)
	if "post" in font and font["post"].formatType == 2.0:
		font["post"].extraNames = []
		font["post"].mapping = {}
	font["maxp"].numGlyphs = len(order)
	for rec in font["name"].names:
		if rec.nameID == 5:
			rec.string = "Version 1.02 (accented letters added for the Orthoverse)"
	font.save(dst)
	print("added %d characters" % len(added))

	if preview:
		from PIL import Image, ImageDraw, ImageFont
		text = ["Death at the Château: Céleste Vermeil, Émile Cendre,",
			"Geneviève Ivoire, Lucien Émeraude, Gaston Safran, « Où est-il ? »",
			"àâäæçéèêëîïôœùûüÿ ÀÂÄÆÇÉÈÊËÎÏÔŒÙÛÜŸ",
			"åÅöÖäÄ ñÑ ßøØ ¡¿ €12° 3×4 l’été “x” – ok"]
		f = ImageFont.truetype(dst, 32)
		im = Image.new("RGB", (1500, 60 * len(text) + 20), (20, 26, 51))
		d = ImageDraw.Draw(im)
		for i, line in enumerate(text):
			d.text((16, 16 + 60 * i), line, font=f, fill=(240, 200, 80))
		im.save(preview)


if __name__ == "__main__":
	main(*sys.argv[1:])
