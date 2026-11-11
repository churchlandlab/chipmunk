import importlib
import sys
import types
import unittest
from unittest import mock


class _ComponentNamespace:
    def __getattr__(self, name):
        def _factory(*args, **kwargs):
            return {"component": name, "args": args, "kwargs": kwargs}

        return _factory


class _IO:
    def __init__(self, *args, **kwargs):
        self.args = args
        self.kwargs = kwargs


class _Layout(dict):
    def __getattr__(self, name):
        try:
            return self[name]
        except KeyError as exc:
            raise AttributeError(name) from exc

    def __setattr__(self, name, value):
        self[name] = value


class _Figure:
    def __init__(self) -> None:
        self.layout = _Layout()
        self.traces = []
        self.hlines = []
        self.vlines = []

    def update_layout(self, **kw) -> None:
        self.layout.update(kw)

    def add_trace(self, trace) -> None:
        self.traces.append(trace)

    def update_yaxes(self, **kw) -> None:
        self.layout.update({f"yaxis_{k}": v for k, v in kw.items()})

    def add_hline(self, **kw) -> None:
        self.hlines.append(kw)

    def add_vline(self, **kw) -> None:
        self.vlines.append(kw)


class _Dash:
    def __init__(self, *args, **kwargs) -> None:
        self.args = args
        self.kwargs = kwargs
        self.layout = None
        self.callbacks = {}

    def callback(self, *cb_args, **cb_kwargs):
        def _decorator(func):
            self.callbacks[func.__name__] = func
            return func

        return _decorator


def _import_app_module():
    sys.modules.pop("dashboard.app", None)

    fake_numpy = types.ModuleType("numpy")
    fake_numpy.ndarray = object
    fake_numpy.median = lambda values: values[0] if values else 0

    fake_dash = types.ModuleType("dash")
    fake_dash.Dash = _Dash
    fake_dash.dcc = _ComponentNamespace()
    fake_dash.html = _ComponentNamespace()
    fake_dash.Input = _IO
    fake_dash.Output = _IO
    fake_dash.State = _IO
    fake_dash.ctx = types.SimpleNamespace(triggered_id=None)

    fake_plotly = types.ModuleType("plotly")
    fake_plotly.__path__ = []
    fake_plotly.colors = importlib.import_module("plotly.colors")
    fake_go = types.ModuleType("plotly.graph_objects")
    fake_go.Figure = _Figure
    fake_go.Scatter = lambda **kwargs: types.SimpleNamespace(type="scatter", **kwargs)
    fake_plotly.graph_objects = fake_go

    fake_data = types.ModuleType("dashboard.data")
    fake_data.get_all_subjects = mock.Mock(return_value=["subject-a", "subject-b"])
    fake_data.get_subjects_with_recent_sessions = mock.Mock(return_value=set())
    fake_data.get_sessions = mock.Mock(return_value=[])
    fake_data.get_subjects_for_date = mock.Mock(return_value=[])
    fake_data.session_metrics = mock.Mock(return_value=None)
    fake_data.multisession_metrics = mock.Mock(return_value=None)
    fake_data.prewarm_multisession_cache = mock.Mock()

    with mock.patch.dict(
        sys.modules,
        {
            "numpy": fake_numpy,
            "dash": fake_dash,
            "plotly": fake_plotly,
            "plotly.graph_objects": fake_go,
            "dashboard.data": fake_data,
        },
    ):
        module = importlib.import_module("dashboard.app")
    return module


def _walk_fake_tree(node):
    if isinstance(node, dict):
        yield node
        for val in node.values():
            yield from _walk_fake_tree(val)
        return
    if isinstance(node, (list, tuple)):
        for item in node:
            yield from _walk_fake_tree(item)


def _find_fake_component(node, component_name: str, component_id: str | None = None):
    for item in _walk_fake_tree(node):
        if item.get("component") != component_name:
            continue
        if component_id is None:
            return item
        if item.get("kwargs", {}).get("id") == component_id:
            return item
    return None


