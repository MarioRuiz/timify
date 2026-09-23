# Changelog

## 1.0.0 - 2026-09-23

### Added

- `Timify#measure` and `Timify.measure` time a block. Nested measures and `add` calls inside a block form a span tree: `inclusive` is the whole block and `secs` is the time not already taken by its children.
- `Timify.trace` yields a timer and returns a `Trace` with both the block's value and the timer.
- `Timify.enabled` / `Timify.enabled?` is a process-wide off switch. `TIMIFY_DISABLE` (`1`, `true`, or `on`) sets the default when the class loads.
- `totals` includes `tree`, `grouped_tree`, `wall_time`, and `inclusive`, `p50`, `p95`, and `p99` on each locations, labels, and ranges entry. The printed summary shows the tree, p95, and inclusive time when it differs from self time. Flat sections are ordered slowest first. `totals(group: true)` also prints a grouped span tree.
- `on_slow` runs callbacks when a mark or a block crosses a threshold.
- `on_share` runs callbacks when a child span takes at least a given share of its parent's elapsed time so far.
- `Timify[:name]` reuses a quiet timer from anywhere in the process. `Timify.clear!` drops that registry.
- Each locations, labels, and ranges entry includes `min`, `max`, and `avg`.
- `Timify#reset` clears recorded segments and starts the clock again.
- `output:` sends printed lines to any object that responds to `puts`, or to a Logger via `info`.
- RSpec suite, YARD documentation, and a GitHub Actions build on Ruby 3.2, 3.3, 3.4, and 4.0.

### Fixed

- `add :database` no longer raises `NoMethodError`. Symbol and string labels that read the same are grouped together.
- `show: false` suppresses the initialization line as well as later output.
- `status` defaults to `:on`.
- Time spent while `status` is `:off` is no longer charged to the next `add`. `measure` still runs its block while paused, and records nothing.
- `totals` keeps returning collected data while the timer is paused.
- Call sites come from `caller_locations` instead of a regular expression over `caller`. Paths under the working directory are relative, and the method name is included.
- Elapsed time uses a monotonic clock, so a wall-clock step cannot produce a negative duration.
- Label, location, and range counts are stored separately.
- Each thread keeps its own cursor and span stack. Shared totals are updated under a mutex.

### Changed

- Requires Ruby 3.2 or newer.
- The version constant is `Timify::VERSION`.
- There are still no runtime dependencies. `totals(json: true)` continues to use the standard-library `json`.
- `total_time` is the sum of self time. Parallel threads can make it larger than `wall_time`.
- Library code is split under `lib/timify/` (`span`, `trace`, `registry`, `recording`, `report`) with a short public shell in `lib/timify.rb`.

## 0.0.6 - 2021-05-27

- Last release published before 1.0.0. Earlier changes are in the GitHub history.
