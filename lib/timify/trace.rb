# frozen_string_literal: true

class Timify
  # Result of {.trace}: the block's return value and the timer used to measure it.
  class Trace
    # @return [Object] the block's return value
    attr_reader :value

    # @return [Timify] the timer created for the block
    attr_reader :timer

    # @param value [Object]
    # @param timer [Timify]
    def initialize(value:, timer:)
      @value = value
      @timer = timer
    end

    # Delegates to {Timify#totals} on {#timer}.
    #
    # @param options [Hash] keyword arguments accepted by {Timify#totals}
    # @return [Hash, String]
    def totals(**options)
      @timer.totals(**options)
    end
  end
end
