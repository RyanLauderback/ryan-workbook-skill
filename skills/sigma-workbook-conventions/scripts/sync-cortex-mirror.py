#!/usr/bin/env python3
"""Regenerate the .cortex/skills/<name>/ mirror from the canonical skill source.

Cortex Code auto-discovers skills from .cortex/skills/<name>/SKILL.md. Upstream
sigma-agent-skills symlinks that file to the canonical copy; symlinks are a
Windows-checkout footgun (need core.symlinks=true + Developer Mode/admin, else
git checks out a plain text file containing the link target instead of the
real content). This keeps a real, checked-in copy instead -- cheap to
regenerate, safe on every platform.

Run after any edit to skills/<name>/{SKILL.md,reference,examples}, before
committing.
"""
import shutil
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent  # skills/sigma-workbook-conventions/
REPO_ROOT = SKILL_DIR.parent.parent
CORTEX_DIR = REPO_ROOT / ".cortex" / "skills" / SKILL_DIR.name


def main():
    if CORTEX_DIR.exists():
        shutil.rmtree(CORTEX_DIR)
    CORTEX_DIR.mkdir(parents=True)
    shutil.copy2(SKILL_DIR / "SKILL.md", CORTEX_DIR / "SKILL.md")
    for sub in ("reference", "examples"):
        src = SKILL_DIR / sub
        if src.exists():
            shutil.copytree(src, CORTEX_DIR / sub)
    print(f"synced {CORTEX_DIR} from {SKILL_DIR}")


if __name__ == "__main__":
    main()
