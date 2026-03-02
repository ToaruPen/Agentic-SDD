from __future__ import annotations

import sys
from pathlib import Path


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def read_text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")
