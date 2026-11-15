"""Synthetic metrics payloads shared by UI-debug mode and tests."""

from __future__ import annotations

import numpy as np


def make_session_metrics(
    *,
    n: int = 100,
    seed: int = 42,
    session_name: str | None = None,
    settings_lines: list[str] | None = None,
) -> dict:
    """Build a session_metrics dict that exercises every figure-building branch."""
    rng = np.random.default_rng(seed)
    trial_nums = list(range(1, n + 1))
    roll_x = list(range(10, n - 9, 5))
    nroll = len(roll_x)
    iti_roll_x = list(range(13, n - 12, 5))
    n_iti_roll = len(iti_roll_x)
    if settings_lines is None:
        settings_lines = [
            "trials: 100",
            "rewarded modality: audio",
            "audio stim range: 5.00 to 15.00",
        ]
        if session_name:
            settings_lines = [f"session: {session_name}", *settings_lines]
    return {
        "stims": [-2.0, -1.0, 0.0, 1.0, 2.0],
        "n_correct": [4, 6, 8, 12, 15],
        "n_incorrect": [10, 8, 6, 4, 2],
        "n_ew": [2, 2, 2, 2, 2],
        "n_no_choice": [1, 1, 1, 1, 1],
        "p_right": [0.1, 0.25, 0.5, 0.75, 0.9],
        "median_rt": [0.3, 0.28, 0.25, 0.24, 0.23],
        "rts": rng.uniform(0.1, 0.5, n).tolist(),
        "rt_trial_nums": trial_nums,
        "rt_vals": rng.uniform(0.1, 0.5, n).tolist(),
        "rt_roll_x": roll_x,
        "rt_roll_y": rng.uniform(0.2, 0.4, nroll).tolist(),
        "response_trial_nums": trial_nums,
        "response_trial_nums_left": trial_nums[::2],
        "response_trial_nums_right": trial_nums[1::2],
        "response_roll_x": roll_x,
        "response_roll_y": rng.uniform(0.1, 0.6, nroll).tolist(),
        "response_roll_left_x": roll_x,
        "response_roll_left_y": rng.uniform(0.1, 0.5, nroll).tolist(),
        "response_roll_right_x": roll_x,
        "response_roll_right_y": rng.uniform(0.2, 0.7, nroll).tolist(),
        "init_times": rng.uniform(0.3, 2.0, n).tolist(),
        "init_trial_nums": trial_nums,
        "init_roll_x": roll_x,
        "init_roll_y": rng.uniform(0.5, 1.5, nroll).tolist(),
        "wait_times": rng.uniform(0.5, 3.0, n).tolist(),
        "wait_min_times": rng.uniform(0.2, 1.0, n).tolist(),
        "wait_delta_times": rng.uniform(0.0, 2.0, n).tolist(),
        "wait_trial_nums": trial_nums,
        "wait_delta_x": roll_x,
        "wait_delta_y": rng.uniform(0.0, 1.0, nroll).tolist(),
        "wait_delta_left_times": rng.uniform(0.0, 1.0, n // 2).tolist(),
        "wait_delta_right_times": rng.uniform(0.0, 1.0, n // 2).tolist(),
        "wait_trial_nums_left": trial_nums[::2],
        "wait_trial_nums_right": trial_nums[1::2],
        "wait_delta_left_x": roll_x,
        "wait_delta_left_y": rng.uniform(0.0, 1.0, nroll).tolist(),
        "wait_delta_right_x": roll_x,
        "wait_delta_right_y": rng.uniform(0.0, 1.0, nroll).tolist(),
        "wait_roll_x": roll_x,
        "wait_roll_y": rng.uniform(0.5, 2.0, nroll).tolist(),
        "wait_times_left": rng.uniform(0.5, 3.0, n // 2).tolist(),
        "wait_times_right": rng.uniform(0.5, 3.0, n // 2).tolist(),
        "wait_left_x": roll_x,
        "wait_left_y": rng.uniform(0.5, 2.0, nroll).tolist(),
        "wait_right_x": roll_x,
        "wait_right_y": rng.uniform(0.5, 2.0, nroll).tolist(),
        "response_times": rng.uniform(0.05, 0.8, n).tolist(),
        "response_times_left": rng.uniform(0.05, 0.5, n // 2).tolist(),
        "response_times_right": rng.uniform(0.2, 0.9, n // 2).tolist(),
        "session_settings_lines": settings_lines,
        "water_side_totals_ul": [120.0, 150.0, 270.0],
        "water_cum_x": trial_nums,
        "water_cum_time_x": [float(v - 1) for v in trial_nums],
        "water_cum_total_ul": np.cumsum(rng.uniform(1.0, 2.0, n)).tolist(),
        "water_cum_left_ul": np.cumsum(rng.uniform(0.4, 1.0, n)).tolist(),
        "water_cum_right_ul": np.cumsum(rng.uniform(0.4, 1.0, n)).tolist(),
        "iti_times": rng.uniform(0.5, 3.0, n).tolist(),
        "iti_times_after_correct": rng.uniform(0.5, 3.0, n // 4).tolist(),
        "iti_times_after_incorrect": rng.uniform(0.5, 3.0, n // 4).tolist(),
        "iti_times_after_ew": rng.uniform(0.5, 3.0, n // 4).tolist(),
        "iti_times_after_no_choice": rng.uniform(0.5, 3.0, n // 4).tolist(),
        "iti_roll_x": iti_roll_x,
        "iti_roll_y": rng.uniform(0.5, 2.0, n_iti_roll).tolist(),
        "iti_roll_correct_x": iti_roll_x,
        "iti_roll_correct_y": rng.uniform(0.5, 2.0, n_iti_roll).tolist(),
        "iti_roll_incorrect_x": iti_roll_x,
        "iti_roll_incorrect_y": rng.uniform(0.5, 2.0, n_iti_roll).tolist(),
        "iti_roll_ew_x": iti_roll_x,
        "iti_roll_ew_y": rng.uniform(0.5, 2.0, n_iti_roll).tolist(),
        "iti_roll_no_choice_x": iti_roll_x,
        "iti_roll_no_choice_y": rng.uniform(0.5, 2.0, n_iti_roll).tolist(),
        "trial_count_x": [0.0, 1.0, 2.0, 3.0],
        "trial_count_trial_nums": [5, 10, 15, 20],
        "trial_count_y": [6.0, 8.0, 9.0, 10.0],
        "slide_x": roll_x,
        "slide_y": rng.uniform(0.5, 0.9, nroll).tolist(),
        "ew_roll_x": roll_x,
        "ew_roll_y": rng.uniform(0.0, 0.2, nroll).tolist(),
    }


def make_multisession_metrics(*, n: int = 10, seed: int = 42) -> dict:
    """Build a multisession_metrics dict for multi-session figure building."""
    rng = np.random.default_rng(seed)
    return {
        "x": [f"2026-01-{i + 1:02d} 12:00:00" for i in range(n)],
        "session_dates": [f"2026-01-{i + 1:02d} 12:00:00" for i in range(n)],
        "training_time_hours": [9.5 + (i * 0.25) for i in range(n)],
        "perf_easy": rng.uniform(0.5, 0.9, n).tolist(),
        "ew_rate": rng.uniform(0.0, 0.3, n).tolist(),
        "n_with_choice": [int(v) for v in rng.integers(50, 120, n)],
        "side_bias": rng.uniform(-0.2, 0.2, n).tolist(),
        "median_init": rng.uniform(0.3, 1.0, n).tolist(),
        "median_rt": rng.uniform(0.2, 0.5, n).tolist(),
        "median_wait": rng.uniform(0.5, 2.0, n).tolist(),
        "water": rng.uniform(1.0, 3.0, n).tolist(),
    }
