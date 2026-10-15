"""The single reproducible release-content entry point (no performance run)."""
import argparse
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"game/content"))
from content_pipeline import ContentError, ROOT, publish

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="validate exact checked-in release bytes without writing")
parser.add_argument("--output", type=Path, default=ROOT/"content/core")
arguments = parser.parse_args()
try:
    print(json.dumps(publish(arguments.output, arguments.check), ensure_ascii=False))
except (ContentError, OSError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
