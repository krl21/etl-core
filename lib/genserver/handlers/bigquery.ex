
defmodule Genserver.Handlers.Bigquery do
    @moduledoc """
    Handler module for BigQuery upload operations.
    Contains the core logic for fetching records from PostgreSQL,
    building queries, and uploading to BigQuery with retry mechanisms.
    """

    require Logger
    alias Connection.Postgres
    alias Statement.Sql
    alias Connection.Odbc
    alias Notification.Notify
    alias Genserver.Protocols.PBigqueryPostProcess

    @doc """
    Uploads pending records to BigQuery.

    ### Parameters:
        - business: Atom. Business type.
        - bq_conn: pid. Active BigQuery ODBC connection (persistent, not closed here).
        - pg_conn: pid | Map. Active PostgreSQL connection (persistent, not closed here).
        - pg_table: String. PostgreSQL table name for pending records.
        - bq_table: String. BigQuery table name.
        - tipo: String. Type field value to filter records.
        - batch_id: String. Batch identifier.
        - batch_size: Integer. Number of records per batch.
        - webhook_url: String. Slack webhook URL for error notifications.

    ### Returns:
        - {:ok, count} - Number of records uploaded
        - {:error, reason} - Upload error
    """
    def run(business, bq_conn, pg_conn, pg_table, bq_table, tipo, batch_id, batch_size, webhook_url) do
        Postgres.get_pending_bq(pg_conn, pg_table, tipo)
        |> case do
            {:ok, records} when records == [] ->
                {:ok, 0}

            {:ok, records} ->

                # Procesa cada grupo, insertando en Bigquery el registro más actualizado posible
                {successful_ids, failed_ids, uploaded_count} =
                    records
                    |> Enum.group_by(&Map.get(&1, :id_nodo))
                    |> process_grouped_records(
                        bq_table,
                        bq_conn,
                        batch_id,
                        batch_size,
                        webhook_url
                    )

                # Marca como enviado en Bigquery los registros exitosos
                if not Enum.empty?(successful_ids) do
                    Postgres.mark_as_sent_to_bq(pg_conn, pg_table, successful_ids)
                end

                # Marca como con problemas los registros fallidos que se analizaron antes de los exitosos
                if not Enum.empty?(failed_ids) do
                    Postgres.mark_as_with_problems(pg_conn, pg_table, failed_ids)
                end

                run_post_process(business, tipo, %{
                    uploaded_count: uploaded_count,
                    successful_ids: successful_ids,
                    failed_ids: failed_ids,
                    batch_id: batch_id,
                    bq_table: bq_table,
                    bq_conn: bq_conn,
                    pg_table: pg_table,
                    pg_conn: pg_conn
                })

                {:ok, uploaded_count}

            {:error, reason} ->
                Logger.error("Error al obtener registros pendientes de #{pg_table}: #{inspect(reason)}")
                {:error, reason}
        end
    end

    #
    # Processes grouped records, trying to insert the most recent record for each group. If insertion fails, tries the next most recent record.
    #
    # ### Parameters:
    #     - grouped_records: Map of id_nodo => sorted records list
    #     - bq_table: String. BigQuery table name
    #     - bq_conn: pid. Active BigQuery ODBC connection
    #     - batch_id: String. Batch identifier
    #     - batch_size: Integer. Number of records per batch
    #     - webhook_url: String. Slack webhook URL
    #
    # ### Returns:
    #     - {list_of_successful_ids, list_of_failed_ids, count_of_uploaded_records}
    #
    defp process_grouped_records(grouped_records, bq_table, bq_conn, batch_id, batch_size, webhook_url) do
        # Extrae el registro más actualizado de cada grupo para la inserción por lotes
        {records_to_insert, group_info} =
            grouped_records
            |> Enum.map(fn {id_nodo, [most_recent | rest]} ->
                all_ids = Enum.map([most_recent | rest], &Map.get(&1, :id))
                {most_recent, {id_nodo, all_ids, rest}}
            end)
            |> Enum.unzip()

        # Construye los datos de inserción para los registros más actualizados
        data =
            records_to_insert
            |> Enum.map(fn record ->
                {
                    Map.get(record, :id_nodo),
                    Map.get(record, :id),
                    record,
                    Sql.insert(bq_table, build_insert_values(record))
                }
            end)

        # Ejecuta la inserción por lotes con retry
        results = execute_insert_with_retry(data, bq_conn, batch_id, batch_size, webhook_url)

        # Procesa los resultados y maneja los fallos
        process_insert_results(results, group_info, bq_table, bq_conn, batch_id, batch_size, webhook_url)
    end

    #
    # Processes insert results and handles failures by trying alternative records
    #
    # ### Parameters:
    #     - results: List of {:ok, id} | {:error, id}
    #     - group_info: List of {id_nodo, all_ids, remaining_records}
    #     - bq_table, bq_conn, batch_id, batch_size, webhook_url: Config params
    #
    # ### Returns:
    #     - {list_of_successful_ids, list_of_failed_ids, count_of_uploaded_records}
    #
    defp process_insert_results(results, group_info, bq_table, bq_conn, batch_id, batch_size, webhook_url) do
        # Crea un mapa de id_nodo => result para una búsqueda rápida
        result_map =
            results
            |> Enum.reduce(%{}, fn
                {:ok, id}, acc ->
                    # Find the id_nodo for this id
                    case Enum.find(group_info, fn {_id_nodo, all_ids, _rest} -> id in all_ids end) do
                        {id_nodo, _, _} -> Map.put(acc, id_nodo, {:ok, id})
                        nil -> acc
                    end
                {:error, id}, acc ->
                    case Enum.find(group_info, fn {_id_nodo, all_ids, _rest} -> id in all_ids end) do
                        {id_nodo, _, _} -> Map.put(acc, id_nodo, {:error, id})
                        nil -> acc
                    end
            end)

        # Procesa cada grupo
        {all_successful_ids, all_failed_ids, uploaded_count} =
            group_info
            |> Enum.reduce(
                {[], [], 0},
                fn {id_nodo, all_ids, remaining_records}, {ids_acc, failed_acc, count_acc} ->
                    case Map.get(result_map, id_nodo) do
                        {:ok, _} ->
                            # Éxito: marca todos los registros en este grupo como enviados
                            {ids_acc ++ all_ids, failed_acc, count_acc + 1}

                        {:error, first_failed_id} ->
                            # Primer registro fallido - intenta los registros restantes
                            # Rastrea el ID fallido por separado
                            try_remaining_records(
                                remaining_records,
                                [first_failed_id],  # IDs que han fallado hasta ahora
                                bq_table,
                                bq_conn,
                                batch_id,
                                batch_size,
                                webhook_url,
                                {ids_acc, failed_acc, count_acc}
                            )

                        nil ->
                            # Sin resultado para este id_nodo
                            {ids_acc, failed_acc, count_acc}
                    end
                end
            )

        {all_successful_ids, all_failed_ids, uploaded_count}
    end

    #
    # Tries to insert remaining records one by one until one succeeds. Tracks which records failed during retries.
    #
    # ### Parameters:
    #     - remaining_records: List of records to try (already sorted by fecha_creado desc)
    #     - tried_failed_ids: List of IDs that have been tried and failed
    #     - bq_table, bq_conn, batch_id, batch_size, webhook_url: Config params
    #     - {ids_acc, failed_acc, count_acc}: Accumulator for successful/failed ids and count
    #
    # ### Returns:
    #     - {updated_ids_acc, updated_failed_acc, updated_count_acc}
    #
    defp try_remaining_records([], tried_failed_ids, _bq_table, _bq_conn, _batch_id, _batch_size, _webhook_url, {ids_acc, failed_acc, count_acc}) do
        # No hay más registros para intentar - todos los registros intentados se marcan como fallidos
        {ids_acc, failed_acc ++ tried_failed_ids, count_acc}
    end

    defp try_remaining_records([record | rest], tried_failed_ids, bq_table, bq_conn, batch_id, batch_size, webhook_url, {ids_acc, failed_acc, count_acc}) do
        # Intenta insertar este registro individual
        current_id = Map.get(record, :id)
        data = [{
            Map.get(record, :id_nodo),
            current_id,
            record,
            Sql.insert(bq_table, build_insert_values(record))
        }]

        results = execute_insert_with_retry(data, bq_conn, batch_id, batch_size, webhook_url)

        case results do
            [{:ok, _}] ->
                # Exito: marca este registro y los registros restantes no intentados como enviados
                # Marca los registros intentados previamente como fallidos
                remaining_ids = Enum.map(rest, &Map.get(&1, :id))
                successful_ids = [current_id | remaining_ids]
                {ids_acc ++ successful_ids, failed_acc ++ tried_failed_ids, count_acc + 1}

            _ ->
                # Fallo: agrega el ID actual a la lista de fallidos y trata el siguiente registro
                try_remaining_records(
                    rest,
                    tried_failed_ids ++ [current_id],
                    bq_table,
                    bq_conn,
                    batch_id,
                    batch_size,
                    webhook_url,
                    {ids_acc, failed_acc, count_acc}
                )
        end
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
    #     - bq_conn: pid. Active BigQuery ODBC connection
    #     - batch_id: String. Batch identifier for error logging
    #     - batch_size: Integer. Number of records per batch
    #     - webhook_url: String. Slack webhook URL for error notifications
    #
    # ### Returns:
    #     - List of tuples {:ok, id} | {:error, id}
    #
    def execute_insert_with_retry([], _bq_conn, _batch_id, _batch_size, _webhook_url), do: []

    def execute_insert_with_retry(data, bq_conn, batch_id, batch_size, webhook_url) do
        insert_tuples =
            data
            |> Enum.chunk_every(batch_size)
            |> Enum.map(&group_for_batch_insert/1)
            |> Enum.reject(&(&1 == []))

        results = execute_insert(insert_tuples, bq_conn)

        has_errors? = Enum.any?(results, fn
            {:error, _} -> true
            _ -> false
        end)

        case {has_errors?, length(data)} do
            {false, _} ->
                results
                |> Enum.flat_map(fn {:ok, ids} -> Enum.map(ids, &{:ok, &1}) end)

            {true, 1} ->
                # Registro individual fallido
                Enum.flat_map(results, fn
                    {:ok, ids} -> Enum.map(ids, &{:ok, &1})
                    {:error, {id_nodos, ids, records, error}} ->
                        handle_processing_error(batch_id, id_nodos, records, error, webhook_url)
                        Enum.map(ids, &{:error, &1})
                end)

            {true, _} ->
                Logger.info("Inserción de lote fallida, dividiendo datos a la mitad y reintentando...")

                mid = div(length(data), 2)
                {first_half, second_half} = Enum.split(data, mid)

                first_results = execute_insert_with_retry(first_half, bq_conn, batch_id, batch_size, webhook_url)
                second_results = execute_insert_with_retry(second_half, bq_conn, batch_id, batch_size, webhook_url)

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
    # Executes the insert operation in BigQuery using persistent connection
    #
    # ### Parameters:
    #     - insert_tuples: List of tuples {id_nodos, ids, records, merged_query}
    #     - bq_conn: pid. Active BigQuery ODBC connection
    #
    # ### Returns:
    #     - List of {:ok, ids} | {:error, {id_nodos, ids, records, error}}
    #
    defp execute_insert(insert_tuples, bq_conn) do
        Enum.map(insert_tuples, fn {id_nodos, ids, records, query} ->
            try do
                Odbc.insert(bq_conn, query)
                {:ok, ids}
            rescue
                error ->
                    {:error, {id_nodos, ids, records, error}}
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

    #
    # Executes post-processing logic after BigQuery upload completes.
    #
    # ### Parameters:
    #     - business: Atom. Business type identifier.
    #     - tipo: String. Type field value used to differentiate processing logic.
    #     - context: Map. Context information about the upload.
    #
    # ### Returns:
    #     - :ok | {:ok, result} | {:error, reason}
    #
    defp run_post_process(business, tipo, context) do
        PBigqueryPostProcess.after_upload(business, tipo, context)
    end

end
