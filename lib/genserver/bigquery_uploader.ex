
defmodule Genserver.BigqueryUploader do
    @moduledoc"""
    GenServer for uploading pending records to BigQuery.
    """

    use GenServer
    require Logger
    alias Genserver.Monitor
    import Time.Timem, only: [notification_frequency: 1]
    import Stuff, only: [random_string_generate: 1]


    @doc"""
    Starts the GenServer for data upload to BigQuery.

    ### Parameters:
        - business (atom): Business/context identifier.
        - data_source (list): ODBC connection configuration for BigQuery.
        - pg_config (map): PostgreSQL connection configuration.
        - info (list): List of maps with table configuration:
            - :bq_table (string): Full BigQuery table name.
            - :tipo (string): Type field value to filter records.
            - :pg_table (string): PostgreSQL table name for pending records.
        - periodicity (map): Activation periodicity map:
            - :day (integer): Days.
            - :hour (integer): Hours.
            - :minute (integer): Minutes.
            - :second (integer): Seconds.
        - batch_size (integer): Number of records to insert per batch.
        - webhook_url (string): Slack webhook URL for error notifications.

    ### Returns:
        - {:ok, pid} | {:error, reason}
    """
    def start_link({business, _data_source, _pg_config, _info, _periodicity, _batch_size, _webhook_url} = args) do
        GenServer.start_link(__MODULE__, args, name: :"#{__MODULE__}.#{business}")
    end

    @doc"""
    Initializes the GenServer state.

    ### Parameters:
        - Tuple with:
            - business (atom): Business identifier.
            - data_source (list): ODBC connection configuration for BigQuery.
            - pg_config (map): PostgreSQL connection configuration.
            - info (list): List of table configurations.
            - periodicity (map): Activation periodicity.
            - batch_size (integer): Number of records per batch.
            - webhook_url (string): Slack webhook URL for error notifications.

    ### Returns:
        - {:ok, state}
    """
    def init({business, data_source, pg_config, info, periodicity, batch_size, webhook_url}) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business))

        Logger.info("#{to_string(__MODULE__)}. Initializing. Business: ---#{to_string(business)}---")

        milliseconds_timeout = notification_frequency(periodicity)

        state = %{
            business: business,
            data_source: data_source,
            pg_config: pg_config,
            info: info,
            milliseconds_timeout: milliseconds_timeout,
            batch_size: batch_size,
            webhook_url: webhook_url
        }

        variable_wait(:start, milliseconds_timeout)

        {:ok, state}
    end

    @doc"""
    Handles the :update message that triggers the data upload to BigQuery.

    ### Parameters:
        - :update (atom): Activation message.
        - state (map): Current GenServer state.

    ### Returns:
        - {:noreply, state}
    """
    def handle_info(:update, state) do
        %{
            business: business,
            data_source: data_source,
            pg_config: pg_config,
            info: info,
            milliseconds_timeout: milliseconds_timeout,
            batch_size: batch_size,
            webhook_url: webhook_url
        } = state

        Enum.each(info, fn table_config ->
            batch_id = random_string_generate(15)

            bq_table = Map.fetch!(table_config, :bq_table)
            tipo = Map.fetch!(table_config, :tipo)
            pg_table = Map.fetch!(table_config, :pg_table)

            # run(business, data_source, pg_config, pg_table, bq_table, tipo, batch_id, batch_size, webhook_url)
        end)

        variable_wait(:later, milliseconds_timeout)
        {:noreply, state}
    end

    #
    # Adjusts the time for the genserver activation
    #
    # ### Parameters:
    #     - state: Atom. GenServer status. Possible values: :start and :later
    #     - milliseconds_timeout: Integer. Total milliseconds to reactivate the genserver.
    #
    defp variable_wait(:start, _milliseconds_timeout) do
        10 * 1_000
        |> :erlang.send_after(self(), :update)
    end

    defp variable_wait(:later, milliseconds_timeout) do
        milliseconds_timeout
        |> :erlang.send_after(self(), :update)
    end

end


