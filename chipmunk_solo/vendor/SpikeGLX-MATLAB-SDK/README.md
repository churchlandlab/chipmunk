SpikeGLX-MATLAB-SDK
===================

### What

The SDK lets MATLAB (Windows and Linux) applications communicate with
SpikeGLX versions 20220101 and later:

* Set/get parameters.
* Start/Stop runs.
* Start/stop writing.
* Fetch data in real time.
* Everything you need to integrate SpikeGLX into your workflow.

There's an included closed-loop latency test program; used to obtain these
results with an NP 2.0 probe:

![CPP API Latency](cpp_latency.png)

### Who

The SDK is developed by Bill Karsh and Jennifer Colonell of the Tim Harris lab.
Initially hosted/funded by HHMI. Currently supported by {NIH, Wellcome Trust}
grants via {JHU, UCL}.

### Precompiled Components

Everything you need is included in the package and precompiled. You would
only need to compile yourself if you need to use a very old MATLAB version.

### Building in Linux

I build using Linux MATLAB R2021b.

### Building in Windows

I build using MS Visual Studio C++ 2015, and MATLAB R2018b.

### Licensing

Use is subject to Janelia Research Campus Software license terms:
[http://license.janelia.org/license](http://license.janelia.org/license).


_fin_

