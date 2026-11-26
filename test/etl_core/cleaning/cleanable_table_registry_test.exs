defmodule Cleaning.CleanableTableRegistryTest do
    use ExUnit.Case, async: false

    alias Cleaning.CleanableTableRegistry, as: Registry

    defmodule EnabledFixture do
        @moduledoc false
        @behaviour Cleaning.CleanableTable

        @impl true
        def business_key, do: :enabled_fixture

        @impl true
        def bigquery_config, do: %{table: "d.enabled", id_fields: [:id], timestamp_field: :ts}

        @impl true
        def postgres_config, do: %{table: "enabled"}

        @impl true
        def enabled?, do: true
    end

    defmodule DisabledFixture do
        @moduledoc false
        @behaviour Cleaning.CleanableTable

        @impl true
        def business_key, do: :disabled_fixture

        @impl true
        def bigquery_config, do: %{table: "d.disabled", id_fields: [:id], timestamp_field: :ts}

        @impl true
        def postgres_config, do: %{table: "disabled"}

        @impl true
        def enabled?, do: false
    end

    defmodule NotCleanable do
        @moduledoc false
        def hello, do: :world
    end

    setup do
        # The registry is a singleton GenServer (named after the module), backed
        # by an ETS table owned by that process. `start_supervised!` ties its
        # lifecycle to this test alone, so each test gets a genuinely fresh,
        # empty registry.
        start_supervised!(Registry)
        :ok
    end

    test "all/0 is empty until something registers" do
        assert Registry.all() == []
        assert :ok = Registry.register(EnabledFixture)
        assert Registry.all() == [EnabledFixture]
    end

    test "register/1 rejects a module that doesn't implement the behaviour" do
        assert {:error, :not_cleanable_table} = Registry.register(NotCleanable)
        refute NotCleanable in Registry.all()
    end

    test "register_all/1 registers every module in the list" do
        assert :ok = Registry.register_all([EnabledFixture, DisabledFixture])
        assert EnabledFixture in Registry.all()
        assert DisabledFixture in Registry.all()
    end

    test "enabled/0 filters out modules whose enabled?/0 returns false" do
        Registry.register_all([EnabledFixture, DisabledFixture])

        enabled = Registry.enabled()
        assert EnabledFixture in enabled
        refute DisabledFixture in enabled
    end

    test "get/1 finds a module by its business_key, or nil if none matches" do
        Registry.register(EnabledFixture)

        assert Registry.get(:enabled_fixture) == EnabledFixture
        assert Registry.get(:no_such_business_key) == nil
    end

    test "bigquery_configs/0 and postgres_configs/0 are keyed by business_key, enabled modules only" do
        Registry.register_all([EnabledFixture, DisabledFixture])

        bq = Registry.bigquery_configs()
        assert bq[:enabled_fixture] == %{table: "d.enabled", id_fields: [:id], timestamp_field: :ts}
        refute Map.has_key?(bq, :disabled_fixture)
    end
end