defmodule A do

    require Logger
    alias Database.Postgres
    alias Statement.Sql
    alias Connection.Odbc
    alias Notification.Notify

    #
    # Uploads pending records to BigQuery
    #
    # ### Parameters:
    #     - business: Atom. Business type.
    #     - data_source: List. ODBC connection configuration for BigQuery.
    #     - pg_config: Map. PostgreSQL connection configuration.
    #     - pg_table: String. PostgreSQL table name for pending records.
    #     - bq_table: String. BigQuery table name.
    #     - tipo: String. Type field value to filter records.
    #     - batch_id: String. Batch identifier.
    #     - batch_size: Integer. Number of records per batch.
    #     - webhook_url: String. Slack webhook URL for error notifications.
    #
    # ### Returns:
    #     - {:ok, count} - Number of records uploaded
    #     - {:error, reason} - Upload error
    #
    def run(_business, data_source, pg_config, pg_table, bq_table, tipo, batch_id, batch_size, webhook_url) do
        {:ok, conn} = Postgres.connect(pg_config)

        Postgres.get_pending_bq(conn, pg_table, tipo)
        |> case do
            {:ok, records} when records == [] ->
                {:ok, 0}

            {:ok, records} ->
                # Build list of {record, query} tuples
                data =
                    records
                    |> Enum.map(fn record ->
                        {
                            record |> Map.get(:id_nodo),
                            record |> Map.get(:id),
                            record,
                            Sql.insert(bq_table, build_insert_values(record))
                        }
                    end)


                results = execute_insert_with_retry(data, data_source, batch_id, batch_size, webhook_url)

                uploaded_ids = get_uploaded_ids(results)
                if not Enum.empty?(uploaded_ids) do
                    Postgres.mark_as_sent_to_bq(conn, pg_table, uploaded_ids)
                end

                {:ok, length(uploaded_ids)}

            {:error, reason} ->
                Logger.error("Error getting pending records from #{pg_table}: #{inspect(reason)}")
                {:error, reason}
        end

        Postgres.disconnect(conn)
    end

    #
    # Builds the list of {column, value} tuples for SQL insert
    #
    # ### Parameters:
    #     - record: Map. Record with :informacion field containing the JSON data.
    #
    # ### Returns:
    #     - List of tuples {column, value}
    #
    defp build_insert_values(record) do
        record
        |> Map.get(:informacion)
        |> Poison.decode!()
        |> Map.to_list()
        |> Enum.map(fn {key, value} -> {String.to_atom(key), value} end)
    end

    #
    # Executes insertion with divide-and-conquer retry strategy.
    # If an error occurs, splits the data in half and retries each part.
    #
    # ### Parameters:
    #     - data: List of tuples {id_nodo, id, record, query} to insert
    #     - data_source: List. ODBC connection configuration
    #     - batch_id: String. Batch identifier for error logging
    #     - batch_size: Integer. Number of records per batch
    #     - webhook_url: String. Slack webhook URL for error notifications
    #
    # ### Returns:
    #     - List of tuples {:ok, id} | {:error, id}
    #
    def execute_insert_with_retry([], _data_source, _batch_id, _batch_size, _webhook_url), do: []

    def execute_insert_with_retry(data, data_source, batch_id, batch_size, webhook_url) do
        # Chunk data into batches and merge queries
        insert_tuples =
            data
            |> Enum.chunk_every(batch_size)
            |> Enum.map(&group_for_batch_insert/1)
            |> Enum.reject(&(&1 == []))

        # Execute inserts
        results = execute_insert(insert_tuples, data_source)

        has_errors? = Enum.any?(results, fn
            {:error, _} -> true
            _ -> false
        end)

        case {has_errors?, length(data)} do
            {false, _} ->
                Logger.info("---> Insert batch successful")
                results
                |> Enum.flat_map(fn {:ok, ids} -> Enum.map(ids, &{:ok, &1}) end)

            {true, 1} ->
                IO.puts("---> Single record failed")
                # Single record failed
                Enum.flat_map(results, fn
                    {:ok, ids} -> Enum.map(ids, &{:ok, &1})
                    {:error, {id_nodos, ids, records, error}} ->
                        handle_processing_error(batch_id, id_nodos, records, error, webhook_url)
                        Enum.map(ids, &{:error, &1})
                end)

            {true, _} ->
                Logger.info("Insert batch failed, splitting data in half and retrying...")

                mid = div(length(data), 2)
                {first_half, second_half} = Enum.split(data, mid)

                first_results = execute_insert_with_retry(first_half, data_source, batch_id, batch_size, webhook_url)
                second_results = execute_insert_with_retry(second_half, data_source, batch_id, batch_size, webhook_url)

                first_results ++ second_results
        end
    end

    #
    # Builds insertion tuples by combining multiple queries
    #
    # ### Parameters:
    #     - data: List of tuples {id_nodo, id, record, query}
    #
    # ### Returns:
    #     - {list_of_id_nodos, list_of_ids, list_of_records, merged_query} or [] if empty
    #
    defp group_for_batch_insert([]), do: []

    defp group_for_batch_insert(data) do
        {id_nodos, ids, records, queries} =
            data
            |> Enum.reduce(
                {[], [], [], []},
                fn {id_nodo, id, record, query}, {nodos_acc, ids_acc, records_acc, queries_acc} ->
                    {
                        nodos_acc ++ [id_nodo],
                        ids_acc ++ [id],
                        records_acc ++ [record],
                        queries_acc ++ [query]
                    }
                end
            )

        {id_nodos, ids, records, Sql.merge_inserts(queries)}
    end

    #
    # Executes the insert operation in BigQuery
    #
    # ### Parameters:
    #     - insert_tuples: List of tuples {id_nodos, ids, records, merged_query}
    #     - data_source: List. ODBC connection configuration
    #
    # ### Returns:
    #     - List of {:ok, ids} | {:error, {id_nodos, ids, records, error}}
    #
    defp execute_insert(insert_tuples, data_source) do
        Enum.map(insert_tuples, fn {id_nodos, ids, records, query} ->
            pid = Odbc.connect(data_source)
            try do
                Odbc.insert(pid, query)

                {:ok, ids}
            rescue
                error ->
                    {:error, {id_nodos, ids, records, error}}
            after
                Process.exit(pid, :kill)
            end
        end)
    end

    #
    # Extracts the IDs of successfully uploaded records
    #
    # ### Parameters:
    #     - results: List of {:ok, id} | {:error, id}
    #
    # ### Returns:
    #     - List of ids that were successfully uploaded
    #
    defp get_uploaded_ids(results) do
        results
        |> Enum.reduce(
            [],
            fn
                {:ok, id}, acc -> acc ++ [id]
                _, acc -> acc
            end
        )
    end

    #
    # Handles errors during record processing
    #
    # ### Parameters:
    #     - batch_id: String. Batch identifier
    #     - id_nodos: List. List of id_nodo values
    #     - records: List. List of failed records
    #     - error: Any. The error that occurred
    #     - webhook_url: String. Slack webhook URL for notifications
    #
    defp handle_processing_error(batch_id, id_nodos, records, error, webhook_url) do
        message = """
        *BigQuery Upload Error*
        Batch: #{batch_id}
        Records: #{inspect(id_nodos)}
        Error: #{inspect(error)}
        Failed Records: #{inspect(records, limit: :infinity)}
        """

        Logger.error(message)

        # Send notification to Slack
        Notify.notify_slack(
            webhook_url,
            [{"Content-type", "application/json"}],
            "BigQuery Uploader",
            message
        )
    end

end

"""
A.run(:tt, [dsn: "bigquery64", warehouse: "ttlchk-cloud.transferencia_vehiculos_qa"], %{hostname: "10.0.32.3", port: 5432, database: "etl_buffer", username: "etl_service", password: "Etl$3rv1c3_2024!", pool_size: 3}, "test_table", "ttlchk-cloud.transferencia_vehiculos_qa.expediente", "expediente", "batch_id", 100, "https://hooks.slack.com/services/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")
"""
