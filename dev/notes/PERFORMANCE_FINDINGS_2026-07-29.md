# Performance Findings — 2026-07-29

## Test method

The debug-only `PerformanceRecorder` sampled Godot performance monitors four
times per second and recorded every frame slower than 25 ms. Its F10 isolation
benchmark measured the complete mill, then temporarily removed each major
top-level station and measured the same running scene again.

The completed recording is stored locally under:

`dev/performance/logs/2026-07-29 06-43-09/`

Runtime recordings are intentionally excluded from Git because they are
generated evidence rather than project source.

## Baseline

The complete mill averaged:

| Metric | Result |
| --- | ---: |
| FPS | 8.65 |
| Frame time | 116.33 ms |
| Process time | 33.22 ms |
| Physics time | 14.63 ms |
| Draw calls | 25,101 |
| Objects drawn | 47,977 |
| Primitives | 3.67 million |
| Video memory | 1.08 GB |

The slow frames were sustained rather than isolated spikes. Frame time most
strongly tracked process time, draw calls, objects drawn, and primitive count.
Memory usage was not the limiting resource in this recording.

Godot's Jolt active-object and collision-pair monitor values remained zero in
this setup, so those two counters should not be used for diagnosis. The
measured physics-process time was valid and was used instead.

## Isolation results

| Removed section | FPS | Frame time | Draw calls | Interpretation |
| --- | ---: | ---: | ---: | --- |
| Nothing (baseline) | 8.65 | 116.33 ms | 25,101 | Full mill |
| BinSorter | 73.40 | 15.49 ms | 2,866 | Primary bottleneck |
| InclineOutfeed | 27.00 | 35.80 ms | 23,563 | Strong secondary bottleneck |
| SawmillEdger | 13.60 | 72.59 ms | 22,619 | Measurable tertiary bottleneck |
| HeadrigStation | 11.35 | 89.62 ms | — | Smaller contribution |
| LogFeedStation | 10.52 | 94.81 ms | — | Smaller contribution |

The percentages from isolation tests are not additive. Each result measures
the whole scene with one section removed, and runtime state continues changing
between phases.

## Root causes

### Bin sorter

The sorter inventory contained approximately:

- 3,197 nodes
- 2,273 visual instances
- 674 enabled collision shapes
- 75 lights
- 20 bins
- 80 moving overhead lugs with 80 moving collision shapes

Removing it reduced average frame time by 86.7%, process time by 71.5%, and
draw calls by about 88.6%.

Its procedural builders create thousands of individual mesh nodes. Many small
parts use normal shadow casting, the bins create 60 status lights, and the
frame adds approximately 14 high-bay spotlights. The physics loop also updates
all overhead lug visuals and collision transforms and checks every bin.

Continuous board spawning is enabled. The run grew by roughly 493 nodes, 2,950
draw calls, and 4,368 drawn objects between the earlier and later normal
segments. That growth is consistent with generated boards or other runtime
content accumulating and should be verified with explicit board lifecycle
counters.

### Incline outfeed

The section contained approximately:

- 4,456 nodes
- 3,715 visual instances
- 105 physics bodies
- 97 enabled collision shapes

Its nine incline-deck tracks create four individual `AnimatableBody3D` lug
bodies per track. Each running physics tick advances every lug and its
collision shape. Removing the complete section reduced physics time by about
53.3%.

### Sawmill edger

The edger had a smaller but still meaningful impact. It should be profiled
again after the sorter and incline are optimized, because their current load
can hide costs elsewhere.

## Recommended work order

1. Batch the sorter's repeated static geometry by material using
   `MultiMeshInstance3D` or combined meshes.
2. Disable shadow casting on bolts, LEDs, grating, small rails, and other
   details that do not materially improve the scene.
3. Replace the 60 sorter status `OmniLight3D` nodes with emissive indicators.
   Reduce the high-bay spotlight count or share broader lights.
4. Replace the 80 moving sorter collision shapes with simpler conveyor-area
   forces, fewer shared pushers, or analytic board motion.
5. Add board pooling and hard lifecycle limits. Freeze settled boards and
   consider replacing completed stacks with a lightweight aggregate.
6. Update gates, photo eyes, cradles, and status indicators only when their
   state changes instead of repeatedly assigning unchanged values.
7. Simplify incline physics: use fewer shared moving bodies or conveyor forces
   instead of individual physical lugs.
8. Rerun the same F10 isolation benchmark and compare against this baseline.
9. Profile and optimize the sawmill edger after the two dominant sections no
   longer mask it.

## Performance targets

Use the following initial targets for the complete mill:

- Fewer than 5,000 draw calls, with a stretch target below 2,000.
- Stable frame time below 16.7 ms for 60 FPS, or below 33.3 ms for a temporary
  30 FPS milestone.
- No unbounded growth in nodes, physics bodies, or drawn objects during a
  ten-minute unattended run.
- No station should cause more than a 20% frame-time change when removed by
  the isolation benchmark.
