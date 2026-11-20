# Changelog

## 0.1.2 — 2026-11-20

- Add a persistent pin preference. The panel stays open by default; unpin to restore click-away dismissal.
- Add an explicit close-panel button without quitting the app.
- Add English and Simplified Chinese interfaces, following the system by default with an immediate language picker in Settings.
- Localize diagnostic states, repair/restore confirmations, progress, and copied reports.
- Add Chinese documentation and bilingual layout/language regression coverage.

## 0.1.1 — 2026-11-20

- Fix a menu bar panel that could be clipped by the screen or its hosting window.
- Explicitly size the popover to the available area of the screen containing its menu bar icon.
- Keep long content inside a vertical scroll area, with the header and footer visible.
- Clamp placement at screen edges, including displays with negative coordinates.
- Add constrained AppKit hosting checks, a native popover check, and geometry regression coverage.

## 0.1.0 — 2026-11-20

- First public preview: local connection diagnostics, backed-up pairing cache repair, restore, and privacy-filtered reports.
