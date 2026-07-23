from importlib.util import find_spec

from .pluginschema import Chipmunk, chipmunkschema
from .utils import (
    chipmunk_insert_decision_task,
    load_chipmunk_trialdata,
    process_chipmunk_file,
)


if find_spec("chipmunk_dashboard") is not None:
    dashboard_name = "**Chipmunk**"


    def dashboard_function(schema=None):
        """Render the Chipmunk page in the labdata Streamlit dashboard."""
        from chipmunk_dashboard.streamlit_page import render_dashboard

        return render_dashboard(schema=schema)
