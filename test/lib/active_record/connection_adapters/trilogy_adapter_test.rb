# frozen_string_literal: true

require "test_helper"

class ActiveRecord::ConnectionAdapters::TrilogyAdapterTest < TestCase
  setup do
    @schema_cache_fixture_path = @fixtures_path.join("schema.dump").to_s

    @host = ENV["DB_HOST"]
    @configuration = {
      adapter: "trilogy",
      username: "root",
      host: @host,
      port: Integer(ENV["DB_PORT"]),
      database: DATABASE
    }

    @adapter = trilogy_adapter
    @adapter.execute("TRUNCATE posts")

    db_config = ActiveRecord::DatabaseConfigurations.new({}).resolve(@configuration)
    pool_config_params = [ActiveRecord::Base, db_config]
    # AR 7.0 expects two additional parameters
    if ActiveRecord::ConnectionAdapters::PoolConfig.instance_method(:initialize).parameters.length == 4
      pool_config_params += [:writing, :default]
    end
    pool_config = ActiveRecord::ConnectionAdapters::PoolConfig.new(*pool_config_params)
    @pool = ActiveRecord::ConnectionAdapters::ConnectionPool.new(pool_config)
  end

  teardown do
    @adapter.disconnect!
  end

  test ".new_client" do
    client = @adapter.class.new_client(@configuration)
    assert_equal Trilogy, client.class
  end

  test ".new_client on db error" do
    configuration = @configuration.merge(database: "unknown")
    assert_raises ActiveRecord::NoDatabaseError do
      @adapter.class.new_client(configuration)
    end
  end

  test ".new_client on access denied error" do
    configuration = @configuration.merge(username: "unknown")
    assert_raises ActiveRecord::DatabaseConnectionError do
      @adapter.class.new_client(configuration)
    end
  end

  test ".new_client on host error" do
    configuration = @configuration.merge(host: "unknown")
    assert_raises ActiveRecord::DatabaseConnectionError do
      @adapter.class.new_client(configuration)
    end
  end

  test ".new_client on port error" do
    configuration = @configuration.merge(port: 1234)
    assert_raises ActiveRecord::ConnectionNotEstablished do
      @adapter.class.new_client(configuration)
    end
  end

  test "#explain for one query" do
    explain = @adapter.explain("select * from posts")
    assert_match %(possible_keys), explain
  end

  test "#default_prepared_statements" do
    assert_not_predicate @pool.connection, :prepared_statements?
  end

  test "#adapter_name answers name" do
    assert_equal "Trilogy", @adapter.adapter_name
  end

  test "#supports_json answers true without Maria DB and greater version" do
    assert @adapter.supports_json?
  end

  test "#supports_json answers false without Maria DB and lesser version" do
    database_version = @adapter.class::Version.new("5.0.0", nil)

    @adapter.stub(:database_version, database_version) do
      assert_equal false, @adapter.supports_json?
    end
  end

  test "#supports_json answers false with Maria DB" do
    @adapter.stub(:mariadb?, true) do
      assert_equal false, @adapter.supports_json?
    end
  end

  test "#supports_comments? answers true" do
    assert @adapter.supports_comments?
  end

  test "#supports_comments_in_create? answers true" do
    assert @adapter.supports_comments_in_create?
  end

  test "#supports_savepoints? answers true" do
    assert @adapter.supports_savepoints?
  end

  test "#requires_reloading? answers false" do
    assert_equal false, @adapter.requires_reloading?
  end

  test "#native_database_types answers known types" do
    assert_equal ActiveRecord::ConnectionAdapters::TrilogyAdapter::NATIVE_DATABASE_TYPES, @adapter.native_database_types
  end

  test "#quote_column_name answers quoted string when not quoted" do
    assert_equal "`test`", @adapter.quote_column_name("test")
  end

  test "#quote_column_name answers triple quoted string when quoted" do
    assert_equal "```test```", @adapter.quote_column_name("`test`")
  end

  test "#quote_column_name answers quoted string for integer" do
    assert_equal "`1`", @adapter.quote_column_name(1)
  end

  test "#quote_table_name delgates to #quote_column_name" do
    @adapter.stub(:quote_column_name, "stubbed_method_check") do
      assert_equal "stubbed_method_check", @adapter.quote_table_name("test")
    end
  end

  test "#quote_string answers string with connection" do
    assert_equal "\\\"test\\\"", @adapter.quote_string(%("test"))
  end

  test "#quote_string works when the connection is known to be closed" do
    adapter = trilogy_adapter
    adapter.connect!
    adapter.instance_variable_get(:@connection).close

    assert_equal "\\\"test\\\"", adapter.quote_string(%("test"))
  end

  test "#quoted_true answers TRUE" do
    assert_equal "TRUE", @adapter.quoted_true
  end

  test "#quoted_false answers FALSE" do
    assert_equal "FALSE", @adapter.quoted_false
  end

  test "#active? answers true with connection" do
    assert @adapter.active?
  end

  test "#active? answers false with connection and exception" do
    @adapter.send(:connection).stub(:ping, -> { raise Trilogy::BaseError.new }) do
      assert_equal false, @adapter.active?
    end
  end

  test "#active? answers false without connection" do
    adapter = trilogy_adapter
    assert_equal false, adapter.active?
  end

  test "#reconnect closes connection with connection" do
    connection = Minitest::Mock.new Trilogy.new(@configuration)
    connection.expect :close, true
    adapter = trilogy_adapter_with_connection(connection)
    adapter.reconnect!

    assert connection.verify
  end

  test "#reconnect doesn't retain old connection on failure" do
    old_connection = Minitest::Mock.new Trilogy.new(@configuration)
    old_connection.expect :close, true

    adapter = trilogy_adapter_with_connection(old_connection)

    begin
      Trilogy.stub(:new, -> _ { raise Trilogy::BaseError.new }) do
        adapter.reconnect!
      end
    rescue ActiveRecord::StatementInvalid => ex
      assert_instance_of Trilogy::BaseError, ex.cause
    else
      flunk "Expected Trilogy::BaseError to be raised"
    end

    assert_nil adapter.send(:connection)
  end

  test "#reconnect answers new connection with existing connection" do
    old_connection = @adapter.send(:connection)
    @adapter.reconnect!
    connection = @adapter.send(:connection)

    assert_instance_of Trilogy, connection
    assert_not_equal old_connection, connection
  end

  test "#reconnect answers new connection without existing connection" do
    adapter = trilogy_adapter
    adapter.reconnect!
    assert_instance_of Trilogy, adapter.send(:connection)
  end

  test "#reset closes connection with existing connection" do
    connection = Minitest::Mock.new Trilogy.new(@configuration)
    connection.expect :close, true
    adapter = trilogy_adapter_with_connection(connection)
    adapter.reset!

    assert connection.verify
  end

  test "#reset answers new connection with existing connection" do
    old_connection = @adapter.send(:connection)
    @adapter.reset!
    connection = @adapter.send(:connection)

    assert_instance_of Trilogy, connection
    assert_not_equal old_connection, connection
  end

  test "#reset answers new connection without existing connection" do
    adapter = trilogy_adapter
    adapter.reset!
    assert_instance_of Trilogy, adapter.send(:connection)
  end

  test "#disconnect closes connection with existing connection" do
    connection = Minitest::Mock.new Trilogy.new(@configuration)
    connection.expect :close, true
    adapter = trilogy_adapter_with_connection(connection)
    adapter.disconnect!

    assert connection.verify
  end

  test "#disconnect makes adapter inactive with connection" do
    @adapter.disconnect!
    assert_equal false, @adapter.active?
  end

  test "#disconnect answers nil with connection" do
    assert_nil @adapter.disconnect!
  end

  test "#disconnect answers nil without connection" do
    adapter = trilogy_adapter
    assert_nil adapter.disconnect!
  end

  test "#disconnect leaves adapter inactive without connection" do
    adapter = trilogy_adapter
    adapter.disconnect!

    assert_equal false, adapter.active?
  end

  test "#discard answers nil with connection" do
    assert_nil @adapter.discard!
  end

  test "#discard makes adapter inactive with connection" do
    @adapter.discard!
    assert_equal false, @adapter.active?
  end

  test "#discard answers nil without connection" do
    adapter = trilogy_adapter
    assert_nil adapter.discard!
  end

  test "#exec_query answers result with valid query" do
    result = @adapter.exec_query "SELECT * FROM posts;"

    assert_equal %w[id author_id title body kind created_at updated_at], result.columns
    assert_equal [], result.rows
  end

  test "#exec_query fails with invalid query" do
    assert_raises_with_message ActiveRecord::StatementInvalid, /'trilogy_test.bogus' doesn't exist/ do
      @adapter.exec_query "SELECT * FROM bogus;"
    end
  end

  test "#exec_insert inserts new row" do
    @adapter.exec_insert "INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('Test', 'example', 'content', '2019-05-31 12:52:00', '2019-05-31 12:52:00');", nil, nil
    result = @adapter.execute "SELECT * FROM posts;"

    assert_equal [[1, nil, "Test", "content", "example", Time.utc(2019, 5, 31, 12, 52), Time.utc(2019, 5, 31, 12, 52)]], result.rows
  end

  test "#exec_delete deletes existing row" do
    @adapter.execute "INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('Test', 'example', 'content', NOW(), NOW());"
    @adapter.exec_delete "DELETE FROM posts WHERE title = 'Test';", nil, nil
    result = @adapter.execute "SELECT * FROM posts;"

    assert_equal [], result.rows
  end

  test "#exec_update updates existing row" do
    @adapter.execute "INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('Test', 'example', 'content', '2019-05-31 12:52:00', '2019-05-31 12:52:00');"
    @adapter.exec_update "UPDATE posts SET title = 'Test II' where kind = 'example';", nil, nil
    result = @adapter.execute "SELECT * FROM posts;"

    assert_equal [[1, nil, "Test II", "content", "example", Time.utc(2019, 5, 31, 12, 52), Time.utc(2019, 5, 31, 12, 52)]], result.rows
  end

  test "default query flags set timezone to UTC" do
    assert_equal :utc, default_timezone
    ruby_time = Time.utc(2019, 5, 31, 12, 52)
    time = '2019-05-31 12:52:00'

    @adapter.execute("INSERT into posts (title, body, kind, created_at, updated_at) VALUES ('title', 'body', 'a kind of post', '#{time}', '#{time}');")
    result = @adapter.execute("select * from posts limit 1;")

    result.each_hash do |hsh|
      assert_equal ruby_time, hsh["created_at"]
      assert_equal ruby_time, hsh["updated_at"]
    end

    assert_equal 1, @adapter.send(:connection).query_flags
  end

  test "query flags for timezone can be set to local" do
    old_timezone = default_timezone
    set_default_timezone(:local)
    assert_equal :local, default_timezone
    ruby_time = Time.local(2019, 5, 31, 12, 52)
    time = '2019-05-31 12:52:00'

    @adapter.execute("INSERT into posts (title, body, kind, created_at, updated_at) VALUES ('title', 'body', 'a kind of post', '#{time}', '#{time}');")
    result = @adapter.execute("select * from posts limit 1;")

    result.each_hash do |hsh|
      assert_equal ruby_time, hsh["created_at"]
      assert_equal ruby_time, hsh["updated_at"]
    end

    assert_equal 5, @adapter.send(:connection).query_flags
  ensure
    set_default_timezone(old_timezone)
  end

  class Post < ActiveRecord::Base; end

  test "bulk fixture inserts when multi statement is configured" do
    ActiveRecord::Base.establish_connection(@configuration.merge(multi_statement: true))
    conn = ActiveRecord::Base.connection

    fixtures = {
      "posts" => [
        { "id" => 1, "title" => "Foo", "body" => "Something", "kind" => "something else", "created_at" => Time.now.utc, "updated_at" => Time.now.utc },
        { "id" => 2, "title" => "Bar", "body" => "Something Else", "kind" => "something", "created_at" => Time.now.utc, "updated_at" => Time.now.utc },
      ]
    }

    assert_nothing_raised do
      conn.execute("SELECT 1; SELECT 2;")
      conn.raw_connection.next_result while conn.raw_connection.more_results_exist?
    end

    assert_difference "Post.count", 2 do
      conn.insert_fixtures_set(fixtures)
    end

    assert_nothing_raised do
      conn.execute("SELECT 1; SELECT 2;")
      conn.raw_connection.next_result while conn.raw_connection.more_results_exist?
    end
  ensure
    Post.delete_all
  end

  test "bulk fixture inserts when multi_statement is disabled by default" do
    ActiveRecord::Base.establish_connection(@configuration.merge(multi_statement: false))
    conn = ActiveRecord::Base.connection

    fixtures = {
      "posts" => [
        { "id" => 1, "title" => "Foo", "body" => "Something", "kind" => "something else", "created_at" => Time.now.utc, "updated_at" => Time.now.utc },
        { "id" => 2, "title" => "Bar", "body" => "Something Else", "kind" => "something", "created_at" => Time.now.utc, "updated_at" => Time.now.utc },
      ]
    }

    assert_raises(ActiveRecord::StatementInvalid) do
      conn.execute("SELECT 1; SELECT 2;")
      conn.raw_connection.next_result while conn.raw_connection.more_results_exist?
    end

    assert_difference "Post.count", 2 do
      conn.insert_fixtures_set(fixtures)
    end

    assert_raises(ActiveRecord::StatementInvalid) do
      conn.execute("SELECT 1; SELECT 2;")
      conn.raw_connection.next_result while conn.raw_connection.more_results_exist?
    end
  ensure
    Post.delete_all
  end

  test "query flags for timezone can be set to local and reset to utc" do
    old_timezone = default_timezone
    set_default_timezone(:local)
    assert_equal :local, default_timezone
    ruby_time = Time.local(2019, 5, 31, 12, 52)
    time = '2019-05-31 12:52:00'

    @adapter.execute("INSERT into posts (title, body, kind, created_at, updated_at) VALUES ('title', 'body', 'a kind of post', '#{time}', '#{time}');")
    result = @adapter.execute("select * from posts limit 1;")

    result.each_hash do |hsh|
      assert_equal ruby_time, hsh["created_at"]
      assert_equal ruby_time, hsh["updated_at"]
    end

    assert_equal 5, @adapter.send(:connection).query_flags

    set_default_timezone(:utc)

    ruby_utc_time = Time.utc(2019, 5, 31, 12, 52)
    utc_result = @adapter.execute("select * from posts limit 1;")

    utc_result.each_hash do |hsh|
      assert_equal ruby_utc_time, hsh["created_at"]
      assert_equal ruby_utc_time, hsh["updated_at"]
    end

    assert_equal 1, @adapter.send(:connection).query_flags
  ensure
    set_default_timezone(old_timezone)
  end

  test "#execute answers results for valid query" do
    result = @adapter.execute "SELECT * FROM posts;"
    assert_equal %w[id author_id title body kind created_at updated_at], result.fields
  end

  test "#execute answers results for valid query after reconnect" do
    mock_connection = Minitest::Mock.new Trilogy.new(@configuration)
    adapter = trilogy_adapter_with_connection(mock_connection)

    # Cause an ER_SERVER_SHUTDOWN error (code 1053) after the session is
    # set. On reconnect, the adapter will get a real, working connection.
    server_shutdown_error = Trilogy::ProtocolError.new
    server_shutdown_error.instance_variable_set(:@error_code, 1053)
    mock_connection.expect(:query, nil) { raise server_shutdown_error }

    assert_raises(TrilogyAdapter::Errors::ServerShutdown) do
      adapter.execute "SELECT * FROM posts;"
    end

    adapter.reconnect!
    result = adapter.execute "SELECT * FROM posts;"

    assert_equal %w[id author_id title body kind created_at updated_at], result.fields
    assert mock_connection.verify
    mock_connection.close
  end

  test "#execute fails with invalid query" do
    assert_raises_with_message ActiveRecord::StatementInvalid, /Table 'trilogy_test.bogus' doesn't exist/ do
      @adapter.execute "SELECT * FROM bogus;"
    end
  end

  test "#execute fails with invalid SQL" do
    assert_raises(ActiveRecord::StatementInvalid) do
      @adapter.execute "SELECT bogus FROM posts;"
    end
  end

  test "#execute answers results for valid query after losing connection" do
    connection = Trilogy.new(@configuration.merge(read_timeout: 1))

    adapter = trilogy_adapter_with_connection(connection)
    assert adapter.active?

    # Make connection lost for future queries by exceeding the read timeout
    assert_raises(ActiveRecord::StatementInvalid) do
      adapter.execute "SELECT sleep(2);"
    end
    assert_not adapter.active?

    # The above failure has not yet caused a reconnect, but the adapter has
    # lost confidence in the connection, so it will re-verify before running
    # the next query -- which means it will succeed.

    # This query triggers a reconnect
    result = adapter.execute "SELECT COUNT(*) FROM posts;"
    assert_equal [[0]], result.rows
    assert adapter.active?
  end

  test "can reconnect after failing to rollback" do
    connection = Trilogy.new(@configuration.merge(read_timeout: 1))

    adapter = trilogy_adapter_with_connection(connection)
    adapter.pool = @pool

    adapter.transaction do
      adapter.execute("SELECT 1")

      # Cause the client to disconnect without the adapter's awareness
      assert_raises Trilogy::TimeoutError do
        adapter.send(:connection).query("SELECT sleep(2)")
      end

      raise ActiveRecord::Rollback
    end

    result = adapter.execute("SELECT 1")
    assert_equal [[1]], result.rows
  end

  test "#execute fails with unknown error" do
    assert_raises_with_message(ActiveRecord::StatementInvalid, /A random error/) do
      connection = Minitest::Mock.new Trilogy.new(@configuration)
      connection.expect(:query, nil) { raise Trilogy::ProtocolError, "A random error." }
      adapter = trilogy_adapter_with_connection(connection)

      adapter.execute "SELECT * FROM posts;"
    end
  end

  test "#select_all when query cache is enabled fires the same notification payload for uncached and cached queries" do
    @adapter.cache do
      event_fired = false
      subscription = ->(name, start, finish, id, payload) {
        event_fired = true

        # First, we test keys that are defined by default by the AbstractAdapter
        assert_includes payload, :sql
        assert_equal "SELECT * FROM posts", payload[:sql]

        assert_includes payload, :name
        assert_equal "uncached query", payload[:name]

        assert_includes payload, :connection
        assert_equal @adapter, payload[:connection]

        assert_includes payload, :binds
        assert_equal [], payload[:binds]

        assert_includes payload, :type_casted_binds
        assert_equal [], payload[:type_casted_binds]

        # :stament_name is always nil and never set 🤷‍♂️
        assert_includes payload, :statement_name
        assert_nil payload[:statement_name]

        refute_includes payload, :cached
      }
      ActiveSupport::Notifications.subscribed(subscription, "sql.active_record") do
        @adapter.select_all "SELECT * FROM posts", "uncached query"
      end
      assert event_fired

      event_fired = false
      subscription = ->(name, start, finish, id, payload) {
        event_fired = true

        # First, we test keys that are defined by default by the AbstractAdapter
        assert_includes payload, :sql
        assert_equal "SELECT * FROM posts", payload[:sql]

        assert_includes payload, :name
        assert_equal "cached query", payload[:name]

        assert_includes payload, :connection
        assert_equal @adapter, payload[:connection]

        assert_includes payload, :binds
        assert_equal [], payload[:binds]

        assert_includes payload, :type_casted_binds
        assert_equal [], payload[:type_casted_binds].is_a?(Proc) ? payload[:type_casted_binds].call : payload[:type_casted_binds]

        # Rails does not include :stament_name for cached queries 🤷‍♂️
        refute_includes payload, :statement_name

        assert_includes payload, :cached
        assert_equal true, payload[:cached]
      }
      ActiveSupport::Notifications.subscribed(subscription, "sql.active_record") do
        @adapter.select_all "SELECT * FROM posts", "cached query"
      end
      assert event_fired
    end
  end

  test "#execute answers result with valid SQL" do
    result = @adapter.execute "SELECT * FROM posts;"

    assert_equal %w[id author_id title body kind created_at updated_at], result.fields
    assert_equal [], result.rows
  end

  test "#execute emits a query notification" do
    assert_notification("sql.active_record") do
      @adapter.execute "SELECT * FROM posts;"
    end
  end

  test "#indexes answers indexes with existing indexes" do
    proof = [{
      table: "posts",
      name: "index_posts_on_kind",
      unique: true,
      columns: ["kind"],
      lengths: {},
      orders: {},
      opclasses: {},
      where: nil,
      type: nil,
      using: :btree,
      comment: nil
    },
    {
      table: "posts",
      name: "index_posts_on_author_id",
      unique: false,
      columns: ["author_id"],
      lengths: {},
      orders: {},
      opclasses: {},
      where: nil,
      type: nil,
      using: :btree,
      comment: nil
    }]

    indexes = @adapter.indexes("posts").map do |index|
      {
        table: index.table,
        name: index.name,
        unique: index.unique,
        columns: index.columns,
        lengths: index.lengths,
        orders: index.orders,
        opclasses: index.opclasses,
        where: index.where,
        type: index.type,
        using: index.using,
        comment: index.comment
      }
    end

    assert_equal proof, indexes
  end

  test "#indexes answers empty array with no indexes" do
    assert_equal [], @adapter.indexes("users")
  end

  test "#begin_db_transaction answers empty result" do
    result = @adapter.begin_db_transaction
    assert_equal [], result.rows

    # rollback transaction so it doesn't bleed into other tests
    @adapter.rollback_db_transaction
  end

  test "#begin_db_transaction raises error" do
    error = Class.new(Exception)
    assert_raises error do
      @adapter.stub(:raw_execute, -> (*) { raise error }) do
        @adapter.begin_db_transaction
      end
    end

    # rollback transaction so it doesn't bleed into other tests
    @adapter.rollback_db_transaction
  end

  test "#commit_db_transaction answers empty result" do
    result = @adapter.commit_db_transaction
    assert_equal [], result.rows
  end

  test "#commit_db_transaction raises error" do
    error = Class.new(Exception)
    assert_raises error do
      @adapter.stub(:raw_execute, -> (*) { raise error }) do
        @adapter.commit_db_transaction
      end
    end
  end

  test "#rollback_db_transaction raises error" do
    error = Class.new(Exception)
    assert_raises error do
      @adapter.stub(:raw_execute, -> (*) { raise error }) do
        @adapter.rollback_db_transaction
      end
    end
  end

  test "#insert answers ID with ID" do
    assert_equal 5, @adapter.insert("INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('test', 'example', 'content', NOW(), NOW());", "test", nil, 5)
  end

  test "#insert answers last ID without ID" do
    assert_equal 1, @adapter.insert("INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('test', 'example', 'content', NOW(), NOW());", "test")
  end

  test "#insert answers incremented last ID without ID" do
    @adapter.insert("INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('test', 'one', 'content', NOW(), NOW());", "test")
    assert_equal 2, @adapter.insert("INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('test', 'two', 'content', NOW(), NOW());", "test")
  end

  test "#update answers affected row count when updatable" do
    @adapter.insert("INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('test', 'example', 'content', NOW(), NOW());")
    assert_equal 1, @adapter.update("UPDATE posts SET title = 'Test' WHERE id = 1;")
  end

  test "#update answers zero affected rows when not updatable" do
    assert_equal 0, @adapter.update("UPDATE posts SET title = 'Test' WHERE id = 1;")
  end

  test "strict mode can be disabled" do
    adapter = trilogy_adapter(strict: false)

    adapter.execute "INSERT INTO posts (title) VALUES ('test');"
    result = adapter.execute "SELECT * FROM posts;"
    assert_equal [[1, nil, "test", "", "", nil, nil]], result.rows
  end

  test "#select_value returns a single value" do
    assert_equal 123, @adapter.select_value("SELECT 123")
  end

  test "#each_hash yields symbolized result rows" do
    @adapter.execute "INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('test', 'example', 'content', NOW(), NOW());"
    result = @adapter.execute "SELECT * FROM posts;"

    @adapter.each_hash(result) do |row|
      assert_equal "test", row[:title]
    end
  end

  test "#each_hash returns an enumarator of symbolized result rows when no block is given" do
    @adapter.execute "INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('test', 'example', 'content', NOW(), NOW());"
    result = @adapter.execute "SELECT * FROM posts;"
    rows_enum = @adapter.each_hash result

    assert_equal "test", rows_enum.next[:title]
  end

  test "#each_hash returns empty array when results is empty" do
    result = @adapter.execute "SELECT * FROM posts;"
    rows = @adapter.each_hash result

    assert_empty rows.to_a
  end

  test "#error_number answers number for exception" do
    exception = Minitest::Mock.new
    exception.expect :error_code, 123

    assert_equal 123, @adapter.error_number(exception)
  end

  test "read timeout raises ActiveRecord::AdapterTimeout" do
    ActiveRecord::Base.establish_connection(@configuration.merge("read_timeout" => 1))

    error = assert_raises(ActiveRecord::AdapterTimeout) do
      ActiveRecord::Base.connection.execute("SELECT SLEEP(2)")
    end
    assert_kind_of ActiveRecord::QueryAborted, error

    assert_equal Trilogy::TimeoutError, error.cause.class
  end

  test "schema cache works without querying DB" do
    adapter = trilogy_adapter
    adapter.schema_cache = adapter.schema_cache.class.load_from(@schema_cache_fixture_path)

    flunk_cb = ->(name, started, finished, unique_id, payload) { puts caller; flunk "expected no queries, but got: #{payload[:sql]}" }
    ActiveSupport::Notifications.subscribed(flunk_cb, "sql.active_record") do
      adapter.schema_cache.data_source_exists?("users")

      # Should still be disconnected
      assert_nil adapter.send(:connection)
    end
  end

  test "async queries can be run" do
    return skip unless ActiveRecord::Base.respond_to?(:asynchronous_queries_tracker)

    @adapter.pool = @pool

    ActiveRecord::Base.asynchronous_queries_tracker.start_session

    payloads = []
    callback = lambda {|name, started, finished, unique_id, payload|
      payloads << payload if payload[:name] != "SCHEMA"
    }

    result = @adapter.select_all("SELECT 123", async: true)
    assert result.pending?
    200.times do
      break unless result.pending?
      sleep 0.001
    end
    refute result.pending?

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      # Data is already loaded, but notifications are buffered
      result.to_a
    end

    assert_kind_of ActiveRecord::FutureResult, result
    assert_equal [{"123" => 123}], result.to_a

    assert_equal 1, payloads.size
    assert payloads[0][:async]

    ActiveRecord::Base.asynchronous_queries_tracker.finalize_session
  end

  test "execute uses AbstractAdapter#transform_query when available" do
    # We only want to test if QueryLogs functionality is available
    skip unless ActiveRecord.respond_to?(:query_transformers)

    # Add custom query transformer
    old_query_transformers = ActiveRecord.query_transformers
    ActiveRecord.query_transformers = [-> (sql, *args) { sql + " /* it works */" }]

    sql = "SELECT * FROM posts;"

    mock_connection = Minitest::Mock.new Trilogy.new(@configuration)
    adapter = trilogy_adapter_with_connection(mock_connection)
    mock_connection.expect :query, nil, [sql + " /* it works */"]

    adapter.execute sql

    assert mock_connection.verify
  ensure
    # Teardown custom query transformers
    ActiveRecord.query_transformers = old_query_transformers if ActiveRecord.respond_to?(:query_transformers)
  end

  test "parses ssl_mode as int" do
    adapter = trilogy_adapter(ssl_mode: 0)
    adapter.connect!

    assert adapter.active?
  end

  test "parses ssl_mode as string" do
    adapter = trilogy_adapter(ssl_mode: "disabled")
    adapter.connect!

    assert adapter.active?
  end

  test "parses ssl_mode as string prefixed" do
    adapter = trilogy_adapter(ssl_mode: "SSL_MODE_DISABLED")
    adapter.connect!

    assert adapter.active?
  end

  def trilogy_adapter_with_connection(connection, **config_overrides)
    ActiveRecord::ConnectionAdapters::TrilogyAdapter
      .new(connection, nil, {}, @configuration.merge(config_overrides))
      .tap { |conn| conn.execute("SELECT 1") }
  end

  def trilogy_adapter(**config_overrides)
    ActiveRecord::ConnectionAdapters::TrilogyAdapter.new(nil, nil, nil, @configuration.merge(config_overrides))
  end

  def default_timezone
    ActiveRecord.version < ::Gem::Version.new('7.0.a') ? ActiveRecord::Base.default_timezone : ActiveRecord.default_timezone
  end

  def set_default_timezone(value)
    if ActiveRecord.version < ::Gem::Version.new('7.0.a') # For ActiveRecord 6.1
      ActiveRecord::Base.default_timezone = value
    else # For ActiveRecord < 7.0
      ActiveRecord.default_timezone = value
    end
  end
end
