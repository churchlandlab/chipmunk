"""Integration tests using real third-party libraries.

Unlike test_data.py — which mocks database access — these
tests import the actual installed versions of dash, plotly, pandas, and numpy.
They catch runtime breakage that mocked tests miss: removed trace types,
renamed kwargs, changed function signatures, and so on.

Only ``labdata`` and ``chipmunk`` are mocked (database access requires VPN).

Three layers:
  A. API surface  — verify every class, function, and kwarg the app uses exists.
  B. App creation — create_app() builds a real Dash layout with real components.
  C. Data processing — session_metrics / multisession_metrics run end-to-end
                       with real pandas/numpy and synthetic DataFrames.
"""

import importlib
import math
import os
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from dash import Dash, Input, Output, State, dcc, html

from dashboard.fixture_data import (
    make_multisession_metrics,
    make_session_metrics,
)

# ---------------------------------------------------------------------------
# Module import helpers
# ---------------------------------------------------------------------------


def _fake_db_modules():
    """Return sys.modules patches for labdata and chipmunk (DB-only deps)."""
    fake_labdata = types.ModuleType("labdata")
    fake_labdata.__path__ = []
    fake_schema = types.ModuleType("labdata.schema")

    class _DecisionTask:
        class TrialSet:
            pass

    class _Watering:
        pass

    fake_schema.DecisionTask = _DecisionTask
    fake_schema.Watering = _Watering
    fake_labdata.schema = fake_schema

    fake_chipmunk = types.ModuleType("chipmunk")

    class _Chipmunk:
        class Trial:
            pass

        class TrialParameters:
            pass

    fake_chipmunk.Chipmunk = _Chipmunk

    return {
        "labdata": fake_labdata,
        "labdata.schema": fake_schema,
        "chipmunk": fake_chipmunk,
    }


def _import_data_with_real_libs():
    """Import dashboard.data with real pandas/numpy; only DB deps mocked."""
    sys.modules.pop("dashboard.data", None)
    with mock.patch.dict(sys.modules, _fake_db_modules()):
        module = importlib.import_module("dashboard.data")
    return module


def _import_app_with_real_libs():
    """Import dashboard.app with real dash/plotly/numpy; only DB deps mocked."""
    sys.modules.pop("dashboard.app", None)

    fake_data = types.ModuleType("dashboard.data")
    fake_data.get_all_subjects = mock.Mock(return_value=["subject-a"])
    fake_data.get_subjects_with_recent_sessions = mock.Mock(return_value=set())
    fake_data.get_sessions = mock.Mock(return_value=["20260101_010101"])
    fake_data.get_subjects_for_date = mock.Mock(return_value=[])
    fake_data.session_metrics = mock.Mock(return_value=None)
    fake_data.multisession_metrics = mock.Mock(return_value=None)

    patches = {**_fake_db_modules(), "dashboard.data": fake_data}
    with mock.patch.dict(sys.modules, patches):
        module = importlib.import_module("dashboard.app")
    return module


class _FakeDash:
    """Minimal Dash stub that captures callbacks by function name."""

    def __init__(self, *args, **kwargs):
        self.layout = None
        self.callbacks: dict = {}

    def callback(self, *cb_args, **cb_kwargs):
        def _deco(func):
            self.callbacks[func.__name__] = func
            return func

        return _deco


def _import_app_fake_dash_real_plotly():
    """Import app.py with fake Dash (callback access) + real plotly/numpy."""
    sys.modules.pop("dashboard.app", None)

    fake_dash_mod = types.ModuleType("dash")
    fake_dash_mod.Dash = _FakeDash
    fake_dash_mod.dcc = dcc
    fake_dash_mod.html = html
    fake_dash_mod.Input = Input
    fake_dash_mod.Output = Output
    fake_dash_mod.State = State
    fake_dash_mod.ctx = types.SimpleNamespace(triggered_id=None)

    fake_data = types.ModuleType("dashboard.data")
    fake_data.get_all_subjects = mock.Mock(return_value=["subject-a", "subject-b"])
    fake_data.get_subjects_with_recent_sessions = mock.Mock(return_value=set())
    fake_data.get_sessions = mock.Mock(return_value=["20260101_010101"])
    fake_data.get_subjects_for_date = mock.Mock(return_value=[])
    fake_data.session_metrics = mock.Mock(return_value=None)
    fake_data.multisession_metrics = mock.Mock(return_value=None)

    patches = {
        **_fake_db_modules(),
        "dash": fake_dash_mod,
        "dashboard.data": fake_data,
    }
    with mock.patch.dict(sys.modules, patches):
        module = importlib.import_module("dashboard.app")
    return module


def _walk_components(node):
    if node is None:
        return
    yield node
    children = getattr(node, "children", None)
    if children is None:
        return
    if isinstance(children, (list, tuple)):
        for child in children:
            yield from _walk_components(child)
        return
    yield from _walk_components(children)


def _find_component_by_id(root, component_id: str):
    for node in _walk_components(root):
        if getattr(node, "id", None) == component_id:
            return node
    return None


# ---------------------------------------------------------------------------
# Synthetic data fixtures
# ---------------------------------------------------------------------------


