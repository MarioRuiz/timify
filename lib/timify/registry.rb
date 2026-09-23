# frozen_string_literal: true

class Timify
  REGISTRY_MUTEX = Mutex.new

  # Returns the timer registered under +name+, creating it on first use.
  # Registered timers start with +show: false+ so fetching one does not print.
  #
  # @param name [Object]
  # @return [Timify]
  def self.[](name)
    REGISTRY_MUTEX.synchronize do
      registry[name] ||= new(name, show: false)
    end
  end

  # Drops every timer created through {.[]}.
  #
  # @return [void]
  def self.clear!
    REGISTRY_MUTEX.synchronize { @registry = {} }
  end

  class << self
    private

    def registry
      @registry ||= {}
    end
  end
end
