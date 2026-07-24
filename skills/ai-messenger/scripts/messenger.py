#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
from pathlib import Path


REPO = Path(os.environ.get("AI_MESSENGER_REPO", r"C:\Repos\ai-messenger")).resolve()
SOURCE = REPO / "src"
if not SOURCE.is_dir():
    raise SystemExit(f"AI Messenger source is missing: {SOURCE}")

sys.path.insert(0, str(SOURCE))

from ai_messenger.cli import main  # noqa: E402


if __name__ == "__main__":
    raise SystemExit(main(list(sys.argv[1:])))
