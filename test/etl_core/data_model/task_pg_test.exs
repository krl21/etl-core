defmodule DataModel.TaskPgTest do
    use ExUnit.Case, async: true

    alias Struct.InfoAttr

    defmodule FixtureTaskPg do
        @moduledoc false
        use DataModel.TaskPg.Base

        @contentref %InfoAttr{id: :contentref, id_payload: "contentref", type: :string}
        @name %InfoAttr{id: :name, id_payload: "name", type: :string}
        @timestamp %InfoAttr{id: :timestamp, type: :integer}

        task_config(
            app: :etl_core_task_pg_test,
            table_name: "tasks",
            group_by_keys: [@contentref, @name],
            value_type: "tarea"
        )

        own_attributes [@contentref, @name]
        computed_attributes [@timestamp]

        generate_task_helper_functions()
    end

    test "attr_list/0 returns own + computed attributes" do
        assert FixtureTaskPg.attr_list() == [FixtureTaskPg.contentref(), FixtureTaskPg.name(), FixtureTaskPg.timestamp()]
    end

    test "table_name/0 returns the configured static table name" do
        assert FixtureTaskPg.table_name() == "tasks"
    end

    test "group_by_composite_key/1 groups by the configured keys" do
        payloads = [%{"contentref" => "c1", "name" => "n1"}, %{"contentref" => "c2", "name" => "n2"}]
        {_grouped, keys} = FixtureTaskPg.group_by_composite_key(payloads)
        assert Enum.sort(keys) == ["c1__n1", "c2__n2"]
    end

    test "build_data/1 extracts own attributes from the payload" do
        data = FixtureTaskPg.build_data([%{"contentref" => "c1", "name" => "n1"}])
        assert Keyword.get(data, :contentref) == "c1"
        assert Keyword.get(data, :name) == "n1"
    end

    describe "prepare_record/3" do
        test "builds a {:ok, record_map} with id_nodo/tipo/informacion" do
            assert {:ok, record} = FixtureTaskPg.prepare_record("batch1", "c1__n1", [%{"contentref" => "c1", "name" => "n1"}])

            assert record.id_nodo == "c1__n1"
            assert record.tipo == "tarea"
            assert record.informacion.contentref == "c1"
            assert record.informacion.name == "n1"
        end
    end
end
