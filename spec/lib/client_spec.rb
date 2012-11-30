require 'spec_helper'

describe Kodama::Client do
  describe '.mysql_url' do
    def mysql_url(options)
      Kodama::Client.mysql_url(options)
    end

    it do
      mysql_url(:username => 'user', :host => 'example.com').should == 'mysql://user@example.com'
      mysql_url(:username => 'user', :host => 'example.com',
                :password => 'password', :port => 3306).should == 'mysql://user:password@example.com:3306'
    end
  end

  describe '#start' do
    class TestBinlogClient
      attr_accessor :connect
      def initialize(events = [], connect = true)
        @events = events
        @connect = connect
      end

      def wait_for_next_event
        event = @events.shift
        stub_event(event)
        event
      end

      def closed?
        true
      end

      def stub_event(target_event)
        target_event_class = target_event.instance_variable_get('@name')
        [Binlog::QueryEvent, Binlog::RowEvent, Binlog::RotateEvent, Binlog::Xid].each do |event|
          if event == target_event_class
            event.stub(:===).and_return { true }
          else
            # :=== is stubbed
            if event.method(:===).owner != Module
              event.unstub(:===)
            end
          end
        end
      end
    end

    class TestPositionFile
      def update(filename, position)
      end

      def read
      end
    end

    def stub_binlog_client(events = [], connect = true)
      client.stub(:binlog_client).and_return { TestBinlogClient.new(events, connect) }
    end

    def stub_position_file(position_file = nil)
      client.stub(:position_file).and_return { position_file || TestPositionFile.new }
    end

    let(:client) { Kodama::Client.new('mysql://user@host') }

    let(:rotate_event) do
      mock(Binlog::RotateEvent).tap do |event|
        event.stub(:next_position).and_return { 0 }
        event.stub(:binlog_file).and_return { 'binlog' }
        event.stub(:binlog_pos).and_return { 100 }
      end
    end

    let(:query_event) do
      mock(Binlog::QueryEvent).tap do |event|
        event.stub(:next_position).and_return { 200 }
      end
    end

    let(:row_event) do
      mock(Binlog::RowEvent).tap do |event|
        event.stub(:next_position).and_return { 300 }
      end
    end

    let(:xid_event) do
      mock(Binlog::Xid).tap do |event|
        event.stub(:next_position).and_return { 400 }
      end
    end

    it 'should receive query_event' do
      stub_binlog_client([query_event])
      expect {|block|
        client.on_query_event(&block)
        client.start
      }.to yield_with_args(query_event)
    end

    it 'should receive row_event' do
      stub_binlog_client([row_event])
      expect {|block|
        client.on_row_event(&block)
        client.start
      }.to yield_with_args(row_event)
    end

    it 'should save position only on row, query and rotate event' do
      stub_binlog_client([rotate_event, query_event, row_event, xid_event])
      position_file = TestPositionFile.new.tap do |pf|
        pf.should_receive(:update).with('binlog', 100).once.ordered
        pf.should_receive(:update).with('binlog', 200).once.ordered
        pf.should_receive(:update).with('binlog', 300).once.ordered
      end
      stub_position_file(position_file)
      client.binlog_position_file = 'test'
      client.start
    end

    it 'should retry exactly specifeid times' do
      stub_binlog_client([query_event], false)
      client.connection_retry_limit = 2
      client.connection_retry_wait = 0.1
      expect { client.start }.to raise_error(Binlog::Error)
      client.connection_retry_count.should == 2
    end
  end
end
