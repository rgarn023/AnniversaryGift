#!/usr/bin/env python3
"""Render anniversary_gift.pdf pages to ~2000px-wide PNGs."""
from pathlib import Path
import sys
try:
    import fitz
except ImportError:
    print("Install PyMuPDF: pip install pymupdf", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
PDF = ROOT / "assets/documents/anniversary_gift.pdf"
OUT = ROOT / "assets/documents/pdf_pages"

def main() -> None:
    if not PDF.exists():
        print(f"Missing {PDF}", file=sys.stderr)
        sys.exit(1)
    OUT.mkdir(parents=True, exist_ok=True)
    doc = fitz.open(PDF)
    for i, page in enumerate(doc):
        scale = 2000.0 / page.rect.width
        pix = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=False)
        out = OUT / f"page_{i+1:03d}.png"
        pix.save(str(out))
        print(f"wrote {out} {pix.width}x{pix.height}")
    doc.close()

if __name__ == "__main__":
    main()
