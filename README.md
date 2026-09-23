# Timify

[![Gem Version](https://badge.fury.io/rb/timify.svg)](https://rubygems.org/gems/timify)
[![CI](https://github.com/MarioRuiz/timify/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/MarioRuiz/timify/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/MarioRuiz/timify/badge.svg?branch=master)](https://coveralls.io/github/MarioRuiz/timify?branch=master)
![Gem](https://img.shields.io/gem/dt/timify)
![GitHub commit activity](https://img.shields.io/github/commit-activity/y/MarioRuiz/timify)
![GitHub last commit](https://img.shields.io/github/last-commit/MarioRuiz/timify)
![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/MarioRuiz/timify)

Timify measures elapsed time from one point in your Ruby code to another and reports it by call site, label, span tree, and the jump between call sites. Use it to see which part of a piece of code is taking the time.

Requires Ruby 3.2 or newer. The gem has no runtime dependencies.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "timify"
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install timify

## Usage

The walkthrough below times a small "create user" path: open a timer, mark steps, nest spans, share the timer across call sites, then read the report.

### Create a timer

```ruby
require "logger"

timer = Timify.new(
  :create_user,
  show: true,
  min_time_to_show: 0.3,
  output: Logger.new($stdout)
)
```

* `show` prints the initialization line, each recorded segment, and the summary from `totals`. It defaults to `true`. Set it to `false` and the timer stays silent while it keeps recording.
* `min_time_to_show` is the shortest segment, in seconds, that gets printed. Shorter segments are still recorded. It defaults to `0`.
* `output` is where those lines go. An IO receives `puts`. A Logger, or anything else that responds to `info` and not `puts`, receives `info`. It defaults to `$stdout`.
* `status` is `:on` by default. Set it to `:off` to pause, and back to `:on` to resume.

You can also set the options after construction:

```ruby
timer = Timify.new(:create_user)
timer.show = false
timer.min_time_to_show = 0.5
```

### Mark steps with `add`

`add` records the time since the previous mark (creation, reset, end of the last `add`/`measure`, or resume) and returns that segment as a Float number of seconds. Pass an optional label to group those segments. A symbol and a string that read the same, such as `:database` and `"database"`, are one group. `nil` and a blank string are ignored.

```ruby
timer = Timify.new(:create_user, show: false)
timer.add
sleep 0.01
database_seconds = timer.add(:database)
timer.add(:mail) if database_seconds > 0.2
```

The first `add` has no range. Each later `add` records the jump from the previous call site to the current one.

A printed segment looks like this. Paths under the working directory are relative, and the method name is included when present. The percentage is that call site's share of the self time recorded so far. The two numbers are the timer's total self seconds, then this segment's self seconds. `(New Max)` appears when this segment is the longest one so far. A 1.0 second `:database` segment followed by a 0.5 second `:mail` segment prints:

```text
<create_user><database>(New Max): app/create_user.rb:10 in create (100%): 1.0; 1.0
<create_user><mail>: app/create_user.rb:20 in create (33%): 1.5; 0.5
```

### Nested `measure`

`measure` times the given block and returns the block's value. Nested `measure` and `add` calls form a span tree. A parent span's inclusive time is the whole block; its self time (`secs`) is what the children did not already take. When time has passed since the previous mark, that gap is stored first as an unlabeled segment (printed as `(gap)`), and the block is stored next. A later `add` does not count the block again.

`add` and `measure` share one timeline. A mark made inside the block keeps its own slice, and `measure` records only the remainder, so the same seconds are not stored twice. The block itself is not a range. If the block raises, the time until the exception is still recorded and the exception propagates. While the timer is paused, the block runs and nothing new is recorded.

```ruby
timer = Timify.new(:create_user, show: false)
timer.measure(:request) do
  timer.measure(:database) { :saved }
  timer.add(:mail)
end
```

With clocks that open `request` at 0, open `database` at 0.25 (after a 0.25 gap), close `database` at 0.75, and close `request` at 1.0, the labels report `request` as 0.25 self / 1.0 inclusive and `database` as 0.5 self / 0.5 inclusive. The tree children under `request` are the gap and `database`.

`Timify.measure` builds a timer, yields it, and returns it when the block completes. It does not return the block's value.

```ruby
timer = Timify.measure(:create_user, show: false) do |job|
  job.measure(:database) { :saved }
  job.add(:mail)
end

timer.totals
```

### `Timify.trace`

`Timify.trace` is the same setup as `Timify.measure`, but returns a `Timify::Trace` that keeps both the block's value and the timer. Options are the same keyword args as `Timify.new`. If the block raises, the exception propagates and no `Trace` is returned.

```ruby
trace = Timify.trace(:create_user, show: false) do |timer|
  timer.measure(:database) { :saved }
end

trace.value  # => :saved
trace.timer  # => the Timify instance
trace.totals # => same as trace.timer.totals
```

`Timify.measure`, `Timify.trace`, and instance `measure` raise `ArgumentError` when no block is given.

### Reuse a named timer

`Timify[:name]` returns a quiet process-wide timer (`show: false` on first create) so two distant call sites can contribute to the same report. `Timify.clear!` drops that registry.

```ruby
def load_row
  Timify[:create_user].measure(:database) { :row }
end

def send_mail
  Timify[:create_user].add(:mail)
end

load_row
send_mail
Timify[:create_user].totals
Timify.clear!
```

### Pause recording

`status` is `:on` by default. Set it to `:off` to pause, and back to `:on` to resume. Paused time is not charged to the next segment. The block still runs. `totals` still returns what was recorded before the pause.

```ruby
timer = Timify.new(:create_user, show: false)
timer.add(:setup)

timer.status = :off
result = timer.measure(:skipped) { :still_runs } # => :still_runs, nothing recorded
timer.add(:also_skipped)                         # => 0.0

timer.status = :on
timer.add(:mail) # charges only time since resume, not the pause
```

### Turn Timify off for the whole process

`Timify.enabled` is a process-wide switch. When it is `false`, every timer is a no-op: `add` returns `0.0` and records nothing, `measure` still runs its block and returns the value but records nothing and does not print, and `new` skips the init line. `totals` still returns whatever was recorded before the switch. `Timify.enabled?` returns the current flag.

The default comes from the environment variable `TIMIFY_DISABLE` when the class loads. Values `1`, `true`, and `on` (case insensitive) disable recording. Setting `Timify.enabled = true` afterwards overrides the env var for the rest of the process. The default is `true` when the variable is unset.

```ruby
# shell: TIMIFY_DISABLE=1 bundle exec ruby app.rb
# or in Ruby, after the gem has loaded:
Timify.enabled = false
timer = Timify.new(:create_user)              # no init line
timer.measure(:database) { :saved }           # => :saved, nothing recorded
timer.totals                                  # empty report

Timify.enabled = true
timer.add(:mail)                              # recording resumes
```

### React to slow or dominant spans

`on_slow` registers a callback that runs when a segment is at least the given number of seconds long. For `add`, the segment length is compared. For `measure`, the block's inclusive time is compared. Several callbacks can be registered. They run after the segment is recorded, outside the timer mutex.

```ruby
timer = Timify.new(:create_user, show: false)
timer.on_slow(0.5) do |event|
  warn "#{event.name} #{event.label} took #{event.inclusive}s at #{event.location}"
end

timer.measure(:database) { :row }
```

`on_share` registers a callback that runs when a child span's inclusive time is at least `ratio` of the parent's elapsed time so far (`ratio` is a Float from `0` to `1` inclusive). It fires for labeled `measure` and `add` children, not for root spans or unlabeled gap spans. Parent elapsed is the time from the parent's start to this moment, so a child that already dominates the parent so far still fires even though the parent has not closed. Several callbacks can be registered and are kept across `reset`, same as `on_slow`. They run outside the timer mutex.

The event is a `Timify::Event` with the usual fields plus `share` (Float) and `parent_label`. For `on_slow` events those two fields are `nil`.

```ruby
timer = Timify.new(:create_user, show: false)
timer.on_share(0.5) do |event|
  warn "#{event.label} took #{(event.share * 100).round}% of #{event.parent_label}"
end

# Parent opens at 0, database closes at 0.8, parent closes at 1.0 → share 0.8, fires.
timer.measure(:request) do
  timer.measure(:database) { :row }
end
```

### Read the report with `totals`

`totals` returns a Hash. `secs` is self time (what this span or bucket spent itself). `inclusive` is wall time covered by that span including children. Flat sections (`locations`, `labels`, `ranges`) are ordered slowest-first by self time.

`totals(group: true)` also prints a `Grouped spans:` section after the chronological Spans section; the default `group: false` does not. `grouped_tree` is always in the hash either way: sibling nodes with the same label are merged recursively (sums `secs` and `inclusive`, sets `count`, keeps the first location, groups children the same way). Nil labels (gaps) merge with other nil labels. Order of first appearance is preserved.

`totals(json: true)` returns the same report as a JSON string and still prints the summary when `show` is true. In JSON, hash keys and a symbol `name` are strings, and `started` and `finished` are time strings.

The hash contains:

* `name` — the name passed to `new`
* `total_time` — sum of self time recorded so far, excluding paused time. Parallel threads can make this larger than `wall_time`.
* `wall_time` — monotonic time from the start to the latest mark, minus pauses
* `started` — wall-clock `Time` when the timer was created or last reset
* `finished` — wall-clock `Time` of the latest recorded segment. It equals `started` until the first segment.
* `tree` — chronological top-level spans. Each node has `label`, `location`, `secs`, `inclusive`, and `children`.
* `grouped_tree` — merged sibling labels as described above
* `message` — the printable summary
* `locations` — one entry for each relative (or absolute) `path:line in method` where `add` or `measure` was called
* `labels` — one entry for each label
* `ranges` — one entry for each jump from one call site to the next. A `measure` block is not itself a range; the approach up to that call is, once a previous call site exists.

Each of `locations`, `labels`, and `ranges` contains `secs`, `inclusive`, `percent`, `count`, `min`, `max`, `avg`, `p50`, `p95`, `p99`, and optionally `samples_truncated` when more than 10_000 samples were seen for that bucket.

Elapsed time uses a monotonic clock. `started` and `finished` stay wall-clock times. Each thread keeps its own cursor and span stack; shared totals are updated under a mutex.

After two `add` calls that took 1.0 seconds and then 0.5 seconds:

```ruby
report = timer.totals
report[:total_time]  # => 1.5
report[:labels].keys # => ["database", "mail"]  (slowest first)
report[:labels]["database"] # => { secs: 1.0, inclusive: 1.0, percent: 67, count: 1, ... }
```

`message` is the text `totals` prints when `show` is true:

```text
Total time <create_user>:1.5 wall 1.5
Spans:
	database inclusive 1.0 self 1.0
	mail inclusive 0.5 self 0.5
Total time by location:
	app/create_user.rb:10 in create: 1.0 (67%) #1 min 1.0 max 1.0 avg 1.0 p95 1.0
	app/create_user.rb:20 in create: 0.5 (33%) #1 min 0.5 max 0.5 avg 0.5 p95 0.5

Total time by label:
	database: 1.0 (67%) #1 min 1.0 max 1.0 avg 1.0 p95 1.0
	mail: 0.5 (33%) #1 min 0.5 max 0.5 avg 0.5 p95 0.5

Total time by range:
	app/create_user.rb:10 in create - app/create_user.rb:20 in create: 0.5 (33%) #1 min 0.5 max 0.5 avg 0.5 p95 0.5
```

When inclusive time differs from self time, bucket lines append ` inclusive N`.

Two sibling `measure(:database)` calls that took 0.3 seconds and 0.2 seconds keep two nodes in `tree` and one merged node in `grouped_tree`:

```ruby
report = timer.totals(group: true)
report[:tree].size            # => 2
report[:grouped_tree].first   # => { label: "database", ..., secs: 0.5, inclusive: 0.5, count: 2, children: [] }
# message includes "Grouped spans:" then "database inclusive 0.5 self 0.5 #2"

json = timer.totals(json: true) # => JSON string of the same report
```

### Start over with `reset`

`reset` drops every recorded segment and starts the clock again. The name, `show`, `min_time_to_show`, `output`, `on_slow`, and `on_share` callbacks stay as they are. A paused timer is left running.

```ruby
timer = Timify.new(:create_user, show: false)
timer.add(:database)
timer.reset
timer.totals[:total_time] # => 0.0
timer.add(:mail)          # new clock from reset
```

## Development

```sh
bundle install
bundle exec rake
bundle exec yard
```

`rake` runs the RSpec suite. Development dependencies are Rake, RSpec, and YARD. CI runs that suite on Ruby 3.2, 3.3, 3.4, and 4.0.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MarioRuiz/timify.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
