"""Package the 10 Hyderabad catalog food photographs into app asset derivatives.

Reads raw source JPEGs from ``--source-dir`` (defaulting to the generated
brain asset directory) and generates cropped/optimized derivatives for
``food``, ``categories``, and ``restaurants`` matching ``tool/refine_assets.py``.
Existing baseline photo keys are guarded against accidental overwrites.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from PIL import Image, ImageOps

DEFAULT_SOURCE_DIR = Path(
    r"C:\Users\Raghu Ram\.gemini\antigravity\brain\48cb54d9-fb22-4f4f-9fc8-f8ed01ee6d44"
)
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "images"

# Existing baseline asset keys that must never be overwritten.
PROTECTED_KEYS = frozenset(
    {
        "biryani",
        "dosa",
        "idli",
        "paneer",
        "pizza",
        "pasta",
        "burger",
        "salad",
    }
)

SOURCE_FILES: dict[str, str] = {
    "chicken-biryani": "chicken_biryani_1794416567326.jpg",
    "mutton-biryani": "mutton_biryani_raw_1794416565347.jpg",
    "haleem": "hyderabadi_haleem_1794416571856.jpg",
    "kebab": "kebab_raw_1794416572334.jpg",
    "noodles": "noodles_raw_1794416575398.jpg",
    "meals": "meals_raw_1794416595758.jpg",
    "chaat": "samosa_chaat_1794416596248.jpg",
    "bakery": "bakery_raw_1794416597697.jpg",
    "chai": "hyderabadi_irani_chai_1794416601587.jpg",
    "dessert": "dessert_raw_1794416603285.jpg",
}

CENTERING = (0.5, 0.55)

# Matches tool/refine_assets.py derivative dimensions and JPEG qualities.
DERIVATIVE_SPECS: tuple[tuple[str, tuple[int, int], int], ...] = (
    ("food", (1400, 1400), 88),
    ("categories", (800, 800), 85),
    ("restaurants", (1800, 1100), 86),
)


def validate_inputs(source_dir: Path) -> dict[str, Path]:
    """Ensure no protected key is targeted and all source files exist."""
    overlap = PROTECTED_KEYS.intersection(SOURCE_FILES)
    if overlap:
        raise ValueError(f"Refusing to overwrite protected keys: {sorted(overlap)}")

    if not source_dir.is_dir():
        raise FileNotFoundError(f"Source directory not found: {source_dir}")

    resolved: dict[str, Path] = {}
    missing: list[str] = []
    for key, filename in SOURCE_FILES.items():
        src_path = source_dir / filename
        if not src_path.is_file():
            missing.append(str(src_path))
        else:
            resolved[key] = src_path

    if missing:
        raise FileNotFoundError(
            "Missing required source image(s):\n  " + "\n  ".join(missing)
        )
    return resolved


def write_derivatives(
    key: str,
    source_path: Path,
    output_dir: Path,
) -> list[tuple[Path, int, tuple[int, int]]]:
    """Generate and validate all 3 JPEG derivatives for a single imageKey."""
    if key in PROTECTED_KEYS:
        raise ValueError(f"Protected key cannot be overwritten: {key}")

    written: list[tuple[Path, int, tuple[int, int]]] = []
    with Image.open(source_path) as raw_img:
        rgb_img = ImageOps.exif_transpose(raw_img).convert("RGB")
        for folder, size, quality in DERIVATIVE_SPECS:
            target_dir = output_dir / folder
            target_dir.mkdir(parents=True, exist_ok=True)
            out_path = target_dir / f"{key}.jpg"

            fitted = ImageOps.fit(rgb_img, size, centering=CENTERING)
            fitted.save(out_path, format="JPEG", quality=quality, optimize=True)

            byte_size = out_path.stat().st_size
            if byte_size <= 0:
                raise RuntimeError(f"Generated empty file: {out_path}")

            with Image.open(out_path) as check_img:
                check_img.verify()
            with Image.open(out_path) as check_img:
                if check_img.format != "JPEG" or check_img.size != size:
                    raise RuntimeError(
                        f"Unexpected derivative metadata for {out_path}: "
                        f"format={check_img.format}, size={check_img.size}"
                    )

            written.append((out_path, byte_size, size))
    return written


def package_assets(source_dir: Path, output_dir: Path) -> list[tuple[Path, int, tuple[int, int]]]:
    """Package all 10 Hyderabad assets into 30 validated JPEG derivatives."""
    resolved = validate_inputs(source_dir)
    all_written: list[tuple[Path, int, tuple[int, int]]] = []
    for key, src_path in resolved.items():
        all_written.extend(write_derivatives(key, src_path, output_dir))
    return all_written


def parse_args() -> argparse.Namespace:
    """Parse command-line options for source and output directories."""
    parser = argparse.ArgumentParser(
        description="Package 10 Hyderabad food images into food/categories/restaurants JPEGs."
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=DEFAULT_SOURCE_DIR,
        help="Directory containing the 10 raw generated JPEG images.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Root assets/images directory to write derivatives into.",
    )
    return parser.parse_args()


def main() -> int:
    """CLI entry point."""
    args = parse_args()
    written = package_assets(args.source_dir, args.output_dir)
    print(f"Packaged {len(written)} JPEG derivatives from {args.source_dir}:")
    for path, byte_size, size in written:
        print(f"  {path} ({size[0]}x{size[1]}, {byte_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
