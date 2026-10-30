
defmodule ForcedLoad.Handler.DirectLoad do
    @moduledoc """
    Direct load to BigQuery of `ForcedLoad.Handler`: when the forced load ends, it loads the records of the temporary Postgres table into BigQuery, through files uploaded to GCS. See `run/4`.
    """

    alias Connection.Gcs
    alias Connection.GcsToBigQuery
    alias Connection.PostgresHelpers
    alias ForcedLoad.Config
    alias ForcedLoad.Helpers


    @unanalyzed_state "sin_analizar"
    @analyzed_in_bq_state "analizado_en_bq"
    @queue_wait_timeout 5 * 60_000
    @queue_check_interval 10_000
    @queue_empty_delay 5_000
    @upload_retries 3
    @upload_retry_delay 5_000


    @doc """
    Loads the pending records of the temporary Postgres table into BigQuery via GCS: waits for the queues, exports each type to a JSONL file, uploads it and loads it into its table. Requires `ForcedLoad.Helpers.validate_direct_load!/1`.

    ### Parameters
        - channel: AMQP.Channel. Channel used to check the queues
        - includes_record: boolean. Whether records were loaded (checks `:record_queue`)
        - includes_task: boolean. Whether tasks were loaded (checks `:task_queue`)
        - config: map. Must contain :postgres_temp_table and :gcs_bucket

    ### Returns
        - :ok | Exception. Raises an exception if the queues cannot be checked.
    """
    def run(channel, includes_record, includes_task, config) do
        business_name = Map.get(config, :business_name, "UNKNOWN")
        bucket = Map.fetch!(config, :gcs_bucket)
        folder = Map.get(config, :gcs_folder)
        files_path = Map.get(config, :files_path, Config.default(:files_path))

        Helpers.notify(config, "CARGA DIRECTA A BIGQUERY. #{business_name}. Inicio", :info)

        # Step 1: wait for the queues
        queues =
            [{includes_record, Map.get(config, :record_queue)}, {includes_task, Map.get(config, :task_queue)}]
            |> Enum.filter(fn {included, _queue} -> included end)
            |> Enum.map(fn {_included, queue} -> queue end)

        Helpers.notify(config, "Esperando a que se vacíen las colas: #{Enum.join(queues, ", ")}", :info)
        wait_for_empty_queues(channel, queues, System.monotonic_time(:millisecond) + @queue_wait_timeout, config)

        # Steps 2 and 3: one file per type, with its table
        exports =
            config
            |> Map.get(:bigquery_tables_by_type, [])
            |> Enum.map(fn {type, table} -> {type, table, export_type_to_file(type, files_path, config)} end)

        files = for {_type, table, {:ok, path}} <- exports, do: {path, table}
        not_exported = for {type, _table, {:error, message}} <- exports, do: {type, message}

        # Step 4: upload to GCS
        Helpers.notify(config, "Subiendo #{length(files)} archivos a GCS (bucket #{bucket})", :info)

        uploads =
            Enum.map(files, fn {path, table} ->
                object = if folder in [nil, ""], do: Path.basename(path), else: Path.join(folder, Path.basename(path))
                {path, table, object, upload_with_retry(bucket, path, object, config)}
            end)

        uploaded = for {path, table, object, {:ok, uri}} <- uploads, do: {path, table, object, uri}
        not_uploaded = for {path, _table, _object, {:error, message}} <- uploads, do: {path, message}

        Enum.each(uploaded, fn {path, _table, _object, _uri} -> File.rm(path) end)

        # Steps 5 and 6: load into BigQuery and delete the loaded files from GCS
        Helpers.notify(config, "Cargando #{length(uploaded)} archivos en BigQuery", :info)

        loads =
            Enum.map(uploaded, fn {_path, table, object, uri} ->
                {table, object, uri, GcsToBigQuery.load(table, uri, format: :ndjson)}
            end)

        loaded = for {table, object, uri, :ok} <- loads, do: {table, object, uri}
        not_loaded = for {table, _object, uri, {:error, message}} <- loads, do: {uri, table, message}

        Enum.each(loaded, fn {_table, object, uri} ->
            try do
                Gcs.delete_object(bucket, object)
            rescue
                error -> Helpers.notify(config, "No se pudo eliminar #{uri} de GCS: #{Exception.message(error)}", :warning)
            end
        end)

        # Step 7: summary
        failures = not_exported ++ not_uploaded ++ not_loaded

        Helpers.notify(config,
            """
            *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
            CARGA DIRECTA A BIGQUERY. #{business_name}. FIN
            Archivos cargados en BigQuery: #{length(loaded)}/#{length(files)}
            #{Enum.map_join(loaded, "\n", fn {table, _object, uri} -> "\t#{uri} -> #{table}" end)}
            Tipos no exportados de Postgres (registros sin cambios): #{length(not_exported)}
            #{Enum.map_join(not_exported, "\n", fn {type, message} -> "\t#{type}: #{message}" end)}
            Archivos no subidos a GCS (quedan en #{files_path}): #{length(not_uploaded)}
            #{Enum.map_join(not_uploaded, "\n", fn {path, message} -> "\t#{path}: #{message}" end)}
            Archivos no cargados en BigQuery (quedan en GCS): #{length(not_loaded)}
            #{Enum.map_join(not_loaded, "\n", fn {uri, table, message} -> "\t#{uri} -> #{table}: #{message}" end)}
            *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
            """,
            if(failures == [], do: :info, else: :warning)
        )

        :ok
    end


    #
    # Waits until the queues are empty (no ready messages), checking every `@queue_check_interval` milliseconds until the deadline. When they are empty, it waits `@queue_empty_delay` milliseconds more before returning.
    #
    # ### Parameters
    #     - channel: AMQP.Channel. Channel used to check the queues
    #     - queues: list of String. Queues to check
    #     - deadline: integer. Monotonic time, in milliseconds, when the wait ends
    #     - config: map. Configuration options
    #
    # ### Returns
    #     - :ok if the queues are empty
    #     - :timeout if they are not empty at the deadline
    #     - Exception if a queue cannot be checked (it is notified first)
    #
    defp wait_for_empty_queues(channel, queues, deadline, config) do
        pending =
            try do
                Enum.reject(queues, fn queue -> AMQP.Queue.message_count(channel, queue) == 0 end)
            rescue
                error ->
                    Helpers.notify(config, "Error al consultar las colas #{Enum.join(queues, ", ")}: #{Exception.message(error)}. Se termina la carga directa", :error)
                    reraise error, __STACKTRACE__
            catch
                :exit, reason ->
                    Helpers.notify(config, "Error al consultar las colas #{Enum.join(queues, ", ")}: #{inspect(reason)}. Se termina la carga directa", :error)
                    exit(reason)
            end

        cond do
            pending == [] ->
                Helpers.notify(config, "Colas vacías. Se continúa en #{div(@queue_empty_delay, 1000)} s", :info)
                Process.sleep(@queue_empty_delay)
                :ok

            System.monotonic_time(:millisecond) >= deadline ->
                Helpers.notify(config, "Las colas #{Enum.join(pending, ", ")} no se vaciaron en #{div(@queue_wait_timeout, 60_000)} minutos. Se continúa con la carga directa", :warning)
                :timeout

            true ->
                Process.sleep(@queue_check_interval)
                wait_for_empty_queues(channel, pending, deadline, config)
        end
    end


    #
    # Writes the pending records (`sin_analizar`) of a type to a JSONL file and marks them as `analizado_en_bq` in the temporary Postgres table, in one transaction. The records are read, written and marked in batches of `:postgres_export_batch_size`. Each line is the `informacion` column of a record. If something fails, the transaction is rolled back and the file is deleted.
    #
    # The file is named `<business_name>_<type>-<yyyyMMddHHmmssSSS>.jsonl` (UTC time).
    #
    # ### Parameters
    #     - type: String. Record type (`tipo` column)
    #     - files_path: String. Directory of the file
    #     - config: map. Must contain :postgres_temp_table; optionally :postgres_pool and :postgres_export_batch_size
    #
    # ### Returns
    #     - {:ok, path} with the path of the file
    #     - :empty if the type has no pending records (no file is created)
    #     - {:error, message} if the transaction failed
    #
    defp export_type_to_file(type, files_path, config) do
        pool = Map.get(config, :postgres_pool, Config.default(:postgres_pool))
        batch_size = Map.get(config, :postgres_export_batch_size, Config.default(:postgres_export_batch_size))
        table = PostgresHelpers.sanitize_identifier(Map.fetch!(config, :postgres_temp_table))
        {query, params} = PostgresHelpers.pending_bq_query(table, type, @unanalyzed_state)

        timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond) |> Calendar.strftime("%Y%m%d%H%M%S%f")
        path = Path.join(files_path, "#{Map.get(config, :business_name, "UNKNOWN")}_#{type}-#{timestamp}.jsonl")

        try do
            Pool.Postgres.transaction(pool, fn conn ->
                count =
                    File.open!(path, [:write], fn file ->
                        conn
                        |> Postgrex.stream(query, params, max_rows: batch_size, timeout: :infinity)
                        |> Enum.reduce(0, fn result, count ->
                            records = PostgresHelpers.parse_query_result(result)
                            IO.binwrite(file, Enum.map(records, fn record ->
                                # `informacion` is stored as a JSON string: it is decoded so each line is a JSON object
                                informacion = if is_binary(record.informacion), do: Poison.decode!(record.informacion), else: record.informacion
                                [Poison.encode!(informacion), "\n"]
                            end))
                            Postgrex.query!(conn, "UPDATE #{table} SET estado_analisis = '#{@analyzed_in_bq_state}' WHERE id = ANY($1)", [Enum.map(records, & &1.id)])
                            count + length(records)
                        end)
                    end)

                if count == 0, do: Postgrex.rollback(conn, :empty)

                count
            end, timeout: :infinity)
        rescue
            error -> {:error, Exception.message(error)}
        end
        |> case do
            {:ok, count} ->
                Helpers.notify(config, "Tipo #{type}: #{count} registros exportados a #{path}", :info)
                {:ok, path}

            {:error, :empty} ->
                File.rm(path)
                Helpers.notify(config, "Tipo #{type}: sin registros pendientes, se omite", :info)
                :empty

            {:error, reason} ->
                File.rm(path)
                message = if is_binary(reason), do: reason, else: inspect(reason)
                Helpers.notify(config, "Tipo #{type}: error al exportar, se revierte la transacción: #{message}", :error)
                {:error, message}
        end
    end


    #
    # Uploads a file to GCS. If it fails, it retries up to `@upload_retries` times, waiting `@upload_retry_delay` milliseconds between attempts.
    #
    # ### Parameters
    #     - bucket: String. Bucket
    #     - path: String. Local path of the file
    #     - object: String. Name of the object in the bucket
    #     - config: map. Configuration options
    #     - attempt: integer. Current attempt (starts at 1)
    #
    # ### Returns
    #     - {:ok, uri} with the GCS URI of the file
    #     - {:error, message} if all the attempts failed
    #
    defp upload_with_retry(bucket, path, object, config, attempt \\ 1) do
        {:ok, Gcs.upload_file(bucket, path, object)}
    rescue
        error ->
            message = Exception.message(error)

            if attempt <= @upload_retries do
                Helpers.notify(config, "Error al subir #{path} a GCS (intento #{attempt}): #{message}. Se reintenta en #{div(@upload_retry_delay, 1000)} s", :warning)
                Process.sleep(@upload_retry_delay)
                upload_with_retry(bucket, path, object, config, attempt + 1)
            else
                Helpers.notify(config, "Error al subir #{path} a GCS tras #{attempt} intentos: #{message}", :error)
                {:error, message}
            end
    end


end
