# chipmunk

Freely moving auditory and visual evidence-accumulation task for mice, adapted from
Raposo et al. 2012. Runs on [Bpod Gen 2](https://github.com/sanworks/Bpod_Gen2).

| Folder | |
|---|---|
| [`chipmunk/`](chipmunk/README.md) | Original protocol (demonstrator/observer) |
| [`chipmunk_solo/`](chipmunk_solo/README.md) | Solo protocol |
| [`labdata_plugin/`](labdata_plugin/README.md) | labdata plugin and dashboard for both protocols |
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

Don't add the whole repo to the MATLAB path; the two protocols have functions with the same names.

### labdata plugin

In `~/labdata/user_preferences.json`:

```json
"plugins": {
    "chipmunk": "/path/to/chipmunk/labdata_plugin"
}
```

For the Chipmunk tab in `labdata dashboard`, install in the same environment:

```sh
pip install -U "labdata[dashboard]" dash "plotly<7"
```

## Tests

- Plugin and dashboard: `pytest tests`. Runs on GitHub on every push.
- Solo task: MATLAB checks in `chipmunk_solo/tests`. See [testing](chipmunk_solo/docs/testing.md).

## License

MIT, except `chipmunk_solo/vendor/SpikeGLX-MATLAB-SDK`, which keeps its own license.