def _make_trial_dataframe() -> pd.DataFrame:
    """Realistic trial DataFrame matching the columns expected by session_metrics."""
    n = 100
    rng = np.random.default_rng(42)
    t_stim = rng.uniform(1.0, 2.0, n)
    return pd.DataFrame(
        {
            "trial_num": list(range(1, n + 1)),
            "rewarded_modality": ["audio"] * n,
            "stim_rate_audio": rng.uniform(5.0, 15.0, n).tolist(),
            "stim_rate_vision": rng.uniform(5.0, 15.0, n).tolist(),
            "category_boundary": [10.0] * n,
            "t_start": rng.uniform(0.0, 0.5, n).tolist(),
            "t_stim": t_stim.tolist(),
            "t_gocue": (t_stim + rng.uniform(0.5, 1.5, n)).tolist(),
            "t_react": (t_stim + rng.uniform(0.5, 2.0, n)).tolist(),
            "t_response": (t_stim + rng.uniform(0.6, 2.1, n)).tolist(),
            "response": rng.choice([0, 1, -1], n).tolist(),
            "rewarded": rng.choice([0, 1], n, p=[0.3, 0.7]).tolist(),
            "punished": rng.choice([0, 1], n, p=[0.7, 0.3]).tolist(),
            "early_withdrawal": rng.choice([0, 1], n, p=[0.9, 0.1]).tolist(),
            "with_choice": rng.choice([0, 1], n, p=[0.2, 0.8]).tolist(),
        }
    )


def _make_subject_dataframe() -> pd.DataFrame:
    """Realistic subject DataFrame matching the columns expected by multisession_metrics."""
    n = 10
    rng = np.random.default_rng(42)
    session_names = [f"202601{i:02d}_120000" for i in range(1, n + 1)]
    return pd.DataFrame(
        {
            "session_name": session_names,
            "performance_easy": rng.uniform(0.5, 0.9, n).tolist(),
            "n_with_choice": rng.integers(50, 120, n).tolist(),
            "response_values": [rng.choice([-1, 0, 1], 80).tolist() for _ in range(n)],
            "initiation_times": [rng.uniform(0.3, 2.0, 80).tolist() for _ in range(n)],
            "reaction_times": [rng.uniform(0.1, 0.5, 50).tolist() for _ in range(n)],
        }
    )


# Layer B: App creation smoke test with real libraries
# ---------------------------------------------------------------------------


class TestAppCreationWithRealLibs(unittest.TestCase):
    def setUp(self):
        self.addCleanup(lambda: sys.modules.pop("dashboard.app", None))
        self.appmod = _import_app_with_real_libs()

    def test_create_app_returns_real_dash_instance(self):
        app = self.appmod.create_app()
        self.assertIsInstance(app, Dash)

    def test_create_app_sets_non_null_layout(self):
        app = self.appmod.create_app()
        self.assertIsNotNone(app.layout)

    def test_create_app_includes_single_session_tabs(self):
        app = self.appmod.create_app()
        tabs = _find_component_by_id(app.layout, "single-session-tabs")
        self.assertIsNotNone(tabs)
        self.assertEqual(tabs.value, "single-overview")
        self.assertEqual(len(tabs.children), 2)
        labels = [child.label for child in tabs.children]
        values = [child.value for child in tabs.children]
        self.assertEqual(labels, ["Overview", "Timing"])
        self.assertEqual(values, ["single-overview", "single-timing"])

    def test_create_app_includes_overview_summary_boxes(self):
        app = self.appmod.create_app()
        self.assertIsNotNone(_find_component_by_id(app.layout, "sidebar-collapsed"))
        self.assertIsNotNone(_find_component_by_id(app.layout, "sidebar-toggle-button"))
        self.assertIsNotNone(_find_component_by_id(app.layout, "session-settings-box"))
        self.assertIsNotNone(
            _find_component_by_id(app.layout, "session-settings-toggle")
        )
        self.assertIsNotNone(_find_component_by_id(app.layout, "water-cumulative"))
        self.assertIsNotNone(_find_component_by_id(app.layout, "training-time"))

    def test_create_app_ui_debug_uses_fixture_data(self):
        sys.modules.pop("dashboard.app", None)

        try:
            with mock.patch.dict(os.environ, {"CHIPMUNK_UI_DEBUG": "1"}):
                appmod = importlib.import_module("dashboard.app")
                app = appmod.create_app()
        finally:
            sys.modules.pop("dashboard.app", None)

        self.assertIsInstance(app, Dash)
        self.assertEqual(
            appmod.get_all_subjects.__module__, "dashboard.debug_data"
        )

    def test_create_app_places_iti_row_after_response_time_row(self):
        app = self.appmod.create_app()
        tabs = _find_component_by_id(app.layout, "single-session-tabs")
        self.assertIsNotNone(tabs)
        timing_tab = next(
            child for child in tabs.children if child.value == "single-timing"
        )
        rows = list(timing_tab.children.children)
        row_ids = []
        for row in rows:
            children = (
                row.children
                if isinstance(row.children, (list, tuple))
                else [row.children]
            )
            row_ids.append(tuple(getattr(child, "id", None) for child in children))

        response_row = ("response-time-line", "response-time")
        iti_row = ("iti-rolling", "iti-dist")
        self.assertIn(response_row, row_ids)
        self.assertIn(iti_row, row_ids)
        self.assertLess(row_ids.index(response_row), row_ids.index(iti_row))

    def test_empty_fig_returns_real_plotly_figure(self):
        fig = self.appmod._empty_fig("No data")
        self.assertIsInstance(fig, go.Figure)
        self.assertFalse(fig.layout.xaxis.visible)
        self.assertFalse(fig.layout.yaxis.visible)
        self.assertEqual(fig.layout.annotations[0].text, "No data")

    def test_layout_helper_applies_title_to_real_figure(self):
        fig = go.Figure()
        self.appmod._layout(fig, title="Test Title", xaxis_title="x")
        self.assertEqual(fig.layout.title.text, "Test Title")


# ---------------------------------------------------------------------------
# Layer C: Data processing with real pandas/numpy
# ---------------------------------------------------------------------------


