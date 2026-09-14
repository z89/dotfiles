#!/usr/bin/env python3
"""Compatibility runner for the shared desktop guard test suite."""
from pathlib import Path
import sys
import unittest

if __name__ == "__main__":
    release = (Path.home() / ".local/lib/desktop-guard/current").resolve(strict=True)
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(release))
    suite = unittest.defaultTestLoader.discover(str(release), pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
