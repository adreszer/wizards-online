#!/usr/bin/env python3
"""Generates levels/castle/castle.tscn and the server's area map from
content/castle/program.json. Run from the project root:

    python3 tools/generate_castle.py [--check] [--preview]

The generator lives in tools/castle/ (see docs/castle-generation.md).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from castle.main import main  # noqa: E402

if __name__ == "__main__":
    main()
