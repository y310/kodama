# Kodama

Kodama is a MySQL replication listener based on [ruby-binlog](https://bitbucket.org/winebarrel/ruby-binlog/overview).
Kodama provides a simple DSL to easily write your own replication listener.

## Features

- Provides simple DSL for writing binlog event handlers
- Automatically restarts from the saved binlog position
- Attempts to reconnect to MySQL when the connection is somehow teminated

These features allow developers to focus on writing their own replication logic rather than having to spend time figuring things out.

## Kodama Benefits

Kodama can be used to replicate MySQL updates to other data stores, arbitrary software or even a flat file. The sole purpose of Kodama is to provide a convenient way to reflect the database updates to other components in your system.

- Replicate from MySQL to Postgres
- Replicate between tables with different schema
- Sync production data to development DB while masking privacy information
- Realtime full text index update

## Dependencies

This gem links against MySQL's libreplication C shared library. You need to first install the [mysql-replication-listener](https://launchpad.net/mysql-replication-listener) package.

But official repository has some bugs. It is recommended to use [winebarrel's patched version](https://bitbucket.org/winebarrel/mysql-replication-listener) (There are rpm package and homebrew formula).

## Installation

Add this line to your application's Gemfile:

    gem 'kodama'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kodama

### binlog_format

It is recommended to set the mysqld binlog_format option to ``ROW``. This is because the ``ROW`` format allows Kodama to pickup every single updates made to the database.

```sql
SET GLOBAL binlog_format = 'ROW';
```

## Usage

### Simple client

```ruby
require 'kodama'

Kodama::Client.start(:host => '127.0.0.1', :username => 'user') do |c|
  c.binlog_position_file = 'position.log'
  c.log_level = :info # [:debug|:info|:warn|:error|:fatal]
  c.connection_retry_limit = 100 # times
  c.connection_retry_wait = 3 # second

  # Exit gracefully when kodama receives specified signals
  c.gracefully_stop_on :QUIT, :INT

  c.on_query_event do |event|
    p event.query
  end

  c.on_row_event do |event|
    p event.rows
  end
end
```

### Replicate to redis

```ruby
require 'rubygems'
require 'kodama'
require 'json'
require 'redis'

class Worker
  def initialize
    @redis = Redis.new
  end

  def perform(event)
    record_id = get_row(event)[0] # first column is id
    @redis.set "#{event.table_name}_#{record_id}", event.rows.to_json
  end

  def get_row(event)
    case event.event_type
    when /Write/, /Delete/
      event.rows[0]    # [row]
    when /Update/
      event.rows[0][1] # [[old_row, new_row]]
    end
  end
end


worker = Worker.new

Kodama::Client.start(:host => '127.0.0.1', :username => 'user') do |c|
  c.binlog_position_file = 'position.log'

  c.on_row_event do |event|
    worker.perform(event)
  end
end
```

## Configuration

### binlog_position_file

Sets the filename to save the binlog position.
Kodama will read this file and resume listening from the stored position.

### log_level

Set logger's log level.
It accepts ``:debug``, ``:info``, ``:warn``, ``:error``, ``:fatal``.

### connection_retry_limit, connection_retry_wait

If for some reason the connection to MySQL is terminated, Kodama will attempt to reconnect ``connection_retry_limit`` times, while waiting ``connection_retry_wait`` seconds between attempts.

### gracefully_stop_on

Kodama traps specified signals and stop gracefully.
It accpets multiple signals like following.

```ruby
Kodama::Client.start do |c|
  c.gracefully_stop_on :INT, :QUIT
end
```

## Authors

Yusuke Mito, Genki Sugawara

## Based On

- [ruby-binlog](https://bitbucket.org/winebarrel/ruby-binlog)
- [mysql-replication-listener](https://launchpad.net/mysql-replication-listener)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
