"""Native Streamlit presentation of the full Chipmunk Dash dashboard."""

from __future__ import annotations

import os
from collections.abc import Callable
from importlib import import_module
from typing import Any

import plotly.graph_objects as go

_SINGLE_FIGURE_IDS = (
    "frac-correct",
    "p-right",
    "chrono",
    "session-perf",
    "init-line",
    "init-hist",
    "wait-delta-line",
    "wait-delta-hist",
    "wait-floor-line",
    "wait-floor-hist",
    "response-time-line",
    "response-time",
    "iti-dist",
    "trial-count-time",
    "water-cumulative",
    "iti-rolling",
)

_MULTI_FIGURE_IDS = (
    "performance",
    "ew-rate",
    "side-bias",
    "init-times",
    "median-rt",
    "median-wait",
    "trial-counts",
    "water",
    "training-time",
)

_OVERVIEW_ROWS = (
    ("frac-correct", "p-right", "chrono", "session-perf"),
    ("trial-count-time", "water-cumulative"),
)

_TIMING_ROWS = (
    ("init-line", "init-hist"),
    ("wait-delta-line", "wait-delta-hist"),
    ("wait-floor-line", "wait-floor-hist"),
    ("response-time-line", "response-time"),
    ("iti-rolling", "iti-dist"),
)

_MULTI_ROWS = (
    ("performance", "ew-rate", "side-bias", "trial-counts"),
    ("init-times", "median-wait", "median-rt", "water", "training-time"),
)

_TALL_FIGURES = frozenset(
    {
        "session-perf",
        "init-line",
        "wait-delta-line",
        "wait-floor-line",
        "response-time-line",
        "water-cumulative",
        "init-hist",
        "wait-delta-hist",
        "wait-floor-hist",
        "response-time",
        "iti-dist",
        "trial-count-time",
        "training-time",
        "iti-rolling",
    }
)


def _data_provider():
    """Return the live or fixture-backed data module."""
    module = ".debug_data" if os.getenv("CHIPMUNK_UI_DEBUG", "0") == "1" else ".data"
    return import_module(module, __package__)


def _create_renderers() -> dict[str, Callable[..., Any]]:
    """Create the exact figure renderers registered by the Dash app."""
    from .app import create_app

    app = create_app()
    return app.chipmunk_renderers


def _session_date(session_name: str) -> str | None:
    """Convert a standard session name to an ISO date string."""
    if len(session_name) < 8 or not session_name[:8].isdigit():
        return None
    raw = session_name[:8]
    return f"{raw[:4]}-{raw[4:6]}-{raw[6:8]}"


def _clear_data_caches(data: Any) -> None:
    """Clear cache-aware data functions after an explicit refresh."""
    for name in (
        "get_all_subjects",
        "get_subjects_with_recent_sessions",
        "get_sessions",
        "get_subjects_for_date",
        "session_metrics",
        "multisession_metrics",
    ):
        func = getattr(data, name, None)
        cache_clear = getattr(func, "cache_clear", None)
        if callable(cache_clear):
            cache_clear()


def _figure_map(
    ids: tuple[str, ...], figures: tuple[go.Figure, ...]
) -> dict[str, go.Figure]:
    """Associate callback outputs with the component ids used by the Dash layout."""
    if len(figures) != len(ids):
        raise ValueError(f"Expected {len(ids)} figures, received {len(figures)}")
    return dict(zip(ids, figures, strict=True))


def _show_figure_rows(
    st: Any,
    figures: dict[str, go.Figure],
    rows: tuple[tuple[str, ...], ...],
    *,
    namespace: str,
) -> None:
    """Render the same figure groupings used by the Dash dashboard."""
    for row in rows:
        columns = st.columns(len(row), gap="small")
        for column, figure_id in zip(columns, row, strict=True):
            figure = figures[figure_id]
            figure.update_layout(height=320 if figure_id in _TALL_FIGURES else 300)
            with column:
                st.plotly_chart(
                    figure,
                    width="stretch",
                    key=f"chipmunk-{namespace}-{figure_id}",
                    config={"displayModeBar": False},
                )


def _available_dates(sessions_by_subject: dict[str, list[str]]) -> list[str]:
    """Return reverse-chronological dates represented in selected sessions."""
    return sorted(
        {
            iso_date
            for sessions in sessions_by_subject.values()
            for session in sessions
            if (iso_date := _session_date(session)) is not None
        },
        reverse=True,
    )


def _subject_options(
    subjects: list[str], recent_subjects: set[str], *, recent_only: bool
) -> list[str]:
    """Filter the subject picker to mice active in the last seven days."""
    if recent_only:
        return [subject for subject in subjects if subject in recent_subjects]
    return subjects


