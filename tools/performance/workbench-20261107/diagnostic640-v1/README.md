# 640 construction coarse diagnostics, v1

Not run. No A-source edits. No engine, compile, functional, or performance tests executed in preparing these artifacts. Only prepare.py was run to generate insertion-only fixture and validate exact marker removal. Original 640wide constructor and all business expressions retained, including the original static/dynamic short circuit, candidates, invalid-position fallback, sync calls and actor/room/facility counts. Marker and timer overhead means these are attribution data, not plain performance. A successful constructor is NOT a qualified legal input: placeholder visitors, guidance/current-rule adaptation and independent validation remain separate.

Parent should first create an independently verified copy of locked A's 1388-file manifest at `diagnostic640-v1/project` (preserve source bytes/modes/native.so, no .godot caches copied), and freeze its manifest. No copy is created by this package. Then:

```bash
D=/workspace/scratch/6962cc21ddf3/ogh-performance-20261107/diagnostic640-v1
python3 -B "$D/install.py" "$D/project"
# Parent runs ordinary headless editor import on this project under its existing
# isolated-profile watchdog to establish global class/import metadata, retaining logs.
# Do not time import as fixture construction. Syntax failures remain tool failures.
python3 -B "$D/run.py" "$D/project" "$D/run01"
```

The final command uses a 120-second process-group watchdog, TERM then KILL after 10 seconds, and isolated HOME/XDG. Run only after current attribution is done. Install only accepts a project inside this new root and verifies original fixture hash before writing. No automatic retries or engine invocation during install.

Markers cover factory enter/exit; each floor enter/exit; rooms/service-object and props boundaries; space enter/exit; staff/patient/visitor stage boundaries and every16 actor; every32 candidate heartbeat; first candidate exhaustion; cumulative sync_actor count/us. Sync clocks wrap exactly the three original calls. No prewarming/caching/extra spatial queries or new placement algorithm added. Candidate cursor is shared per floor; 43×43=1849 total candidate locations per floor. A timeout between two coarse markers only localizes to that interval; add fine static/dynamic instrumentation in a later bounded diagnostic if needed.

Result classification: continuing cursors = progress, not proof of eventual completion; first exhaustion = this candidate grid/ordering failed, not universal640 impossibility; error output or missing driver markers = inspect loading/tool failures. Preserve failure and original fallback behavior; never promote errors plus repeated fallback positions to legal input. `result.json` explicitly keeps legal_input_qualified=false and performance_pass=null even on returncode0.
