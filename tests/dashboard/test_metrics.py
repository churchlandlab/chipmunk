"""Metrics the dashboard computes from trials, with the database calls replaced."""
import importlib
import math
import sys
import types

import numpy as np
import pandas as pd
import pytest

from dashboard.fixture_data import make_multisession_metrics, make_session_metrics

SESSION = "20260101_010101"


@pytest.fixture
def data(monkeypatch):
    """dashboard.data imported without labdata or a database."""
    schema = types.SimpleNamespace(DecisionTask=None, Watering=None)
    monkeypatch.setitem(sys.modules, "labdata", types.SimpleNamespace(schema=schema))
    monkeypatch.setitem(sys.modules, "labdata.schema", schema)
    monkeypatch.setitem(sys.modules, "chipmunk", types.SimpleNamespace(Chipmunk=None))
    monkeypatch.delitem(sys.modules, "dashboard.data", raising=False)
    module = importlib.import_module("dashboard.data")
    monkeypatch.setattr(module, "get_subject_water", lambda *a, **k: {})
    monkeypatch.setattr(module, "get_wait_medians_for_sessions", lambda *a, **k: {})
    yield module
    sys.modules.pop("dashboard.data", None)


def trials(n=100, **columns):
    rng = np.random.default_rng(42)
    t_stim = rng.uniform(1.0, 2.0, n)
    frame = pd.DataFrame(
        {
            "trial_num": np.arange(1, n + 1),
            "rewarded_modality": "audio",
            "stim_rate_audio": rng.uniform(5.0, 15.0, n),
            "stim_rate_vision": rng.uniform(5.0, 15.0, n),
            "category_boundary": 10.0,
            "t_start": rng.uniform(0.0, 0.5, n),
            "t_stim": t_stim,
            "t_gocue": t_stim + rng.uniform(0.5, 1.5, n),
            "t_react": t_stim + rng.uniform(0.5, 2.0, n),
            "t_response": t_stim + rng.uniform(0.6, 2.1, n),
            "response": rng.choice([0, 1, -1], n),
            "rewarded": rng.choice([0, 1], n, p=[0.3, 0.7]),
            "punished": rng.choice([0, 1], n, p=[0.7, 0.3]),
            "early_withdrawal": rng.choice([0, 1], n, p=[0.9, 0.1]),
            "with_choice": rng.choice([0, 1], n, p=[0.2, 0.8]),
        }
    )
    for name, values in columns.items():
        frame[name] = values
    return frame


def sessions(names, **columns):
    n = len(names)
    frame = pd.DataFrame(
        {
            "session_name": names,
            "performance_easy": [0.7] * n,
            "n_with_choice": [60] * n,
            "response_values": [[-1, 1]] * n,
            "initiation_times": [[0.5, 0.6]] * n,
            "reaction_times": [[0.2, 0.3]] * n,
        }
    )
    for name, values in columns.items():
        frame[name] = values
    return frame


def session_metrics(data, monkeypatch, frame):
    monkeypatch.setattr(data, "get_session_trials", lambda *a, **k: frame)
    return data.session_metrics("subject-a", SESSION)


def multisession_metrics(data, monkeypatch, frame, **kwargs):
    monkeypatch.setattr(data, "get_subject_data", lambda *a, **k: frame)
    return data.multisession_metrics("subject-a", sessions_back=10, **kwargs)


def test_metrics_have_the_keys_the_fixture_figures_are_built_from(data, monkeypatch):
    # The page test renders fixture metrics, so the real ones must have the same keys.
    assert set(session_metrics(data, monkeypatch, trials())) == set(make_session_metrics())
    real = multisession_metrics(data, monkeypatch, sessions(["20260105_090000"]))
    assert set(real) == set(make_multisession_metrics())


def test_no_trials_gives_no_metrics(data, monkeypatch):
    assert session_metrics(data, monkeypatch, pd.DataFrame()) is None
    assert multisession_metrics(data, monkeypatch, pd.DataFrame()) is None


def test_outcome_counts_use_choice_and_reward_not_punished(data, monkeypatch):
    frame = trials(  # one stimulus rate, so one count per outcome
        6,
        stim_rate_audio=10.0,
        stim_rate_vision=10.0,
        rewarded=[1, 0, 0, 0, 1, 0],
        with_choice=[1, 1, 1, 0, 0, 1],
        early_withdrawal=[0, 0, 1, 1, 0, 0],
        punished=0,
    )
    result = session_metrics(data, monkeypatch, frame)
    counts = [result[k] for k in ("n_correct", "n_incorrect", "n_ew", "n_no_choice")]
    assert counts == [[2], [3], [1], [0]]


def test_iti_after_an_unrewarded_choice_counts_as_after_incorrect(data, monkeypatch):
    start = np.arange(6) * 2.0
    frame = trials(
        6,
        t_start=start,
        t_stim=start + 0.5,
        t_gocue=start + 1.0,
        t_react=start + 1.2,
        t_response=start + 1.5,
        response=[1, 1, -1, -1, 1, 1],
        with_choice=1,
        rewarded=[0, 1, 1, 1, 1, 1],
        punished=0,
        early_withdrawal=0,
    )
    assert session_metrics(data, monkeypatch, frame)["iti_times_after_incorrect"] == [2.0]


def test_settings_list_every_presented_stimulus_rate(data, monkeypatch):
    rates = np.resize([4.0, 8.0, 10.0, 14.0, 16.0, 20.0], 100)
    result = session_metrics(
        data, monkeypatch, trials(stim_rate_audio=rates, stim_rate_vision=rates)
    )
    assert "audio stim: 4, 8, 10, 14, 16, 20" in result["session_settings_lines"]


def test_two_sessions_on_one_day_stay_separate(data, monkeypatch):
    names = ["20260105_090000", "20260105_150000", "20260106_120000"]
    result = multisession_metrics(data, monkeypatch, sessions(names))
    assert result["x"] == [
        "2026-01-05 09:00:00",
        "2026-01-05 15:00:00",
        "2026-01-06 12:00:00",
    ]


def test_start_date_keeps_sessions_up_to_that_day(data, monkeypatch):
    names = [f"202601{day:02d}_120000" for day in range(1, 11)]
    result = multisession_metrics(
        data, monkeypatch, sessions(names), start_date="2026-01-05"
    )
    assert len(result["x"]) == 5


def test_side_bias_is_nan_without_choices(data, monkeypatch):
    frame = sessions(["20260105_090000"], response_values=[[0, 0, 0]])
    result = multisession_metrics(data, monkeypatch, frame)
    assert math.isnan(result["side_bias"][0])
