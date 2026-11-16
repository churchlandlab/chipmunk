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

Schedule `ChipmunkPassive` as well as `Chipmunk`: populating the task table does
not populate replay rows. The passive key source waits for the corresponding
task session, so pending replays can be retried independently:

```sh
labdata run populate --delete-on-complete -t local --force-submit -- chipmunk.ChipmunkPassive -i labdata
```

Passive ingestion reuses a local MAT when available. Otherwise it retrieves the
registered file through labdata only when `allow_s3_download` is enabled in the
worker's preferences. Disable that preference on Hodgkin for local-only work;
AWS workers enable it to read uploaded files from S3. Avoid a session-date
restriction on retries, since task ingestion may finish after the passive upload.
