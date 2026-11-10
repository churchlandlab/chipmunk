# chipmunk

Freely moving auditory and visual evidence-accumulation task for mice, adapted from
Raposo et al. 2012 and run with [Bpod Gen 2](https://github.com/sanworks/Bpod_Gen2).
Mice poke a center port to start a trial, watch and/or listen to a stochastic train of
flashes or clicks, and report their choice at a left or right port.

## What's here

| Folder | Contents |
|---|---|
| [`chipmunk/`](chipmunk/README.md) | The original protocol: demonstrator/observer task variants and miniscope synchronization. |
| [`chipmunk_solo/`](chipmunk_solo/README.md) | The Solo protocol for single mice, with camera recording, optional Neuropixels recording through SpikeGLX, stimulus manipulations and passive stimulus replay. |
| [`labdata_plugin/`](labdata_plugin/README.md) | The labdata plugin that imports sessions from both protocols. |
| [`tests/`](tests) | Python tests for the labdata plugin. |
| [`custom_parts/`](custom_parts), [`hardware_setup/`](hardware_setup) | Enclosure and nose-poke designs, parts list and nose-poke assembly instructions, shared by both setups. Parts used only by the original setup (observer side, miniscope) are in [`chipmunk/hardware/`](chipmunk/hardware). |
| [`docs/`](docs/accounting-contract.md) | How the plugin counts trials, choices and rewards. |

## Install

The two protocols are separate Bpod protocols. Clone this repository anywhere and link
each protocol folder you use into Bpod's `Protocols` folder, keeping these exact names:
Bpod settings, the runners and the legacy launchers look for them.

Linux or macOS:

```sh
git clone https://github.com/churchlandlab/chipmunk.git ~/chipmunk
ln -s ~/chipmunk/chipmunk      ~/"Bpod Local/Protocols/chipmunk"
ln -s ~/chipmunk/chipmunk_solo ~/"Bpod Local/Protocols/chipmunk_solo"
```

Windows (a directory junction needs no administrator rights):

```bat
git clone https://github.com/churchlandlab/chipmunk.git C:\code\chipmunk
mklink /J "<Bpod Local>\Protocols\chipmunk" C:\code\chipmunk\chipmunk
mklink /J "<Bpod Local>\Protocols\chipmunk_solo" C:\code\chipmunk\chipmunk_solo
```

Both protocols contain functions with the same names but different behavior, and each
runner adds only its own `Functions` folder to the MATLAB path. Do not add the whole
repository to the path, and restart MATLAB when switching between protocols.

Protocol-specific setup, calibration and training are in the [chipmunk](chipmunk/README.md)
and [chipmunk_solo](chipmunk_solo/README.md) READMEs.

### labdata plugin

Register the plugin in `~/labdata/user_preferences.json`, pointing at this repository's
`labdata_plugin` folder:

```json
"plugins": {
    "chipmunk": "/path/to/chipmunk/labdata_plugin"
}
```

To add a **Chipmunk** page to the labdata dashboard, also install
[chipmunk-dashboard](https://github.com/rojasgabriel/chipmunk-dashboard) in the same Python
environment. Run the plugin tests from `tests/` with `python -m unittest`.
