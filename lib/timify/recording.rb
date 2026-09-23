# frozen_string_literal: true

class Timify
  # Retained samples per bucket. min, max, count, and the sums stay exact
  # after this cap; percentiles then use the retained prefix.
  MAX_SAMPLES = 10_000

  THREAD_STATE_KEY = :__timify_thread_state__

  # Pauses or resumes recording.
  # Time spent paused is dropped: the next segment on each thread starts when
  # the timer is turned back on. +:off+ does not erase segments already recorded.
  #
  # @param value [Symbol, String] +:on+ or +:off+
  # @return [Symbol]
  # @raise [ArgumentError] when +value+ is not +:on+ or +:off+
  def status=(value)
    normalized = value.respond_to?(:to_sym) ? value.to_sym : nil
    unless %i[on off].include?(normalized)
      raise ArgumentError, "status must be :on or :off"
    end

    synchronize do
      if @status == :on && normalized == :off
        @pause_started = monotonic
      elsif @status == :off && normalized == :on
        now = monotonic
        @paused_monotonic += now - @pause_started if @pause_started
        @pause_started = nil
        @resume_at = now
        thread_state[:last_mark] = now
      end
      @status = normalized
    end
  end

  # Records the time elapsed since the previous mark on this thread.
  # Inside {#measure}, the mark becomes a child span instead of being counted
  # again as part of the parent's self time. The first call on a thread has no
  # range. Later calls record the jump from the previous call site to this one.
  # When {.enabled} is +false+, returns +0.0+ and records nothing.
  #
  # @param label [Object, nil] optional name. Symbols and strings with the
  #   same text are grouped together. +nil+ and blank strings are ignored.
  # @return [Float] self time of this segment, or +0.0+ when paused or disabled
  def add(label = nil)
    return 0.0 unless self.class.enabled?

    location = caller_location
    normalized = normalize_label(label)
    time_spent, events = synchronize do
      paused? ? [0.0, []] : record_add(location, normalized)
    end
    deliver(events)
    time_spent
  end

  # Records the time spent inside +block+ and returns the block's value.
  # Time from the previous mark up to this call is stored first, when it is
  # longer than zero, as an unlabeled segment. The block is a span: its
  # inclusive time is the whole block, and its self time is what nested
  # {#measure} and {#add} calls did not take. If the block raises, the span is
  # still recorded and the exception propagates. While paused, or when
  # {.enabled} is +false+, the block runs and nothing is recorded.
  #
  # @param label [Object, nil] same rules as {#add}
  # @yield the work to time
  # @return [Object] the block's return value
  # @raise [ArgumentError] when no block is given
  def measure(label = nil)
    raise ArgumentError, "measure requires a block" unless block_given?
    return yield unless self.class.enabled?

    location = caller_location
    normalized = normalize_label(label)
    opened = false
    events = []
    synchronize do
      unless paused?
        open_measure(location, normalized)
        opened = true
      end
    end
    return yield unless opened

    begin
      yield
    ensure
      synchronize { events = close_measure }
      deliver(events)
    end
  end

  # Registers a callback invoked when a segment is at least +seconds+ long.
  # {#add} compares the segment. {#measure} compares the block's inclusive
  # time. Callbacks run after the timer has recorded the segment, and several
  # callbacks can be registered.
  #
  # @param seconds [Numeric]
  # @yield [event]
  # @yieldparam event [Timify::Event]
  # @return [Timify] self
  # @raise [ArgumentError] when no block is given or +seconds+ is negative
  def on_slow(seconds, &block)
    raise ArgumentError, "on_slow requires a block" unless block

    threshold = Float(seconds)
    raise ArgumentError, "threshold must be >= 0" if threshold.negative?

    synchronize { @slow_handlers << [threshold, block] }
    self
  end

  # Registers a callback invoked when a child span's inclusive time is at least
  # +ratio+ of the parent's elapsed time so far. Fires for labeled {#measure}
  # and {#add} children, not for root spans or unlabeled gap spans. Several
  # callbacks can be registered. They run after the segment is recorded,
  # outside the timer mutex.
  #
  # @param ratio [Numeric] share from +0+ to +1+ inclusive
  # @yield [event]
  # @yieldparam event [Timify::Event] includes +share+ and +parent_label+
  # @return [Timify] self
  # @raise [ArgumentError] when no block is given or +ratio+ is outside +0..1+
  def on_share(ratio, &block)
    raise ArgumentError, "on_share requires a block" unless block

    value = Float(ratio)
    unless value >= 0.0 && value <= 1.0
      raise ArgumentError, "ratio must be between 0 and 1"
    end

    synchronize { @share_handlers << [value, block] }
    self
  end

  # Clears recorded segments and starts the clock again.
  # Keeps {#name}, {#show}, {#min_time_to_show}, {#output}, {#on_slow}, and
  # {#on_share} callbacks. The timer is left running even if it was paused.
  # Other threads drop their old cursor on the next mark.
  #
  # @return [Timify] self
  def reset
    synchronize do
      @generation += 1
      @status = :on
      @locations = {}
      @labels = {}
      @ranges = {}
      @roots = []
      @total = 0.0
      @max_time_spent = 0.0
      @initial_time = Time.now
      @finished_time = @initial_time
      @paused_monotonic = 0.0
      @pause_started = nil
      @resume_at = nil
      now = monotonic
      @origin_mark = now
      @last_record_mark = now
      thread_table[object_id] = {
        generation: @generation,
        last_mark: now,
        stack: [],
        location_prev: nil
      }
    end
    self
  end

  private

  def synchronize(&block)
    @mutex.synchronize(&block)
  end

  def paused?
    @status == :off
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def thread_table
    Thread.current[THREAD_STATE_KEY] ||= {}
  end

  def thread_state
    state = thread_table[object_id]
    if state.nil? || state[:generation] != @generation
      state = {
        generation: @generation,
        last_mark: monotonic,
        stack: [],
        location_prev: nil
      }
      thread_table[object_id] = state
    end
    state[:last_mark] = @resume_at if @resume_at && state[:last_mark] < @resume_at
    state
  end

  def normalize_label(label)
    return nil if label.nil?

    text = label.to_s.strip
    text.empty? ? nil : text
  end

  def record_add(location, label)
    state = thread_state
    now = monotonic
    time_spent = (now - state[:last_mark]).to_f
    state[:last_mark] = now
    record_segment(location, label, time_spent, inclusive: time_spent, range: true, state: state)
    parent = state[:stack].last
    attach_span(state, Span.new(label: label, location: location).tap { |span|
      span.inclusive = time_spent
      span.exclusive = time_spent
    })
    events = slow_events(label, location, time_spent, time_spent)
    events.concat(share_events(label, location, time_spent, time_spent, parent, now))
    [time_spent, events]
  end

  def open_measure(location, label)
    state = thread_state
    now = monotonic
    gap = (now - state[:last_mark]).to_f
    if gap.positive?
      state[:last_mark] = now
      record_segment(location, nil, gap, inclusive: gap, range: true, state: state)
      attach_span(state, Span.new(label: nil, location: location).tap { |span|
        span.inclusive = gap
        span.exclusive = gap
      })
    end
    state[:stack] << Span.new(label: label, location: location, started_mark: now)
    state[:last_mark] = now
  end

  def close_measure
    state = thread_state
    span = state[:stack].pop
    finished = monotonic
    inclusive = (finished - span.started_mark).to_f
    exclusive = inclusive - span.children.sum(&:inclusive)
    exclusive = 0.0 if exclusive.negative?
    span.inclusive = inclusive
    span.exclusive = exclusive
    state[:last_mark] = finished
    record_segment(span.location, span.label, exclusive, inclusive: inclusive, range: false, state: state)
    state[:location_prev] = span.location
    parent = state[:stack].last
    attach_span(state, span)
    events = slow_events(span.label, span.location, exclusive, inclusive)
    events.concat(share_events(span.label, span.location, exclusive, inclusive, parent, finished))
    events
  end

  def attach_span(state, span)
    if (parent = state[:stack].last)
      parent.children << span
    else
      @roots << span
    end
  end

  def record_segment(location, label, exclusive, inclusive:, range:, state:)
    @total += exclusive
    @finished_time = Time.now
    @last_record_mark = state[:last_mark]
    new_max = exclusive > @max_time_spent
    @max_time_spent = exclusive if new_max

    update_bucket(@locations, location, exclusive, inclusive)
    update_bucket(@labels, label, exclusive, inclusive) if label
    if range && state[:location_prev]
      update_bucket(@ranges, "#{state[:location_prev]} - #{location}", exclusive, inclusive)
    end
    state[:location_prev] = location if range

    return if exclusive < @min_time_to_show

    emit(segment_message(label, new_max, location, location_percent(location), exclusive))
  end

  def update_bucket(buckets, key, exclusive, inclusive)
    bucket = buckets[key] ||= empty_bucket
    bucket[:secs] += exclusive
    bucket[:inclusive] += inclusive
    bucket[:count] += 1
    bucket[:min] = exclusive if bucket[:min].nil? || exclusive < bucket[:min]
    bucket[:max] = exclusive if bucket[:max].nil? || exclusive > bucket[:max]
    if bucket[:samples].length < MAX_SAMPLES
      bucket[:samples] << exclusive
    else
      bucket[:samples_truncated] = true
    end
    bucket
  end

  def empty_bucket
    {
      secs: 0.0,
      inclusive: 0.0,
      count: 0,
      min: nil,
      max: nil,
      samples: [],
      samples_truncated: false
    }
  end

  def location_percent(location)
    return 0 if @total.zero?

    ((@locations[location][:secs] / @total) * 100).round
  end

  def slow_events(label, location, secs, inclusive)
    @slow_handlers.filter_map do |threshold, handler|
      next if inclusive < threshold

      [handler, Event.new(name: @name, label: label, location: location, secs: secs, inclusive: inclusive)]
    end
  end

  def share_events(label, location, secs, inclusive, parent, now)
    return [] if parent.nil? || label.nil?

    parent_elapsed = (now - parent.started_mark).to_f
    return [] if parent_elapsed <= 0.0

    share = inclusive / parent_elapsed
    @share_handlers.filter_map do |ratio, handler|
      next if share < ratio

      [
        handler,
        Event.new(
          name: @name,
          label: label,
          location: location,
          secs: secs,
          inclusive: inclusive,
          share: share,
          parent_label: parent.label
        )
      ]
    end
  end

  def deliver(events)
    events.each { |handler, event| handler.call(event) }
  end

  def segment_message(label, new_max, location, percent, time_spent)
    label_text = label ? "<#{label}>" : ""
    max_text = new_max ? "(New Max)" : ""
    "<#{@name}>#{label_text}#{max_text}: #{location} (#{percent}%): " \
      "#{format_secs(@total)}; #{format_secs(time_spent)}"
  end

  def emit(message)
    return unless @show

    if @output.respond_to?(:info) && !@output.respond_to?(:puts)
      @output.info(message)
    else
      @output.puts(message)
    end
  end
end
