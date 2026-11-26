defmodule DataModel.TaskTest do
    use ExUnit.Case, async: false

    alias Struct.InfoAttr

    defmodule FixtureTask do
        @moduledoc false
        use DataModel.Task.Base

        @contentref %InfoAttr{id: :contentref, id_payload: "contentref", type: :string}
        @name %InfoAttr{id: :name, id_payload: "name", type: :string}
        @status %InfoAttr{id: :status, id_payload: "status", type: :string}
        @timestamp %InfoAttr{id: :timestamp, type: :integer}

        task_config(app: :etl_core_task_test, table_key: :task, group_by_keys: [@contentref, @name])

        own_attributes [@contentref, @name, @status]
        computed_attributes [@timestamp]

        generate_task_helper_functions()
    end

    # Reuses the `:test_business` business defined in `Time.WorkingTimeTest`
    # (`defimpl Time.PWorkingTimeForBusiness, for: DateTime` — protocol impls
    # are global once compiled, not scoped to one test file).
    defmodule FixtureTaskWithElapsed do
        @moduledoc false
        use DataModel.Task.Base

        @contentref %InfoAttr{id: :contentref, type: :string}
        @start_date %InfoAttr{id: :start_date, type: :string}
        @end_date %InfoAttr{id: :end_date, type: :string}
        @elapsed %InfoAttr{id: :elapsed_working_time, type: :integer, default_value: -1}
        @timestamp %InfoAttr{id: :timestamp, type: :integer}

        task_config(
            app: :etl_core_task_elapsed_test,
            table_key: :task,
            group_by_keys: [@contentref],
            elapsed_time_config: %{
                start_date_attr: @start_date,
                end_date_attr: @end_date,
                target_attr: @elapsed,
                business: :test_business,
                change_timezone: false
            }
        )

        own_attributes [@contentref, @start_date, @end_date]
        computed_attributes [@elapsed, @timestamp]

        generate_task_helper_functions()
    end

    test "attr_list/0 returns own attributes followed by computed attributes" do
        assert FixtureTask.attr_list() == [
            FixtureTask.contentref(),
            FixtureTask.name(),
            FixtureTask.status(),
            FixtureTask.timestamp()
        ]
    end

    test "table_id/0 resolves the table from Application config via :table_key" do
        Application.put_env(:etl_core_task_test, :bigquery, table: %{task: "dataset.task"})
        on_exit(fn -> Application.delete_env(:etl_core_task_test, :bigquery) end)

        assert FixtureTask.table_id() == "dataset.task"
    end

    test "group_by_composite_key/1 groups by the configured keys" do
        payloads = [
            %{"contentref" => "c1", "name" => "n1"},
            %{"contentref" => "c1", "name" => "n1"},
            %{"contentref" => "c2", "name" => "n2"}
        ]

        {grouped, keys} = FixtureTask.group_by_composite_key(payloads)
        assert Enum.sort(keys) == ["c1__n1", "c2__n2"]
        assert length(grouped["c1__n1"]) == 2
    end

    describe "build_data/1" do
        test "extracts own attributes from a single payload" do
            data = FixtureTask.build_data([%{"contentref" => "c1", "name" => "n1", "status" => "ok"}])
            assert Keyword.get(data, :contentref) == "c1"
            assert Keyword.get(data, :name) == "n1"
            assert Keyword.get(data, :status) == "ok"
        end

        test "merges multiple payloads, the latest value winning per field" do
            data = FixtureTask.build_data([
                %{"contentref" => "c1", "name" => "n1", "status" => "pending"},
                %{"contentref" => "c1", "name" => "n1", "status" => "done"}
            ])

            assert Keyword.get(data, :status) == "done"
        end
    end

    describe "parse_composite_key/1" do
        test "splits on the first '__', keeping any further '__' in the second part" do
            assert FixtureTask.parse_composite_key("c1__n1") == {"c1", "n1"}
            assert FixtureTask.parse_composite_key("c1__n1__extra") == {"c1", "n1__extra"}
        end

        test "no separator: the whole string as the first element, nil as the second" do
            assert FixtureTask.parse_composite_key("no-separator") == {"no-separator", nil}
        end

        test "a non-binary input yields {nil, nil}" do
            assert FixtureTask.parse_composite_key(nil) == {nil, nil}
        end
    end

    describe "calculate_elapsed_time/1" do
        test "is a no-op when no elapsed_time_config is set" do
            assert FixtureTask.calculate_elapsed_time([a: 1]) == [a: 1]
        end

        test "computes the elapsed working time when both dates are present" do
            start_date = Timex.to_datetime({{2024, 1, 8}, {10, 0, 0}})
            end_date = Timex.to_datetime({{2024, 1, 8}, {14, 0, 0}})

            result = FixtureTaskWithElapsed.calculate_elapsed_time(start_date: start_date, end_date: end_date)
            assert Keyword.get(result, :elapsed_working_time) == 4 * 3600
        end

        test "falls back to the attribute's default_value when a date is missing" do
            result = FixtureTaskWithElapsed.calculate_elapsed_time(start_date: nil)
            assert Keyword.get(result, :elapsed_working_time) == -1
        end
    end
end