class TestSessionMetricsWithRealLibs(unittest.TestCase):
    def setUp(self):
        self.addCleanup(lambda: sys.modules.pop("dashboard.data", None))
        self.data = _import_data_with_real_libs()
        self.data.session_metrics.cache_clear()

    def test_session_metrics_returns_all_expected_keys(self):
        trials = _make_trial_dataframe()
        with (
            mock.patch.object(self.data, "get_session_trials", return_value=trials),
            mock.patch.object(
                self.data, "get_subject_water", return_value={"20260101_010101": 1.5}
            ),
        ):
            result = self.data.session_metrics("subject-a", "20260101_010101")

        self.assertIsNotNone(result)
        expected_keys = {
            "stims",
            "n_correct",
            "n_incorrect",
            "n_ew",
            "n_no_choice",
            "p_right",
            "median_rt",
            "rts",
            "rt_trial_nums",
            "rt_vals",
            "rt_roll_x",
            "rt_roll_y",
            "response_trial_nums",
            "response_trial_nums_left",
            "response_trial_nums_right",
            "response_roll_x",
            "response_roll_y",
            "response_roll_left_x",
            "response_roll_left_y",
            "response_roll_right_x",
            "response_roll_right_y",
            "response_times",
            "response_times_left",
            "response_times_right",
            "session_settings_lines",
            "water_side_totals_ul",
            "water_cum_x",
            "water_cum_time_x",
            "water_cum_total_ul",
            "water_cum_left_ul",
            "water_cum_right_ul",
            "iti_times",
            "trial_count_x",
            "trial_count_trial_nums",
            "trial_count_y",
            "init_times",
            "init_trial_nums",
            "init_roll_x",
            "init_roll_y",
            "wait_times",
            "wait_min_times",
            "wait_delta_times",
            "wait_delta_left_times",
            "wait_delta_right_times",
            "wait_trial_nums",
            "wait_trial_nums_left",
            "wait_trial_nums_right",
            "wait_delta_x",
            "wait_delta_y",
            "wait_delta_left_x",
            "wait_delta_left_y",
            "wait_delta_right_x",
            "wait_delta_right_y",
            "wait_roll_x",
            "wait_roll_y",
            "wait_times_left",
            "wait_times_right",
            "wait_left_x",
            "wait_left_y",
            "wait_right_x",
            "wait_right_y",
            "slide_x",
            "slide_y",
            "ew_roll_x",
            "ew_roll_y",
            "iti_times_after_correct",
            "iti_times_after_incorrect",
            "iti_times_after_ew",
            "iti_times_after_no_choice",
            "iti_roll_x",
            "iti_roll_y",
            "iti_roll_correct_x",
            "iti_roll_correct_y",
            "iti_roll_incorrect_x",
            "iti_roll_incorrect_y",
            "iti_roll_ew_x",
            "iti_roll_ew_y",
            "iti_roll_no_choice_x",
            "iti_roll_no_choice_y",
        }
        self.assertEqual(set(result.keys()), expected_keys)

    def test_session_metrics_all_values_are_plain_lists(self):
        trials = _make_trial_dataframe()
        with (
            mock.patch.object(self.data, "get_session_trials", return_value=trials),
            mock.patch.object(
                self.data, "get_subject_water", return_value={"20260101_010101": 1.5}
            ),
        ):
            result = self.data.session_metrics("subject-a", "20260101_010101")

        self.assertIsNotNone(result)
        for key, val in result.items():
            self.assertIsInstance(
                val, list, f"key '{key}' should be a list, got {type(val)}"
            )

    def test_session_metrics_returns_none_for_empty_trials(self):
        with mock.patch.object(
            self.data, "get_session_trials", return_value=pd.DataFrame()
        ):
            result = self.data.session_metrics("subject-a", "20260101_010101")
        self.assertIsNone(result)

    def test_session_metrics_iti_incorrect_falls_back_to_unrewarded_choices(self):
        trials = _make_trial_dataframe().head(6).copy()
        trials["trial_num"] = [1, 2, 3, 4, 5, 6]
        trials["t_start"] = [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]
        trials["t_stim"] = [0.5, 2.5, 4.5, 6.5, 8.5, 10.5]
        trials["t_gocue"] = [1.0, 3.0, 5.0, 7.0, 9.0, 11.0]
        trials["t_react"] = [1.2, 3.2, 5.2, 7.2, 9.2, 11.2]
        trials["t_response"] = [1.5, 3.5, 5.5, 7.5, 9.5, 11.5]
        trials["response"] = [1, 1, -1, -1, 1, 1]
        trials["with_choice"] = [1, 1, 1, 1, 1, 1]
        # Trial 1 is incorrect even though punished=0, which is a valid data shape.
        trials["rewarded"] = [0, 1, 1, 1, 1, 1]
        trials["punished"] = [0, 0, 0, 0, 0, 0]
        trials["early_withdrawal"] = [0, 0, 0, 0, 0, 0]

        with (
            mock.patch.object(self.data, "get_session_trials", return_value=trials),
            mock.patch.object(self.data, "get_subject_water", return_value={}),
        ):
            result = self.data.session_metrics("subject-a", "20260101_010101")

        self.assertIsNotNone(result)
        self.assertEqual(result["iti_times_after_incorrect"], [2.0])
        self.assertEqual(result["iti_roll_incorrect_x"], [1])
        self.assertEqual(result["iti_roll_incorrect_y"], [2.0])

    def test_session_metrics_incorrect_count_uses_with_choice_and_rewarded(self):
        trials = _make_trial_dataframe().head(6).copy()
        trials["trial_num"] = [1, 2, 3, 4, 5, 6]
        trials["stim_rate_audio"] = [10.0] * 6
        trials["stim_rate_vision"] = [10.0] * 6
        trials["rewarded"] = [1, 0, 0, 0, 1, 0]
        trials["with_choice"] = [1, 1, 1, 0, 0, 1]
        trials["early_withdrawal"] = [0, 0, 1, 1, 0, 0]
        # punished is intentionally unused for incorrect classification.
        trials["punished"] = [0, 0, 0, 0, 0, 0]

        with (
            mock.patch.object(self.data, "get_session_trials", return_value=trials),
            mock.patch.object(self.data, "get_subject_water", return_value={}),
        ):
            result = self.data.session_metrics("subject-a", "20260101_010101")

        self.assertIsNotNone(result)
        self.assertEqual(result["n_correct"], [2])
        self.assertEqual(result["n_incorrect"], [3])
        self.assertEqual(result["n_ew"], [1])
        self.assertEqual(result["n_no_choice"], [0])

    def test_session_metrics_lists_all_presented_stim_rates(self):
        rates = [4.0, 8.0, 10.0, 14.0, 16.0, 20.0]
        trials = _make_trial_dataframe().copy()
        n = len(trials)
        trials["stim_rate_audio"] = [rates[i % len(rates)] for i in range(n)]
        trials["stim_rate_vision"] = [rates[i % len(rates)] for i in range(n)]

        with (
            mock.patch.object(self.data, "get_session_trials", return_value=trials),
            mock.patch.object(self.data, "get_subject_water", return_value={}),
        ):
            result = self.data.session_metrics("subject-a", "20260101_010101")

        self.assertIsNotNone(result)
        expected = "audio stim: 4, 8, 10, 14, 16, 20"
        self.assertIn(expected, result["session_settings_lines"])
        self.assertNotIn(
            "audio stim: 4.00 to 20.00",
            result["session_settings_lines"],
        )


