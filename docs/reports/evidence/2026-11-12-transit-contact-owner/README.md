# Contact-owner candidate evidence (not production publication)

Concatenate the ordered byte parts in `parts.json` to recover the exact original ZIP. Verify the whole-archive SHA256, ZIP CRC, and every raw member against `members.json`. The archive contains its original embedded manifest. No recompression or red-result removal occurred.

The tested candidate source is preserved inside `final-source/`; this evidence-only commit does not install it into the game. Original mixed-boundary congestion remains unresolved. Standalone interface checks are not an upgrade-completion or whole-system reachability result. The companion report details failed, passed and untested boundaries.
