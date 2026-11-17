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
        "from dashboard.streamlit_page import render_dashboard\nrender_dashboard()\n"
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


def test_history_shows_outcome_rates_and_wait_endpoints_per_modality(monkeypatch):
    from dashboard import app as dashboard_app
    from dashboard.fixture_data import make_multisession_metrics

    metrics = make_multisession_metrics(n=3)
    monkeypatch.setattr(
        dashboard_app, "get_subject_modalities", lambda subject: ["audio", "visual"]
    )
    monkeypatch.setattr(
        dashboard_app, "multisession_metrics", lambda *args, **kwargs: metrics
    )
    renderer = dashboard_app.create_app().chipmunk_renderers["multi"]
    figures = dict(
        zip(
            dashboard_app.MULTI_FIGURE_IDS,
            renderer(["mouse-a"], [], 3, None, [], 3, 0),
            strict=True,
        )
    )
    outcomes = figures["ew-rate"]
    assert len(outcomes.data) == 10
    assert outcomes.layout.legend.visible
    assert {t.name for t in outcomes.data} >= {"not initiated", "EW before stimulus"}
    assert sum(t.showlegend for t in outcomes.data) == 5
    assert "mouse-a audio" in outcomes.data[0].hovertemplate
    assert "mouse-a visual" in outcomes.data[5].hovertemplate
    waits = figures["median-wait"]
    assert len(waits.data) == 6
    assert waits.layout.legend.visible
    assert list(waits.data[0].y) == metrics["required_wait_start"]
    assert list(waits.data[1].y) == metrics["required_wait_end"]
    assert len(figures["water"].data) == 1
    assert figures["water"].layout.title.text == "Recorded Water"


def test_settings_context_and_unknown_water_are_visible(monkeypatch):
    import math

    from dashboard import app as dashboard_app
    from dashboard.fixture_data import make_session_metrics

    metrics = make_session_metrics()
    metrics["water_side_totals_ul"] = [2.0, math.nan, math.nan]
    metrics["recorded_water_ul"] = 8.0
    monkeypatch.setattr(
        dashboard_app, "get_sessions", lambda subject: ["20260101_120000"]
    )
    monkeypatch.setattr(dashboard_app, "session_metrics", lambda *args: metrics)
    renderers = dashboard_app.create_app().chipmunk_renderers
    settings = renderers["settings"](["mouse-a"], [], None, 0, None)
    assert "estimated reward (µL): total unknown | L 2.0 | R unknown" in settings
    assert "recorded Watering total (µL): 8.0" in settings
    figures = dict(
        zip(
            dashboard_app.SINGLE_FIGURE_IDS,
            renderers["single"](["mouse-a"], [], None, 0, None),
            strict=True,
        )
    )
    performance = figures["session-perf"]
    assert list(performance.data[0].text) == metrics["performance_settings"]
    changes = next(t for t in performance.data if "settings changed" in t.name)
    assert list(changes.x) == metrics["settings_change_trials"]
    assert list(changes.text) == metrics["settings_change_text"]
    assert (
        figures["water-cumulative"].layout.title.text == "Estimated Rewarded Water (µL)"
    )
