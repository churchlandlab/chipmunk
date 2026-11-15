import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "labdata_plugin"))
os.environ.setdefault("CHIPMUNK_UI_DEBUG", "1")  # fixture data, no database
