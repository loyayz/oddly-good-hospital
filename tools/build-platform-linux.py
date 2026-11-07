#!/usr/bin/env python3
"""Offline Linux native build entry point; use --help."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).resolve().parent / 'linux/build.py'), run_name='__main__')
