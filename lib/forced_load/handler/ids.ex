
defmodule ForcedLoad.Handler.Ids do
    @moduledoc """
    Fetching of the IDs to load in `ForcedLoad.Handler`, from BigQuery and ElasticSearch. See `fetch_all/4`.
    """

    alias Connection.ElasticSearch
    alias Connection.Odbc
    alias Statement.Sql
    alias ForcedLoad.Helpers


    @doc """
    Fetches unique IDs from both BigQuery and ElasticSearch, applies optional filter.

    ### Parameters
        - start_date: DateTime. Start of date range
        - end_date: DateTime. End of date range
        - bq_pid: pid | nil. BigQuery ODBC connection process
        - config: map. Configuration options

    ### Returns
        - list. Unique IDs from both sources, optionally filtered
    """
    def fetch_all(start_date, end_date, bq_pid, config) do
        bq_ids = fetch_ids_from_bigquery(start_date, end_date, bq_pid, config)
        es_ids = fetch_ids_from_elasticsearch(start_date, end_date, config)

        all_ids = (bq_ids ++ es_ids) |> Enum.uniq()

        # Apply ID filter if configured
        case Map.get(config, :id_filter) do
            nil -> all_ids
            filter_fn when is_function(filter_fn, 1) -> filter_fn.(all_ids)
        end
    end


    #
    # Fetches IDs from BigQuery using the provided connection or custom function.
    #
    # ### Parameters
    #     - start_date: DateTime. Start of date range
    #     - end_date: DateTime. End of date range
    #     - bq_pid: pid. BigQuery ODBC connection process
    #     - config: map. Configuration options
    #
    # ### Returns
    #     - list. List of unique IDs from BigQuery
    #
    defp fetch_ids_from_bigquery(_start_date, _end_date, nil, _config), do: []

    defp fetch_ids_from_bigquery(start_date, end_date, bq_pid, config) do
        case Map.get(config, :get_ids_fn) do
            nil -> default_get_ids_bq(start_date, end_date, bq_pid, config)
            custom_fn -> custom_fn.(start_date, end_date, bq_pid, config)
        end
    end


    #
    # Fetches IDs from BigQuery using the provided connection or custom function.
    # Returns empty list if bq_pid is nil (BigQuery skipped).
    #
    # ### Parameters
    #     - start_date: DateTime. Start of date range
    #     - end_date: DateTime. End of date range
    #     - bq_pid: pid. BigQuery ODBC connection process
    #     - config: map. Configuration options
    #
    # ### Returns
    #     - list. List of unique IDs from BigQuery
    #
    defp fetch_ids_from_elasticsearch(start_date, end_date, config) do
        if Map.get(config, :skip_elasticsearch, false) do
            []
        else
            case Map.get(config, :get_ids_es_fn) do
                nil -> default_get_ids_es(start_date, end_date, config)
                custom_fn -> custom_fn.(start_date, end_date, config)
            end
        end
    end


    #
    # Default implementation for fetching IDs from BigQuery.
    # Builds SQL SELECT query and executes against BigQuery via ODBC.
    #
    # ### Parameters
    #     - start_date: DateTime. Start of date range
    #     - end_date: DateTime. End of date range
    #     - bq_pid: pid. BigQuery ODBC connection process
    #     - config: map. Must contain :bigquery_table, :unique_id_field, :last_update_field
    #
    # ### Returns
    #     - list. List of unique IDs from BigQuery
    #
    defp default_get_ids_bq(start_date, end_date, bq_pid, config) do
        bigquery_table = Map.fetch!(config, :bigquery_table)
        unique_id_field = Map.fetch!(config, :unique_id_field)
        last_update_field = Map.fetch!(config, :last_update_field)

        statement = Sql.select(
            bigquery_table,
            [unique_id_field],
            [[
                {
                    last_update_field,
                    start_date |> Poison.encode!() |> Poison.decode!(),
                    :gte,
                    :timestamp
                },
                {
                    last_update_field,
                    end_date |> Poison.encode!() |> Poison.decode!(),
                    :lte,
                    :timestamp
                }
            ]],
            [:and]
        )

        try do
            Odbc.select(bq_pid, statement)
            |> Enum.map(fn [{_, id}] -> id end)
        rescue
            error ->
                Helpers.notify(config, "Error al obtener IDs de BigQuery: #{inspect(error)}", :error)
                []
        end
    end


    #
    # Default implementation for fetching IDs from ElasticSearch.
    # Queries ElasticSearch for documents within the date range.
    #
    # ### Parameters
    #     - start_date: DateTime. Start of date range
    #     - end_date: DateTime. End of date range
    #     - config: map. Must contain :documentary_type, :unique_id_payload_field, :last_update_payload_field
    #
    # ### Returns
    #     - list. List of unique IDs from ElasticSearch
    #
    defp default_get_ids_es(start_date, end_date, config) do
        documentary_type = Map.fetch!(config, :documentary_type)
        unique_id_payload_field = Map.fetch!(config, :unique_id_payload_field)
        last_update_payload_field = Map.fetch!(config, :last_update_payload_field)
        es_config = Helpers.get_elasticsearch_config(config)

        ElasticSearch.get_from_range(
            es_config.url,
            es_config.headers,
            documentary_type,
            ElasticSearch.mode(),
            start_date |> Poison.encode!() |> Poison.decode!(),
            end_date |> Poison.encode!() |> Poison.decode!(),
            last_update_payload_field,
            unique_id_payload_field
        )
        |> case do
            {:ok, list} -> list
            {:error, error} ->
                Helpers.notify(config, "Error al obtener IDs de ElasticSearch: #{inspect(error)}", :error)
                []
        end
    end


end
