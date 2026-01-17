
defmodule Cleaning.CleanableTable.Macro do
    @moduledoc """
    Macro to simplify the implementation of CleanableTable behaviour.
    """

    @doc """
    Macro to define cleanable table configuration in a declarative way.

    ## Options
        - `:business_key` (required) - Atom identifying this entity type
        - `:bigquery` (required) - Map with BigQuery configuration
            - `:table` (required) - Full table name
            - `:id_fields` (required) - List of atoms for ID fields
            - `:timestamp_field` (required) - Atom for timestamp field
            - `:partition_field` (optional) - Atom for partition field
        - `:postgres` (required) - Map with PostgreSQL configuration
            - `:table` (required) - Table name
            - `:id_fields` (optional) - List of atoms (defaults to bigquery)
            - `:timestamp_field` (optional) - Atom (defaults to bigquery)
        - `:enabled` (optional) - Boolean, defaults to true

    ## Example

    ```elixir
    cleanable_table(
        business_key: :record,
        bigquery: %{
            table: "my_dataset.records",
            id_fields: [:unique_id],
            timestamp_field: :timestamp
        },
        postgres: %{
            table: "records"
        }
    )
    ```
    """
    defmacro cleanable_table(opts) do
        quote bind_quoted: [opts: opts] do
        # Validate required options
        unless Keyword.has_key?(opts, :business_key) do
            raise ArgumentError, "cleanable_table requires :business_key option"
        end

        unless Keyword.has_key?(opts, :bigquery) do
            raise ArgumentError, "cleanable_table requires :bigquery option"
        end

        unless Keyword.has_key?(opts, :postgres) do
            raise ArgumentError, "cleanable_table requires :postgres option"
        end

        bq_config = Keyword.fetch!(opts, :bigquery)
        pg_config = Keyword.fetch!(opts, :postgres)
        business_key = Keyword.fetch!(opts, :business_key)
        enabled = Keyword.get(opts, :enabled, true)

        # Validate BigQuery config
        unless Map.has_key?(bq_config, :table) do
            raise ArgumentError, "bigquery config requires :table"
        end

        unless Map.has_key?(bq_config, :id_fields) do
            raise ArgumentError, "bigquery config requires :id_fields"
        end

        unless Map.has_key?(bq_config, :timestamp_field) do
            raise ArgumentError, "bigquery config requires :timestamp_field"
        end

        # Validate PostgreSQL config
        unless Map.has_key?(pg_config, :table) do
            raise ArgumentError, "postgres config requires :table"
        end

        # Store configuration
        @cleanable_business_key business_key
        @cleanable_bq_config bq_config
        @cleanable_pg_config pg_config
        @cleanable_enabled enabled

        @impl Cleaning.CleanableTable
        def business_key, do: @cleanable_business_key

        @impl Cleaning.CleanableTable
        def bigquery_config, do: @cleanable_bq_config

        @impl Cleaning.CleanableTable
        def postgres_config do
            # Merge with defaults from BigQuery config
            bq = @cleanable_bq_config
            pg = @cleanable_pg_config

            %{
            table: pg.table,
            id_fields: Map.get(pg, :id_fields, bq.id_fields),
            timestamp_field: Map.get(pg, :timestamp_field, bq.timestamp_field)
            }
        end

        @impl Cleaning.CleanableTable
        def enabled?, do: @cleanable_enabled

        # Register this module as a cleanable table
        @after_compile {Cleaning.CleanableTableRegistry, :register_module}
        end
    end

end
