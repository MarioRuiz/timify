# frozen_string_literal: true

RSpec.describe Timify do
  def start_timer(*times, **options)
    queue = times.dup
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) do
      raise "monotonic clock stub exhausted" if queue.empty?

      queue.shift
    end
    name = options.delete(:name) || :job
    Timify.new(name, **{ show: false }.merge(options))
  end

  def add_at_first_site(timer, label = nil)
    timer.add(label)
  end

  def add_at_second_site(timer, label = nil)
    timer.add(label)
  end

  def measure_at_site(timer, label = nil, &block)
    timer.measure(label, &block)
  end

  def source_line(method_name)
    file, line = method(method_name).source_location
    path = File.expand_path(file)
    prefix = "#{Dir.pwd}/"
    relative = path.start_with?(prefix) ? path.delete_prefix(prefix) : path
    "#{relative}:#{line + 1} in #{method_name}"
  end

  describe "VERSION" do
    it "is 1.0.0" do
      expect(Timify::VERSION).to eq("1.0.0")
    end
  end

  describe ".new" do
    it "starts running, with nothing recorded" do
      timer = start_timer(0)

      expect(timer.name).to eq(:job)
      expect(timer.status).to eq(:on)
      expect(timer.show).to eq(false)
      expect(timer.min_time_to_show).to eq(0)
      expect(timer.total).to eq(0.0)
      expect(timer.max_time_spent).to eq(0.0)
      expect(timer.initial_time).to be_a(Time)
    end

    it "prints the init line to stdout when show is left on" do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0)

      expect { Timify.new(:create_user) }.to output(/<create_user> Timify init:/).to_stdout
    end

    it "stays quiet when show is false" do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0)

      expect { Timify.new(:create_user, show: false) }.not_to output.to_stdout
    end

    it "records the call site of new" do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0)
      buffer = StringIO.new
      line = __LINE__; Timify.new(:job, output: buffer)

      expect(buffer.string).to include("spec/timify_spec.rb:#{line}")
    end
  end

  describe "#add" do
    it "returns the seconds since the previous mark and accumulates them" do
      timer = start_timer(0, 1, 1.5)

      expect(add_at_first_site(timer)).to eq(1.0)
      expect(add_at_second_site(timer, :mail)).to eq(0.5)
      expect(timer.total).to eq(1.5)
      expect(timer.max_time_spent).to eq(1.0)
    end

    it "groups symbols and strings that read the same" do
      timer = start_timer(0, 1, 1.5)

      add_at_first_site(timer, :database)
      add_at_second_site(timer, "database")
      label = timer.totals[:labels]["database"]

      expect(label).to include(secs: 1.5, count: 2, min: 0.5, max: 1.0, avg: 0.75, percent: 100)
    end

    it "ignores a blank label" do
      timer = start_timer(0, 1, 1.5)

      add_at_first_site(timer, "")
      add_at_second_site(timer, "   ")

      expect(timer.totals[:labels]).to be_empty
    end

    it "keeps label counts separate when a label matches a call site" do
      timer = start_timer(0, 1, 1.5)
      add_at_first_site(timer)
      location = timer.totals[:locations].keys.first

      add_at_first_site(timer, location)
      report = timer.totals

      expect(report[:locations][location]).to include(count: 2, secs: 1.5)
      expect(report[:labels][location]).to include(count: 1, secs: 0.5)
    end

    it "records the jump from the previous call site" do
      timer = start_timer(0, 1, 1.5)

      add_at_first_site(timer, :database)
      add_at_second_site(timer, :mail)
      report = timer.totals
      first_site = source_line(:add_at_first_site)
      second_site = source_line(:add_at_second_site)

      expect(report[:locations].keys).to eq([first_site, second_site])
      expect(report[:ranges].keys).to eq(["#{first_site} - #{second_site}"])
      expect(report[:ranges].values.first).to include(secs: 0.5, count: 1, percent: 33)
      expect(report[:locations][first_site][:percent]).to eq(67)
    end

    it "prints a segment only when it reaches min_time_to_show, and marks a new maximum" do
      buffer = StringIO.new
      timer = start_timer(0, 0.25, 1, output: buffer, show: true, min_time_to_show: 0.5)

      add_at_first_site(timer)
      expect(buffer.string).not_to include("(New Max)")

      add_at_second_site(timer)
      segment_lines = buffer.string.lines.select { |line| line.include?("%") }

      expect(segment_lines.size).to eq(1)
      expect(segment_lines.first).to include("(New Max)")
      expect(segment_lines.first).to include("0.75")
    end

    it "marks only the segments that set a new maximum" do
      buffer = StringIO.new
      timer = start_timer(0, 1, 1.5, output: buffer, show: true)

      add_at_first_site(timer)
      add_at_second_site(timer, :mail)
      segment_lines = buffer.string.lines.select { |line| line.include?("%") }

      expect(segment_lines[0]).to include("<job>(New Max):")
      expect(segment_lines[0]).to include("(100%): 1.0; 1.0")
      expect(segment_lines[1]).to include("<job><mail>:")
      expect(segment_lines[1]).not_to include("New Max")
      expect(segment_lines[1]).to include("(33%): 1.5; 0.5")
    end
  end

  describe "#status" do
    it "drops time spent paused" do
      timer = start_timer(0, 2, 4, 10, 12)
      expect(timer.add).to eq(2.0)

      timer.status = :off
      expect(timer.add).to eq(0.0)
      expect(timer.measure(:skipped) { :ran }).to eq(:ran)
      expect(timer.total).to eq(2.0)

      timer.status = "on"
      expect(timer.add).to eq(2.0)
      expect(timer.total).to eq(4.0)
      expect(timer.totals[:wall_time]).to eq(6.0)
      expect(timer.totals[:labels]).to be_empty
    end

    it "still returns the report while paused" do
      timer = start_timer(0, 1, 2)
      timer.add(:database)
      timer.status = :off

      expect(timer.totals[:total_time]).to eq(1.0)
      expect(timer.totals[:labels]["database"][:count]).to eq(1)
    end

    it "rejects an unknown status" do
      timer = start_timer(0)

      expect { timer.status = :paused }.to raise_error(ArgumentError, "status must be :on or :off")
    end
  end

  describe "#measure" do
    it "returns the block value and times only the block" do
      timer = start_timer(0, 1, 1.5)

      value = measure_at_site(timer, :database) { :saved }
      report = timer.totals

      expect(value).to eq(:saved)
      expect(timer.total).to eq(1.5)
      expect(report[:labels]["database"]).to include(secs: 0.5, count: 1, min: 0.5, max: 0.5, avg: 0.5)
      expect(report[:locations].values.first).to include(secs: 1.5, count: 2, min: 0.5, max: 1.0, avg: 0.75)
      expect(report[:ranges]).to be_empty
    end

    it "does not count a mark inside the block twice" do
      timer = start_timer(0, 0, 0.5, 1)

      timer.measure(:request) { timer.add(:database) }
      report = timer.totals

      expect(timer.total).to eq(1.0)
      expect(report[:labels]["database"][:secs]).to eq(0.5)
      expect(report[:labels]["request"][:secs]).to eq(0.5)
    end

    it "records inclusive and exclusive times for nested measures with a gap" do
      timer = start_timer(0, 0, 0.25, 0.75, 1.0)

      timer.measure(:request) do
        timer.measure(:database) { :row }
      end
      report = timer.totals

      expect(report[:labels]["request"]).to include(secs: 0.25, inclusive: 1.0)
      expect(report[:labels]["database"]).to include(secs: 0.5, inclusive: 0.5)
      expect(report[:tree].size).to eq(1)
      expect(report[:tree].first[:label]).to eq("request")
      expect(report[:tree].first[:children].map { |child| child[:label] }).to eq([nil, "database"])
    end

    it "does not count the block again on the next add" do
      timer = start_timer(0, 1, 1.5, 2)

      measure_at_site(timer, :database) { :saved }
      expect(add_at_second_site(timer, :mail)).to eq(0.5)

      report = timer.totals
      expect(timer.total).to eq(2.0)
      expect(report[:labels]["database"][:secs]).to eq(0.5)
      expect(report[:labels]["mail"][:secs]).to eq(0.5)
      expect(report[:ranges].values.first[:secs]).to eq(0.5)
    end

    it "records the block when it raises, then continues after it" do
      timer = start_timer(0, 0, 0.5, 1)

      expect { measure_at_site(timer, :boom) { raise "nope" } }.to raise_error(RuntimeError, "nope")

      expect(timer.add).to eq(0.5)
      expect(timer.total).to eq(1.0)
      expect(timer.totals[:labels]["boom"][:secs]).to eq(0.5)
    end

    it "requires a block" do
      timer = start_timer(0)

      expect { timer.measure(:database) }.to raise_error(ArgumentError, "measure requires a block")
    end
  end

  describe ".measure" do
    it "yields a timer and returns it" do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0, 0, 0.5)
      seen = nil

      timer = Timify.measure(:create_user, show: false) do |yielded|
        seen = yielded
        yielded.measure(:database) { :row }
      end

      expect(timer).to be_a(Timify)
      expect(timer).to equal(seen)
      expect(timer.name).to eq(:create_user)
      expect(timer.totals[:labels]["database"][:secs]).to eq(0.5)
    end

    it "requires a block and does not create a timer without one" do
      expect { Timify.measure(:create_user) }.to raise_error(ArgumentError, "measure requires a block")
    end
  end

  describe ".trace" do
    it "returns the block value and the timer" do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0, 0, 0.5)

      trace = Timify.trace(:create_user, show: false) do |timer|
        timer.measure(:database) { :saved }
      end

      expect(trace).to be_a(Timify::Trace)
      expect(trace.value).to eq(:saved)
      expect(trace.timer).to be_a(Timify)
      expect(trace.timer.name).to eq(:create_user)
      expect(trace.totals[:labels]["database"][:secs]).to eq(0.5)
      expect(trace.totals).to eq(trace.timer.totals)
    end

    it "requires a block and propagates exceptions" do
      expect { Timify.trace(:create_user) }.to raise_error(ArgumentError, "trace requires a block")
      expect {
        Timify.trace(:create_user, show: false) { raise "nope" }
      }.to raise_error(RuntimeError, "nope")
    end
  end

  describe ".enabled" do
    after { Timify.enabled = true }

    it "skips recording and init output while disabled, then records again when enabled" do
      Timify.enabled = false
      buffer = StringIO.new
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0, 1, 2, 3)

      expect { Timify.new(:quiet, output: buffer) }.not_to output.to_stdout
      timer = Timify.new(:job, show: false, output: buffer)

      expect(timer.add(:skipped)).to eq(0.0)
      expect(timer.measure(:also_skipped) { :ran }).to eq(:ran)
      expect(timer.total).to eq(0.0)
      expect(timer.totals[:labels]).to be_empty
      expect(buffer.string).to be_empty

      Timify.enabled = true
      expect(timer.add(:mail)).to eq(1.0)
      expect(timer.totals[:labels]["mail"][:secs]).to eq(1.0)
    end

    it "keeps totals recorded before the switch" do
      timer = start_timer(0, 1, 2)
      timer.add(:database)
      Timify.enabled = false

      expect(timer.add(:ignored)).to eq(0.0)
      expect(timer.totals[:labels]["database"][:secs]).to eq(1.0)
      expect(timer.totals[:labels]).not_to have_key("ignored")
    end

    it "reads TIMIFY_DISABLE without leaking enabled state" do
      allow(ENV).to receive(:[]).and_call_original
      %w[1 true ON].each do |value|
        allow(ENV).to receive(:[]).with("TIMIFY_DISABLE").and_return(value)
        expect(Timify.env_disabled?).to eq(true)
      end
      allow(ENV).to receive(:[]).with("TIMIFY_DISABLE").and_return("0")
      expect(Timify.env_disabled?).to eq(false)
      allow(ENV).to receive(:[]).with("TIMIFY_DISABLE").and_return(nil)
      expect(Timify.env_disabled?).to eq(false)
      expect(Timify.enabled?).to eq(true)
    end
  end

  describe "#on_slow" do
    it "fires for add when the segment meets the threshold" do
      timer = start_timer(0, 1.5)
      events = []
      timer.on_slow(1.0) { |event| events << event }

      timer.add(:database)

      expect(events.size).to eq(1)
      expect(events.first).to have_attributes(
        name: :job,
        label: "database",
        secs: 1.5,
        inclusive: 1.5,
        share: nil,
        parent_label: nil
      )
    end

    it "fires for measure using inclusive time" do
      timer = start_timer(0, 0, 0.5, 1.0)
      events = []
      timer.on_slow(0.75) { |event| events << event }

      timer.measure(:request) { timer.add(:database) }

      expect(events.size).to eq(1)
      expect(events.first).to have_attributes(label: "request", secs: 0.5, inclusive: 1.0)
    end

    it "requires a block and rejects a negative threshold" do
      timer = start_timer(0)

      expect { timer.on_slow(1.0) }.to raise_error(ArgumentError, "on_slow requires a block")
      expect { timer.on_slow(-0.1) { } }.to raise_error(ArgumentError, "threshold must be >= 0")
    end
  end

  describe "#on_share" do
    it "fires when a child is at least the ratio of the parent so far" do
      timer = start_timer(0, 0, 0, 0.8, 1.0)
      events = []
      timer.on_share(0.5) { |event| events << event }

      timer.measure(:request) do
        timer.measure(:database) { :row }
      end

      expect(events.size).to eq(1)
      expect(events.first).to have_attributes(
        label: "database",
        parent_label: "request",
        inclusive: 0.8,
        share: 1.0
      )
    end

    it "does not fire for a small child" do
      timer = start_timer(0, 0, 0.9, 1.0, 1.0)
      events = []
      timer.on_share(0.5) { |event| events << event }

      timer.measure(:request) do
        timer.measure(:database) { :row }
      end

      expect(events).to be_empty
    end

    it "rejects a ratio outside 0..1 and requires a block" do
      timer = start_timer(0)

      expect { timer.on_share(0.5) }.to raise_error(ArgumentError, "on_share requires a block")
      expect { timer.on_share(1.5) { } }.to raise_error(ArgumentError, "ratio must be between 0 and 1")
      expect { timer.on_share(-0.1) { } }.to raise_error(ArgumentError, "ratio must be between 0 and 1")
    end

    it "keeps handlers across reset" do
      timer = start_timer(0, 0, 0, 0.8, 1.0, 1.0, 1.0, 1.0, 1.8, 2.0)
      events = []
      timer.on_share(0.5) { |event| events << event }
      timer.measure(:request) { timer.measure(:database) { :a } }
      timer.reset
      timer.measure(:request) { timer.measure(:database) { :b } }

      expect(events.map(&:label)).to eq(%w[database database])
    end
  end

  describe ".[]" do
    after { Timify.clear! }

    it "creates or reuses a quiet timer and clear! empties the registry" do
      first = Timify[:shared]
      second = Timify[:shared]

      expect(first).to equal(second)
      expect(first.show).to eq(false)
      expect(first.name).to eq(:shared)

      Timify.clear!
      expect(Timify[:shared]).not_to equal(first)
    end
  end

  describe "#totals" do
    it "builds the printable summary" do
      timer = start_timer(0, 1.5)
      add_at_first_site(timer, :database)
      report = timer.totals
      location = report[:locations].keys.first

      expect(report[:name]).to eq(:job)
      expect(report[:total_time]).to eq(1.5)
      expect(report[:wall_time]).to eq(1.5)
      expect(report[:started]).to eq(timer.initial_time)
      expect(report[:finished]).to be_a(Time)
      expect(report[:message]).to eq(
        "\n\nTotal time <job>:1.5 wall 1.5\n" \
        "Spans:\n" \
        "\tdatabase inclusive 1.5 self 1.5\n" \
        "Total time by location:\n" \
        "\t#{location}: 1.5 (100%) #1 min 1.5 max 1.5 avg 1.5 p95 1.5\n" \
        "\nTotal time by label:\n" \
        "\tdatabase: 1.5 (100%) #1 min 1.5 max 1.5 avg 1.5 p95 1.5\n" \
        "\n\n"
      )
    end

    it "orders buckets by self time descending and reports percentiles" do
      timer = start_timer(0, 0.5, 1.5)
      add_at_first_site(timer, :fast)
      add_at_second_site(timer, :slow)
      report = timer.totals

      expect(report[:labels].keys).to eq(%w[slow fast])
      expect(report[:labels]["slow"]).to include(p50: 1.0, p95: 1.0, p99: 1.0)
      expect(report[:labels]["fast"]).to include(p50: 0.5, p95: 0.5, p99: 0.5)
    end

    it "computes nearest-rank percentiles across samples" do
      timer = start_timer(0, 0.5, 1.5)
      add_at_first_site(timer, :database)
      add_at_second_site(timer, :database)
      label = timer.totals[:labels]["database"]

      expect(label).to include(p50: 0.5, p95: 1.0, p99: 1.0)
    end

    it "marks samples_truncated when the sample cap is hit" do
      stub_const("Timify::MAX_SAMPLES", 2)
      timer = start_timer(0, 1, 2, 3)
      3.times { timer.add(:database) }
      label = timer.totals[:labels]["database"]

      expect(label[:count]).to eq(3)
      expect(label[:samples_truncated]).to eq(true)
      expect(label).to include(min: 1.0, max: 1.0, secs: 3.0)
    end

    it "returns JSON and still prints when show is on" do
      buffer = StringIO.new
      timer = start_timer(0, 1, output: buffer, show: true)
      timer.add(:database)

      parsed = JSON.parse(timer.totals(json: true))

      expect(buffer.string).to include("Total time <job>:1.0 wall 1.0")
      expect(parsed["name"]).to eq("job")
      expect(parsed["total_time"]).to eq(1.0)
      expect(parsed["wall_time"]).to eq(1.0)
      expect(parsed["labels"]["database"]["avg"]).to eq(1.0)
      expect(parsed["started"]).to be_a(String)
    end

    it "reports an empty timer" do
      timer = start_timer(0)
      report = timer.totals

      expect(report[:total_time]).to eq(0.0)
      expect(report[:wall_time]).to eq(0.0)
      expect(report[:locations]).to eq({})
      expect(report[:labels]).to eq({})
      expect(report[:ranges]).to eq({})
      expect(report[:tree]).to eq([])
      expect(report[:grouped_tree]).to eq([])
      expect(report[:finished]).to eq(report[:started])
      expect(report[:message]).to include("Total time <job>:0.0 wall 0.0")
      expect(report[:message]).not_to include("Total time by label:")
      expect(report[:message]).not_to include("Spans:")
      expect(report[:message]).not_to include("Grouped spans:")
    end

    it "merges sibling spans with the same label in grouped_tree" do
      timer = start_timer(0, 0, 0.3, 0.3, 0.5)
      timer.measure(:database) { :a }
      timer.measure(:database) { :b }
      report = timer.totals

      expect(report[:tree].size).to eq(2)
      expect(report[:tree].map { |node| node[:secs] }).to eq([0.3, 0.2])
      expect(report[:grouped_tree].size).to eq(1)
      expect(report[:grouped_tree].first).to include(
        label: "database",
        secs: 0.5,
        inclusive: 0.5,
        count: 2,
        children: []
      )
      expect(report[:message]).not_to include("Grouped spans:")

      grouped = timer.totals(group: true)
      expect(grouped[:message]).to include("Grouped spans:")
      expect(grouped[:message]).to include("database inclusive 0.5 self 0.5 #2")
    end
  end

  describe "#reset" do
    it "clears segments and restarts the clock without changing configuration" do
      buffer = StringIO.new
      timer = start_timer(0, 5, 5, 6, 7, name: :create_user, show: false, min_time_to_show: 0.4, output: buffer)
      timer.add(:database)
      timer.status = :off

      timer.reset

      expect(timer.name).to eq(:create_user)
      expect(timer.show).to eq(false)
      expect(timer.min_time_to_show).to eq(0.4)
      expect(timer.output).to equal(buffer)
      expect(timer.status).to eq(:on)
      expect(timer.total).to eq(0.0)
      expect(timer.max_time_spent).to eq(0.0)
      expect(timer.totals[:locations]).to eq({})
      expect(timer.add).to eq(1.0)
      expect(timer.total).to eq(1.0)
    end

    it "keeps on_slow handlers" do
      timer = start_timer(0, 1, 1, 2)
      events = []
      timer.on_slow(0.5) { |event| events << event }
      timer.add(:first)
      timer.reset
      timer.add(:second)

      expect(events.map(&:label)).to eq(%w[first second])
    end
  end

  describe "output" do
    it "writes to an IO" do
      buffer = StringIO.new
      timer = start_timer(0, 1, output: buffer, show: true)

      timer.add(:database)
      timer.totals

      expect(buffer.string).to include("<job> Timify init:")
      expect(buffer.string).to include("<job><database>(New Max):")
      expect(buffer.string).to include("Total time by label:")
      expect(buffer.string).to include("Spans:")
      expect(buffer.string).to include("p95")
    end

    it "writes to a Logger with info" do
      buffer = StringIO.new
      logger = Logger.new(buffer)
      timer = start_timer(0, 1, output: logger, show: true)

      timer.add

      expect(buffer.string).to include("INFO")
      expect(buffer.string).to include("<job> Timify init:")
      expect(buffer.string).to include("(New Max)")
    end
  end

  describe "a real clock" do
    it "records a non-negative segment" do
      timer = Timify.new(:real, show: false)
      elapsed = timer.add

      expect(elapsed).to be >= 0
      expect(timer.max_time_spent).to eq(elapsed)
      expect(timer.total).to eq(elapsed)
    end
  end

  describe "threads" do
    it "lets several threads measure and add on one timer" do
      timer = Timify.new(:threaded, show: false)
      threads = 4.times.map do
        Thread.new do
          timer.measure(:work) { timer.add(:step) }
        end
      end
      threads.each(&:join)
      report = timer.totals

      expect(report[:labels]["work"][:count]).to eq(4)
      expect(report[:labels]["step"][:count]).to eq(4)
      expect(timer.total).to be >= 0
    end
  end
end
