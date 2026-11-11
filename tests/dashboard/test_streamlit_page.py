from types import SimpleNamespace

import plotly.graph_objects as go
import pytest
from streamlit.testing.v1 import AppTest

from dashboard.app import (
    MULTI_FIGURE_IDS,
    OVERVIEW_ROWS,
    SINGLE_FIGURE_IDS,
    TIMING_ROWS,
)
from dashboard.streamlit_page import (
    _available_dates,
    _clear_data_caches,
    _data_provider,
    _figure_map,
    _session_date,
    _show_figure_rows,
    _subject_options,
)


def test_session_dates_are_reverse_chronological():
    sessions = {
        "GRB050": ["20260102_090000", "20260103_090000"],
        "GRB058": ["20260101_120000", "invalid"],
    }

    assert _session_date("20260102_090000") == "2026-01-02"
    assert _session_date("invalid") is None
    assert _available_dates(sessions) == ["2026-01-03", "2026-01-02", "2026-01-01"]


def test_data_provider_uses_debug_module(monkeypatch):
    monkeypatch.setenv("CHIPMUNK_UI_DEBUG", "1")

    provider = _data_provider()

    assert provider.__name__ == "dashboard.debug_data"
    assert provider.get_all_subjects()


def test_subject_options_can_show_recent_or_all_mice():
    subjects = ["GRB050", "GRB058", "GRB101"]
    recent = {"GRB058", "GRB101"}

    assert _subject_options(subjects, recent, recent_only=True) == [
        "GRB058",
        "GRB101",
    ]
    assert _subject_options(subjects, recent, recent_only=False) == subjects


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


def test_clear_data_caches():
    cleared = []

    def cached_function():
        return None

    cached_function.cache_clear = lambda: cleared.append("cleared")
    data = SimpleNamespace(
        get_all_subjects=cached_function,
        get_sessions=cached_function,
        session_metrics=cached_function,
    )

    _clear_data_caches(data)

    assert cleared == ["cleared", "cleared", "cleared"]


def test_figure_map_preserves_dash_output_order():
    figures = tuple(go.Figure() for _ in SINGLE_FIGURE_IDS)

    mapped = _figure_map(SINGLE_FIGURE_IDS, figures)

    assert tuple(mapped) == SINGLE_FIGURE_IDS
    assert mapped["frac-correct"] is figures[0]
    with pytest.raises(ValueError, match="Expected 16 figures"):
        _figure_map(SINGLE_FIGURE_IDS, figures[:-1])


def test_streamlit_rows_match_dash_layout():
    assert OVERVIEW_ROWS[0] == (
        "frac-correct",
        "p-right",
        "chrono",
        "session-perf",
    )
    assert sum(len(row) for row in TIMING_ROWS) == 10
    assert len(SINGLE_FIGURE_IDS) == 16
    assert len(MULTI_FIGURE_IDS) == 9


def test_show_figure_rows_uses_unique_keys_and_dash_heights():
    class Column:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return None

    class FakeStreamlit:
        def __init__(self):
            self.keys = []

        def columns(self, count, **_kwargs):
            return [Column() for _ in range(count)]

        def plotly_chart(self, figure, *, key, **_kwargs):
            self.keys.append((key, figure.layout.height))

    st = FakeStreamlit()
    figures = {
        "frac-correct": go.Figure(),
        "session-perf": go.Figure(),
    }

    _show_figure_rows(
        st,
        figures,
        (("frac-correct", "session-perf"),),
        namespace="overview",
    )

    assert st.keys == [
        ("chipmunk-overview-frac-correct", 300),
        ("chipmunk-overview-session-perf", 320),
    ]
