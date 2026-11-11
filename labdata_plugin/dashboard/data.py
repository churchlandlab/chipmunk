"""Data fetching and metric computation."""

import os
import threading
import time
from collections.abc import Callable
from datetime import date, timedelta
from functools import lru_cache, wraps
from typing import Any, cast

import labdata  # noqa: F401 — registers prefs plugins (chipmunk) into sys.modules
import numpy as np
import pandas as pd
from labdata.schema import DecisionTask, Watering  # type: ignore
from chipmunk import Chipmunk  # type: ignore

from .perf import perf_log

_DB_LOCK = threading.RLock()
_CACHE_TTL_SECONDS = int(os.getenv("CHIPMUNK_CACHE_TTL_SECONDS", "1800"))
_PREWARM_ENABLED = os.getenv("CHIPMUNK_PREWARM", "1") == "1"
_PREWARM_LOCK = threading.Lock()
_PREWARM_INFLIGHT: set[tuple[tuple[str, ...], int, str | None]] = set()


def _ttl_lru_cache(
    maxsize: int = 128, ttl_seconds: int = _CACHE_TTL_SECONDS
) -> Callable[[Callable[..., Any]], Callable[..., Any]]:
    def decorator(func: Callable[..., Any]) -> Callable[..., Any]:
        @lru_cache(maxsize=maxsize)
        def _cached(ttl_bucket: int, /, *args: Any, **kwargs: Any) -> Any:
            return func(*args, **kwargs)

        @wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            return _cached(int(time.time() // ttl_seconds), *args, **kwargs)

        cast(Any, wrapper).cache_clear = _cached.cache_clear
        return wrapper

    return decorator


@_ttl_lru_cache(maxsize=1)
def get_all_subjects() -> list[str]:
    """Fetch all unique subject names from the database.

    Returns:
        A sorted list of unique subject names.

    Side Effects:
        Executes a database query under ``_DB_LOCK``.
    """
    with _DB_LOCK:
        subjects = DecisionTask.TrialSet().fetch("subject_name")
    return sorted(set(subjects))


@_ttl_lru_cache(maxsize=1)
def get_subjects_with_recent_sessions(days: int = 7) -> set[str]:
    """Return subjects with at least one session recorded in the last ``days`` days.

    Session names are expected to follow the ``YYYYMMDD_HHMMSS`` format; any
    session whose leading 8-character date component is on or after the cutoff
    date counts as recent.

    Args:
        days: Number of days to look back from today (default: 14).

    Returns:
        A set of subject names that have had at least one session in the last
        ``days`` days.

    Side Effects:
        Executes a database query under ``_DB_LOCK``.
    """
    cutoff = (date.today() - timedelta(days=days)).strftime("%Y%m%d")  # noqa: DTZ011 — lab-local calendar day
    with _DB_LOCK:
        recent_trials = DecisionTask.TrialSet() & f"session_name >= '{cutoff}'"
        subjects = recent_trials.fetch("subject_name")
    return {str(subject) for subject in subjects}


@_ttl_lru_cache(maxsize=64)
def get_subject_data(subject: str) -> pd.DataFrame:
    """Fetch all trial-set rows for a subject.

    Args:
        subject: Subject name to query.

    Returns:
        A DataFrame of trial-set rows ordered by ``session_name``.

    Side Effects:
        Executes a database query under ``_DB_LOCK`` and logs timing metrics
        when profiling is enabled.
    """
    start = time.perf_counter()
    fields = [
        "subject_name",
        "session_name",
        "performance_easy",
        "n_with_choice",
        "response_values",
        "initiation_times",
        "reaction_times",
    ]
    with _DB_LOCK:
        rel = DecisionTask.TrialSet() & f"subject_name = '{subject}'"
        try:
            rows = rel.fetch(*fields, order_by="session_name", as_dict=True)
            df = pd.DataFrame(rows)
            perf_log("get_subject_data", start, subject=subject, rows=len(df))
            return df
        except Exception:  # noqa: BLE001 — DataJoint fetch failure surface is broad
            df = pd.DataFrame(rel)
            perf_log("get_subject_data_fallback", start, subject=subject, rows=len(df))
            return df


@_ttl_lru_cache(maxsize=64)
def get_session_trials(subject: str, session_name: str) -> pd.DataFrame:
    """Fetch per-trial Chipmunk rows for a single session.

    Args:
        subject: Subject name to query.
        session_name: Session name to query.

    Returns:
        A DataFrame of per-trial rows ordered by ``trial_num``.

    Side Effects:
        Executes a database query under ``_DB_LOCK``.
    """
    restriction = f"subject_name = '{subject}' AND session_name = '{session_name}'"
    with _DB_LOCK:
        return pd.DataFrame(
            (Chipmunk * Chipmunk.Trial * Chipmunk.TrialParameters & restriction).fetch(
                order_by="trial_num"
            )
        )


@_ttl_lru_cache(maxsize=64)
def get_subject_water(subject: str) -> dict[str, float]:
    """Fetch water volume by session for a subject.

    Args:
        subject: Subject name to query.

    Returns:
        A mapping from ``session_name`` to water volume in mL.

    Side Effects:
        Executes a database query under ``_DB_LOCK``.
    """
    with _DB_LOCK:
        rows = (DecisionTask * Watering & f"subject_name = '{subject}'").fetch(
            "session_name", "water_volume", as_dict=True
        )
    return {row["session_name"]: float(row["water_volume"]) for row in rows}


@_ttl_lru_cache(maxsize=64)
def get_trials_for_sessions(
    subject: str, session_names: tuple[str, ...]
) -> dict[str, pd.DataFrame]:
    """Fetch per-trial rows for multiple sessions in one query.

    Args:
        subject: Subject name to query.
        session_names: Session names to include.

    Returns:
        A mapping from ``session_name`` to a trial DataFrame for that session.
        Returns an empty dict when no sessions are provided or no rows exist.

    Side Effects:
        Executes a database query under ``_DB_LOCK`` and logs timing metrics
        when profiling is enabled.
    """
    start = time.perf_counter()
    if not session_names:
        return {}

    quoted = ", ".join(f"'{s}'" for s in session_names)
    restriction = f"subject_name = '{subject}' AND session_name in ({quoted})"

    with _DB_LOCK:
        df = pd.DataFrame(
            (Chipmunk * Chipmunk.Trial * Chipmunk.TrialParameters & restriction).fetch(
                order_by="session_name, trial_num"
            )
        )

    if df.empty:
        return {}

    grouped: dict[str, pd.DataFrame] = {}
    for session, session_df in df.groupby("session_name", sort=False):
        grouped[str(session)] = session_df.reset_index(drop=True)
    perf_log(
        "get_trials_for_sessions",
        start,
        subject=subject,
        sessions=len(session_names),
        rows=len(df),
    )
    return grouped


@_ttl_lru_cache(maxsize=64)
def get_wait_medians_for_sessions(
    subject: str, session_names: tuple[str, ...]
) -> dict[str, float]:
    """Compute median wait time per session using trial timing columns.

    Args:
        subject: Subject name to query.
        session_names: Session names to include.

    Returns:
        A mapping from ``session_name`` to median wait time in seconds.
        Returns an empty dict when inputs or rows are empty after filtering.

    Side Effects:
        Executes a database query under ``_DB_LOCK`` and logs timing metrics
        when profiling is enabled.
    """
    start = time.perf_counter()
    if not session_names:
        return {}

    quoted = ", ".join(f"'{s}'" for s in session_names)
    restriction = f"subject_name = '{subject}' AND session_name in ({quoted})"

    with _DB_LOCK:
        rows = (Chipmunk.Trial & restriction).fetch(
            "session_name", "t_react", "t_stim", as_dict=True
        )

    if not rows:
        return {}

    df = pd.DataFrame(rows)
    wait = df["t_react"].to_numpy() - df["t_stim"].to_numpy()
    mask = np.isfinite(wait) & (wait > 0) & (wait < 30)
    valid = df.loc[mask, ["session_name"]].copy()
    valid["wait"] = wait[mask]

    if valid.empty:
        return {}

    grouped = valid.groupby("session_name", sort=False)["wait"].median().to_dict()
    out = {str(k): float(v) for k, v in grouped.items()}
    perf_log(
        "get_wait_medians_for_sessions",
        start,
        subject=subject,
        sessions=len(session_names),
        rows=len(df),
    )
    return out


@_ttl_lru_cache(maxsize=256)
def get_subjects_for_date(date_str: str) -> list[str]:
    """Return subjects that have at least one session on the given calendar date.

    Args:
        date_str: Date in ``YYYYMMDD`` format (the raw prefix used in session names).

    Returns:
        A sorted list of subject names with sessions starting on that date.
        Returns an empty list when the date string is empty, not exactly 8 digits,
        or no matches exist.

    Side Effects:
        Executes a database query under ``_DB_LOCK``.
    """
    if not date_str or not date_str.isdigit() or len(date_str) != 8:
        return []
    with _DB_LOCK:
        rows = (DecisionTask.TrialSet() & f"session_name LIKE '{date_str}%'").fetch(
            "subject_name"
        )
    return sorted(set(rows))


def clear_data_cache() -> None:
    """Clear all in-memory cached data and metric results.

    Returns:
        None.

    Side Effects:
        Invalidates TTL/LRU caches for subject lists, sessions, trial fetches,
        and computed metrics so subsequent reads hit the database again.
    """
    get_all_subjects.cache_clear()
    get_subjects_with_recent_sessions.cache_clear()
    get_subject_data.cache_clear()
    get_session_trials.cache_clear()
    get_subject_water.cache_clear()
    get_trials_for_sessions.cache_clear()
    get_wait_medians_for_sessions.cache_clear()
    get_sessions.cache_clear()
    get_subjects_for_date.cache_clear()
    session_metrics.cache_clear()
    multisession_metrics.cache_clear()


def prewarm_multisession_cache(
    subjects: list[str], sessions_back: int = 30, start_date: str | None = None
) -> None:
    """Precompute multi-session metrics in a background thread.

    Args:
        subjects: Subject names to prewarm.
        sessions_back: Number of sessions to include per subject.
        start_date: Optional anchor date in ``YYYY-MM-DD`` format.

    Returns:
        None.

    Side Effects:
        Starts a daemon thread that populates ``multisession_metrics`` cache
        entries, guarded by in-flight deduplication and lock coordination.
        No-op when prewarming is disabled or subject list is empty.
    """
    if not _PREWARM_ENABLED or not subjects:
        return

    key = (tuple(sorted(set(subjects))), int(sessions_back), start_date)
    with _PREWARM_LOCK:
        if key in _PREWARM_INFLIGHT:
            return
        _PREWARM_INFLIGHT.add(key)

    def _worker() -> None:
        """Compute and populate multi-session cache entries in the background.

        Returns:
            None.

        Side Effects:
            Invokes ``multisession_metrics`` for each subject in the prewarm key,
            updates the in-flight tracking set under lock, and emits perf logs.
        """
        start = time.perf_counter()
        try:
            for subject in key[0]:
                multisession_metrics(subject, key[1], key[2], False, 3)
        finally:
            with _PREWARM_LOCK:
                _PREWARM_INFLIGHT.discard(key)
            perf_log(
                "prewarm_multisession_cache",
                start,
                subjects=len(key[0]),
                sessions_back=key[1],
            )

    threading.Thread(target=_worker, daemon=True).start()


@_ttl_lru_cache(maxsize=64)
def get_sessions(subject: str) -> list[str]:
    """Fetch session names for a subject in chronological order.

    Args:
        subject: Subject name to query.

    Returns:
        A list of ``session_name`` values ordered ascending.

    Side Effects:
        Executes a database query under ``_DB_LOCK``.
    """
    with _DB_LOCK:
        sessions = (DecisionTask.TrialSet() & f"subject_name = '{subject}'").fetch(
            "session_name", order_by="session_name"
        )
    return list(sessions)


def _compute_intensity(trials: pd.DataFrame) -> np.ndarray:
    """Compute per-trial stimulus intensity from modality-specific rates.

    Args:
        trials: Trial DataFrame containing modality, rate, and boundary columns.

    Returns:
        A NumPy array where each entry is ``stim_rate - category_boundary``
        for the trial's rewarded modality.
    """
    intensity = np.full(len(trials), np.nan)
    for mod, rate_col in [
        ("audio", "stim_rate_audio"),
        ("visual", "stim_rate_vision"),
        ("visual+audio", "stim_rate_vision"),
    ]:
        mask = trials.rewarded_modality == mod
        if mask.any():
            intensity[mask] = (
                trials.loc[mask, rate_col].to_numpy()
                - trials.loc[mask, "category_boundary"].to_numpy()
            )
    return intensity


@_ttl_lru_cache(maxsize=256)
def session_metrics(subject: str, session_name: str) -> dict | None:
    """Compute single-session behavioral metrics used by dashboard figures.

    Args:
        subject: Subject name to query.
        session_name: Session name to analyze.

    Returns:
        A dict of arrays and summary values for outcomes, psychometric and
        chronometric curves, rolling metrics, initiation, wait, and reaction
        time distributions. Returns ``None`` when no trial rows are found.

    Side Effects:
        Reads cached trial data and logs timing metrics when profiling is
        enabled.
    """
    start = time.perf_counter()
    trials = get_session_trials(subject, session_name)
    if trials.empty:
        perf_log(
            "session_metrics", start, subject=subject, session=session_name, rows=0
        )
        return None

    intensity = _compute_intensity(trials)

    # Reaction times: t_response - t_gocue (Chipmunk.Trial fields)
    rts = trials["t_response"].to_numpy() - trials["t_gocue"].to_numpy()
    rts[trials.response.to_numpy() == 0] = np.nan
    valid_rts = rts[np.isfinite(rts)]
    valid_rts = valid_rts[valid_rts < 2]

    # Per-stimulus outcome counts (4 categories) + chronometric + p(right)
    ustims = np.unique(intensity[np.isfinite(intensity)])
    n_correct, n_incorrect, n_ew, n_no_choice, p_right, median_rt = (
        [],
        [],
        [],
        [],
        [],
        [],
    )
    for s in ustims:
        m = intensity == s
        t = trials[m]
        t_rewarded = t.rewarded.to_numpy() == 1
        t_incorrect = (t.with_choice.to_numpy() == 1) & ~t_rewarded
        t_ew_only = (t.early_withdrawal.to_numpy() == 1) & ~t_rewarded & ~t_incorrect
        t_no_choice = ~(t_rewarded | t_incorrect | t_ew_only)

        nc = int(np.sum(t_rewarded))
        ni = int(np.sum(t_incorrect))
        ne = int(np.sum(t_ew_only))
        nn = int(np.sum(t_no_choice))
        n_correct.append(nc)
        n_incorrect.append(ni)
        n_ew.append(ne)
        n_no_choice.append(nn)
        with_choice_trials = t[t.with_choice == 1]
        pr = (
            (with_choice_trials.response == 1).sum() / len(with_choice_trials)
            if len(with_choice_trials)
            else 0
        )
        p_right.append(pr)
        # Median RT for chronometric curve
        trial_rts = rts[m]
        trial_rts = trial_rts[np.isfinite(trial_rts) & (trial_rts < 2)]
        median_rt.append(float(np.median(trial_rts)) if len(trial_rts) else np.nan)

    # Within-session sliding-window performance (20-trial window)
    with_choice = trials.with_choice.to_numpy()
    choice_mask = with_choice == 1
    rewarded = trials.rewarded.to_numpy()
    trial_nums = trials.trial_num.to_numpy()
    win = 20
    iti_roll_win = 25
    slide_x, slide_y = [], []
    choice_idx = np.where(choice_mask)[0]
    for start in range(0, len(choice_idx) - win + 1, 5):  # step 5
        block = choice_idx[start : start + win]
        slide_x.append(int(np.mean(trial_nums[block])))
        slide_y.append(float(rewarded[block].sum() / win))

    # Calculate initiation times (t_stim - t_start)
    # Filter for valid (finite) initiation times
    init_raw = trials["t_stim"].to_numpy() - trials["t_start"].to_numpy()
    init_mask = np.isfinite(init_raw) & (init_raw > 0)
    init_vals = init_raw[init_mask]
    init_trial_nums = trials["trial_num"].to_numpy()[init_mask]

    # Sort by trial number for rolling calcs
    # (Note: init_trial_nums and init_vals might not be sorted if fetch order wasn't strict, but fetch(order_by="trial_num") should handle it. Being safe:)
    init_sorted_idx = np.argsort(init_trial_nums)
    init_trial_nums = init_trial_nums[init_sorted_idx]
    init_vals = init_vals[init_sorted_idx]

    # Rolling median of initiation time (20-trial window)
    init_roll_x, init_roll_y = [], []
    for start in range(0, len(init_vals) - win + 1, 5):
        init_roll_x.append(int(np.mean(init_trial_nums[start : start + win])))
        init_roll_y.append(float(np.median(init_vals[start : start + win])))

    # Wait times: actual vs minimum
    wait_actual = trials["t_react"].to_numpy() - trials["t_stim"].to_numpy()
    wait_min = trials["t_gocue"].to_numpy() - trials["t_stim"].to_numpy()
    wait_mask = (
        np.isfinite(wait_actual)
        & np.isfinite(wait_min)
        & (wait_actual > 0)
        & (wait_actual < 30)
        & (wait_min > 0)
        & (wait_min < 30)
    )
    wait_actual = wait_actual[wait_mask]
    wait_min = wait_min[wait_mask]
    wait_delta = wait_actual - wait_min

    # Wait delta filtered for histogram/lines
    wait_trial_nums = trials["trial_num"].to_numpy()[wait_mask]

    # Reaction times (Trial vs RT)
    rt_full_mask = np.isfinite(rts) & (rts < 2) & (trials.response != 0)
    rt_trial_nums = trials["trial_num"].to_numpy()[rt_full_mask]
    rt_vals = rts[rt_full_mask]

    # Sort for rolling
    rt_sorted_idx = np.argsort(rt_trial_nums)
    rt_trial_nums = rt_trial_nums[rt_sorted_idx]
    rt_vals = rt_vals[rt_sorted_idx]

    # Rolling median of RT (20-trial window)
    rt_roll_x, rt_roll_y = [], []
    for start in range(0, len(rt_vals) - win + 1, 5):
        rt_roll_x.append(int(np.mean(rt_trial_nums[start : start + win])))
        rt_roll_y.append(float(np.median(rt_vals[start : start + win])))

    # Response times (movement time): response - react, split by choice.
    response_raw = trials["t_response"].to_numpy() - trials["t_react"].to_numpy()
    response_vals = trials["response"].to_numpy()
    rewarded = trials["rewarded"].to_numpy()
    early_withdrawal = trials["early_withdrawal"].to_numpy()
    response_mask = (
        np.isfinite(response_raw)
        & (response_raw > 0)
        & (response_raw < 5)
        & (response_vals != 0)
    )
    response_times = response_raw[response_mask]
    response_trial_nums = trials["trial_num"].to_numpy()[response_mask]
    response_choices = response_vals[response_mask]

    response_sort_idx = np.argsort(response_trial_nums)
    response_times = response_times[response_sort_idx]
    response_trial_nums = response_trial_nums[response_sort_idx]
    response_choices = response_choices[response_sort_idx]

    response_left_mask = response_choices == -1
    response_right_mask = response_choices == 1
    response_left = response_times[response_left_mask]
    response_right = response_times[response_right_mask]
    response_trial_nums_left = response_trial_nums[response_left_mask]
    response_trial_nums_right = response_trial_nums[response_right_mask]

    # Left/right choice splits for post-go center dwell and wait floor.
    wait_choice = response_vals[wait_mask]
    left_choice_mask = wait_choice == -1
    right_choice_mask = wait_choice == 1
    wait_delta_left = wait_delta[left_choice_mask]
    wait_delta_right = wait_delta[right_choice_mask]
    wait_left = wait_actual[left_choice_mask]
    wait_right = wait_actual[right_choice_mask]
    wait_trial_nums_left = wait_trial_nums[left_choice_mask]
    wait_trial_nums_right = wait_trial_nums[right_choice_mask]

    # Rolling helper used for split traces.
    def _rolling_median(
        x_vals: np.ndarray,
        y_vals: np.ndarray,
        window: int = win,
        fallback_single: bool = False,
    ) -> tuple[list[int], list[float]]:
        roll_x: list[int] = []
        roll_y: list[float] = []
        for start in range(0, len(y_vals) - window + 1, 5):
            roll_x.append(int(np.mean(x_vals[start : start + window])))
            roll_y.append(float(np.median(y_vals[start : start + window])))
        if fallback_single and not roll_x and len(y_vals):
            roll_x.append(int(np.mean(x_vals)))
            roll_y.append(float(np.median(y_vals)))
        return roll_x, roll_y

    wait_delta_left_roll_x, wait_delta_left_roll_y = _rolling_median(
        wait_trial_nums_left, wait_delta_left
    )
    wait_delta_right_roll_x, wait_delta_right_roll_y = _rolling_median(
        wait_trial_nums_right, wait_delta_right
    )
    wait_left_roll_x, wait_left_roll_y = _rolling_median(
        wait_trial_nums_left, wait_left
    )
    wait_right_roll_x, wait_right_roll_y = _rolling_median(
        wait_trial_nums_right, wait_right
    )
    response_roll_x, response_roll_y = _rolling_median(
        response_trial_nums, response_times
    )
    response_roll_left_x, response_roll_left_y = _rolling_median(
        response_trial_nums_left, response_left
    )
    response_roll_right_x, response_roll_right_y = _rolling_median(
        response_trial_nums_right, response_right
    )

    # Inter-trial intervals from consecutive trial starts, split by preceding outcome.
    start_times_all = trials["t_start"].to_numpy()
    iti_all: list[float] = []
    iti_trial_nums: list[int] = []
    iti_after_correct: list[float] = []
    iti_trial_nums_after_correct: list[int] = []
    iti_after_incorrect: list[float] = []
    iti_trial_nums_after_incorrect: list[int] = []
    iti_after_ew: list[float] = []
    iti_trial_nums_after_ew: list[int] = []
    iti_after_no_choice: list[float] = []
    iti_trial_nums_after_no_choice: list[int] = []
    for i in range(len(start_times_all) - 1):
        start_prev = start_times_all[i]
        start_next = start_times_all[i + 1]
        if not (np.isfinite(start_prev) and np.isfinite(start_next)):
            continue
        iti = float(start_next - start_prev)
        if not (0 < iti < 30):
            continue
        iti_trial_num = int(trial_nums[i])
        iti_all.append(iti)
        iti_trial_nums.append(iti_trial_num)
        prev_rewarded = rewarded[i] == 1
        prev_with_choice = with_choice[i] == 1
        prev_incorrect = prev_with_choice and (not prev_rewarded)
        prev_ew = early_withdrawal[i] == 1

        if prev_rewarded:
            iti_after_correct.append(iti)
            iti_trial_nums_after_correct.append(iti_trial_num)
        elif prev_incorrect:
            iti_after_incorrect.append(iti)
            iti_trial_nums_after_incorrect.append(iti_trial_num)
        elif prev_ew:
            iti_after_ew.append(iti)
            iti_trial_nums_after_ew.append(iti_trial_num)
        else:
            iti_after_no_choice.append(iti)
            iti_trial_nums_after_no_choice.append(iti_trial_num)
    iti_vals = np.asarray(iti_all, dtype=float)
    iti_roll_x, iti_roll_y = _rolling_median(
        np.asarray(iti_trial_nums, dtype=int),
        iti_vals,
        window=iti_roll_win,
    )
    iti_roll_correct_x, iti_roll_correct_y = _rolling_median(
        np.asarray(iti_trial_nums_after_correct, dtype=int),
        np.asarray(iti_after_correct, dtype=float),
        window=iti_roll_win,
        fallback_single=True,
    )
    iti_roll_incorrect_x, iti_roll_incorrect_y = _rolling_median(
        np.asarray(iti_trial_nums_after_incorrect, dtype=int),
        np.asarray(iti_after_incorrect, dtype=float),
        window=iti_roll_win,
        fallback_single=True,
    )
    iti_roll_ew_x, iti_roll_ew_y = _rolling_median(
        np.asarray(iti_trial_nums_after_ew, dtype=int),
        np.asarray(iti_after_ew, dtype=float),
        window=iti_roll_win,
        fallback_single=True,
    )
    iti_roll_no_choice_x, iti_roll_no_choice_y = _rolling_median(
        np.asarray(iti_trial_nums_after_no_choice, dtype=int),
        np.asarray(iti_after_no_choice, dtype=float),
        window=iti_roll_win,
        fallback_single=True,
    )

    # Rolling trial counts in a trailing 5-minute window, sampled every 5 trials.
    start_mask = np.isfinite(start_times_all)
    start_times = start_times_all[start_mask]
    start_trial_nums = trial_nums[start_mask]
    if start_times.size:
        start_sort_idx = np.argsort(start_times)
        start_times = start_times[start_sort_idx]
        start_trial_nums = start_trial_nums[start_sort_idx]
        window_sec = 5.0 * 60.0
        first_start_t = float(start_times[0])
        trial_count_x: list[float] = []
        trial_count_trial_nums: list[int] = []
        trial_count_vals_list: list[float] = []
        left_idx = 0
        for idx, current_t in enumerate(start_times):
            while left_idx < idx and start_times[left_idx] < (current_t - window_sec):
                left_idx += 1
            if idx % 5 == 0 or idx == (start_times.size - 1):
                trial_count_x.append(float((current_t - first_start_t) / 60.0))
                trial_count_trial_nums.append(int(start_trial_nums[idx]))
                trial_count_vals_list.append(float(idx - left_idx + 1))
        trial_count_vals = np.asarray(trial_count_vals_list, dtype=float)
    else:
        trial_count_vals = np.array([])
        trial_count_x = []
        trial_count_trial_nums = []

    # Rolling median of wait delta (20-trial window)
    wait_delta_x, wait_delta_y = [], []
    for start in range(0, len(wait_delta) - win + 1, 5):
        wait_delta_x.append(int(np.mean(wait_trial_nums[start : start + win])))
        wait_delta_y.append(float(np.median(wait_delta[start : start + win])))

    # Rolling median of wait actual (20-trial window)
    wait_roll_x, wait_roll_y = [], []
    for start in range(0, len(wait_actual) - win + 1, 5):
        wait_roll_x.append(int(np.mean(wait_trial_nums[start : start + win])))
        wait_roll_y.append(float(np.median(wait_actual[start : start + win])))

    # Rolling EW Rate (20-trial window)
    ew_roll_x, ew_roll_y = [], []
    ew_raw = trials.early_withdrawal.to_numpy()  # 0 or 1
    # We want rolling mean of this binary vector vs trial number
    # Assuming trials are sorted by trial_num, which they are from fetch(order_by="trial_num")
    trial_nums_all = trials.trial_num.to_numpy()

    for start in range(0, len(ew_raw) - win + 1, 5):
        ew_roll_x.append(int(np.mean(trial_nums_all[start : start + win])))
        ew_roll_y.append(float(np.mean(ew_raw[start : start + win])))

    def _range_text(values: np.ndarray, precision: int = 2) -> str | None:
        finite_vals = values[np.isfinite(values)]
        if finite_vals.size == 0:
            return None
        lo = float(np.min(finite_vals))
        hi = float(np.max(finite_vals))
        if np.isclose(lo, hi):
            return f"{lo:.{precision}f}"
        return f"{lo:.{precision}f} to {hi:.{precision}f}"

    session_settings_lines: list[str] = [f"trials: {len(trials)}"]
    used_setting_cols: set[str] = set()

    def _summarize_setting(col_name: str, label: str, mode: str = "auto") -> str | None:
        if col_name not in trials.columns:
            return None
        series = trials[col_name].dropna()
        if series.empty:
            return None

        numeric_vals = pd.to_numeric(series, errors="coerce").to_numpy(dtype=float)
        finite_numeric = numeric_vals[np.isfinite(numeric_vals)]
        if finite_numeric.size:
            rounded = np.round(finite_numeric, 6)
            unique_vals = np.unique(rounded)
            if mode == "values":
                text = ", ".join(f"{val:.3g}" for val in unique_vals.tolist())
            elif mode == "range" or (
                mode == "auto" and len(unique_vals) > 3 and "stim" in col_name.lower()
            ):
                text = _range_text(finite_numeric)
                if text is None:
                    return None
            elif len(unique_vals) <= 3:
                text = ", ".join(f"{val:.3g}" for val in unique_vals.tolist())
            else:
                text = _range_text(finite_numeric)
                if text is None:
                    return None
            return f"{label}: {text}"

        text_vals = sorted({str(v) for v in series.tolist() if str(v).strip()})
        if not text_vals or len(text_vals) > 4:
            return None
        return f"{label}: {', '.join(text_vals)}"

    preferred_settings = [
        ("rewarded_modality", "modality", "auto"),
        ("category_boundary", "boundary", "auto"),
        ("stim_rate_audio", "audio stim", "values"),
        ("stim_rate_vision", "visual stim", "values"),
        ("stim_rate_visual", "visual stim", "values"),
        ("wait_duration", "wait duration", "auto"),
        ("delay_duration", "delay duration", "auto"),
        ("sample_duration", "sample duration", "auto"),
        ("response_duration", "response duration", "auto"),
        ("timeout_duration", "timeout duration", "auto"),
        ("reward_amount", "reward amount", "auto"),
        ("reward_amount_ul", "reward amount (µL)", "auto"),
    ]
    for col_name, label, mode in preferred_settings:
        line = _summarize_setting(col_name, label, mode)
        if line and line not in session_settings_lines:
            session_settings_lines.append(line)
            used_setting_cols.add(col_name)

    excluded_cols = {
        "subject_name",
        "session_name",
        "trial_num",
        "response",
        "rewarded",
        "punished",
        "early_withdrawal",
        "with_choice",
        "performance_easy",
        "n_with_choice",
        "response_values",
        "initiation_times",
        "reaction_times",
    }
    keyword_fragments = (
        "stim",
        "reward",
        "wait",
        "delay",
        "timeout",
        "sample",
        "modality",
        "boundary",
        "block",
        "choice",
    )
    for col_name in trials.columns:
        col_l = col_name.lower()
        if (
            col_name in used_setting_cols
            or col_name in excluded_cols
            or col_name.startswith("t_")
            or not any(fragment in col_l for fragment in keyword_fragments)
        ):
            continue
        line = _summarize_setting(col_name, col_name.replace("_", " "), "auto")
        if line and line not in session_settings_lines:
            session_settings_lines.append(line)
        if len(session_settings_lines) >= 9:
            break

    if start_times.size > 1:
        session_duration_min = (
            float(np.max(start_times)) - float(np.min(start_times))
        ) / 60.0
        session_settings_lines.append(f"duration: {session_duration_min:.1f} min")

    rewarded_mask = rewarded == 1
    rewarded_left_mask = rewarded_mask & (response_vals == -1)
    rewarded_right_mask = rewarded_mask & (response_vals == 1)
    water_by_session = get_subject_water(subject)
    session_water_ml = water_by_session.get(session_name, np.nan)
    session_water_ul = (
        float(session_water_ml) * 1000.0
        if np.isfinite(session_water_ml) and float(session_water_ml) > 0
        else np.nan
    )
    rewarded_count = int(np.sum(rewarded_mask))
    reward_step_ul = (
        session_water_ul / rewarded_count
        if rewarded_count and np.isfinite(session_water_ul)
        else (1.0 if rewarded_count else 0.0)
    )
    water_step_total = np.where(rewarded_mask, reward_step_ul, 0.0)
    water_step_left = np.where(rewarded_left_mask, reward_step_ul, 0.0)
    water_step_right = np.where(rewarded_right_mask, reward_step_ul, 0.0)
    water_cum_total = np.cumsum(water_step_total)
    water_cum_left = np.cumsum(water_step_left)
    water_cum_right = np.cumsum(water_step_right)
    water_cum_x = trial_nums.astype(int).tolist()
    valid_trial_start_times = np.where(
        np.isfinite(start_times_all), start_times_all, np.nan
    )
    if np.any(np.isfinite(valid_trial_start_times)):
        first_trial_start_t = float(np.nanmin(valid_trial_start_times))
        water_cum_time_x = (
            (valid_trial_start_times - first_trial_start_t) / 60.0
        ).astype(float)
        water_cum_time_x = np.where(
            np.isfinite(water_cum_time_x), water_cum_time_x, np.nan
        ).tolist()
    else:
        water_cum_time_x = []
    water_side_totals_ul = [
        float(water_cum_left[-1]) if water_cum_left.size else 0.0,
        float(water_cum_right[-1]) if water_cum_right.size else 0.0,
        float(water_cum_total[-1]) if water_cum_total.size else 0.0,
    ]

    out = {
        "stims": ustims.tolist(),
        "n_correct": n_correct,
        "n_incorrect": n_incorrect,
        "n_ew": n_ew,
        "n_no_choice": n_no_choice,
        "p_right": p_right,
        "median_rt": median_rt,
        "rts": valid_rts.tolist(),
        "rt_trial_nums": rt_trial_nums.tolist(),
        "rt_vals": rt_vals.tolist(),
        "rt_roll_x": rt_roll_x,
        "rt_roll_y": rt_roll_y,
        "response_trial_nums": response_trial_nums.astype(int).tolist(),
        "response_trial_nums_left": response_trial_nums_left.astype(int).tolist(),
        "response_trial_nums_right": response_trial_nums_right.astype(int).tolist(),
        "response_roll_x": response_roll_x,
        "response_roll_y": response_roll_y,
        "response_roll_left_x": response_roll_left_x,
        "response_roll_left_y": response_roll_left_y,
        "response_roll_right_x": response_roll_right_x,
        "response_roll_right_y": response_roll_right_y,
        "response_times": response_times.tolist(),
        "response_times_left": response_left.tolist(),
        "response_times_right": response_right.tolist(),
        "session_settings_lines": session_settings_lines,
        "water_cum_x": water_cum_x,
        "water_cum_total_ul": water_cum_total.astype(float).tolist(),
        "water_cum_left_ul": water_cum_left.astype(float).tolist(),
        "water_cum_right_ul": water_cum_right.astype(float).tolist(),
        "water_side_totals_ul": water_side_totals_ul,
        "water_cum_time_x": water_cum_time_x,
        "iti_times": iti_vals.tolist(),
        "iti_times_after_correct": iti_after_correct,
        "iti_times_after_incorrect": iti_after_incorrect,
        "iti_times_after_ew": iti_after_ew,
        "iti_times_after_no_choice": iti_after_no_choice,
        "iti_roll_x": iti_roll_x,
        "iti_roll_y": iti_roll_y,
        "iti_roll_correct_x": iti_roll_correct_x,
        "iti_roll_correct_y": iti_roll_correct_y,
        "iti_roll_incorrect_x": iti_roll_incorrect_x,
        "iti_roll_incorrect_y": iti_roll_incorrect_y,
        "iti_roll_ew_x": iti_roll_ew_x,
        "iti_roll_ew_y": iti_roll_ew_y,
        "iti_roll_no_choice_x": iti_roll_no_choice_x,
        "iti_roll_no_choice_y": iti_roll_no_choice_y,
        "trial_count_x": trial_count_x,
        "trial_count_trial_nums": trial_count_trial_nums,
        "trial_count_y": trial_count_vals.astype(float).tolist(),
        "init_times": init_vals.tolist(),
        "init_trial_nums": init_trial_nums.tolist(),
        "init_roll_x": init_roll_x,
        "init_roll_y": init_roll_y,
        "wait_times": wait_actual.tolist(),
        "wait_min_times": wait_min.tolist(),
        "wait_delta_times": wait_delta.tolist(),
        "wait_delta_left_times": wait_delta_left.tolist(),
        "wait_delta_right_times": wait_delta_right.tolist(),
        "wait_trial_nums": wait_trial_nums.tolist(),
        "wait_trial_nums_left": wait_trial_nums_left.tolist(),
        "wait_trial_nums_right": wait_trial_nums_right.tolist(),
        "wait_delta_x": wait_delta_x,
        "wait_delta_y": wait_delta_y,
        "wait_delta_left_x": wait_delta_left_roll_x,
        "wait_delta_left_y": wait_delta_left_roll_y,
        "wait_delta_right_x": wait_delta_right_roll_x,
        "wait_delta_right_y": wait_delta_right_roll_y,
        "wait_roll_x": wait_roll_x,
        "wait_roll_y": wait_roll_y,
        "wait_times_left": wait_left.tolist(),
        "wait_times_right": wait_right.tolist(),
        "wait_left_x": wait_left_roll_x,
        "wait_left_y": wait_left_roll_y,
        "wait_right_x": wait_right_roll_x,
        "wait_right_y": wait_right_roll_y,
        "slide_x": slide_x,  # rolling performance x
        "slide_y": slide_y,  # rolling performance y
        "ew_roll_x": ew_roll_x,  # rolling EW x
        "ew_roll_y": ew_roll_y,  # rolling EW y
    }
    perf_log(
        "session_metrics",
        start,
        subject=subject,
        session=session_name,
        rows=len(trials),
    )
    return out


@_ttl_lru_cache(maxsize=256)
def multisession_metrics(
    subject: str,
    sessions_back: int,
    start_date: str | None = None,
    smooth: bool = False,
    smooth_window: int = 3,
) -> dict | None:
    """Compute cross-session trend metrics for dashboard time series.

    Args:
        subject: Subject name to analyze.
        sessions_back: Number of recent sessions to include.
        start_date: Optional anchor date in ``YYYY-MM-DD`` format.
        smooth: Whether to apply rolling mean smoothing to output series.
        smooth_window: Rolling window size used when smoothing is enabled.

    Returns:
        A dict of aligned x-axis values and per-session metric series,
        optionally smoothed. Returns ``None`` when no subject data is found.

    Side Effects:
        Reads cached subject/session aggregates and logs timing metrics when
        profiling is enabled.
    """
    start = time.perf_counter()
    df = get_subject_data(subject).copy()
    if df.empty:
        perf_log("multisession_metrics", start, subject=subject, sessions=0)
        return None

    df = df.sort_values("session_name")

    # Parse full session datetimes so same-day sessions keep distinct x positions.
    df["session_dt"] = pd.to_datetime(
        df["session_name"], format="%Y%m%d_%H%M%S", errors="coerce"
    )
    missing_dt = df["session_dt"].isna()
    if missing_dt.any():
        df.loc[missing_dt, "session_dt"] = pd.to_datetime(
            df.loc[missing_dt, "session_name"].astype(str).str.slice(0, 8),
            format="%Y%m%d",
            errors="coerce",
        )
    df["date"] = df["session_dt"].dt.normalize()

    # Filter by date if provided
    if start_date:
        anchor_dt = pd.to_datetime(start_date)
        # Keep sessions <= start_date
        df = df[df["date"] <= anchor_dt]
    else:
        # If no date provided, use the latest session timestamp of this subject.
        if not df.empty:
            anchor_dt = df["session_dt"].iloc[-1]
        else:  # pragma: no cover — df can't be empty here (already checked above)
            perf_log("multisession_metrics", start, subject=subject, sessions=0)
            return None

    # Take the last N sessions
    n = min(sessions_back, len(df))
    d = df.tail(n).copy()
    d_session_names = tuple(d["session_name"].tolist())

    wait_medians = get_wait_medians_for_sessions(subject, d_session_names)
    water_by_session = get_subject_water(subject)

    try:
        x_axis = [
            pd.Timestamp(v).isoformat(sep=" ")
            if pd.notna(v)
            else pd.Timestamp(d["date"].iloc[i]).isoformat(sep=" ")
            for i, v in enumerate(d["session_dt"].tolist())
        ]
    except Exception:  # noqa: BLE001  # pragma: no cover — defensive fallback for unexpected types
        x_axis = [
            pd.Timestamp(v).isoformat(sep=" ") if pd.notna(v) else str(name)
            for v, name in zip(
                d["date"].tolist(), d["session_name"].tolist(), strict=False
            )
        ]

    response_values = d["response_values"].tolist()
    initiation_values = d["initiation_times"].tolist()
    reaction_values = d["reaction_times"].tolist()
    session_names = d["session_name"].tolist()
    session_dates = [
        pd.Timestamp(ts).strftime("%Y-%m-%d %H:%M:%S")
        if pd.notna(ts)
        else (
            f"{name[:4]}-{name[4:6]}-{name[6:8]}"
            if isinstance(name, str) and len(name) >= 8
            else str(name)
        )
        for ts, name in zip(d["session_dt"].tolist(), session_names, strict=False)
    ]
    training_time_hours: list[float] = []
    for name in session_names:
        if (
            isinstance(name, str)
            and len(name) >= 15
            and name[8] == "_"
            and name[9:15].isdigit()
        ):
            hh = int(name[9:11])
            mm = int(name[11:13])
            ss = int(name[13:15])
            training_time_hours.append(hh + (mm / 60.0) + (ss / 3600.0))
        else:
            training_time_hours.append(np.nan)

    ew_rate: list[float] = []
    side_bias: list[float] = []
    for resp_vals in response_values:
        resp = np.asarray(resp_vals)
        choice = np.isin(resp, [-1, 1])
        n_choice = int(choice.sum())
        ew_rate.append(float((~choice).sum() / resp.shape[0]) if resp.size else np.nan)
        if n_choice > 0:
            frac = float((resp[choice] == 1).sum() / n_choice)
            side_bias.append(frac - 0.5)
        else:
            side_bias.append(np.nan)

    median_init: list[float] = []
    for init_vals in initiation_values:
        init = np.asarray(init_vals)
        finite = init[np.isfinite(init)]
        median_init.append(float(np.median(finite)) if finite.size else np.nan)

    median_rt_list: list[float] = []
    for rt_vals in reaction_values:
        if rt_vals is None:
            median_rt_list.append(np.nan)
            continue
        rt_arr = np.asarray(rt_vals).ravel()
        rt_valid = rt_arr[np.isfinite(rt_arr) & (rt_arr > 0) & (rt_arr < 2)]
        median_rt_list.append(float(np.median(rt_valid)) if rt_valid.size else np.nan)

    median_wait_list = [
        wait_medians.get(session_name, np.nan) for session_name in session_names
    ]

    # Water earned per session (from Watering table via DecisionTask)
    water = [
        water_by_session.get(session_name, np.nan) for session_name in session_names
    ]

    # --- Smoothing Logic ---
    res = {
        "perf_easy": np.array(d["performance_easy"]),
        "ew_rate": np.array(ew_rate),
        "n_with_choice": np.array(d["n_with_choice"]),
        "side_bias": np.array(side_bias),
        "median_init": np.array(median_init),
        "median_rt": np.array(median_rt_list),
        "median_wait": np.array(median_wait_list),
        "water": np.array(water),
        "training_time_hours": np.array(training_time_hours),
    }

    out: dict[str, list[Any]] = {}
    if smooth and smooth_window > 1:
        # Simple moving average, handling NaNs
        # We can use pandas rolling on a temporary series for each metric
        for k, v in res.items():
            s = pd.Series(v)
            # Center=True, min_periods=1 to keep tails
            out[k] = (
                s.rolling(window=smooth_window, center=True, min_periods=1)
                .mean()
                .tolist()
            )
    else:
        # Convert back to list
        for k, v in res.items():
            out[k] = np.asarray(v).tolist()

    out["x"] = x_axis
    out["session_dates"] = session_dates
    perf_log(
        "multisession_metrics",
        start,
        subject=subject,
        sessions=len(d),
        smooth=smooth,
        smooth_window=smooth_window,
    )
    return out
