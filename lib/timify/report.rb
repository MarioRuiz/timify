# frozen_string_literal: true

class Timify
  # Returns the report for every segment recorded so far.
  # Pausing the timer does not hide this report. When {#show} is true, the
  # printable summary is also written to {#output}.
  #
  # +locations+, +labels+, and +ranges+ are ordered by self time, slowest
  # first. Each entry contains:
  # - +secs+ [Float] accumulated self time
  # - +inclusive+ [Float] accumulated inclusive time
  # - +percent+ [Integer] share of {#total}, rounded to the nearest percent
  # - +count+ [Integer] number of segments
  # - +min+ [Float] shortest self time
  # - +max+ [Float] longest self time
  # - +avg+ [Float] +secs / count+
  # - +p50+, +p95+, +p99+ [Float] nearest-rank percentiles of self time
  # - +samples_truncated+ [Boolean] present when the percentile sample was capped
  #
  # +tree+ is the chronological list of top-level spans. Each node has
  # +label+, +location+, +secs+, +inclusive+, and +children+.
  # +grouped_tree+ merges sibling nodes with the same label recursively:
  # +secs+ and +inclusive+ are summed, +count+ is how many spans were merged,
  # and +children+ are grouped the same way. Order of first appearance is
  # preserved. +wall_time+ is monotonic time from the start to the latest mark,
  # minus pauses.
  #
  # @param json [Boolean] when true, return the same report as a JSON string
  # @param group [Boolean] when true, print a +Grouped spans:+ section after
  #   the chronological Spans section. +grouped_tree+ is always included in
  #   the hash either way.
  # @return [Hash, String]
  def totals(json: false, group: false)
    report = synchronize { build_report(group: group) }
    emit(report[:message])

    if json
      require "json"
      report.to_json
    else
      report
    end
  end

  private

  def caller_location
    format_location(caller_locations(2, 1).first)
  end

  def format_location(loc)
    path = relative_path(loc.absolute_path || loc.path)
    method = loc.base_label
    suffix = method.nil? || method.empty? ? "" : " in #{method}"
    "#{path}:#{loc.lineno}#{suffix}"
  end

  def relative_path(path)
    return path if path.nil? || path.empty?

    expanded = File.expand_path(path)
    prefix = "#{Dir.pwd}/"
    expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : expanded
  end

  def build_report(group: false)
    wall = @last_record_mark - @origin_mark - @paused_monotonic
    wall = 0.0 if wall.negative?
    tree = @roots.map(&:to_h)
    report = {
      name: @name,
      total_time: @total.to_f,
      wall_time: wall.to_f,
      started: @initial_time,
      finished: @finished_time,
      tree: tree,
      grouped_tree: group_tree(tree),
      locations: report_buckets(@locations),
      labels: report_buckets(@labels),
      ranges: report_buckets(@ranges)
    }
    report[:message] = summary_message(report, group: group)
    report
  end

  def group_tree(nodes)
    order = []
    buckets = {}
    nodes.each do |node|
      key = node[:label]
      unless buckets.key?(key)
        order << key
        buckets[key] = []
      end
      buckets[key] << node
    end
    order.map do |key|
      group = buckets[key]
      first = group.first
      {
        label: first[:label],
        location: first[:location],
        secs: group.sum { |node| node[:secs] },
        inclusive: group.sum { |node| node[:inclusive] },
        count: group.size,
        children: group_tree(group.flat_map { |node| node[:children] })
      }
    end
  end

  def report_buckets(buckets)
    ordered = buckets.sort_by { |key, bucket| [-bucket[:secs], key.to_s] }
    ordered.each_with_object({}) do |(key, bucket), report|
      count = bucket[:count]
      secs = bucket[:secs]
      samples = bucket[:samples].sort
      entry = {
        secs: secs,
        inclusive: bucket[:inclusive],
        percent: @total.zero? ? 0 : (secs * 100 / @total.to_f).round,
        count: count,
        min: bucket[:min] || 0.0,
        max: bucket[:max] || 0.0,
        avg: count.zero? ? 0.0 : secs / count,
        p50: percentile(samples, 50),
        p95: percentile(samples, 95),
        p99: percentile(samples, 99)
      }
      entry[:samples_truncated] = true if bucket[:samples_truncated]
      report[key] = entry
    end
  end

  # Nearest-rank percentile. +samples+ must already be sorted.
  def percentile(samples, percent)
    return 0.0 if samples.empty?

    rank = (percent / 100.0 * samples.length).ceil
    rank = 1 if rank < 1
    samples[rank - 1]
  end

  def summary_message(report, group: false)
    message = "\n\nTotal time <#{@name}>:#{format_secs(report[:total_time])} wall #{format_secs(report[:wall_time])}"
    unless report[:tree].empty?
      message += "\nSpans:\n"
      message += tree_text(report[:tree])
      if group && !report[:grouped_tree].empty?
        message += "Grouped spans:\n"
        message += tree_text(report[:grouped_tree])
      end
      message += "Total time by location:\n"
    else
      message += "\nTotal time by location:\n"
    end
    message += bucket_text(report[:locations])
    unless report[:labels].empty?
      message += "\nTotal time by label:\n"
      message += bucket_text(report[:labels])
    end
    unless report[:ranges].empty?
      message += "\nTotal time by range:\n"
      message += bucket_text(report[:ranges])
    end
    "#{message}\n\n"
  end

  def tree_text(nodes, depth = 0)
    nodes.map { |node|
      label = node[:label] || "(gap)"
      count = node.key?(:count) ? " ##{node[:count]}" : ""
      line = "\t#{'  ' * depth}#{label} inclusive #{format_secs(node[:inclusive])} self #{format_secs(node[:secs])}#{count}\n"
      line + tree_text(node[:children], depth + 1)
    }.join
  end

  def bucket_text(buckets)
    buckets.map { |key, data|
      inclusive = ""
      if (data[:inclusive] - data[:secs]).abs > 0.000_001
        inclusive = " inclusive #{format_secs(data[:inclusive])}"
      end
      "\t#{key}: #{format_secs(data[:secs])} (#{data[:percent]}%) ##{data[:count]} " \
        "min #{format_secs(data[:min])} max #{format_secs(data[:max])} avg #{format_secs(data[:avg])} " \
        "p95 #{format_secs(data[:p95])}#{inclusive}\n"
    }.join
  end

  def format_secs(value)
    value.round(2)
  end
end
