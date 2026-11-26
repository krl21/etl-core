defmodule DataModel.RecordPgTest do
    use ExUnit.Case, async: false

    alias Struct.InfoAttr

    defmodule FixtureRecordPg do
        @moduledoc false
        use DataModel.RecordPg.Base

        @unique_id %InfoAttr{id: :unique_id, id_payload: "unique_id", type: :string}
        @nombre %InfoAttr{id: :nombre, id_payload: "nombre", type: :string}

        entity_config(
            app: :etl_core_record_pg_test,
            table_name: "records",
            batch_size_key: :batch_size,
            unique_id: @unique_id,
            value_type: "expediente"
        )

        own_attributes [@unique_id, @nombre]
        subentities []
        special_post_processing []

        generate_helper_functions()
    end

    defmodule FixtureRecordPgMultiRow do
        @moduledoc false
        use DataModel.RecordPg.Base

        @unique_id %InfoAttr{id: :unique_id, id_payload: "unique_id", type: :string}

        entity_config(
            app: :etl_core_record_pg_multi_test,
            table_name: "records",
            batch_size_key: :batch_size,
            unique_id: @unique_id,
            value_type: "expediente"
        )

        own_attributes [@unique_id]
        subentities []
        special_post_processing []

        generate_helper_functions()

        # Simulates an entity that expands one message into several DB rows.
        def build_data(_payloads, _stored_data, _additional_info) do
            [[unique_id: "A", n: 1], [unique_id: "A", n: 2]]
        end
    end

    defmodule FixtureRecordPgRaising do
        @moduledoc false
        use DataModel.RecordPg.Base

        @unique_id %InfoAttr{id: :unique_id, type: :string}

        entity_config(app: :etl_core_record_pg_raise_test, table_name: "t", batch_size_key: :batch_size, unique_id: @unique_id)

        own_attributes [@unique_id]
        subentities []
        special_post_processing []

        generate_helper_functions()

        def build_data(_payloads, _stored_data, _additional_info), do: raise("boom")
    end

    test "attr_list/0 returns the own attributes" do
        assert FixtureRecordPg.attr_list() == [FixtureRecordPg.unique_id(), FixtureRecordPg.nombre()]
    end

    test "filter_batch/1 is the identity function by default" do
        assert FixtureRecordPg.filter_batch([%{"a" => 1}]) == [%{"a" => 1}]
    end

    test "group_by_unique_id/1 groups by the configured unique_id attribute" do
        payloads = [%{"unique_id" => "A"}, %{"unique_id" => "B"}]
        {grouped, keys} = FixtureRecordPg.group_by_unique_id(payloads)
        assert Enum.sort(keys) == ["A", "B"]
        assert map_size(grouped) == 2
    end

    test "build_data/3 extracts attributes from the most recent payload" do
        data = FixtureRecordPg.build_data([%{"nombre" => "old"}, %{"nombre" => "new"}], [], nil)
        assert Keyword.get(data, :nombre) == "new"
    end

    describe "prepare_record/4" do
        test "a single-row build_data result becomes {:ok, :single, record_map}" do
            assert {:ok, :single, record} = FixtureRecordPg.prepare_record("A", [%{"nombre" => "x"}], [], nil)
            assert record.id_nodo == "A"
            assert record.tipo == "expediente"
            assert record.informacion.nombre == "x"
        end

        test "a multi-row build_data result becomes {:ok, :multi, [record_map, ...]}" do
            assert {:ok, :multi, records} = FixtureRecordPgMultiRow.prepare_record("A", [%{}], [], nil)
            assert length(records) == 2
            assert Enum.all?(records, &(&1.id_nodo == "A" and &1.tipo == "expediente"))
            assert Enum.map(records, & &1.informacion.n) == [1, 2]
        end

        test "an error building the data is caught and reported, not raised" do
            assert {:error, %RuntimeError{}} = FixtureRecordPgRaising.prepare_record("A", [%{}], [], nil)
        end
    end
end
