#!/usr/bin/env python3
"""Render a DOCX file to PNG pages for visual review.

Converts DOCX -> PDF (via LibreOffice `soffice`) -> PNG pages (via `pdf2image`/Poppler).

Usage:
    python3 render_docx.py /path/to/file.docx --output_dir /tmp/docx_pages
"""

import argparse
import os
import subprocess
import sys
import tempfile


def convert_docx_to_pdf(docx_path: str, out_dir: str) -> str:
    profile_dir = tempfile.mkdtemp(prefix="lo_profile_")
    cmd = [
        "soffice",
        f"-env:UserInstallation=file://{profile_dir}",
        "--headless",
        "--convert-to",
        "pdf",
        "--outdir",
        out_dir,
        docx_path,
    ]
    subprocess.run(cmd, check=True)
    base_name = os.path.splitext(os.path.basename(docx_path))[0]
    pdf_path = os.path.join(out_dir, f"{base_name}.pdf")
    if not os.path.exists(pdf_path):
        raise FileNotFoundError(f"Expected PDF not found: {pdf_path}")
    return pdf_path


def convert_pdf_to_pngs(pdf_path: str, out_dir: str) -> list:
    try:
        from pdf2image import convert_from_path
    except ImportError as exc:
        raise ImportError(
            "pdf2image is required. Install with: uv pip install pdf2image "
            "(or python3 -m pip install pdf2image), and ensure Poppler is installed."
        ) from exc

    base_name = os.path.splitext(os.path.basename(pdf_path))[0]
    pages = convert_from_path(pdf_path)
    output_paths = []
    for i, page in enumerate(pages, start=1):
        png_path = os.path.join(out_dir, f"{base_name}-{i}.png")
        page.save(png_path, "PNG")
        output_paths.append(png_path)
    return output_paths


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("docx_path", help="Path to the input .docx file")
    parser.add_argument(
        "--output_dir",
        default=None,
        help="Directory to write the PDF and PNG pages to (default: a temp dir under /tmp)",
    )
    args = parser.parse_args()

    if not os.path.isfile(args.docx_path):
        print(f"Error: file not found: {args.docx_path}", file=sys.stderr)
        return 1

    out_dir = args.output_dir or tempfile.mkdtemp(prefix="docx_pages_")
    os.makedirs(out_dir, exist_ok=True)

    pdf_path = convert_docx_to_pdf(args.docx_path, out_dir)
    png_paths = convert_pdf_to_pngs(pdf_path, out_dir)

    print(f"PDF: {pdf_path}")
    for p in png_paths:
        print(f"Page: {p}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
