from __future__ import annotations

import sys


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)
