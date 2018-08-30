###############################################################
# Calculates the time running from one location to another inside your code. More info: https://github.com/MarioRuiz/timify/
#
#   attr_accessor:
#     min_time_to_show: minimum time to show the elapsed time when calling 'add' method
#     show: print out results on screen
#	  status: (default :on) You can set :on or :off the status so it will counting the time or not
#
#   attr_reader:
#     name: name given for the Timify instance
#     initial_time: when the instance was created
#     total: total time elapsed
#     max_time_spent: maximum time measured for this instance
###############################################################
class Timify
  attr_accessor :min_time_to_show, :show, :status
  attr_reader :name, :total, :initial_time, :max_time_spent

  ###############################################################
  # input:
  #   name: name for the instance
  #   min_time_to_show: minimum time to show the elapsed time when calling 'add' method
  #   show: print out results on screen
  #
  # examples:
  #   t = Timify.new :create_user
  #   t.show = false
  #   $tim = Timify.new :dbprocess, show:false, min_time_to_show: 0.5
  ###############################################################
  def initialize(name, min_time_to_show: 0, show: true)
    @name=name
    @min_time_to_show=min_time_to_show
    @show=show
    @initial_time=Time.new
    @max_time_spent=0
    @timify_prev=@initial_time
    @location_prev=nil
    @timify={}
    @timify_by_label={}
    @timify_by_range={}
    @count={}
    @total=0
    puts "<#{@name}> Timify init:<#{@initial_time}>. Location: #{caller[0].scan(/(.+):in\s/).join}"
  end

  ###############################################################
  # Adds a new point to count the time elapsed.
  # It will count from the last 'add' call or Timify creation in case of the first 'add'.
  #
  #   input:
  #     label: (optional) In case supplied it will summarize all the ones with the same label
  #
  #   output: (float)
  #     time elapsed in seconds
  #
  #   examples:
  #     t=Timify.new :example
  #     t.add; run_sqls; t.add :database
  #     t.add
  #     #some processes
  #     t.add
  #     #some processes
  #     send_email_alert if t.add > 0.2
  #     #some processes
  #     do_log(t.totals[:message]) if t.add > 0.5
  ###############################################################
  def add(*label)
	return 0 if @status==:off
    if !label.empty?
      label=label[0]
    else
      label=""
    end

    time_now=Time.new
    time_spent=(time_now-@timify_prev).to_f
    @total=(time_now-@initial_time).to_f
    new_max=false
    location=caller[0].scan(/(.+):in\s/).join
    if time_spent > @max_time_spent then
      new_max = true
      @max_time_spent = time_spent
    end
    @timify[location]=@timify[location].to_f+time_spent
    @count[location]=@count[location].to_i+1
    if !label.empty?
      @timify_by_label[label]=@timify_by_label[label].to_f+time_spent
      @count[label]=@count[label].to_i+1
    end
    if !@location_prev.nil?
      @timify_by_range["#{@location_prev} - #{location}"]=@timify_by_range["#{@location_prev} - #{location}"].to_f + time_spent
      @count["#{@location_prev} - #{location}"]=@count["#{@location_prev} - #{location}"].to_i+1
    end


    if @total > 0
      percent=((@timify[location]/@total)*100).round(0)
    else
      percent=0
    end
    if time_spent>=@min_time_to_show
      if @show
        puts "<#{@name}>#{"<#{label}>" if !label.empty?}#{"(New Max)" if new_max}: #{location} (#{percent}%): #{@total.round(2)}; #{time_spent.round(2)}"
      end
    end
    @timify_prev=time_now
    @location_prev=location
    return time_spent
  end


  ###############################################################
  # returns all data for this instance
  #
  #   input:
  #     json: (boolean) in case of true the output will be in json format instead of a hash
  #
  #   output: (Hash or json string)
  #     name: (String) name given for this instance
  #     total_time: (float) total elapsed time from initialization to last 'add' call
  #     started: (Time)
  #     finished: (Time)
  #     message: (String) a printable friendly message giving all information
  #     locations, labels, ranges: (Hash) the resultant hash contains:
  #       secs: (float) number of seconds
  #       percent: (integer) percentage in reference to the total time
  #       count: (integer) number of times
  #     locations: (Hash) All summary data by location where was called
  #     labels: (Hash) All summary data by label given on 'add' method
  #     ranges: (Hash) All summary data by ranges where was called, from last 'add' call to current 'add' call
  ###############################################################
  def totals(json: false)
  	return {} if @status==:off
    require 'json' if json
    output={
        name: @name,
        total_time: @total.to_f,
        started: @initial_time,
        finished: @timify_prev,
        locations: {},
        labels: {},
        ranges: {}
    }
    message="\n\nTotal time <#{@name}>:#{@total.to_f.round(2)}"
    message+="\nTotal time by location:\n"
    @timify.each {|location, secs|
      if @total==0 then
        percent=0
      else
        percent=(secs*100/(@total).to_f).round(0)
      end
      message+= "\t#{location}: #{secs.round(2)} (#{percent}%) ##{@count[location]}"
      output[:locations][location]={
          secs: secs,
          percent: percent,
          count: @count[location]
      }
    }
    if !@timify_by_label.empty?
      message+= "\nTotal time by label:\n"
      @timify_by_label.each {|label, secs|
        if @total==0 then
          percent=0
        else
          percent=(secs*100/(@total).to_f).round(0)
        end
        message+= "\t#{label}: #{secs.round(2)} (#{percent}%) ##{@count[label]}"
        output[:labels][label]={
            secs: secs,
            percent: percent,
            count: @count[label]
        }
      }
    end

    if !@timify_by_range.empty?
      message+= "\nTotal time by range:\n"
      @timify_by_range.each {|range, secs|
        if @total==0 then
          percent=0
        else
          percent=(secs*100/(@total).to_f).round(0)
        end
        message+= "\t#{range}: #{secs.round(2)} (#{percent}%) ##{@count[range]}"
        output[:ranges][range]={
            secs: secs,
            percent: percent,
            count: @count[range]
        }
      }
    end

    message+= "\n\n"
    output[:message]=message
    puts message if @show
    output=output.to_json if json
    return output
  end
end
