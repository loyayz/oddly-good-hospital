# Prefix/window metering v2 review notes

Not yet engine-qualified or executed as baseline. v1 unchanged. The new loop runs exactly prefix_steps + steps original full steps. At the fixed prefix boundary it snapshots cumulative business counters and actual population, then starts the sample wall clock. Prefix wall time and whole-loop wall time remain reported, while percentiles use only predefined sample indices. Sample clinical work uses cumulative differences and excludes reception in the external series gate. Total business counters/events and all raw per-step markers remain available.

Run-level environment files capture host load, memory and cgroup quota/stat before each repeat. Each run is a fresh engine process with independent user directories. Runtime caches warm only through the same real prefix; OS caches are not claimed cold. run_engine process-group watchdog and raw logs remain authoritative for exit/timeout.

An interrupted series must not be rerun blindly: it refuses existing run directories. Inspect each status/result and resume missing repeat explicitly using its recorded run_engine command and a new absent directory; preserve all earlier complete/incomplete runs. No B, speedup, GPU/FPS or formal whole-product pass is represented.