def render_dashboard(schema: Any = None) -> None:
    """Render full Chipmunk dashboard parity inside the labdata Streamlit app."""
    del schema  # The data layer resolves the project activated by labdata.
    import streamlit as st

    data = _data_provider()
    load_renderers = st.cache_resource(_create_renderers)
    renderers = load_renderers()

    title_col, refresh_col = st.columns([6, 1])
    with title_col:
        st.title("Chipmunk Dashboard")
    with refresh_col:
        if st.button("Refresh", icon=":material/refresh:", key="chipmunk-refresh"):
            _clear_data_caches(data)
            st.rerun()

    subjects = data.get_all_subjects()
    if not subjects:
        st.info("No Chipmunk subjects were found for this project.")
        return

    recent = data.get_subjects_with_recent_sessions()
    with st.container(border=True):
        recent_only = st.toggle(
            "Recent mice only",
            value=True,
            key="chipmunk-recent-subjects-only",
            help="Only show mice with a session in the last 7 days.",
        )
        subject_options = _subject_options(
            subjects,
            recent,
            recent_only=recent_only,
        )
        if not subject_options:
            st.info(
                "No mice have sessions in the last 7 days. "
                "Turn off Recent mice only to see every mouse."
            )
            return

        default_subject = subject_options[0]
        selected_subjects = st.multiselect(
            "Subjects",
            subject_options,
            default=[default_subject],
            key=(
                "chipmunk-subjects-recent" if recent_only else "chipmunk-subjects-all"
            ),
        )
        if not selected_subjects:
            st.info("Select at least one subject.")
            return

        sessions_by_subject = {
            subject: data.get_sessions(subject) for subject in selected_subjects
        }
        available_dates = _available_dates(sessions_by_subject)
        if not available_dates:
            st.info("No sessions were found for the selected subjects.")
            return

        primary_subject = selected_subjects[0]
        date_col, session_col, smooth_col, window_col, history_col = st.columns(
            [1.2, 1.4, 0.8, 0.7, 1.2],
            gap="small",
        )
        with date_col:
            selected_date = st.selectbox(
                "Session date",
                available_dates,
                key="chipmunk-session-date",
            )

        primary_sessions = [
            session
            for session in sessions_by_subject[primary_subject]
            if _session_date(session) == selected_date
        ]
        with session_col:
            primary_session = (
                st.selectbox(
                    f"{primary_subject} session",
                    primary_sessions,
                    index=max(0, len(primary_sessions) - 1),
                    key="chipmunk-primary-session",
                )
                if primary_sessions
                else None
            )
        with smooth_col:
            smooth = st.toggle("Smooth", value=False, key="chipmunk-smooth")
        with window_col:
            smooth_window = st.number_input(
                "Window",
                min_value=1,
                max_value=10,
                value=3,
                disabled=not smooth,
                key="chipmunk-smooth-window",
            )
        with history_col:
            sessions_back = st.slider(
                "Sessions back",
                min_value=1,
                max_value=30,
                value=10,
                key="chipmunk-sessions-back",
            )

    if primary_session is None:
        st.info(f"{primary_subject} has no session on {selected_date}.")
        return

    selected_recent = [subject for subject in selected_subjects if subject in recent]
    selected_older = [subject for subject in selected_subjects if subject not in recent]

    single_figures = _figure_map(
        _SINGLE_FIGURE_IDS,
        renderers["single"](
            selected_recent,
            selected_older,
            primary_session,
            0,
            selected_date,
        ),
    )
    settings = renderers["settings"](
        selected_recent,
        selected_older,
        primary_session,
        0,
        selected_date,
    )

    st.subheader("Single Session", divider="gray")
    overview_tab, timing_tab = st.tabs(["Overview", "Timing"])
    with overview_tab:
        _show_figure_rows(
            st,
            single_figures,
            _OVERVIEW_ROWS,
            namespace="single-overview",
        )
        with st.expander("Session settings"):
            st.code(settings, language=None)
    with timing_tab:
        _show_figure_rows(
            st,
            single_figures,
            _TIMING_ROWS,
            namespace="single-timing",
        )

    multi_figures = _figure_map(
        _MULTI_FIGURE_IDS,
        renderers["multi"](
            selected_recent,
            selected_older,
            int(sessions_back),
            selected_date,
            ["smooth"] if smooth else [],
            int(smooth_window),
            0,
        ),
    )
    st.subheader("Multi Session", divider="gray")
    _show_figure_rows(
        st,
        multi_figures,
        _MULTI_ROWS,
        namespace="multi",
    )
