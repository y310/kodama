# coding: utf-8

require 'binlog'
require 'logger'

module Kodama
  class Client
    LOG_LEVEL = {
      :fatal => Logger::FATAL,
      :error => Logger::ERROR,
      :warn => Logger::WARN,
      :info => Logger::INFO,
      :debug => Logger::DEBUG,
    }

    class << self
      def start(options = {}, &block)
        client = self.new(mysql_url(options))
        block.call(client)
        client.start
      end

      def mysql_url(options = {})
        password = options[:password] ? ":#{options[:password]}" : nil
        port = options[:port] ? ":#{options[:port]}" : nil
        "mysql://#{options[:username]}#{password}@#{options[:host]}#{port}"
      end
    end

    def initialize(url)
      @url = url
      @binlog_info = BinlogInfo.new
      @retry_info = RetryInfo.new(:limit => 100, :wait => 3)
      @callbacks = {}
      @logger = Logger.new(STDOUT)
      @safe_to_stop = true

      self.log_level = :info
    end

    def on_query_event(&block); @callbacks[:on_query_event] = block; end
    def on_rotate_event(&block); @callbacks[:on_rotate_event] = block; end
    def on_int_var_event(&block); @callbacks[:on_int_var_event] = block; end
    def on_user_var_event(&block); @callbacks[:on_user_var_event] = block; end
    def on_format_event(&block); @callbacks[:on_format_event] = block; end
    def on_xid(&block); @callbacks[:on_xid] = block; end
    def on_table_map_event(&block); @callbacks[:on_table_map_event] = block; end
    def on_row_event(&block); @callbacks[:on_row_event] = block; end
    def on_incident_event(&block); @callbacks[:on_incident_event] = block; end
    def on_unimplemented_event(&block); @callbacks[:on_unimplemented_event] = block; end

    def binlog_position_file=(filename)
      @position_file = position_file(filename)
      @binlog_info.load!(@position_file)
    end

    def connection_retry_wait=(wait)
      @retry_info.wait = wait
    end

    def connection_retry_limit=(limit)
      @retry_info.limit = limit
    end

    def log_level=(level)
      @logger.level = LOG_LEVEL[level]
    end

    def gracefully_stop_on(*signals)
      signals.each do |signal|
        Signal.trap(signal) do
          if safe_to_stop?
            exit(0)
          else
            stop_request
          end
        end
      end
    end

    def binlog_client(url)
      Binlog::Client.new(url)
    end

    def position_file(filename)
      PositionFile.new(filename)
    end

    def connection_retry_count
      @retry_info.count
    end

    def safe_to_stop?
      !!@safe_to_stop
    end

    def stop_request
      @stop_requested = true
    end

    def start
      begin
        client = binlog_client(@url)
        raise Binlog::Error, 'MySQL server has gone away' unless client.connect
        @retry_info.count_reset

        if @binlog_info.valid?
          client.set_position(@binlog_info.filename, @binlog_info.position)
        end

        while event = client.wait_for_next_event
          unsafe do
            process_event(event)
          end
          break if stop_requested?
        end
      rescue Binlog::Error => e
        @logger.debug e
        if client.closed? && @retry_info.retryable?
          sleep @retry_info.wait
          @retry_info.count_up
          retry
        end
        raise e
      end
    end

    private
    def unsafe
      @safe_to_stop = false
      yield
      @safe_to_stop = true
    end

    def stop_requested?
      @stop_requested
    end

    def process_event(event)
      @binlog_info.position = event.next_position
      case event
      when Binlog::QueryEvent
        callback :on_query_event, event
        @binlog_info.save(@position_file)
      when Binlog::RotateEvent
        callback :on_rotate_event, event
        @binlog_info.filename = event.binlog_file
        @binlog_info.position = event.binlog_pos
        @binlog_info.save(@position_file)
      when Binlog::IntVarEvent
        callback :on_int_var_event, event
      when Binlog::UserVarEvent
        callback :on_user_var_event, event
      when Binlog::FormatEvent
        callback :on_format_event, event
      when Binlog::Xid
        callback :on_xid, event
      when Binlog::TableMapEvent
        callback :on_table_map_event, event
      when Binlog::RowEvent
        callback :on_row_event, event
        @binlog_info.save(@position_file)
      when Binlog::IncidentEvent
        callback :on_incident_event, event
      when Binlog::UnimplementedEvent
        callback :on_unimplemented_event, event
      else
        @logger.error "Not Implemented: #{event.event_type}"
      end
    end

    def callback(name, *args)
      if @callbacks[name]
        instance_exec *args, &@callbacks[name]
      else
        @logger.debug "Unhandled: #{name}"
      end
    end

    class BinlogInfo
      attr_accessor :filename, :position

      def initialize(filename = nil, position = nil)
        @filename = filename
        @position = position
      end

      def valid?
        @filename && @position
      end

      def save(position_file = nil)
        if position_file
          position_file.update(@filename, @position)
        end
      end

      def load!(position_file)
        @filename, @position = position_file.read
      end
    end

    class RetryInfo
      attr_accessor :count, :limit, :wait
      def initialize(options = {})
        @wait = options[:wait] || 3
        @limit = options[:limit] || 100
        @count = 0
      end

      def retryable?
        @count < @limit
      end

      def count_up
        @count += 1
      end

      def count_reset
        @count = 0
      end
    end

    class PositionFile
      def initialize(filename)
        @file = open(filename, File::RDWR|File::CREAT)
        @file.sync = true
      end

      def update(filename, position)
        @file.pos = 0
        @file.write "#{filename}\t#{position}"
        @file.truncate @file.pos
      end

      def read
        @file.pos = 0
        if line = @file.gets
          filename, position = line.split("\t")
          [filename, position.to_i]
        end
      end
    end
  end
end
