# labdata plugin

Imports Chipmunk sessions from both protocols into labdata and adds a Chipmunk tab to `labdata dashboard`.

## Setup

In `~/labdata/user_preferences.json`:

```json
"plugins": {
    "chipmunk": "/path/to/chipmunk/labdata_plugin"
}
```

For the dashboard tab, install in the same environment:

```sh
pip install -U "labdata[dashboard]" dash "plotly<7"
```

## Tables

| Table | |
|---|---|
| `Chipmunk` | One row per session: duration and task settings |
| `Chipmunk.TrialParameters` | Stimulus and reward settings for each trial |
| `Chipmunk.Trial` | Event times, pokes and outcome for each trial |
| `ChipmunkPassive` | One row per passive replay |
| `ChipmunkPassive.Trial` | One row per replayed trial, linked to its source trial in `Chipmunk.Trial` |

Importing a session also adds its weight, notes, water and `DecisionTask` row in labdata.

All times are in seconds on the task's Bpod clock, replay included.

## Populating

```python
from labdata import plugins
chipmunk = plugins['chipmunk']
chipmunk.Chipmunk.populate()
chipmunk.ChipmunkPassive.populate()  # after Chipmunk
```

`make_kwargs=dict(download_videos=False)` skips downloading the camera videos.

`ChipmunkPassive` is populated separately from `Chipmunk`, so if you schedule
ingestion, schedule both. A replay is only picked up once its task session is in
`Chipmunk`. Don't restrict retries to a session date, because the task session
may be ingested after the replay was uploaded.

Passive ingestion uses the replay's MAT file if it is already on the machine.
If it isn't, the file is downloaded only when `allow_s3_download` is `true` in
that machine's labdata preferences. Otherwise the populate stops with a
`FileNotFoundError`.
