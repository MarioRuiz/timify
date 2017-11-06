# Timify

[![Gem Version](https://badge.fury.io/rb/timify.svg)](https://rubygems.org/gems/timify)
[![Build Status](https://travis-ci.org/marioruiz/timify.svg?branch=master)](https://travis-ci.org/marioruiz/timify)
[![Coverage Status](https://coveralls.io/repos/github/marioruiz/timing/badge.svg?branch=master)](https://coveralls.io/github/marioruiz/timify?branch=master)
[![Code Climate](https://codeclimate.com/github/marioruiz/timify.svg)](https://codeclimate.com/github/marioruiz/timify)
[![Dependency Status](https://gemnasium.com/marioruiz/timify.svg)](https://gemnasium.com/marioruiz/timify)

Ruby gem to calculate the time running from one location to another inside your code and report summaries

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'timify'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install timify

## Usage

### initialize
You need to supply a name for your Timify instance. 
You can have all the Timify instances you want at the same time.
```ruby
t = Timify.new :create_user
t.show = false
t.min_time_to_show = 0.5
```
min_time_to_show: minimum time to show the elapsed time when calling 'add' method

show: print out results on screen

you can supply those parameters also:

```ruby
t = Timify.new :create_user, show: true, min_time_to_show: 0.3
```

The scopes of the instances can be even global so you can measure the elapsed times between different classes, methods... on your code.

### add

Adds a new point to count the time elapsed. It will count from the last 'add' call or Timify creation in case of the first 'add'.

You can supply a label that will summarize all the ones with the same label

The output of this method will be the time elapsed in seconds (float).

Examples:

```ruby
t=Timify.new :example
t.add; run_sqls; t.add :database
t.add
#some processes
t.add
#some processes
send_email_alert if t.add > 0.2
#some processes
do_log(t.totals[:message]) if t.add > 0.5
```

### totals

Returns all data for this instance

In case json parameter supplied as true, the output will be in json format instead of a hash.

The output hash contains:

  name: (String) name given for this instance'

  total_time: (float) total elapsed time from initialization to last 'add' call

  started: (Time)

  finished: (Time)

  message: (String) a printable friendly message giving all information

  locations, labels, ranges: (Hash) the resultant hash contains:

    secs: (float) number of seconds

    percent: (integer) percentage in reference to the total time

    count: (integer) number of times

  locations: (Hash) All summary data by location where was called

  labels: (Hash) All summary data by label given on 'add' method

  ranges: (Hash) All summary data by ranges where was called, from last 'add' call to current 'add' call


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/marioruiz/timify.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

