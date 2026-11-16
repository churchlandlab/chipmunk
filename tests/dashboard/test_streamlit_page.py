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


def test_wait_figures_show_saved_progression_and_rare_negative_delta(monkeypatch):
    from dashboard import app as dashboard_app
    from dashboard.fixture_data import make_session_metrics

    metrics = make_session_metrics()
    metrics["wait_delta_times"] = [-0.7] + [0.2] * 99
    metrics["required_wait_times"] = [0.1] * 99 + [1.5]
    monkeypatch.setattr(
        dashboard_app, "get_sessions", lambda subject: ["20260101_120000"]
    )
    monkeypatch.setattr(dashboard_app, "session_metrics", lambda *args: metrics)
    renderer = dashboard_app.create_app().chipmunk_renderers["single"]

    for subjects in [["mouse-a"], ["mouse-a", "mouse-b"]]:
        figures = dict(
            zip(
                dashboard_app.SINGLE_FIGURE_IDS,
                renderer(subjects, [], "20260101_120000", 0, None),
                strict=True,
            )
        )
        delta = figures["wait-delta-line"]
        assert delta.layout.title.text == "Actual − Required Wait"
        assert delta.data[0].y[0] == -0.7
        assert delta.layout.yaxis.range[0] <= -0.7
        required = figures["wait-floor-line"]
        assert required.layout.title.text == "Required Wait"
        assert list(required.data[0].x) == list(range(1, 101))
        assert required.data[0].y[0] == 0.1
        assert required.data[0].y[-1] == 1.5
        assert required.data[0].line.shape == "hv"
        assert required.layout.yaxis.range[1] >= 1.5
        assert (
            not required.layout.updatemenus
        )  # Requirements do not depend on the choice.
        assert figures["wait-floor-hist"].layout.title.text == "Required Wait Dist"
