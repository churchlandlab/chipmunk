"""Optional timing logs when ``CHIPMUNK_PROFILE=1``."""

from __future__ import annotations

import logging
import os
import time

_PROFILE_PERF = os.getenv("CHIPMUNK_PROFILE", "0") == "1"
_LOGGER = logging.getLogger(__name__)


def perf_log(label: str, start_time: float, **fields) -> None:
    if not _PROFILE_PERF:
        return
    elapsed_ms = (time.perf_counter() - start_time) * 1000
    details = " ".join(f"{k}={v}" for k, v in fields.items())
    msg = f"perf {label} elapsed_ms={elapsed_ms:.1f}"
    if details:
        msg = f"{msg} {details}"
    _LOGGER.info(msg)
