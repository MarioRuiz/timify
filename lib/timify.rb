# frozen_string_literal: true

require_relative "timify/version"
require_relative "timify/span"
require_relative "timify/trace"
require_relative "timify/registry"
require_relative "timify/recording"
require_relative "timify/report"

# Measures elapsed time between points in Ruby code.
#
# {#measure} blocks nest. A parent span's +inclusive+ time is the whole block,
# and its +secs+ (self time) is what the children did not already take.
# {#add} marks the time since the previous mark on this thread. Intervals use
# a monotonic clock. {#totals} still reports +started+ and +finished+ as Time
# objects.
#
# Each thread has its own cursor and span stack. Totals are shared and guarded
# by a mutex, so two threads can mark the same timer. +total_time+ is the sum
# of self time and can exceed +wall_time+ when threads overlap.
#
# {.enabled} is a process-wide switch. When it is +false+, every timer is a
# no-op: {#add} and {#measure} record nothing, and {#initialize} does not
# print. The default comes from +TIMIFY_DISABLE+ (+1+, +true+, or +on+, case
# insensitive). Setting {.enabled=} overrides that for the rest of the process.
#
# @example Time a few nested steps without printing
#   timer = Timify.new(:create_user, show: false)
#   timer.measure(:request) do
#     timer.measure(:database) { :saved }
#     timer.add(:mail)
#   end
#   timer.totals
class Timify
  class << self
    # Process-wide recording switch. When +false+, every timer is a no-op.
    # Defaults from +TIMIFY_DISABLE+ when the class loads; {.enabled=} overrides
    # that for the rest of the process.
    #
    # @return [Boolean]
    attr_accessor :enabled

    # @return [Boolean] whether recording is currently enabled
    def enabled?
      !!@enabled
    end

    # Whether +TIMIFY_DISABLE+ is set to a disabling value (+1+, +true+, or
    # +on+, case insensitive). Used as the default for {.enabled} when the
    # class loads.
    #
    # @return [Boolean]
    def env_disabled?
      value = ENV["TIMIFY_DISABLE"]
      return false if value.nil?

      %w[1 true on].include?(value.to_s.strip.downcase)
    end
  end

  self.enabled = !env_disabled?

  # @return [Object] name given when the timer was created
  attr_reader :name

  # @return [Float] self time recorded so far, excluding paused time
  attr_reader :total

  # @return [Time] wall-clock time when the timer was created or last {#reset}
  attr_reader :initial_time

  # @return [Float] longest single self-time segment since creation or {#reset}
  attr_reader :max_time_spent

  # @return [Symbol] +:on+ while the timer is recording, +:off+ while it is paused
  attr_reader :status

  # Minimum segment length, in seconds, required before {#add} or {#measure}
  # prints. Shorter segments are still recorded. Defaults to +0+.
  #
  # @return [Numeric]
  attr_accessor :min_time_to_show

  # When +false+, the timer stays silent. Segments are still recorded.
  # Defaults to +true+.
  #
  # @return [Boolean]
  attr_accessor :show

  # Where printed lines are sent. An object that responds to +puts+ is written
  # with +puts+. An object that responds to +info+ and not +puts+, such as a
  # Logger, is written with +info+. Defaults to +$stdout+.
  #
  # @return [#puts, #info]
  attr_accessor :output

  # @param name [Object] name included in reports and printed lines
  # @param min_time_to_show [Numeric] shortest segment that should be printed
  # @param show [Boolean] whether to print the init line, segments, and summaries
  # @param output [#puts, #info] destination for printed lines
  def initialize(name, min_time_to_show: 0, show: true, output: $stdout)
    @name = name
    @min_time_to_show = min_time_to_show
    @show = show
    @output = output
    @mutex = Mutex.new
    @generation = 0
    @slow_handlers = []
    @share_handlers = []
    @resume_at = nil
    @pause_started = nil
    @paused_monotonic = 0.0
    reset
    emit("<#{@name}> Timify init:<#{@initial_time}>. Location: #{caller_location}") if self.class.enabled?
  end

  # Creates a timer, yields it, and returns it after the block finishes.
  # The block's return value is not returned; use {#measure} on the yielded
  # timer when you need that value, or use {.trace} to keep both. If the block
  # raises, the exception propagates and the timer is not returned.
  #
  # @param name [Object]
  # @param options [Hash] keyword arguments accepted by {#initialize}
  # @yield [timer] the new timer
  # @yieldparam timer [Timify]
  # @return [Timify]
  # @raise [ArgumentError] when no block is given
  def self.measure(name, **options)
    raise ArgumentError, "measure requires a block" unless block_given?

    timer = new(name, **options)
    yield timer
    timer
  end

  # Creates a timer, yields it, and returns a {Trace} with the block's value
  # and the timer. If the block raises, the exception propagates and no
  # {Trace} is returned.
  #
  # @param name [Object]
  # @param options [Hash] keyword arguments accepted by {#initialize}
  # @yield [timer] the new timer
  # @yieldparam timer [Timify]
  # @return [Timify::Trace]
  # @raise [ArgumentError] when no block is given
  def self.trace(name, **options)
    raise ArgumentError, "trace requires a block" unless block_given?

    timer = new(name, **options)
    value = yield timer
    Trace.new(value: value, timer: timer)
  end
end
