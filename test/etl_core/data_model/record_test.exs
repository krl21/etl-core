defmodule DataModel.RecordTest do
    use ExUnit.Case, async: false

    import Mox

    setup :verify_on_exit!

    alias Struct.InfoAttr

    defmodule FixtureRecord do
        @moduledoc false
        use DataModel.Record.Base

        @unique_id %InfoAttr{id: :unique_id, id_payload: "unique_id", type: :string}
        @timestamp %InfoAttr{id: :timestamp, type: :integer}
        @nombre %InfoAttr{id: :nombre, id_payload: "nombre", type: :string}

        entity_config(
            app: :etl_core_record_test,
            table_key: :record,
            batch_size_key: :batch_size,
            unique_id: @unique_id,
            timestamp: @timestamp
        )

        own_attributes [@unique_id, @timestamp, @nombre]
        subentities []
        special_post_processing []

        generate_helper_functions()
    end

    defmodule FixtureRecordRetry do
        @moduledoc false
        use DataModel.Record.Base

        @unique_id %InfoAttr{id: :unique_id, id_payload: "unique_id", type: :string}

        entity_config(
            app: :etl_core_record_retry_test,
            table_key: :record,
            batch_size_key: :batch_size,
            unique_id: @unique_id
        )

        own_attributes [@unique_id]
        subentities []
        special_post_processing []

        generate_helper_functions()

        # Overrides the real (Odbc-backed) `execute_insert/1` so the
        # divide-and-conquer retry logic in `execute_insert_with_retry/2` can be
        # exercised deterministically, with no mocking at all: any chunk whose
        # ids include one marked as failing (via the process dictionary, since
        # everything here runs in the test's own process) reports an error.
        def execute_insert(data) do
            failing_ids = Process.get(:test_failing_ids, MapSet.new())

            Enum.map(data, fn {ids, _query} ->
                if Enum.any?(ids, &MapSet.member?(failing_ids, &1)) do
                    {:error, {ids, %RuntimeError{message: "simulated failure"}}}
                else
                    {:ok, ids}
                end
            end)
        end
    end

    setup do
        Application.put_env(:etl_core_record_test, :bigquery, table: %{record: "dataset.record"}, configuration: [dsn: "x"])
        Application.put_env(:etl_core_record_test, :batch_size, 10)
        # batch_size: 1 so every record is its own chunk/own call to
        # execute_insert/1 below — keeps the expected :ok/:error lists aligned
        # 1:1 with the input records, instead of with (fewer) merged chunks.
        Application.put_env(:etl_core_record_retry_test, :batch_size, 1)

        on_exit(fn ->
            Application.delete_env(:etl_core_record_test, :bigquery)
            Application.delete_env(:etl_core_record_test, :batch_size)
            Application.delete_env(:etl_core_record_retry_test, :batch_size)
        end)
    end

    describe "pure building blocks" do
        test "attr_list/0 returns exactly the own attributes (no subentities here)" do
            assert FixtureRecord.attr_list() == [
                FixtureRecord.unique_id(),
                FixtureRecord.timestamp(),
                FixtureRecord.nombre()
            ]
        end

        test "filter_batch/1 is the identity function by default" do
            assert FixtureRecord.filter_batch([%{"a" => 1}]) == [%{"a" => 1}]
        end

        test "group_by_unique_id/1 groups payloads by the configured unique_id attribute" do
            payloads = [%{"unique_id" => "A"}, %{"unique_id" => "A"}, %{"unique_id" => "B"}]
            {grouped, keys} = FixtureRecord.group_by_unique_id(payloads)

            assert Enum.sort(keys) == ["A", "B"]
            assert length(grouped["A"]) == 2
            assert length(grouped["B"]) == 1
        end

        test "fetch_stored_data/2 defaults to {:ok, %{}}" do
            assert FixtureRecord.fetch_stored_data(["A"], nil) == {:ok, %{}}
        end

        test "build_data/3 extracts attributes from the most recent payload" do
            data = FixtureRecord.build_data([%{"nombre" => "old"}, %{"nombre" => "new"}], [], nil)
            assert Keyword.get(data, :nombre) == "new"
        end

        test "prepare_insert_query/4 builds an INSERT statement, stamped with a timestamp" do
            assert {:ok, {"A", query}} =
                FixtureRecord.prepare_insert_query("A", [%{"nombre" => "x"}], [], nil)

            assert query =~ "INSERT INTO dataset.record"
            assert query =~ "'x'"
            assert query =~ to_string(FixtureRecord.timestamp_attr().id)
        end

        test "build_insert_tuples/1 merges several prepared queries into one, keeping all keys" do
            {:ok, q1} = FixtureRecord.prepare_insert_query("A", [%{"nombre" => "x"}], [], nil)
            {:ok, q2} = FixtureRecord.prepare_insert_query("B", [%{"nombre" => "y"}], [], nil)

            {keys, merged} = FixtureRecord.build_insert_tuples([q1, q2])

            assert keys == ["A", "B"]
            assert merged =~ "'x'"
            assert merged =~ "'y'"
        end

        test "build_insert_tuples/1 on an empty list is a no-op" do
            assert FixtureRecord.build_insert_tuples([]) == []
        end
    end

    describe "execute_insert/1 (Mox: Connection.Odbc, via EtlCore.Deps)" do
        test "connects, inserts the merged query, and tears down the connection afterward" do
            dummy_pid = spawn(fn -> Process.sleep(:infinity) end)

            Connection.OdbcMock
            |> expect(:connect, fn _config -> dummy_pid end)
            |> expect(:insert, fn pid, query ->
                assert pid == dummy_pid
                assert query =~ "INSERT INTO"
                {:updated, 1}
            end)

            assert FixtureRecord.execute_insert([{["A"], "INSERT INTO dataset.record (nombre) VALUES ('x');"}]) ==
                [{:ok, ["A"]}]

            refute Process.alive?(dummy_pid)
        end

        test "an Odbc error is caught and reported as {:error, {ids, error}}, not raised" do
            dummy_pid = spawn(fn -> Process.sleep(:infinity) end)

            Connection.OdbcMock
            |> expect(:connect, fn _config -> dummy_pid end)
            |> expect(:insert, fn _pid, _query -> raise "boom" end)

            assert [{:error, {["A"], %RuntimeError{}}}] =
                FixtureRecord.execute_insert([{["A"], "INSERT INTO dataset.record (nombre) VALUES ('x');"}])
        end
    end

    describe "execute_insert_with_retry/2 — divide-and-conquer control flow (execute_insert overridden, no mocking)" do
        test "no errors at all: every record reports :ok" do
            Process.put(:test_failing_ids, MapSet.new())

            data = [{"A", "qA"}, {"B", "qB"}]
            assert FixtureRecordRetry.execute_insert_with_retry(data, "batch1") == [:ok, :ok]
        end

        test "a single failing record, alone, reports :error without raising" do
            Process.put(:test_failing_ids, MapSet.new(["A"]))

            assert FixtureRecordRetry.execute_insert_with_retry([{"A", "qA"}], "batch1") == [:error]
        end

        test "one bad record among several: the batch is halved until the bad one is isolated" do
            Process.put(:test_failing_ids, MapSet.new(["B"]))

            data = [{"A", "qA"}, {"B", "qB"}]
            assert FixtureRecordRetry.execute_insert_with_retry(data, "batch1") == [:ok, :error]
        end

        test "an empty batch returns an empty result immediately" do
            assert FixtureRecordRetry.execute_insert_with_retry([], "batch1") == []
        end
    end
end
