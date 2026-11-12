"""The Chipmunk tab renders in Streamlit with fixture data."""
from streamlit.testing.v1 import AppTest

from dashboard.streamlit_page import _available_dates, _session_date


def test_session_dates_are_reverse_chronological():
    sessions = {
        "GRB050": ["20260102_090000", "20260103_090000"],
        "GRB058": ["20260101_120000", "invalid"],
    }

    assert _session_date("20260102_090000") == "2026-01-02"
    assert _session_date("invalid") is None
    assert _available_dates(sessions) == ["2026-01-03", "2026-01-02", "2026-01-01"]


def test_streamlit_dashboard_renders_and_filters_recent_mice(monkeypatch):
    monkeypatch.setenv("CHIPMUNK_UI_DEBUG", "1")
    source = (
        "from dashboard.streamlit_page import render_dashboard\n"
        "render_dashboard()\n"
    )

    app = AppTest.from_string(source).run(timeout=30)

    assert not app.exception
    assert [title.value for title in app.title] == ["Chipmunk Dashboard"]
    assert len(app.get("plotly_chart")) == 25
    assert app.toggle[0].label == "Recent mice only"
    assert app.toggle[0].value is True
    recent_options = app.multiselect[0].options

    app.toggle[0].set_value(False).run(timeout=30)

    assert not app.exception
    assert len(app.multiselect[0].options) > len(recent_options)
    assert len(app.get("plotly_chart")) == 25
