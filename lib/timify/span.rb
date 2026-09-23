# frozen_string_literal: true

class Timify
  # One timed block or mark in the tree returned by {Timify#totals}.
  class Span
    attr_accessor :label, :location, :inclusive, :exclusive, :children, :started_mark

    def initialize(label:, location:, started_mark: nil)
      @label = label
      @location = location
      @started_mark = started_mark
      @inclusive = 0.0
      @exclusive = 0.0
      @children = []
    end

    # @return [Hash]
    def to_h
      {
        label: label,
        location: location,
        secs: exclusive,
        inclusive: inclusive,
        children: children.map(&:to_h)
      }
    end
  end

  # A segment that crossed an {Timify#on_slow} or {Timify#on_share} threshold.
  class Event
    # @return [Object]
    attr_reader :name

    # @return [String, nil]
    attr_reader :label

    # @return [String]
    attr_reader :location

    # @return [Float] self time of the segment
    attr_reader :secs

    # @return [Float] inclusive time of the segment
    attr_reader :inclusive

    # @return [Float, nil] child inclusive / parent elapsed so far; set for
    #   {Timify#on_share} events, +nil+ for {Timify#on_slow}
    attr_reader :share

    # @return [String, nil] label of the parent span; set for {Timify#on_share}
    #   events, +nil+ for {Timify#on_slow}
    attr_reader :parent_label

    # @param name [Object]
    # @param label [String, nil]
    # @param location [String]
    # @param secs [Float]
    # @param inclusive [Float]
    # @param share [Float, nil]
    # @param parent_label [String, nil]
    def initialize(name:, label:, location:, secs:, inclusive:, share: nil, parent_label: nil)
      @name = name
      @label = label
      @location = location
      @secs = secs
      @inclusive = inclusive
      @share = share
      @parent_label = parent_label
    end
  end
end