class TestMultisessionMetricsWithRealLibs(unittest.TestCase):
    def setUp(self):
        self.addCleanup(lambda: sys.modules.pop("dashboard.data", None))
        self.data = _import_data_with_real_libs()
        self.data.multisession_metrics.cache_clear()
        self.data.get_subject_data.cache_clear()

    def _patched(self, df):
        return (
            mock.patch.object(self.data, "get_subject_data", return_value=df),
            mock.patch.object(
                self.data, "get_wait_medians_for_sessions", return_value={}
            ),
            mock.patch.object(self.data, "get_subject_water", return_value={}),
        )

    def test_multisession_metrics_returns_all_expected_keys(self):
        df = _make_subject_dataframe()
        with self._patched(df)[0], self._patched(df)[1], self._patched(df)[2]:
            result = self.data.multisession_metrics("subject-a", sessions_back=5)

        self.assertIsNotNone(result)
        expected_keys = {
            "x",
            "session_dates",
            "training_time_hours",
            "perf_easy",
            "ew_rate",
            "n_with_choice",
            "side_bias",
            "median_init",
            "median_rt",
            "median_wait",
            "water",
        }
        self.assertEqual(set(result.keys()), expected_keys)

    def test_multisession_metrics_smoothed_has_same_length_as_unsmoothed(self):
        df = _make_subject_dataframe()
        patches = self._patched(df)
        with patches[0], patches[1], patches[2]:
            raw = self.data.multisession_metrics(
                "subject-a", sessions_back=5, smooth=False, smooth_window=3
            )
        self.data.multisession_metrics.cache_clear()
        patches = self._patched(df)
        with patches[0], patches[1], patches[2]:
            smoothed = self.data.multisession_metrics(
                "subject-a", sessions_back=5, smooth=True, smooth_window=3
            )

        self.assertEqual(len(raw["x"]), len(smoothed["x"]))
        self.assertEqual(len(raw["perf_easy"]), len(smoothed["perf_easy"]))

    def test_multisession_metrics_returns_none_for_empty_subject_data(self):
        with mock.patch.object(
            self.data, "get_subject_data", return_value=pd.DataFrame()
        ):
            result = self.data.multisession_metrics("subject-a", sessions_back=5)
        self.assertIsNone(result)

    def test_multisession_metrics_returns_nan_training_time_when_session_name_lacks_time(
        self,
    ):
        df = pd.DataFrame(
            {
                "session_name": ["20260105", "bad-session"],
                "performance_easy": [0.6, 0.7],
                "n_with_choice": [60, 65],
                "response_values": [[-1, 1], [-1, 1]],
                "initiation_times": [[0.5, 0.6], [0.7, 0.8]],
                "reaction_times": [[0.2, 0.3], [0.4, 0.5]],
            }
        )
        with self._patched(df)[0], self._patched(df)[1], self._patched(df)[2]:
            result = self.data.multisession_metrics("subject-a", sessions_back=10)

        self.assertIsNotNone(result)
        self.assertTrue(math.isnan(result["training_time_hours"][0]))
        self.assertTrue(math.isnan(result["training_time_hours"][1]))


# ---------------------------------------------------------------------------
# Layer D: Callback bodies with real plotly figures
# ---------------------------------------------------------------------------


