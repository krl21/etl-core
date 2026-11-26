defmodule Cleaning.CleanableTableTest do
    use ExUnit.Case, async: true

    defmodule FixtureDefaults do
        @moduledoc false
        use Cleaning.CleanableTable

        cleanable_table(
            business_key: :record,
            bigquery: %{table: "dataset.records", id_fields: [:unique_id], timestamp_field: :timestamp},
            postgres: %{table: "records"}
        )
    end

    defmodule FixtureOverrides do
        @moduledoc false
        use Cleaning.CleanableTable

        cleanable_table(
            business_key: :task,
            bigquery: %{table: "dataset.tasks", id_fields: [:unique_id], timestamp_field: :timestamp},
            postgres: %{table: "tasks", id_fields: [:pg_id], timestamp_field: :updated_at},
            enabled: false
        )
    end

    defmodule PlainBehaviourFixture do
        @moduledoc false
        use Cleaning.CleanableTable

        @impl true
        def business_key, do: :plain

        @impl true
        def bigquery_config, do: %{table: "x", id_fields: [:id], timestamp_field: :ts}

        @impl true
        def postgres_config, do: %{table: "x"}
    end

    describe "cleanable_table/1 — happy path" do
        test "exposes business_key/0, bigquery_config/0 and postgres_config/0" do
            assert FixtureDefaults.business_key() == :record
            assert FixtureDefaults.bigquery_config() == %{table: "dataset.records", id_fields: [:unique_id], timestamp_field: :timestamp}
            assert FixtureDefaults.postgres_config() == %{table: "records", id_fields: [:unique_id], timestamp_field: :timestamp}
        end

        test "postgres id_fields/timestamp_field default from the bigquery config when omitted" do
            assert FixtureDefaults.postgres_config().id_fields == [:unique_id]
            assert FixtureDefaults.postgres_config().timestamp_field == :timestamp
        end

        test "an explicit postgres id_fields/timestamp_field overrides the bigquery default" do
            assert FixtureOverrides.postgres_config().id_fields == [:pg_id]
            assert FixtureOverrides.postgres_config().timestamp_field == :updated_at
        end

        test "enabled?/0 defaults to true, and can be set to false" do
            assert FixtureDefaults.enabled?() == true
            assert FixtureOverrides.enabled?() == false
        end
    end

    describe "use Cleaning.CleanableTable without the cleanable_table/1 macro" do
        test "enabled?/0 still defaults to true and is overridable" do
            assert PlainBehaviourFixture.enabled?() == true
        end
    end

    describe "cleanable_table/1 — compile-time validation" do
        test "raises when :business_key is missing" do
            assert_raise ArgumentError, ~r/requires :business_key/, fn ->
                Code.eval_string("""
                defmodule Cleaning.CleanableTableTest.Missing.BusinessKey do
                    use Cleaning.CleanableTable
                    cleanable_table(
                        bigquery: %{table: "t", id_fields: [:id], timestamp_field: :ts},
                        postgres: %{table: "t"}
                    )
                end
                """)
            end
        end

        test "raises when the bigquery config is missing :id_fields" do
            assert_raise ArgumentError, ~r/bigquery config requires :id_fields/, fn ->
                Code.eval_string("""
                defmodule Cleaning.CleanableTableTest.Missing.IdFields do
                    use Cleaning.CleanableTable
                    cleanable_table(
                        business_key: :x,
                        bigquery: %{table: "t", timestamp_field: :ts},
                        postgres: %{table: "t"}
                    )
                end
                """)
            end
        end

        test "raises when the postgres config is missing :table" do
            assert_raise ArgumentError, ~r/postgres config requires :table/, fn ->
                Code.eval_string("""
                defmodule Cleaning.CleanableTableTest.Missing.PgTable do
                    use Cleaning.CleanableTable
                    cleanable_table(
                        business_key: :x,
                        bigquery: %{table: "t", id_fields: [:id], timestamp_field: :ts},
                        postgres: %{}
                    )
                end
                """)
            end
        end
    end
end
