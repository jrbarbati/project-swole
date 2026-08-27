# 5x5ive

A 5×5 barbell progression tracker for iOS. SwiftUI + SwiftData, with the
training logic split into a standalone `SwoleData` package.

## Features

### Working

- **5×5 progression** — clear a session and the lift goes up by its
  increment; miss and it holds; three consecutive misses at the same weight
  trigger a deload.
- **A/B workout alternation**, scheduled automatically from the last
  completed session.
- **Rep logging** — tap a set tile to cycle reps down from target to 0 to
  unlogged; a 1.5s settle debounce means rapid corrections only register the
  final value. Long-press a tile to jump straight to a rep count.
- **Rest timer** — starts automatically after a set settles, duration
  depends on whether that set was a hit or a miss; skippable.
- **Auto-advance** between exercises with a non-blocking completion banner
  and undo.
- **Workout summary** — shows exactly what progression will do to each lift
  next session, before you save.
- **Plate math** — per-side plate breakdown shown next to every target
  weight, for both lb and kg.
- **Warmup ramp** — derived warmup sets (bar, ~55/75/90%) shown per exercise;
  not persisted across app relaunch yet.
- **History** — session log grouped by month, plus a per-lift working-weight
  trend chart.
- **Notes** — free-text notes per session and per exercise.
- **Settings** — editable working weights, units (lb/kg), and appearance
  (dark/light).
- Full dark/light theming; all data persisted locally via SwiftData.

### Planned

- Editable rest durations and deload threshold from Settings (currently
  read-only).
- Persisting warmup-set completion across a relaunch mid-workout.
- Custom flat tab bar as an alternative to the stock iOS tab bar (the
  component exists, just not wired up as the default).
- Broader interactive UI test coverage for the active-workout flow.

## Structure

- `5x5ive/` — the SwiftUI app.
- `SwoleData/` — Swift package with the models, progression/plate/warmup
  logic, and the active-workout view model. Has its own test suite
  (`swift test` from `SwoleData/`).