class TestCallbacksWithRealPlotly(unittest.TestCase):
    """Run _update_single and _update_multi with real plotly and synthetic data.

    Uses _FakeDash so callbacks are accessible via app.callbacks[name], while
    plotly.graph_objects and numpy are the real installed libraries.  Only the
    data layer is mocked.
    """

    def setUp(self):
        self.addCleanup(lambda: sys.modules.pop("dashboard.app", None))
        self.appmod = _import_app_fake_dash_real_plotly()

    def test_update_single_single_subject_returns_sixteen_figures(self):
        app = self.appmod.create_app()
        update_single = app.callbacks["_update_single"]
        sm = make_session_metrics()
        with (
            mock.patch.object(
                self.appmod, "get_sessions", return_value=["20260101_010101"]
            ),
            mock.patch.object(self.appmod, "session_metrics", return_value=sm),
        ):
            figures = update_single(["subject-a"], [], "20260101_010101", 0, None)

        self.assertEqual(len(figures), 16)
        for fig in figures:
            self.assertIsInstance(fig, go.Figure)
        # Single-subject outcome chart: 4 vertical bar traces (one per outcome type)
        self.assertEqual(len(figures[0].data), 4)
        # P(right) and chronometric charts have one trace each
        self.assertEqual(len(figures[1].data), 1)
        self.assertEqual(len(figures[2].data), 1)
        # Wait-floor plot includes aggregate + split traces with aggregate visible by default.
        self.assertGreaterEqual(len(figures[8].data), 2)
        # Timing scatter panels apply robust default y-axis clipping.
        self.assertIsNotNone(figures[4].layout.yaxis.range)
        self.assertIsNotNone(figures[6].layout.yaxis.range)
        self.assertIsNotNone(figures[8].layout.yaxis.range)
        # Initiation / wait-floor dist panels use density histograms.
        self.assertIsInstance(figures[5].data[0], go.Histogram)
        self.assertGreaterEqual(len(figures[9].data), 1)
        self.assertIsInstance(figures[9].data[0], go.Histogram)
        # Response-time rolling plot (index 10): raw + rolling (+ split hidden traces)
        self.assertGreaterEqual(len(figures[10].data), 3)
        self.assertIsInstance(figures[10].data[0], go.Scattergl)
        self.assertEqual(figures[10].layout.updatemenus[0].buttons[0].label, "Choice")
        self.assertEqual(figures[10].layout.updatemenus[0].active, -1)
        # Response-time dist (index 11): combined histogram + split hidden traces
        self.assertGreaterEqual(len(figures[11].data), 3)
        self.assertIsInstance(figures[11].data[0], go.Histogram)
        self.assertEqual(figures[11].layout.updatemenus[0].buttons[0].label, "Choice")
        self.assertEqual(figures[6].layout.updatemenus[0].buttons[0].label, "Choice")
        self.assertEqual(figures[8].layout.updatemenus[0].buttons[0].label, "Choice")
        self.assertEqual(figures[12].layout.updatemenus[0].buttons[0].label, "Outcome")
        # ITI dist panel (index 12) includes aggregate + split traces.
        self.assertGreaterEqual(len(figures[12].data), 1)
        self.assertIsInstance(figures[12].data[0], go.Histogram)
        # Trial-count-time (index 13) is a rolling scatter in single-subject mode
        self.assertEqual(len(figures[13].data), 2)
        self.assertIsInstance(figures[13].data[0], go.Scatter)
        self.assertIsInstance(figures[13].data[1], go.Scatter)
        self.assertEqual(figures[13].layout.xaxis.title.text, "elapsed time (min)")
        self.assertEqual(list(figures[13].data[0].x), sm["trial_count_x"])
        self.assertEqual(
            list(figures[13].data[0].customdata), sm["trial_count_trial_nums"]
        )
        self.assertEqual(list(figures[13].data[1].x), sm["water_cum_time_x"])
        self.assertEqual(figures[13].data[1].visible, False)
        self.assertEqual(figures[13].layout.updatemenus[0].buttons[0].label, "Water")
        # Water cumulative plot (index 14) has line traces + side toggle
        self.assertGreaterEqual(len(figures[14].data), 1)
        self.assertIsInstance(figures[14].data[0], go.Scatter)
        self.assertEqual(figures[14].layout.updatemenus[0].buttons[0].label, "Side")
        # ITI rolling trend (index 15) includes aggregate + split traces.
        self.assertGreaterEqual(len(figures[15].data), 1)
        self.assertIsInstance(figures[15].data[0], go.Scatter)
        self.assertEqual(figures[15].layout.updatemenus[0].buttons[0].label, "Outcome")

    def test_update_single_multi_subject_uses_box_and_horizontal_bars(self):
        app = self.appmod.create_app()
        update_single = app.callbacks["_update_single"]
        sm = make_session_metrics()
        with (
            mock.patch.object(
                self.appmod, "get_sessions", return_value=["20260101_010101"]
            ),
            mock.patch.object(self.appmod, "session_metrics", return_value=sm),
        ):
            figures = update_single(
                ["subject-a"], ["subject-b"], "20260101_010101", 0, "2026-01-01"
            )

        self.assertEqual(len(figures), 16)
        for fig in figures:
            self.assertIsInstance(fig, go.Figure)
        # Multi-col outcome chart: 4 horizontal bar traces
        self.assertEqual(len(figures[0].data), 4)
        self.assertIsInstance(figures[0].data[0], go.Bar)
        self.assertEqual(figures[0].data[0].orientation, "h")
        # Initiation dist uses Box in multi mode
        self.assertIsInstance(figures[5].data[0], go.Box)
        # Wait floor includes aggregate + split traces in multi-subject mode.
        self.assertGreaterEqual(len(figures[8].data), 4)
        # Wait-floor dist (index 9) uses Box in multi mode
        self.assertIsInstance(figures[9].data[0], go.Box)
        # Response-time rolling (index 10) uses scatter markers/lines in multi mode
        self.assertIsInstance(figures[10].data[0], go.Scattergl)
        # Response-time dist (index 11) uses per-subject box plots in multi mode
        self.assertIsInstance(figures[11].data[0], go.Box)
        # ITI dist (index 12) uses Box in multi mode
        self.assertIsInstance(figures[12].data[0], go.Box)
        # Trial-count-time (index 13) uses scatter in multi mode
        self.assertIsInstance(figures[13].data[0], go.Scatter)
        # Water cumulative (index 14) uses scatter in multi mode
        self.assertIsInstance(figures[14].data[0], go.Scatter)
        # ITI rolling trend (index 15) uses scatter lines in multi mode
        self.assertIsInstance(figures[15].data[0], go.Scatter)

    def test_update_overview_boxes_renders_subject_summaries(self):
        app = self.appmod.create_app()
        update_overview_boxes = app.callbacks["_update_overview_boxes"]
        sm = make_session_metrics()
        with (
            mock.patch.object(
                self.appmod, "get_sessions", return_value=["20260101_010101"]
            ),
            mock.patch.object(self.appmod, "session_metrics", return_value=sm),
        ):
            settings = update_overview_boxes(
                ["subject-a"], [], "20260101_010101", 0, None
            )

        self.assertIn("subject-a (20260101_010101)", settings)
        self.assertIn("rewarded modality", settings)
        self.assertIn("water (µL):", settings)

    def test_update_multi_with_data_returns_eight_figures(self):
        app = self.appmod.create_app()
        update_multi = app.callbacks["_update_multi"]
        ms = make_multisession_metrics()
        with mock.patch.object(self.appmod, "multisession_metrics", return_value=ms):
            figures = update_multi(["subject-a"], [], 10, "2026-01-10", [], 3, 0)

        self.assertEqual(len(figures), 9)
        for fig in figures:
            self.assertIsInstance(fig, go.Figure)
        # Performance figure should have one Scatter trace
        self.assertEqual(len(figures[0].data), 1)
        self.assertIsInstance(figures[0].data[0], go.Scatter)

    def test_update_multi_hover_shows_session_date(self):
        app = self.appmod.create_app()
        update_multi = app.callbacks["_update_multi"]
        ms = make_multisession_metrics()
        with mock.patch.object(self.appmod, "multisession_metrics", return_value=ms):
            figures = update_multi(["subject-a"], [], 10, "2026-01-10", [], 3, 0)

        perf_trace = figures[0].data[0]
        self.assertEqual(list(perf_trace.customdata), ms["session_dates"])
        self.assertIn("session date: %{customdata}", perf_trace.hovertemplate)
        self.assertEqual(list(perf_trace.x), ms["x"])
        self.assertEqual(figures[0].layout.xaxis.type, "date")
        self.assertEqual(figures[0].layout.xaxis.title.text, "session datetime")

    def test_update_multi_smooth_enabled_still_returns_eight_figures(self):
        app = self.appmod.create_app()
        update_multi = app.callbacks["_update_multi"]
        ms = make_multisession_metrics()
        with mock.patch.object(self.appmod, "multisession_metrics", return_value=ms):
            figures = update_multi(
                ["subject-a"], [], 10, "2026-01-10", ["smooth"], 5, 0
            )

        self.assertEqual(len(figures), 9)
        for fig in figures:
            self.assertIsInstance(fig, go.Figure)

    def test_update_single_recent_and_older_subjects_are_merged(self):
        """Subjects from both checklists are combined and processed together."""
        app = self.appmod.create_app()
        update_single = app.callbacks["_update_single"]
        sm = make_session_metrics()
        with (
            mock.patch.object(
                self.appmod, "get_sessions", return_value=["20260101_010101"]
            ),
            mock.patch.object(self.appmod, "session_metrics", return_value=sm),
        ):
            figures = update_single(
                ["subject-a"], ["subject-b"], "20260101_010101", 0, "2026-01-01"
            )

        self.assertEqual(len(figures), 16)

    def test_update_multi_recent_and_older_subjects_are_merged(self):
        """Subjects from both checklists are combined and processed together."""
        app = self.appmod.create_app()
        update_multi = app.callbacks["_update_multi"]
        ms = make_multisession_metrics()
        with mock.patch.object(self.appmod, "multisession_metrics", return_value=ms):
            figures = update_multi(["subject-a"], ["subject-b"], 10, None, [], 3, 0)

        self.assertEqual(len(figures), 9)

    def test_update_date_options_caps_future_dates_at_today(self):
        app = self.appmod.create_app()
        update_date_options = app.callbacks["_update_date_options"]

        class _FakeDate:
            @staticmethod
            def today():
                from datetime import date

                return date(2026, 1, 10)

        with (
            mock.patch.object(self.appmod, "_date", _FakeDate),
            mock.patch.object(
                self.appmod,
                "get_sessions",
                return_value=["20260105_010101", "20260114_120000"],
            ),
        ):
            result = update_date_options([], ["subject-a"], 0, 0)

        self.assertEqual(
            result, ("2026-01-10", "2026-01-05", "2026-01-10", "2026-01-10")
        )

    def test_update_single_skips_subjects_with_falsy_session_name(self):
        """Line 590: `if not ses: continue` — session name resolves to empty string."""
        app = self.appmod.create_app()
        update_single = app.callbacks["_update_single"]
        # get_sessions returns [""] — non-empty list so subject is "valid", but
        # ses = "" which is falsy → the loop body is skipped via continue.
        with mock.patch.object(self.appmod, "get_sessions", return_value=[""]):
            figures = update_single(["subject-a"], [], None, 0, None)
        self.assertEqual(len(figures), 16)
        for fig in figures:
            self.assertIsInstance(fig, go.Figure)

    def test_update_single_skips_subject_when_session_metrics_none(self):
        """Line 593: `if not sm: continue` — session_metrics returns None."""
        app = self.appmod.create_app()
        update_single = app.callbacks["_update_single"]
        with (
            mock.patch.object(
                self.appmod, "get_sessions", return_value=["20260101_010101"]
            ),
            mock.patch.object(self.appmod, "session_metrics", return_value=None),
        ):
            figures = update_single(["subject-a"], [], "20260101_010101", 0, None)
        self.assertEqual(len(figures), 16)

    def test_update_multi_skips_subject_when_multisession_metrics_none(self):
        """Line 1128: `if not ms: continue` — multisession_metrics returns None."""
        app = self.appmod.create_app()
        update_multi = app.callbacks["_update_multi"]
        with mock.patch.object(self.appmod, "multisession_metrics", return_value=None):
            figures = update_multi(["subject-a"], [], 10, "2026-01-10", [], 3, 0)
        self.assertEqual(len(figures), 9)

    def test_update_multi_training_time_plot_uses_clock_axis(self):
        app = self.appmod.create_app()
        update_multi = app.callbacks["_update_multi"]
        ms = make_multisession_metrics()
        with mock.patch.object(self.appmod, "multisession_metrics", return_value=ms):
            figures = update_multi(["subject-a"], [], 10, "2026-01-10", [], 3, 0)

        training_trace = figures[8].data[0]
        self.assertEqual(training_trace.type, "scatter")
        self.assertEqual(list(training_trace.x), ms["x"])
        self.assertEqual(list(training_trace.y), ms["training_time_hours"])
        self.assertEqual(figures[8].layout.title.text, "Training Time")
        self.assertEqual(figures[8].layout.yaxis.ticktext[3], "09:00")
        self.assertEqual(list(figures[8].layout.yaxis.range), [24, 0])

    def test_toggle_sidebar_callback_updates_class_name(self):
        app = self.appmod.create_app()
        toggle_sidebar = app.callbacks["_toggle_sidebar"]
        collapsed, class_name, icon, *_rest = toggle_sidebar(1, False)
        self.assertTrue(collapsed)
        self.assertEqual(class_name, "dashboard-root dashboard-root--sidebar-collapsed")
        self.assertEqual(icon, "➡️")
        collapsed, class_name, icon, *_rest = toggle_sidebar(2, True)
        self.assertFalse(collapsed)
        self.assertEqual(class_name, "dashboard-root")

    def test_update_time_options_filters_and_defaults_to_latest(self):
        app = self.appmod.create_app()
        update_time_options = app.callbacks["_update_time_options"]
        self.assertEqual(update_time_options(None, [], ["subject-a"]), ([], None))
        with mock.patch.object(
            self.appmod,
            "get_sessions",
            return_value=[
                "20260102_010101",
                "20260102_120000",
                "20260103_000000",
                "20260102_BAD",
            ],
        ):
            options, value = update_time_options("2026-01-02", [], ["subject-a"])
        self.assertEqual(len(options), 3)
        self.assertEqual(options[-1]["value"], "20260102_BAD")
        self.assertEqual(value, "20260102_BAD")

    def test_clear_subjects_callback_returns_empty_lists(self):
        app = self.appmod.create_app()
        self.assertEqual(app.callbacks["_clear_subjects"](1), ([], []))

    def test_update_single_and_multi_return_empty_figures_without_subjects(self):
        app = self.appmod.create_app()
        with mock.patch.object(self.appmod, "get_sessions", return_value=[]):
            singles = app.callbacks["_update_single"](["subject-a"], [], None, 0, None)
        self.assertEqual(len(singles), 16)
        multis = app.callbacks["_update_multi"]([], [], 10, None, [], 3, 0)
        self.assertEqual(len(multis), 9)


