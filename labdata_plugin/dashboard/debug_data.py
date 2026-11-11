"""Fixture-backed data provider for database-free UI debugging."""

from __future__ import annotations

from datetime import date, timedelta

from .fixture_data import make_multisession_metrics, make_session_metrics

_SUBJECTS = ["GRB050", "GRB058", "GRB059", "GRB061", "GRB062", "GRB063"]
_RECENT = {"GRB050", "GRB058", "GRB059"}
_BASE_DATE = date(2026, 5, 22)


def _subject_offset(subject: str) -> int:
    return sum(ord(ch) for ch in subject) % 7


def get_all_subjects() -> list[str]:
    return list(_SUBJECTS)


def get_subjects_with_recent_sessions(days: int = 7) -> set[str]:
    return set(_RECENT)


def get_sessions(subject: str) -> list[str]:
    offset = _subject_offset(subject)
    sessions = []
    for day_back in range(12, -1, -1):
        session_date = _BASE_DATE - timedelta(days=day_back)
        hour = 9 + ((offset + day_back) % 6)
        minute = (offset * 7 + day_back * 3) % 60
        sessions.append(f"{session_date:%Y%m%d}_{hour:02d}{minute:02d}17")
    return sessions


def get_subjects_for_date(raw_date: str) -> list[str]:
    return [
        subject
        for subject in _SUBJECTS
        if any(s.startswith(raw_date) for s in get_sessions(subject))
    ]


def session_metrics(subject: str, session_name: str) -> dict:
    return make_session_metrics(
        n=80,
        seed=42 + _subject_offset(subject),
        session_name=session_name,
        settings_lines=[
            "debug fixture data",
            f"session: {session_name}",
            "rewarded modality: audio",
            "audio stim range: 5.00 to 15.00",
            "visual stim range: 5.00 to 15.00",
        ],
    )


def multisession_metrics(
    subject: str,
    sessions_back: int = 10,
    start_date: str | None = None,
    smooth: bool = False,
    smooth_window: int = 3,
) -> dict:
    del start_date, smooth, smooth_window
    count = max(1, int(sessions_back or 10))
    offset = _subject_offset(subject)
    metrics = make_multisession_metrics(n=count, seed=42 + offset)
    session_dates = [
        (_BASE_DATE - timedelta(days=count - idx - 1)).isoformat()
        for idx in range(count)
    ]
    metrics["session_dates"] = session_dates
    metrics["x"] = [
        f"{day}T{9 + ((idx + offset) % 6):02d}:30:00"
        for idx, day in enumerate(session_dates)
    ]
    return metrics


def prewarm_multisession_cache(*_args, **_kwargs) -> None:
    return None
