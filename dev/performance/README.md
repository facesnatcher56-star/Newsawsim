# Performance recording

`PerformanceRecorder` is a debug-only autoload. It records whenever the game runs from a debug build and does nothing in release builds.

Each run creates a timestamped folder under `dev/performance/logs/` containing:

- `samples.csv`: engine counters sampled four times per second. The first five seconds are labeled `startup`; steady-state summary arrays reset after that warmup.
- `spikes.csv`: every frame slower than 25 ms (below 40 FPS), with the engine state at that moment.
- `inventory.csv`: per-section node, script, physics, render-instance, MultiMesh, and estimated triangle counts.
- `summary.csv`: average, median, p95, p99, and maximum frame/process/physics measurements, written when the run stops normally.
- `isolation.csv`: controlled machine-removal comparisons, created only after running the isolation benchmark.

## Normal recording

Run the game normally and reproduce the choppy section. Stop the game normally so the summary is written.

## Controlled station-isolation benchmark

Start a fresh game session, leave the game alone, and press **F10**. The recorder measures a baseline and then temporarily removes one major top-level mill section at a time. Each section is restored before the next measurement. Stop the run after the console reports that the benchmark finished.

This benchmark changes the live test scene temporarily and should be run in a fresh disposable session. The resulting differences are measured combined contributions under that workload; they can include interactions between connected machines.

The logs are intentionally ignored by Git.
