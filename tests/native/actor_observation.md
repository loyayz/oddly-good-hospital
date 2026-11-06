# Actor observation isolation

Run from the repository with a local Godot executable:

```sh
python3 -B tests/native/actor_observation.py --output /absolute/new-result.json
```

The tool loads the complete baseline and current `waiting_dependencies.gd`, plus current `BodyIndex`, with script-local preload names. A conservative same-floor spatial adapter replaces the native bridge; the real `BodyIndex` still performs exact rectangle filtering. This is not a full hospital, native Boost integration or STAFF-69 pass.

Independent expected dirty sets and baseline comparison cover initial/unchanged state, same-rectangle updates, old/new locations, floor changes, creation/deletion, strict edge contact, non-subscribed third parties, removed subscribers and clear/re-subscribe. Facts supplied through the index must remain unchanged.

The benchmark uses 160 actors and 16 waiters, resets both source and observer before each window, and alternates baseline/current order. It records every window for unchanged and one-changing-actor modes. This measures observation overhead with the explicit adapter, not whole-step or frame performance. Whole-world freshness and complete owner notification remain integration responsibilities.
