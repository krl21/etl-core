
defmodule Cleaning.CleanableTable do
    @moduledoc """
    Behaviour that defines the required configuration for tables that need cleaning.

    Any module that implements this behaviour MUST define:
    - BigQuery table configuration (table name, ID fields, timestamp field)
    - PostgreSQL table configuration (table name)

    ## Usage

    ```elixir
    defmodule MyApp.Entity.Record do
        @behaviour Cleaning.CleanableTable

        @impl true
        def bigquery_config do
        %{
            table: "dataset.my_records",
            id_fields: [:unique_id],
            timestamp_field: :timestamp
        }
        end

        @impl true
        def postgres_config do
        %{
            table: "my_records"
        }
        end

        @impl true
        def business_key, do: :record
    end
    ```

    Or use the convenience macro:

    ```elixir
    defmodule MyApp.Entity.Record do
        use Cleaning.CleanableTable

        cleanable_table(
        business_key: :record,
        bigquery: %{
            table: "dataset.my_records",
            id_fields: [:unique_id],
            timestamp_field: :timestamp
        },
        postgres: %{
            table: "my_records"
        }
        )
    end
    ```
    """

    @doc """
    Returns the BigQuery configuration for this cleanable table.

    ## Required Keys
        - `:table` - Full BigQuery table name (dataset.table)
        - `:id_fields` - List of atoms representing the fields that form the unique identifier
        - `:timestamp_field` - Atom representing the field used to determine freshness

    ## Optional Keys
        - `:partition_field` - Atom for partition field (if table is partitioned)
    """
    @callback bigquery_config() :: %{
        table: String.t(),
        id_fields: [atom()],
        timestamp_field: atom(),
        optional(:partition_field) => atom()
    }

    @doc """
    Returns the PostgreSQL configuration for this cleanable table.

    ## Required Keys
        - `:table` - PostgreSQL table name

    ## Optional Keys
        - `:id_fields` - List of atoms for ID fields (defaults to bigquery id_fields)
        - `:timestamp_field` - Atom for timestamp field (defaults to bigquery timestamp_field)
    """
    @callback postgres_config() :: %{
        table: String.t(),
        optional(:id_fields) => [atom()],
        optional(:timestamp_field) => atom()
    }

    @doc """
    Returns the business key that identifies this entity type.
    Used for routing in cleaning operations.
    """
    @callback business_key() :: atom()

    @doc """
    Optional callback to determine if this table should be cleaned.
    Defaults to true.
    """
    @callback enabled?() :: boolean()

    @optional_callbacks [enabled?: 0]

    defmacro __using__(_opts) do
        quote do
            @behaviour Cleaning.CleanableTable
            import Cleaning.CleanableTable.Macro

            # Default implementation for enabled?
            @impl Cleaning.CleanableTable
            def enabled?, do: true

            defoverridable enabled?: 0
        end
    end
end