# ---------------------------------------------------------------------------
# Layer E: data.py non-empty code paths
# ---------------------------------------------------------------------------


class _QueryChain:
    """Chainable fake for DataJoint table expressions used in data.py queries.

    Supports ``Table * Table.Part * Table.Params & restriction`` chaining and
    a ``.fetch()`` call that returns the rows passed at construction time.
    Attribute access (for nested table names like ``Chipmunk.Trial``) returns
    ``self`` so the full expression evaluates to a single ``_QueryChain``.
    """

    def __init__(self, rows):
        self._rows = rows

    def __mul__(self, other):
        return self

    def __rmul__(self, other):
        return self

    def __and__(self, _):
        return self

    def fetch(self, *args, **kwargs):
        if kwargs.get("as_dict"):
            return self._rows
        return self._rows

    def __getattr__(self, name):
        return self


class TestDataNonEmptyPaths(unittest.TestCase):
    """Cover data.py branches that are only reached with non-empty DB results."""

    def setUp(self):
        self.addCleanup(lambda: sys.modules.pop("dashboard.data", None))
        self.data = _import_data_with_real_libs()
        self.data.get_trials_for_sessions.cache_clear()
        self.data.get_wait_medians_for_sessions.cache_clear()
        self.data.multisession_metrics.cache_clear()
        self.data.get_subject_data.cache_clear()

    # -- get_trials_for_sessions (lines 257-280) ------------------------------

    def test_get_trials_for_sessions_non_empty_returns_grouped_dict(self):
        rows = [
            {"session_name": "20260101", "trial_num": 1, "x": 10},
            {"session_name": "20260101", "trial_num": 2, "x": 20},
            {"session_name": "20260102", "trial_num": 1, "x": 30},
        ]
        with mock.patch.object(self.data, "Chipmunk", _QueryChain(rows)):
            result = self.data.get_trials_for_sessions(
                "subject-a", ("20260101", "20260102")
            )

        self.assertEqual(set(result.keys()), {"20260101", "20260102"})
        self.assertEqual(len(result["20260101"]), 2)
        self.assertEqual(len(result["20260102"]), 1)

    def test_get_trials_for_sessions_empty_db_result_returns_empty_dict(self):
        with mock.patch.object(self.data, "Chipmunk", _QueryChain([])):
            result = self.data.get_trials_for_sessions("subject-a", ("20260101",))

        self.assertEqual(result, {})

    # -- get_wait_medians_for_sessions (lines 305-334) ------------------------

    def test_get_wait_medians_for_sessions_non_empty_returns_float_per_session(self):
        rows = [
            {"session_name": "20260101", "t_react": 1.5, "t_stim": 1.0},
            {"session_name": "20260101", "t_react": 2.0, "t_stim": 1.2},
            {"session_name": "20260102", "t_react": 1.8, "t_stim": 1.3},
        ]
        with mock.patch.object(self.data, "Chipmunk", _QueryChain(rows)):
            result = self.data.get_wait_medians_for_sessions(
                "subject-a", ("20260101", "20260102")
            )

        self.assertIn("20260101", result)
        self.assertIn("20260102", result)
        self.assertIsInstance(result["20260101"], float)
        self.assertAlmostEqual(result["20260101"], 0.65)

    def test_get_wait_medians_for_sessions_empty_rows_returns_empty_dict(self):
        """Line 314: `if not rows: return {}` — DB query returns no rows."""
        with mock.patch.object(self.data, "Chipmunk", _QueryChain([])):
            result = self.data.get_wait_medians_for_sessions("subject-a", ("20260101",))
        self.assertEqual(result, {})

    def test_get_wait_medians_for_sessions_all_invalid_wait_returns_empty(self):
        # wait = t_react - t_stim; all negative -> mask filters everything out
        rows = [
            {"session_name": "20260101", "t_react": 0.5, "t_stim": 1.5},
        ]
        with mock.patch.object(self.data, "Chipmunk", _QueryChain(rows)):
            result = self.data.get_wait_medians_for_sessions("subject-a", ("20260101",))

        self.assertEqual(result, {})

    # -- multisession_metrics: start_date branch (lines 684-686) --------------

    def test_multisession_metrics_with_start_date_filters_to_that_date(self):
        # Sessions span Jan 1-10; start_date=Jan 5 should keep only Jan 1-5.
        df = _make_subject_dataframe()
        with (
            mock.patch.object(self.data, "get_subject_data", return_value=df),
            mock.patch.object(
                self.data, "get_wait_medians_for_sessions", return_value={}
            ),
            mock.patch.object(self.data, "get_subject_water", return_value={}),
        ):
            result = self.data.multisession_metrics(
                "subject-a", sessions_back=10, start_date="2026-01-05"
            )

        self.assertIsNotNone(result)
        # Only Jan 1-5 pass the <= filter; sessions_back=10 keeps all 5.
        self.assertEqual(len(result["x"]), 5)

    def test_multisession_metrics_keeps_same_day_sessions_distinct_on_x_axis(self):
        df = pd.DataFrame(
            {
                "session_name": [
                    "20260105_090000",
                    "20260105_150000",
                    "20260106_120000",
                ],
                "performance_easy": [0.6, 0.7, 0.8],
                "n_with_choice": [60, 65, 70],
                "response_values": [[-1, 1]] * 3,
                "initiation_times": [[0.5, 0.6]] * 3,
                "reaction_times": [[0.2, 0.3]] * 3,
            }
        )
        with (
            mock.patch.object(self.data, "get_subject_data", return_value=df),
            mock.patch.object(
                self.data, "get_wait_medians_for_sessions", return_value={}
            ),
            mock.patch.object(self.data, "get_subject_water", return_value={}),
        ):
            result = self.data.multisession_metrics("subject-a", sessions_back=10)

        self.assertIsNotNone(result)
        self.assertEqual(
            result["x"],
            [
                "2026-01-05 09:00:00",
                "2026-01-05 15:00:00",
                "2026-01-06 12:00:00",
            ],
        )
        self.assertEqual(
            result["session_dates"],
            [
                "2026-01-05 09:00:00",
                "2026-01-05 15:00:00",
                "2026-01-06 12:00:00",
            ],
        )

    # -- multisession_metrics: side_bias no-choice path (line 730) ------------

    def test_multisession_metrics_side_bias_is_nan_when_no_choices(self):
        df = _make_subject_dataframe().copy()
        # All response values are 0 → not in [-1, 1] → n_choice = 0 → nan bias
        df["response_values"] = [[0, 0, 0, 0]] * len(df)
        with (
            mock.patch.object(self.data, "get_subject_data", return_value=df),
            mock.patch.object(
                self.data, "get_wait_medians_for_sessions", return_value={}
            ),
            mock.patch.object(self.data, "get_subject_water", return_value={}),
        ):
            result = self.data.multisession_metrics("subject-a", sessions_back=5)

        self.assertIsNotNone(result)
        for v in result["side_bias"]:
            self.assertTrue(math.isnan(v), f"expected NaN but got {v}")

    # -- multisession_metrics: None reaction_times path (lines 741-742) -------

    def test_multisession_metrics_median_rt_is_nan_when_reaction_times_is_none(self):
        df = _make_subject_dataframe().copy()
        df["reaction_times"] = [None] * len(df)
        with (
            mock.patch.object(self.data, "get_subject_data", return_value=df),
            mock.patch.object(
                self.data, "get_wait_medians_for_sessions", return_value={}
            ),
            mock.patch.object(self.data, "get_subject_water", return_value={}),
        ):
            result = self.data.multisession_metrics("subject-a", sessions_back=5)

        self.assertIsNotNone(result)
        for v in result["median_rt"]:
            self.assertTrue(math.isnan(v), f"expected NaN but got {v}")