class TestAppUtilities(unittest.TestCase):
    def setUp(self) -> None:
        self.addCleanup(lambda: sys.modules.pop("dashboard.app", None))
        self.appmod = _import_app_module()

    def test_empty_fig_builds_placeholder_annotation(self) -> None:
        fig = self.appmod._empty_fig("No data")
        self.assertEqual(fig.layout["annotations"][0]["text"], "No data")
        self.assertFalse(fig.layout["xaxis"]["visible"])
        self.assertFalse(fig.layout["yaxis"]["visible"])

    def test_layout_wraps_title_and_applies_overrides(self) -> None:
        fig = self.appmod.go.Figure()
        self.appmod._layout(fig, title="Title", xaxis_title="x-axis")
        self.assertEqual(fig.layout["title"]["text"], "Title")
        self.assertEqual(fig.layout["xaxis_title"], "x-axis")
        self.assertEqual(fig.layout["font"]["color"], self.appmod._THEME["text"])

    def test_create_app_includes_sidebar_controls(self) -> None:
        app = self.appmod.create_app()
        sidebar_toggle = _find_fake_component(
            app.layout, "Button", "sidebar-toggle-button"
        )
        self.assertIsNotNone(sidebar_toggle)
        state = _find_fake_component(app.layout, "Store", "sidebar-collapsed")
        self.assertIsNotNone(state)

    def test_toggle_sidebar_callback_updates_class_name(self) -> None:
        app = self.appmod.create_app()
        toggle_sidebar = app.callbacks["_toggle_sidebar"]

        collapsed, class_name, icon, title, aria_label, pressed = toggle_sidebar(
            1, False
        )
        self.assertTrue(collapsed)
        self.assertEqual(class_name, "dashboard-root dashboard-root--sidebar-collapsed")
        self.assertEqual(icon, "➡️")
        self.assertEqual(title, "Show sidebar")
        self.assertEqual(aria_label, "Show sidebar")
        self.assertEqual(pressed, "true")

        collapsed, class_name, icon, title, aria_label, pressed = toggle_sidebar(
            2, True
        )
        self.assertFalse(collapsed)
        self.assertEqual(class_name, "dashboard-root")
        self.assertEqual(icon, "⬅️")
        self.assertEqual(title, "Hide sidebar")
        self.assertEqual(aria_label, "Hide sidebar")
        self.assertEqual(pressed, "false")

    def test_perf_log_skips_when_disabled(self) -> None:
        import dashboard.perf as perf_mod

        with (
            mock.patch.object(perf_mod, "_PROFILE_PERF", False),
            mock.patch.object(perf_mod._LOGGER, "info") as log_info,
        ):
            perf_mod.perf_log("metric", 0.0, key="value")
        log_info.assert_not_called()

    def test_perf_log_emits_when_enabled(self) -> None:
        import dashboard.perf as perf_mod

        with (
            mock.patch.object(perf_mod, "_PROFILE_PERF", True),
            mock.patch("dashboard.perf.time.perf_counter", return_value=2.0),
            mock.patch.object(perf_mod._LOGGER, "info") as log_info,
        ):
            perf_mod.perf_log("metric", 0.0, key="value")
        log_info.assert_called_once()
        msg = log_info.call_args[0][0]
        self.assertIn("perf metric", msg)
        self.assertIn("key=value", msg)

    def test_update_date_options_handles_empty_and_valid_sessions(self) -> None:
        app = self.appmod.create_app()
        update_date_options = app.callbacks["_update_date_options"]

        class _FakeDate:
            @staticmethod
            def today():
                from datetime import date

                return date(2026, 1, 10)

        with mock.patch.object(self.appmod, "_date", _FakeDate):
            self.assertEqual(
                update_date_options([], [], 0, 0),
                (None, None, "2026-01-10", "2026-01-10"),
            )

            with (
                mock.patch.object(
                    self.appmod,
                    "get_sessions",
                    return_value=["20260101_010101", "20260103_010101", "bad"],
                ),
                mock.patch.object(self.appmod, "prewarm_multisession_cache") as prewarm,
            ):
                result = update_date_options([], ["subject-a"], 0, 0)

            self.assertEqual(
                result, ("2026-01-03", "2026-01-01", "2026-01-10", "2026-01-03")
            )
            prewarm.assert_called_once_with(
                ["subject-a"], sessions_back=30, start_date="2026-01-03"
            )

    def test_update_date_options_today_button_returns_todays_date(self) -> None:
        app = self.appmod.create_app()
        update_date_options = app.callbacks["_update_date_options"]

        class _FakeDate:
            @staticmethod
            def today():
                from datetime import date

                return date(2026, 1, 10)

        self.appmod.ctx.triggered_id = "today-button"
        try:
            with mock.patch.object(self.appmod, "_date", _FakeDate):
                date_val, min_d, max_d, month = update_date_options([], [], 0, 1)
        finally:
            self.appmod.ctx.triggered_id = None

        self.assertEqual(date_val, "2026-01-10")
        self.assertIsNone(min_d)
        self.assertEqual(max_d, "2026-01-10")
        self.assertEqual(month, "2026-01-10")

    def test_update_date_options_caps_future_sessions_at_today(self) -> None:
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
            mock.patch.object(self.appmod, "prewarm_multisession_cache") as prewarm,
        ):
            result = update_date_options([], ["subject-a"], 0, 0)

        self.assertEqual(
            result, ("2026-01-10", "2026-01-05", "2026-01-10", "2026-01-10")
        )
        prewarm.assert_called_once_with(
            ["subject-a"], sessions_back=30, start_date="2026-01-10"
        )

    def test_update_time_options_filters_and_defaults_to_latest(self) -> None:
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
        self.assertEqual(options[0]["label"], "01:01:01")
        self.assertEqual(options[1]["label"], "12:00:00")
        self.assertEqual(options[2]["label"], "20260102_BAD")
        self.assertEqual(value, "20260102_BAD")

    def test_clear_subjects_callback_returns_empty_list(self) -> None:
        app = self.appmod.create_app()
        clear_subjects = app.callbacks["_clear_subjects"]
        self.assertEqual(clear_subjects(1), ([], []))

    def test_update_subject_options_prioritizes_recent_subjects(self) -> None:
        app = self.appmod.create_app()
        update_subject_options = app.callbacks["_update_subject_options"]

        with (
            mock.patch.object(
                self.appmod, "get_all_subjects", return_value=["subject-a", "subject-b"]
            ),
            mock.patch.object(
                self.appmod,
                "get_subjects_with_recent_sessions",
                return_value={"subject-b"},
            ),
        ):
            recent_opts, older_opts, divider_style = update_subject_options(None, 1)

        # Recent subject has a styled Span label
        self.assertEqual(len(recent_opts), 1)
        recent_opt = recent_opts[0]
        self.assertEqual(recent_opt["value"], "subject-b")
        self.assertEqual(recent_opt["label"]["args"], ("subject-b",))
        self.assertEqual(recent_opt["label"]["component"], "Span")
        self.assertIn("style", recent_opt["label"]["kwargs"])
        self.assertEqual(
            recent_opt["label"]["kwargs"]["style"]["color"],
            self.appmod._THEME["accent"],
        )
        self.assertEqual(recent_opt["label"]["kwargs"]["style"]["fontWeight"], "bold")
        # Older subject is in a separate list with a plain string label
        self.assertEqual(len(older_opts), 1)
        self.assertEqual(older_opts[0], {"label": "subject-a", "value": "subject-a"})
        # Divider is shown when both groups are non-empty
        self.assertEqual(divider_style.get("display"), "block")

    def test_update_single_returns_empty_figures_when_no_valid_subjects(self) -> None:
        app = self.appmod.create_app()
        update_single = app.callbacks["_update_single"]

        with mock.patch.object(self.appmod, "get_sessions", return_value=[]):
            figures = update_single(["subject-a"], [], None, 0, None)

        self.assertEqual(len(figures), 16)
        self.assertEqual(
            figures[0].layout["annotations"][0]["text"], "Select subject(s)"
        )

    def test_update_single_builds_response_time_figure(self) -> None:
        app = self.appmod.create_app()
        update_single = app.callbacks["_update_single"]

        # Minimal trace factories so fake graph_objects supports callback execution.
        trace_names = ("Bar", "Scatter", "Scattergl", "Box", "Histogram")
        for trace_name in trace_names:
            setattr(
                self.appmod.go,
                trace_name,
                lambda **kw: {"trace": "generic", "kwargs": kw},
            )

        metrics = {
            "stims": [0.0],
            "n_correct": [1],
            "n_incorrect": [0],
            "n_ew": [0],
            "n_no_choice": [0],
            "p_right": [0.5],
            "median_rt": [0.2],
            "slide_x": [],
            "slide_y": [],
            "ew_roll_x": [],
            "ew_roll_y": [],
            "init_trial_nums": [],
            "init_times": [],
            "init_roll_x": [],
            "init_roll_y": [],
            "wait_delta_times": [0.2, 0.3],
            "wait_trial_nums": [1, 2],
            "wait_delta_x": [],
            "wait_delta_y": [],
            "wait_delta_left_times": [0.12, 0.15],
            "wait_delta_right_times": [0.2, 0.24],
            "wait_trial_nums_left": [1, 3],
            "wait_trial_nums_right": [2, 4],
            "wait_delta_left_x": [],
            "wait_delta_left_y": [],
            "wait_delta_right_x": [],
            "wait_delta_right_y": [],
            "wait_times": [0.5, 0.6],
            "wait_roll_x": [],
            "wait_roll_y": [],
            "wait_times_left": [0.5],
            "wait_times_right": [0.6],
            "wait_left_x": [],
            "wait_left_y": [],
            "wait_right_x": [],
            "wait_right_y": [],
            "rts": [],
            "rt_trial_nums": [],
            "rt_vals": [],
            "rt_roll_x": [],
            "rt_roll_y": [],
            "response_trial_nums": [1, 2, 3],
            "response_trial_nums_left": [1, 2],
            "response_trial_nums_right": [3],
            "response_roll_x": [2],
            "response_roll_y": [0.25],
            "response_roll_left_x": [2],
            "response_roll_left_y": [0.23],
            "response_roll_right_x": [3],
            "response_roll_right_y": [0.4],
            "response_times": [0.2, 0.25, 0.4],
            "response_times_left": [0.2, 0.25],
            "response_times_right": [0.4],
            "session_settings_lines": ["trials: 42", "rewarded modality: audio"],
            "water_side_totals_ul": [120.0, 180.0, 300.0],
            "water_cum_x": [1, 2, 3],
            "water_cum_time_x": [0.0, 1.0, 2.0],
            "water_cum_total_ul": [100.0, 200.0, 300.0],
            "water_cum_left_ul": [100.0, 200.0, 200.0],
            "water_cum_right_ul": [0.0, 0.0, 100.0],
            "iti_times": [0.8, 1.1, 1.0],
            "iti_times_after_correct": [0.8],
            "iti_times_after_incorrect": [1.1],
            "iti_times_after_ew": [1.0],
            "iti_times_after_no_choice": [0.9],
            "iti_roll_x": [13, 18],
            "iti_roll_y": [0.95, 1.02],
            "iti_roll_correct_x": [13],
            "iti_roll_correct_y": [0.9],
            "iti_roll_incorrect_x": [18],
            "iti_roll_incorrect_y": [1.1],
            "iti_roll_ew_x": [23],
            "iti_roll_ew_y": [1.0],
            "iti_roll_no_choice_x": [28],
            "iti_roll_no_choice_y": [0.85],
            "trial_count_x": [0.0, 1.0],
            "trial_count_trial_nums": [5, 10],
            "trial_count_y": [6.0, 8.0],
        }

        with (
            mock.patch.object(
                self.appmod, "get_sessions", return_value=["20260101_010101"]
            ),
            mock.patch.object(self.appmod, "session_metrics", return_value=metrics),
        ):
            figures = update_single(["subject-a"], [], "20260101_010101", 0, None)

        self.assertEqual(len(figures), 16)
        self.assertEqual(figures[11].layout["title"]["text"], "Response Time Dist")
        self.assertEqual(len(figures[11].traces), 3)
        self.assertIn("yaxis_range", figures[4].layout)  # init-line
        self.assertIn("yaxis_range", figures[6].layout)  # wait-delta-line
        self.assertIn("yaxis_range", figures[8].layout)  # wait-floor-line
        self.assertIn("yaxis_range", figures[10].layout)  # response-time-line
        self.assertIn("updatemenus", figures[6].layout)  # dwell choice toggle
        self.assertIn("updatemenus", figures[8].layout)  # wait-floor choice toggle
        self.assertIn("updatemenus", figures[10].layout)  # response-line choice toggle
        self.assertIn("updatemenus", figures[11].layout)  # response dist choice toggle
        self.assertEqual(
            figures[11].layout["updatemenus"][0]["buttons"][0]["label"], "Choice"
        )
        self.assertEqual(figures[11].layout["updatemenus"][0]["active"], -1)
        self.assertIn("updatemenus", figures[12].layout)  # iti outcome toggle
        self.assertIn("updatemenus", figures[14].layout)  # water side toggle
        self.assertEqual(
            figures[14].layout["updatemenus"][0]["buttons"][0]["label"], "Side"
        )
        self.assertIn("updatemenus", figures[15].layout)  # iti rolling outcome toggle
        self.assertEqual(
            figures[15].layout["updatemenus"][0]["buttons"][0]["label"], "Outcome"
        )

    def test_update_overview_boxes_formats_session_metadata(self) -> None:
        app = self.appmod.create_app()
        update_overview_boxes = app.callbacks["_update_overview_boxes"]

        with (
            mock.patch.object(
                self.appmod, "get_sessions", return_value=["20260101_010101"]
            ),
            mock.patch.object(
                self.appmod,
                "session_metrics",
                return_value={
                    "session_settings_lines": [
                        "trials: 80",
                        "rewarded modality: audio",
                    ],
                    "water_side_totals_ul": [120.0, 130.0, 250.0],
                },
            ),
        ):
            settings = update_overview_boxes(
                ["subject-a"], [], "20260101_010101", 0, None
            )

        self.assertIn("subject-a (20260101_010101)", settings)
        self.assertIn("rewarded modality: audio", settings)
        self.assertIn("water (µL): total 250.0 | L 120.0 | R 130.0", settings)

    def test_update_overview_boxes_returns_placeholders_without_subjects(self) -> None:
        app = self.appmod.create_app()
        update_overview_boxes = app.callbacks["_update_overview_boxes"]
        settings = update_overview_boxes([], [], None, 0, None)
        self.assertIn("Select subject(s)", settings)

    def test_update_multi_returns_empty_figures_when_no_subjects(self) -> None:
        app = self.appmod.create_app()
        update_multi = app.callbacks["_update_multi"]
        figures = update_multi([], [], 10, None, [], 3, 0)
        self.assertEqual(len(figures), 9)
        self.assertEqual(
            figures[0].layout["annotations"][0]["text"], "Select subject(s)"
        )

    def test_update_multi_renders_training_time_plot(self) -> None:
        app = self.appmod.create_app()
        update_multi = app.callbacks["_update_multi"]
        ms = {
            "x": ["2026-01-01 09:00:00", "2026-01-02 10:30:00"],
            "session_dates": ["2026-01-01 09:00:00", "2026-01-02 10:30:00"],
            "training_time_hours": [9.0, 10.5],
            "perf_easy": [0.6, 0.7],
            "ew_rate": [0.1, 0.2],
            "n_with_choice": [60, 70],
            "side_bias": [0.0, 0.1],
            "median_init": [0.5, 0.6],
            "median_rt": [0.2, 0.3],
            "median_wait": [1.0, 1.2],
            "water": [1.5, 1.7],
        }
        with mock.patch.object(self.appmod, "multisession_metrics", return_value=ms):
            figures = update_multi(["subject-a"], [], 10, "2026-01-10", [], 3, 0)

        self.assertEqual(len(figures), 9)
        self.assertEqual(figures[8].layout["title"]["text"], "Training Time")
        self.assertEqual(figures[8].traces[0].type, "scatter")

    def test_update_date_options_returns_none_when_sessions_empty(self) -> None:
        app = self.appmod.create_app()
        update_date_options = app.callbacks["_update_date_options"]
        with mock.patch.object(self.appmod, "get_sessions", return_value=[]):
            result = update_date_options([], ["subject-a"], 0, 0)
        self.assertEqual(
            result,
            (
                None,
                None,
                self.appmod._date.today().isoformat(),
                self.appmod._date.today().isoformat(),
            ),
        )

    def test_update_date_options_returns_none_when_all_sessions_too_short(self) -> None:
        app = self.appmod.create_app()
        update_date_options = app.callbacks["_update_date_options"]
        with mock.patch.object(self.appmod, "get_sessions", return_value=["short"]):
            result = update_date_options([], ["subject-a"], 0, 0)
        self.assertEqual(
            result,
            (
                None,
                None,
                self.appmod._date.today().isoformat(),
                self.appmod._date.today().isoformat(),
            ),
        )

    def test_update_time_options_returns_empty_when_no_sessions_on_date(self) -> None:
        app = self.appmod.create_app()
        update_time_options = app.callbacks["_update_time_options"]
        with mock.patch.object(
            self.appmod, "get_sessions", return_value=["20260103_010101"]
        ):
            result = update_time_options("2026-01-02", [], ["subject-a"])
        self.assertEqual(result, ([], None))

    def test_update_time_options_handles_session_without_underscore(self) -> None:
        app = self.appmod.create_app()
        update_time_options = app.callbacks["_update_time_options"]
        with mock.patch.object(self.appmod, "get_sessions", return_value=["20260102"]):
            options, value = update_time_options("2026-01-02", [], ["subject-a"])
        self.assertEqual(len(options), 1)
        self.assertEqual(options[0]["label"], "20260102")
        self.assertEqual(value, "20260102")
