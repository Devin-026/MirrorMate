# Contributing

MirrorMate aims to make a narrow, reversible repair understandable. Keep diagnostics read-only and repairs explicit.

- Run `swift run MirrorMateChecks` and build the app before proposing a change.
- Exercise transaction failures with simulated services and temporary folders. Do not make tests reset the developer’s live pairing.
- Preserve both the original and current caches when changing recovery behavior.
- Refuse symlinked or unrecognized cache paths; do not broaden privileges or automatically sign the user out.
- Keep raw logs and personal device information out of shareable reports.
- Describe which macOS and iOS versions were actually tested. Mark untested compatibility as unknown.
- Keep the English and Simplified Chinese interfaces concise, accessible, and native to macOS.

The first release is intentionally small. New repairs should have independent evidence, a supported detection rule, a backup/recovery story, and meaningful failure tests.
