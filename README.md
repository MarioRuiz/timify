# Timify

[![Gem Version](https://badge.fury.io/rb/timify.svg)](https://rubygems.org/gems/timify)

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


Example of output:
```ruby
{  :name=>:add_customer_wrong, 
   :total_time=>4.461446, 
   :started=>2017-11-06 16:10:53 +0000, 
   :finished=>2017-11-06 16:10:57 +0000, 
   :locations=>{
      "/add_customer.rb:509"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:529"=>{:secs=>0.008001, :percent=>0, :count=>1}, 
	  "/add_customer.rb:532"=>{:secs=>0.212021, :percent=>5, :count=>1}, 
	  "/add_customer.rb:569"=>{:secs=>0.006001, :percent=>0, :count=>1}, 
	  "/add_customer.rb:581"=>{:secs=>0.446045, :percent=>10, :count=>1}, 
	  "/add_customer.rb:583"=>{:secs=>3.789378, :percent=>85, :count=>1}, 
	  "/add_customer.rb:585"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:587"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:595"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:603"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:612"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:617"=>{:secs=>0.0, :percent=>0, :count=>1}
	}, 
	:labels=>{
		:database_access=>{:secs=>4,447444, :percent=>99, :count=>3},
		:checkouts=>{:secs=>0.0, :percent=>0, :count=>2},
	}, 
	:ranges=>{
	  "/add_customer.rb:509 - /add_customer.rb:529"=>{:secs=>0.008001, :percent=>0, :count=>1}, 
	  "/add_customer.rb:529 - /add_customer.rb:532"=>{:secs=>0.212021, :percent=>5, :count=>1}, 
	  "/add_customer.rb:532 - /add_customer.rb:569"=>{:secs=>0.006001, :percent=>0, :count=>1}, 
	  "/add_customer.rb:569 - /add_customer.rb:581"=>{:secs=>0.446045, :percent=>10, :count=>1}, 
	  "/add_customer.rb:581 - /add_customer.rb:583"=>{:secs=>3.789378, :percent=>85, :count=>1}, 
	  "/add_customer.rb:583 - /add_customer.rb:585"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:585 - /add_customer.rb:587"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:587 - /add_customer.rb:595"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:595 - /add_customer.rb:603"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:603 - /add_customer.rb:612"=>{:secs=>0.0, :percent=>0, :count=>1}, 
	  "/add_customer.rb:612 - /add_customer.rb:617"=>{:secs=>0.0, :percent=>0, :count=>1}
	}, 
	:message=>"
	
		Total time <add_customer_wrong>:4.46
		Total time by location:
			/add_customer.rb:509: 0.0 (0%) #1
			/add_customer.rb:529: 0.01 (0%) #1
			/add_customer.rb:532: 0.21 (5%) #1
			/add_customer.rb:569: 0.01 (0%) #1
			/add_customer.rb:581: 0.45 (10%) #1
			/add_customer.rb:583: 3.79 (85%) #1
			/add_customer.rb:585: 0.0 (0%) #1
			/add_customer.rb:587: 0.0 (0%) #1
			/add_customer.rb:595: 0.0 (0%) #1
			/add_customer.rb:603: 0.0 (0%) #1
			/add_customer.rb:612: 0.0 (0%) #1
			/add_customer.rb:617: 0.0 (0%) #1
		Total time by label:
			database_access: 4.45 (99%) #3
			checkouts: 0.0 (0%) #2
		Total time by range:
			/add_customer.rb:509 - /add_customer.rb:529: 0.01 (0%) #1
			/add_customer.rb:529 - /add_customer.rb:532: 0.21 (5%) #1
			/add_customer.rb:532 - /add_customer.rb:569: 0.01 (0%) #1
			/add_customer.rb:569 - /add_customer.rb:581: 0.45 (10%) #1
			/add_customer.rb:581 - /add_customer.rb:583: 3.79 (85%) #1
			/add_customer.rb:583 - /add_customer.rb:585: 0.0 (0%) #1
			/add_customer.rb:585 - /add_customer.rb:587: 0.0 (0%) #1
			/add_customer.rb:587 - /add_customer.rb:595: 0.0 (0%) #1
			/add_customer.rb:595 - /add_customer.rb:603: 0.0 (0%) #1
			/add_customer.rb:603 - /add_customer.rb:612: 0.0 (0%) #1
			/add_customer.rb:612 - /add_customer.rb:617: 0.0 (0%) #1
	"
}
```


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/marioruiz/timify.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

