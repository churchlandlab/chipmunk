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
