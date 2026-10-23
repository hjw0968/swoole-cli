#!/usr/bin/env python3
"""Fix two legacy K&R function definitions in xlswriter 1.5.8 on Apple Clang."""

from pathlib import Path
import re

MINIZIP = (
    Path(__file__).resolve().parents[2]
    / "ext/xlswriter/library/libxlsxwriter/third_party/minizip"
)

PATCHES = {
    "ioapi.c": (
        r"void fill_fopen_filefunc\s*\(\s*pzlib_filefunc_def\s*\)\s*\n"
        r"\s*zlib_filefunc_def\s*\*\s*pzlib_filefunc_def\s*;",
        "void fill_fopen_filefunc(zlib_filefunc_def *pzlib_filefunc_def)",
    ),
    "mztools.c": (
        r"extern int ZEXPORT unzRepair\(file,\s*fileOut,\s*fileOutTmp,\s*"
        r"nRecovered,\s*bytesRecovered\)\s*\n"
        r"\s*const char\s*\*\s*file;\s*\n"
        r"\s*const char\s*\*\s*fileOut;\s*\n"
        r"\s*const char\s*\*\s*fileOutTmp;\s*\n"
        r"\s*uLong\s*\*\s*nRecovered;\s*\n"
        r"\s*uLong\s*\*\s*bytesRecovered;",
        "extern int ZEXPORT unzRepair(const char *file, const char *fileOut, "
        "const char *fileOutTmp, uLong *nRecovered, uLong *bytesRecovered)",
    ),
}

for filename, (pattern, replacement) in PATCHES.items():
    path = MINIZIP / filename
    source = path.read_text()
    updated, count = re.subn(pattern, replacement, source, count=1)
    if count != 1:
        raise SystemExit(f"Expected legacy function declaration in {path}")
    path.write_text(updated)
    print(f"Patched {path}")
