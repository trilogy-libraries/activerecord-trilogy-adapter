# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Trilogy
      module DatabaseStatements
        READ_QUERY = ActiveRecord::ConnectionAdapters::AbstractAdapter.build_read_query_regexp(
          :desc, :describe, :set, :show, :use
        ) # :nodoc:
        private_constant :READ_QUERY

        HIGH_PRECISION_CURRENT_TIMESTAMP = Arel.sql("CURRENT_TIMESTAMP(6)").freeze # :nodoc:
        private_constant :HIGH_PRECISION_CURRENT_TIMESTAMP

        def execute(sql, name = nil, **kwargs)
          sql = transform_query(sql)
          check_if_write_query(sql)
          mark_transaction_written_if_write(sql)

          result = raw_execute(sql, name, **kwargs)
          ActiveRecord::Result.new(result.fields, result.to_a)
        end

        def write_query?(sql) # :nodoc:
          !READ_QUERY.match?(sql)
        rescue ArgumentError # Invalid encoding
          !READ_QUERY.match?(sql.b)
        end

        def explain(arel, binds = [])
          sql     = "EXPLAIN #{to_sql(arel, binds)}"
          start   = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result  = internal_exec_query(sql, "EXPLAIN", binds)
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

          MySQL::ExplainPrettyPrinter.new.pp(result, elapsed)
        end

        def select_all(*, **) # :nodoc:
          result = super
          with_trilogy_connection do |conn|
            conn.next_result while conn.more_results_exist?
          end
          result
        end

        def exec_query(sql, name = "SQL", binds = [], prepare: false, **kwargs)
          internal_exec_query(sql, name, binds, prepare: prepare, **kwargs)
        end

        def internal_exec_query(sql, name = "SQL", binds = [], prepare: false, async: false) # :nodoc:
          sql = transform_query(sql)
          check_if_write_query(sql)
          mark_transaction_written_if_write(sql)

          result = raw_execute(sql, name, async: async)
          ActiveRecord::Result.new(result.fields, result.to_a)
        end

        def exec_insert(sql, name, binds, pk = nil, sequence_name = nil, returning: nil) # :nodoc:
          sql = transform_query(sql)
          check_if_write_query(sql)
          mark_transaction_written_if_write(sql)

          raw_execute(to_sql(sql, binds), name)
        end

        def exec_delete(sql, name = nil, binds = []) # :nodoc:
          sql = transform_query(sql)
          check_if_write_query(sql)
          mark_transaction_written_if_write(sql)

          result = raw_execute(to_sql(sql, binds), name)
          result.affected_rows
        end

        alias :exec_update :exec_delete # :nodoc:

        def high_precision_current_timestamp
          HIGH_PRECISION_CURRENT_TIMESTAMP
        end

        private
          if ActiveRecord.version < ::Gem::Version.new('7.0.a') # ActiveRecord <= 6.1 support
            def transform_query(sql); sql; end
            def check_if_write_query(*args); end

            if ActiveRecord.version < ::Gem::Version.new('6.1.a') # ActiveRecord <= 6.0 support
              def mark_transaction_written_if_write(sql)
                transaction = current_transaction
                if transaction.respond_to?(:written) && transaction.open?
                  transaction.written ||= write_query?(sql)
                end
              end
            end
          end

          def raw_execute(sql, name, async: false, uses_transaction: true)
            log_kwargs = {}
            log_kwargs[:async] = async if ActiveRecord.version >= ::Gem::Version.new('7.0.a')
            log(sql, name, **log_kwargs) do
              with_trilogy_connection(uses_transaction: uses_transaction) do |conn|
                sync_timezone_changes(conn)
                conn.query(sql)
              end
            end
          end

          def last_inserted_id(result)
            result.last_insert_id
          end

          def sync_timezone_changes(conn)
            # Sync any changes since connection last established.
            if default_timezone == :local
              conn.query_flags |= ::Trilogy::QUERY_FLAGS_LOCAL_TIMEZONE
            else
              conn.query_flags &= ~::Trilogy::QUERY_FLAGS_LOCAL_TIMEZONE
            end
          end

          def execute_batch(statements, name = nil)
            statements = statements.map { |sql| transform_query(sql) } if respond_to?(:transform_query)
            combine_multi_statements(statements).each do |statement|
              with_trilogy_connection do |conn|
                raw_execute(statement, name)
                conn.next_result while conn.more_results_exist?
              end
            end
          end

          def multi_statements_enabled?
            !!@config[:multi_statement]
          end

          def with_multi_statements
            if multi_statements_enabled?
              return yield
            end

            with_trilogy_connection do |conn|
              conn.set_server_option(::Trilogy::SET_SERVER_MULTI_STATEMENTS_ON)

              yield
            ensure
              conn.set_server_option(::Trilogy::SET_SERVER_MULTI_STATEMENTS_OFF)
            end
          end

          def combine_multi_statements(total_sql)
            total_sql.each_with_object([]) do |sql, total_sql_chunks|
              previous_packet = total_sql_chunks.last
              if max_allowed_packet_reached?(sql, previous_packet)
                total_sql_chunks << +sql
              else
                previous_packet << ";\n"
                previous_packet << sql
              end
            end
          end
      end
    end
  end
end
