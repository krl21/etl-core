defmodule DataModel.Schema.GeneratorTest do
    use ExUnit.Case, async: false

    import ExUnit.CaptureLog

    alias DataModel.Schema.Generator
    alias Struct.InfoAttr

    defmodule FakeEntity do
        @moduledoc false

        def attr_list, do: Agent.get(__MODULE__.Attrs, & &1)
        def bigquery_config, do: %{table: "dataset.fake_entity"}
        def business_key, do: :fake_entity
    end

    setup do
        start_supervised!(%{id: FakeEntity.Attrs, start: {Agent, :start_link, [fn -> [] end, [name: FakeEntity.Attrs]]}})

        priv_dir = Path.join(System.tmp_dir!(), "etl_core_generator_test_#{System.unique_integer([:positive])}")
        File.mkdir_p!(priv_dir)
        on_exit(fn -> File.rm_rf!(priv_dir) end)

        %{priv_dir: priv_dir}
    end

    defp set_attrs(attrs), do: Agent.update(FakeEntity.Attrs, fn _ -> attrs end)
    defp migration_files(priv_dir), do: priv_dir |> Path.join("fake_entity/*.exs") |> Path.wildcard()

    test "the first generate/2 for an entity produces a single create_table migration", %{priv_dir: priv_dir} do
        set_attrs([%InfoAttr{id: :nombre, type: :string}])

        assert {:generated, path} = Generator.generate(FakeEntity, priv_dir: priv_dir)
        assert Path.basename(path) == "1_create_table.exs"

        {migration, _bindings} = Code.eval_file(path)
        assert migration.version == 1
        assert migration.business_key == :fake_entity
        assert migration.operations == [
            %{op: :create_table, columns: [%{name: "nombre", type: "STRING", mode: "NULLABLE", description: nil}]}
        ]

        assert File.exists?(Path.join(priv_dir, "fake_entity/_schema.json"))
    end

    test "running generate/2 again with no changes produces no new file", %{priv_dir: priv_dir} do
        set_attrs([%InfoAttr{id: :nombre, type: :string}])
        assert {:generated, _path} = Generator.generate(FakeEntity, priv_dir: priv_dir)

        assert {:no_changes, :fake_entity} = Generator.generate(FakeEntity, priv_dir: priv_dir)
        assert length(migration_files(priv_dir)) == 1
    end

    test "a real change produces a second, sequentially-numbered migration", %{priv_dir: priv_dir} do
        set_attrs([%InfoAttr{id: :nombre, type: :string}])
        assert {:generated, _path} = Generator.generate(FakeEntity, priv_dir: priv_dir)

        set_attrs([%InfoAttr{id: :nombre, type: :string, description: "Nombre completo"}])
        assert {:generated, path} = Generator.generate(FakeEntity, priv_dir: priv_dir)

        assert Path.basename(path) == "2_alter_column_description_nombre.exs"
        {migration, _bindings} = Code.eval_file(path)
        assert migration.operations == [
            %{op: :alter_column_description, name: "nombre", description: "Nombre completo"}
        ]
    end

    test "a :required field is only honoured on the initial migration; later ones fall back to NULLABLE and warn", %{priv_dir: priv_dir} do
        set_attrs([%InfoAttr{id: :nombre, type: :string}])
        assert {:generated, _path} = Generator.generate(FakeEntity, priv_dir: priv_dir)

        set_attrs([
            %InfoAttr{id: :nombre, type: :string},
            %InfoAttr{id: :email, type: :string, description: "Email", constraint: :required}
        ])

        {result, log} =
            capture_result(fn -> Generator.generate(FakeEntity, priv_dir: priv_dir) end)

        assert {:generated, path} = result
        assert log =~ "required ignorado en email"

        {migration, _bindings} = Code.eval_file(path)
        assert migration.operations == [
            %{op: :add_column, column: %{name: "email", type: "STRING", mode: "NULLABLE", description: "Email"}}
        ]
    end

    test "a :required column already created produces no operation on a later generate/2, as long as it's unchanged", %{priv_dir: priv_dir} do
        set_attrs([%InfoAttr{id: :nombre, type: :string, constraint: :required}])
        assert {:generated, path1} = Generator.generate(FakeEntity, priv_dir: priv_dir)

        {migration1, _bindings} = Code.eval_file(path1)
        assert migration1.operations == [
            %{op: :create_table, columns: [%{name: "nombre", type: "STRING", mode: "REQUIRED", description: nil}]}
        ]

        # Same attrs, nothing changed: :required stays honoured, no operation proposed.
        assert {:no_changes, :fake_entity} = Generator.generate(FakeEntity, priv_dir: priv_dir)
        assert length(migration_files(priv_dir)) == 1
    end

    test "turning an existing NULLABLE column into :required in code is rejected silently (no operation), with a warning", %{priv_dir: priv_dir} do
        set_attrs([%InfoAttr{id: :nombre, type: :string}])
        assert {:generated, _path} = Generator.generate(FakeEntity, priv_dir: priv_dir)

        set_attrs([%InfoAttr{id: :nombre, type: :string, constraint: :required}])

        {result, log} = capture_result(fn -> Generator.generate(FakeEntity, priv_dir: priv_dir) end)

        assert {:no_changes, :fake_entity} = result
        assert log =~ "required ignorado en nombre"
        assert length(migration_files(priv_dir)) == 1
    end

    test "bootstrap/2 writes the schema snapshot without generating a migration file", %{priv_dir: priv_dir} do
        set_attrs([%InfoAttr{id: :nombre, type: :string, constraint: :required}])

        assert {:bootstrapped, :fake_entity} = Generator.bootstrap(FakeEntity, priv_dir: priv_dir)
        assert migration_files(priv_dir) == []
        assert File.exists?(Path.join(priv_dir, "fake_entity/_schema.json"))

        # bootstrap/2 never honours :required — it's only for tables that already
        # exist, and BigQuery only allows a REQUIRED column at table creation.
        snapshot = priv_dir |> Path.join("fake_entity/_schema.json") |> File.read!() |> Jason.decode!()
        assert [%{"mode" => "NULLABLE"}] = snapshot
    end

    # Runs `fun`, returning both its result and anything it logged — unlike
    # `ExUnit.CaptureLog.capture_log/1`, which only returns the captured log.
    defp capture_result(fun) do
        log = capture_log(fn -> send(self(), {:capture_result, fun.()}) end)
        receive do
            {:capture_result, result} -> {result, log}
        after
            0 -> flunk("expected fun to produce a result")
        end
    end
end
