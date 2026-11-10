# chipmunk

Freely moving auditory and visual evidence-accumulation task for mice, adapted from
Raposo et al. 2012. Runs on [Bpod Gen 2](https://github.com/sanworks/Bpod_Gen2).

| Folder | |
|---|---|
| [`chipmunk/`](chipmunk/README.md) | Original protocol (demonstrator/observer) |
| [`chipmunk_solo/`](chipmunk_solo/README.md) | Solo protocol |
| [`labdata_plugin/`](labdata_plugin/README.md) | labdata plugin for both protocols |
| [`tests/`](tests) | Plugin tests |
| [`custom_parts/`](custom_parts), [`hardware_setup/`](hardware_setup) | Hardware designs, parts lists, assembly instructions |

## Install

Clone the repo and link each protocol you use into `Bpod Local/Protocols`, keeping the folder names.

```sh
git clone https://github.com/churchlandlab/chipmunk.git ~/chipmunk
ln -s ~/chipmunk/chipmunk      ~/"Bpod Local/Protocols/chipmunk"
ln -s ~/chipmunk/chipmunk_solo ~/"Bpod Local/Protocols/chipmunk_solo"
```

On Windows, use `mklink /J` instead of `ln -s`.

Don't add the whole repo to the MATLAB path; the two protocols have functions with the same names. Restart MATLAB when switching protocols.

### labdata plugin

In `~/labdata/user_preferences.json`:

```json
"plugins": {
    "chipmunk": "/path/to/chipmunk/labdata_plugin"
}
```

For the dashboard page, install [chipmunk-dashboard](https://github.com/rojasgabriel/chipmunk-dashboard).

## Tests

- Plugin: `python -m unittest` in `tests/`. Runs on GitHub on every push.
- Solo task: `chipmunk_solo/tests/run_rig_checks.sh` on a rig. See [testing](chipmunk_solo/docs/testing.md).
