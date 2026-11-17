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
    schema = types.SimpleNamespace(DecisionTask=None, Watering=None, Weighing=None)
    monkeypatch.setitem(sys.modules, "labdata", types.SimpleNamespace(schema=schema))
    monkeypatch.setitem(sys.modules, "labdata.schema", schema)
    monkeypatch.setitem(sys.modules, "chipmunk", types.SimpleNamespace(Chipmunk=None))
    monkeypatch.delitem(sys.modules, "dashboard.data", raising=False)
    module = importlib.import_module("dashboard.data")
    monkeypatch.setattr(module, "get_subject_water", lambda *a, **k: {})
    monkeypatch.setattr(
        module,
        "get_subject_weights",
        lambda *a, **k: pd.DataFrame(columns=["weighing_datetime", "weight"]),
    )
    monkeypatch.setattr(module, "get_trials_for_sessions", lambda *a, **k: {})
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
            "t_earlywithdraw": np.nan,
            "initiated": 1,
            "t_initiate": np.nan,
            "configured_reward_volume": 2.0,
            "required_wait_time": 0.8,
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
            "trialset_description": ["visual"] * n,
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
    assert set(session_metrics(data, monkeypatch, trials())) == set(
        make_session_metrics()
    )
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
    assert session_metrics(data, monkeypatch, frame)["iti_times_after_incorrect"] == [
        2.0
    ]


def test_settings_list_every_presented_stimulus_rate(data, monkeypatch):
    rates = np.resize([4.0, 8.0, 10.0, 14.0, 16.0, 20.0], 100)
    result = session_metrics(
        data, monkeypatch, trials(stim_rate_audio=rates, stim_rate_vision=rates)
    )
    assert "audio stim: 4, 8, 10, 14, 16, 20" in [
        line.strip() for line in result["session_settings_lines"]
    ]


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


def test_modalities_stay_separate_and_sessions_back_counts_sessions(data, monkeypatch):
    names = ["20260105_090000", "20260105_090000", "20260106_120000", "20260107_120000"]
    frame = sessions(names, trialset_description=["visual", "audio", "visual", "audio"])
    monkeypatch.setattr(data, "get_subject_data", lambda *a, **k: frame)

    assert data.get_subject_modalities("subject-a") == ["audio", "visual"]
    visual = data.multisession_metrics("subject-a", sessions_back=2, modality="visual")
    audio = data.multisession_metrics("subject-a", sessions_back=2, modality="audio")

    assert visual["x"] == ["2026-01-06 12:00:00"]
    assert audio["x"] == ["2026-01-07 12:00:00"]
    per_session = data.multisession_metrics("subject-a", sessions_back=3)
    assert len(per_session["water"]) == 3


def test_wait_delta_uses_saved_requirement_and_keeps_early_withdrawals(
    data, monkeypatch
):
    frame = trials(
        5,
        t_stim=[1.0, 11.0, 21.0, 31.0, np.nan],
        t_react=[2.2, np.nan, 21.8, 32.0, np.nan],
        t_earlywithdraw=[np.nan, 11.3, np.nan, np.nan, 40.2],
        # A missing go cue must not remove an otherwise measured withdrawal.
        t_gocue=np.nan,
        required_wait_time=[0.8, 0.8, 0.8, None, 0.8],
        early_withdrawal=[0, 1, 0, 0, 1],
        response=[1, 0, -1, 1, 0],
    )
    result = session_metrics(data, monkeypatch, frame)
    assert result["wait_trial_nums"] == [1, 2, 3]
    np.testing.assert_allclose(result["wait_delta_times"], [0.4, -0.5, 0.0], atol=1e-12)
    np.testing.assert_allclose(result["wait_delta_right_times"], [0.4])
    np.testing.assert_allclose(result["wait_delta_left_times"], [0.0], atol=1e-12)
    assert result["required_wait_trial_nums"] == [1, 2, 3, 5]
    assert result["required_wait_times"] == [0.8] * 4


def test_required_wait_preserves_progression_without_completed_trials(
    data, monkeypatch
):
    result = session_metrics(
        data,
        monkeypatch,
        trials(
            4,
            required_wait_time=[0.0, 0.4, None, 1.2],
            t_stim=np.nan,
            t_react=np.nan,
        ),
    )
    assert result["required_wait_trial_nums"] == [1, 2, 4]
    assert result["required_wait_times"] == [0.0, 0.4, 1.2]
    assert result["wait_delta_times"] == []


@pytest.mark.parametrize("required", [None, np.nan, -1.0, np.inf])
def test_unknown_or_invalid_requirement_is_not_inferred(data, monkeypatch, required):
    result = session_metrics(data, monkeypatch, trials(required_wait_time=required))
    assert result["required_wait_times"] == []
    assert result["wait_delta_times"] == []


def test_legacy_rows_without_required_wait_leave_wait_plots_empty(data, monkeypatch):
    result = session_metrics(
        data, monkeypatch, trials().drop(columns="required_wait_time")
    )
    assert result["required_wait_times"] == []
    assert result["wait_delta_times"] == []


def outcome_trials():
    return trials(
        6,
        rewarded=[1, 0, 0, 0, 0, 0],
        with_choice=[1, 1, 0, 0, 0, 0],
        initiated=[1, 1, 1, 1, 0, 1],
        early_withdrawal=[0, 0, 1, 1, 0, 0],
        t_stim=[0.2, 10.2, np.nan, 30.2, np.nan, 50.2],
        t_react=[1.0, 11.0, np.nan, np.nan, np.nan, 51.0],
        response=[1, -1, 0, 0, 0, 0],
    )


def test_outcomes_separate_initiation_early_withdrawal_and_no_choice(data, monkeypatch):
    frame = outcome_trials()
    result = session_metrics(data, monkeypatch, frame)
    assert result["outcome_counts"] == {
        "correct": 1,
        "incorrect": 1,
        "ew_pre": 1,
        "ew_stim": 1,
        "not_initiated": 1,
        "no_choice": 1,
    }
    summary = data._trial_summary(frame)
    assert summary["ew_rate"] == 2 / 6
    assert summary["completion_rate"] == 3 / 6
    assert sum(
        summary[key + "_rate"] for key in result["outcome_counts"]
    ) == pytest.approx(1.0)


def test_water_uses_each_reward_amount_and_keeps_recorded_total_separate(
    data, monkeypatch
):
    monkeypatch.setattr(data, "get_subject_water", lambda *a: {SESSION: 0.5})
    result = session_metrics(
        data,
        monkeypatch,
        trials(
            4,
            rewarded=[1, 1, 0, 1],
            response=[-1, 1, 1, -1],
            configured_reward_volume=[2.0, 4.0, 99.0, 8.0],
        ),
    )
    assert result["water_cum_total_ul"] == [2.0, 6.0, 6.0, 14.0]
    assert result["water_side_totals_ul"] == [10.0, 4.0, 14.0]
    assert result["recorded_water_ul"] == 500.0


@pytest.mark.parametrize("unknown", [None, np.nan, -1.0, np.inf])
def test_unknown_reward_amount_is_not_invented_or_rescaled(data, monkeypatch, unknown):
    monkeypatch.setattr(data, "get_subject_water", lambda *a: {SESSION: 1.0})
    result = session_metrics(
        data,
        monkeypatch,
        trials(
            3,
            rewarded=1,
            response=[-1, 1, -1],
            configured_reward_volume=[0.0, unknown, 2.0],
        ),
    )
    assert result["water_cum_total_ul"][0] == 0.0
    assert all(math.isnan(v) for v in result["water_cum_total_ul"][1:])
    assert result["water_side_totals_ul"][0] == 2.0


def test_settings_are_grouped_complete_and_mark_reversions(data, monkeypatch):
    result = session_metrics(
        data,
        monkeypatch,
        trials(
            4,
            required_wait_time=[0.1, 0.2, 0.3, 0.4],
            pre_stim_delay=0.2,
            incorrect_choice_timeout=2.0,
            early_withdrawal_timeout=1.0,
            anti_bias_tau=10.0,
            anti_bias_strength=[0.0, 0.5, 0.5, 0.0],
            proportion_left=0.5,
            stim_brightness=0.3,
            stim_loudness=0.7,
        ),
    )
    lines = result["session_settings_lines"]
    assert all(group in lines for group in ["Stimulus", "Timing", "Reward and bias"])
    assert "  required wait (s): 0.1 → 0.4; range 0.1–0.4" in lines
    assert any("anti-bias window" in line for line in lines)
    assert result["settings_change_trials"] == [2, 4]
    assert result["settings_change_text"] == [
        "anti-bias strength: 0 → 0.5",
        "anti-bias strength: 0.5 → 0",
    ]


def test_multisession_rates_use_trial_flags_and_keep_modalities_separate(
    data, monkeypatch
):
    name = "20260105_090000"
    frame = outcome_trials()
    frame["rewarded_modality"] = ["audio"] * 3 + ["visual"] * 3
    monkeypatch.setattr(data, "get_trials_for_sessions", lambda *a: {name: frame})
    history = sessions([name, name], trialset_description=["audio", "visual"])
    audio = multisession_metrics(data, monkeypatch, history, modality="audio")
    visual = multisession_metrics(data, monkeypatch, history, modality="visual")
    assert audio["ew_pre_rate"] == [1 / 3]
    assert audio["not_initiated_rate"] == [0.0]
    assert visual["ew_stim_rate"] == [1 / 3]
    assert visual["not_initiated_rate"] == [1 / 3]
    assert visual["no_choice_rate"] == [1 / 3]


def test_smoothing_does_not_change_saved_start_and_end_requirements(data, monkeypatch):
    names = ["20260105_090000", "20260106_090000"]
    frames = {
        names[0]: trials(2, required_wait_time=[0.1, 0.2]),
        names[1]: trials(2, required_wait_time=[0.9, 1.1]),
    }
    monkeypatch.setattr(data, "get_trials_for_sessions", lambda *a: frames)
    result = multisession_metrics(
        data, monkeypatch, sessions(names), smooth=True, smooth_window=2
    )
    assert result["required_wait_start"] == [0.1, 0.9]
    assert result["required_wait_end"] == [0.2, 1.1]


def test_missing_trial_history_has_unknown_outcome_rates(data, monkeypatch):
    result = multisession_metrics(data, monkeypatch, sessions(["20260105_090000"]))
    assert math.isnan(result["ew_rate"][0])
    assert math.isnan(result["required_wait_start"][0])


def test_initiation_timestamp_overrides_missing_legacy_flag(data):
    frame = trials(
        3,
        initiated=0,
        t_initiate=[0.5, np.nan, np.nan],
        t_stim=[np.nan, 1.0, np.nan],
        rewarded=0,
        with_choice=0,
        early_withdrawal=0,
    )
    masks = data._outcome_masks(frame)
    assert masks["not_initiated"].tolist() == [False, False, True]
    assert masks["no_choice"].tolist() == [True, True, False]


def test_weight_history_uses_actual_times_and_selected_dates_without_smoothing(
    data, monkeypatch
):
    names = ["20260105_150000", "20260107_120000"]
    measurements = pd.DataFrame(
        {
            "weighing_datetime": [
                "2026-01-04 22:00:00",
                "2026-01-05 08:00:00",
                "2026-01-05 18:00:00",
                "2026-01-06 08:00:00",
                "2026-01-07 23:59:00",
                "2026-01-08 00:00:00",
            ],
            "weight": [99.0, 22.0, 22.5, 23.0, 24.0, 99.0],
        }
    )
    monkeypatch.setattr(data, "get_subject_weights", lambda *a: measurements)
    result = multisession_metrics(
        data, monkeypatch, sessions(names), smooth=True, smooth_window=3
    )
    assert result["weight_x"] == measurements["weighing_datetime"].tolist()[1:-1]
    assert result["weight_g"] == [22.0, 22.5, 23.0, 24.0]


def test_missing_and_invalid_weights_are_not_filled(data, monkeypatch):
    frame = pd.DataFrame(
        {
            "weighing_datetime": ["2026-01-05 08:00:00"] * 5,
            "weight": [None, np.nan, -1.0, 0.0, np.inf],
        }
    )
    monkeypatch.setattr(data, "get_subject_weights", lambda *a: frame)
    result = multisession_metrics(data, monkeypatch, sessions(["20260105_150000"]))
    assert result["weight_x"] == []
    assert result["weight_g"] == []
