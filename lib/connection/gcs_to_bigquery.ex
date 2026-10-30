
defmodule Connection.GcsToBigQuery do
    @moduledoc"""
    Module for loading files stored in Google Cloud Storage (GCS) into BigQuery tables. It runs `LOAD DATA` statements through the ODBC connection (`Connection.Odbc`).
    """

    require Logger

    alias Connection.Gcs
    alias Connection.Gcs.Helpers, as: GcsHelpers
    alias Connection.Odbc

    @formats %{
        csv: "CSV",
        ndjson: "NEWLINE_DELIMITED_JSON",
        jsonl: "NEWLINE_DELIMITED_JSON",
        parquet: "PARQUET",
        avro: "AVRO",
        orc: "ORC"
    }

    @table_regex ~r/^[A-Za-z0-9_\-]+(\.[A-Za-z0-9_\-]+){1,2}$/
    @uri_regex ~r/^gs:\/\/[a-z0-9._\-]+\/[^'\\\n\r]+$/

    @data_source_key {__MODULE__, :data_source}
    @default_dsn "bigquery64"
    # Service account authentication of the Simba BigQuery ODBC driver
    @oauth_service_account 0


    ################
    ### Functions
    ################

    @doc"""
    Stores the ODBC configuration used by `load/3` and `export_records/5`, so the Simba driver authenticates with a service account instead of the account of the DSN. It must be called once, before those functions. Calling it again replaces the configuration.

    ### Parameters:
        - credentials: String | Map. Path to the service account JSON file, the JSON content as a string, or the already decoded map. The driver needs a file: when the content or the map is given, it is written to a temporary file readable only by the current user.
        - opts: Keyword.
            - `:dsn` - String. ODBC data source. Default: `"bigquery64"`.
            - `:project` - String. Project where the queries run (`Catalog`). Default: `project_id` of the credentials.
            - `:warehouse` - String. Default dataset. Optional.

    ### Return:
        - :ok | Exception. Raises an exception if the credentials are invalid or the connection cannot be opened with them.

    """
    def configure(credentials, opts \\ []) do
        decoded = GcsHelpers.load_credentials!(credentials)
        email = Map.get(decoded, "client_email") || raise(ArgumentError, "Las credenciales no tienen client_email")
        project = Keyword.get(opts, :project) || Map.get(decoded, "project_id") || raise(ArgumentError, "Las credenciales no tienen project_id; indicar opts[:project]")

        data_source =
            [
                dsn: Keyword.get(opts, :dsn, @default_dsn),
                OAuthMechanism: @oauth_service_account,
                Email: email,
                KeyFilePath: key_file_path(credentials, decoded),
                Catalog: project
            ]
            |> add_warehouse(Keyword.get(opts, :warehouse))

        # Validates the configuration right away
        Logger.debug("Validando configuración ODBC de carga a BigQuery: se abre y cierra una conexión de prueba")
        with_odbc(data_source, [], fn _pid -> :ok end)

        :persistent_term.put(@data_source_key, data_source)
        Logger.debug("Carga a BigQuery configurada para #{email} (proyecto #{project})")
        :ok
    end

    @doc"""
    Loads one or more GCS files into a BigQuery table, with the ODBC configuration stored by `configure/2`.

    ### Parameters:
        - table: String. Destination table: `dataset.table` or `project.dataset.table`.
        - uris: String | list of String. GCS URIs of the files.
        - opts: Keyword. Same options as `load/4`.

    ### Return:
        - :ok | {:error, String} | Exception. Same as `load/4`. Raises an exception if `configure/2` was not called.

    """
    def load(table, uris, opts), do:
        load(configured_data_source!(), table, uris, opts)

    @doc"""
    Loads one or more GCS files into a BigQuery table. The table must exist: its columns are read from `INFORMATION_SCHEMA.COLUMNS` and given to `LOAD DATA`, so BigQuery uses the table schema instead of detecting it from the files (e.g. a `STRING` column with dates is not loaded as `DATE`).

    ### Parameters:
        - connection: ODBC connection, in any of these forms:
            - Process. An open connection (`Connection.Odbc.connect/1`). It is not closed.
            - Atom. Name of a `Pool.BigQuery` pool. A connection is taken from the pool.
            - Keyword. ODBC configuration (e.g. `[dsn: "bigquery64", warehouse: "project.dataset"]`). A connection is opened and closed for this call.
        - table: String. Destination table: `dataset.table` or `project.dataset.table`.
        - uris: String | list of String. GCS URIs of the files. Wildcards are allowed (e.g. `gs://bucket/folder/*.jsonl`).
        - opts: Keyword.
            - `:format` - Atom. Required. One of `:csv`, `:ndjson` (or `:jsonl`), `:parquet`, `:avro`, `:orc`.
            - `:mode` - Atom. `:append` (default) adds the rows; `:overwrite` replaces the table content.
            - `:skip_leading_rows` - Integer. Only for `:csv`. Header rows to skip. Default: `0`.
            - `:timeout` - Integer. Only for a pool. Milliseconds to wait for a connection and for the load. Default: the pool timeout.

    ### Return:
        - :ok | {:error, String} | Exception. `:ok` if the load finished. `{:error, message}` if the connection could not be obtained, the table does not exist or BigQuery rejected the load (the message ends with the URIs). Raises `ArgumentError` if the table, the URIs or the options are invalid.

    """
    def load(connection, table, uris, opts) do
        # Validates the arguments before opening the connection
        validate_load!(table, uris, opts)

        try do
            with_odbc(connection, Keyword.take(opts, [:timeout]), fn pid ->
                with {:ok, columns} <- table_columns(pid, table) do
                    statement = build_load_statement(table, uris, columns, opts)
                    Logger.debug("Cargando en BigQuery: #{statement}")

                    try do
                        Odbc.execute(pid, statement)
                    rescue
                        error -> {:error, "#{Exception.message(error)}. URIs: #{Enum.join(List.wrap(uris), ", ")}"}
                    end
                end
            end)
        rescue
            error -> {:error, Exception.message(error)}
        catch
            :exit, reason -> {:error, reason}
        end
        |> case do
            {:error, error} ->
                message = error_message(error)
                Logger.error("Error al cargar en BigQuery la tabla #{table}: #{message}")
                {:error, message}

            # A script returns {:updated, :undefined}: BigQuery does not report the loaded rows
            _result ->
                :ok
        end
    end

    @doc"""
    Converts records to NDJSON (one JSON per line), uploads them to GCS and loads them into a BigQuery table. By default, the file is deleted from the bucket after the load, even if the load fails.

    ### Parameters:
        - connection: ODBC connection, in any of these forms:
            - Process. An open connection (`Connection.Odbc.connect/1`). It is not closed.
            - Atom. Name of a `Pool.BigQuery` pool. A connection is taken from the pool.
            - Keyword. ODBC configuration (e.g. `[dsn: "bigquery64", warehouse: "project.dataset"]`). A connection is opened and closed for this call.
        - records: list of Map. Records to load. Keys must match the table columns. Values are encoded with `Jason` (`DateTime` -> ISO 8601).
        - bucket: String. Bucket where the temporary file is stored.
        - object: String. Full name of the file in the bucket (e.g. `tmp/servicio_20231001.jsonl`).
        - table: String. Destination table.
        - opts: Keyword.
            - `:mode` - Atom. `:append` (default) or `:overwrite`.
            - `:keep_file` - Boolean. Keeps the file in the bucket. Default: `false`.
            - `:timeout` - Integer. Same as in `load/4`.

    ### Return:
        - :ok | {:error, String} | :no_records | Exception. Result of `load/4`. Returns `:no_records` without uploading anything if `records` is empty.

    """
    def export_records(_connection, [], _bucket, _object, _table, _opts), do:
        :no_records

    def export_records(connection, records, bucket, object, table, opts) when is_list(records) do
        data = Enum.map(records, fn record -> [Jason.encode!(record), "\n"] end)
        uri = Gcs.upload_binary(bucket, data, object, "application/jsonl")

        try do
            load(connection, table, uri, [format: :ndjson, mode: Keyword.get(opts, :mode, :append)] ++ Keyword.take(opts, [:timeout]))
        after
            if not Keyword.get(opts, :keep_file, false) do
                Gcs.delete_object(bucket, object)
            end
        end
    end

    @doc"""
    Same as `export_records/6`, with the ODBC configuration stored by `configure/2`.

    ### Parameters:
        - records: list of Map. Records to load.
        - bucket: String. Bucket where the temporary file is stored.
        - object: String. Full name of the file in the bucket.
        - table: String. Destination table.
        - opts: Keyword. Same options as `export_records/6`.

    ### Return:
        - :ok | {:error, String} | :no_records | Exception. Same as `export_records/6`. Raises an exception if `configure/2` was not called.

    """
    def export_records(records, bucket, object, table, opts \\ []) when is_list(records), do:
        export_records(configured_data_source!(), records, bucket, object, table, opts)

    @doc"""
    Builds the `LOAD DATA` statement, wrapped in a `BEGIN ... END;` script. Validates the table name, URIs and options to avoid breaking or injecting SQL.

    ### Parameters:
        - table: String. Destination table.
        - uris: String | list of String. GCS URIs.
        - columns: list of {String, String}. Columns of the table as `{name, type}`, in order (e.g. `[{"id", "STRING"}, {"fecha", "DATE"}]`). With `[]`, no column list is given and BigQuery detects the schema from the files.
        - opts: Keyword. Same options as `load/4`.

    ### Return:
        - String | Exception

    """
    def build_load_statement(table, uris, columns, opts) do
        validate_load!(table, uris, opts)

        uris = List.wrap(uris)
        format = Keyword.fetch!(opts, :format)

        mode =
            case Keyword.get(opts, :mode, :append) do
                :append -> "INTO"
                :overwrite -> "OVERWRITE"
            end

        options =
            ["format = '#{Map.fetch!(@formats, format)}'", "uris = [#{Enum.map_join(uris, ", ", &"'#{&1}'")}]"]
            |> add_skip_leading_rows(format, Keyword.get(opts, :skip_leading_rows, 0))
            |> Enum.join(", ")

        # Wrapped in a script: as a single statement, the Simba ODBC driver sends it with a destination table and
        # BigQuery rejects it ("Cannot set destination table in jobs with DDL statements")
        "BEGIN LOAD DATA #{mode} `#{table}`#{column_list(columns)} FROM FILES (#{options}); END;"
    end


    ################
    ### Helper functions
    ################

    #
    # Returns the ODBC configuration stored by `configure/2`.
    #
    # ### Parameters:
    #     - None.
    #
    # ### Return:
    #     - Keyword | Exception. Raises an exception if `configure/2` was not called.
    #
    defp configured_data_source!(), do:
        :persistent_term.get(@data_source_key, nil)
        || raise("Carga a BigQuery no configurada. Llamar primero a Connection.GcsToBigQuery.configure/2")

    #
    # Returns the path of the credentials file for the `KeyFilePath` option of the driver. If the credentials were given as content or as a map, they are written to a temporary file readable only by the current user.
    #
    # ### Parameters:
    #     - credentials: String | Map. Credentials as received by `configure/2`.
    #     - decoded: Map. Decoded credentials.
    #
    # ### Return:
    #     - String. Absolute path of the credentials file.
    #
    defp key_file_path(credentials, decoded) do
        if is_binary(credentials) and not String.starts_with?(String.trim_leading(credentials), "{") do
            Path.expand(credentials)
        else
            path = Path.join(System.tmp_dir!(), "etl_core_bigquery_#{decoded["client_email"]}.json")
            File.write!(path, Jason.encode!(decoded))
            File.chmod!(path, 0o600)
            path
        end
    end

    #
    # Adds the default dataset (`warehouse`) to the ODBC configuration, if it is given.
    #
    # ### Parameters:
    #     - data_source: Keyword. ODBC configuration.
    #     - warehouse: String | nil. Default dataset.
    #
    # ### Return:
    #     - Keyword. ODBC configuration.
    #
    defp add_warehouse(data_source, nil), do:
        data_source
    defp add_warehouse(data_source, warehouse), do:
        data_source ++ [warehouse: warehouse]

    #
    # Executes a function with an ODBC connection, obtained according to the form of `connection`.
    #
    # ### Parameters:
    #     - connection: Process | Atom | Keyword. Open connection, name of a `Pool.BigQuery` pool, or ODBC configuration.
    #     - opts: Keyword. `:timeout` for the pool.
    #     - fun: Function. Receives the ODBC connection (pid).
    #
    # ### Return:
    #     - t() | Exception. Result of `fun`. Raises `ArgumentError` if `connection` has none of the expected forms.
    #
    defp with_odbc(pid, _opts, fun) when is_pid(pid), do:
        fun.(pid)

    defp with_odbc(pool, opts, fun) when is_atom(pool) and not is_nil(pool) and not is_boolean(pool), do:
        Pool.BigQuery.with_connection(pool, fun, opts)

    defp with_odbc([{key, _} | _] = data_source, _opts, fun) when is_atom(key) do
        Odbc.start()
        pid = Odbc.connect(data_source)

        try do
            fun.(pid)
        after
            try do
                Odbc.disconnect(pid)
            rescue
                error -> Logger.warning("No se pudo cerrar la conexión ODBC: #{Exception.message(error)}")
            end
        end
    end

    defp with_odbc(connection, _opts, _fun), do:
        raise(ArgumentError, "Conexión ODBC inválida: se espera un pid, el nombre de un pool o la configuración ODBC (keyword list). Valor: #{inspect(connection)}")

    #
    # Validates the arguments of a load: table name, URIs, format and mode.
    #
    # ### Parameters:
    #     - table: String. Destination table.
    #     - uris: String | list of String. GCS URIs.
    #     - opts: Keyword. Same options as `load/4`.
    #
    # ### Return:
    #     - :ok | Exception. Raises `ArgumentError` (or `KeyError` without `:format`) if an argument is invalid.
    #
    defp validate_load!(table, uris, opts) do
        validate_table!(table)
        Enum.each(List.wrap(uris), &validate_uri!/1)

        format = Keyword.fetch!(opts, :format)

        if not Map.has_key?(@formats, format) do
            raise(ArgumentError, "Formato no soportado: #{inspect(format)}. Valores: #{inspect(Map.keys(@formats))}")
        end

        mode = Keyword.get(opts, :mode, :append)

        if mode not in [:append, :overwrite] do
            raise(ArgumentError, "Modo no soportado: #{inspect(mode)}. Valores: [:append, :overwrite]")
        end

        :ok
    end

    #
    # Reads the columns of a table from `INFORMATION_SCHEMA.COLUMNS`, in order. Hidden pseudo-columns (e.g. `_PARTITIONTIME`) are excluded.
    #
    # ### Parameters:
    #     - pid: Process. ODBC connection.
    #     - table: String. Table already validated: `dataset.table` or `project.dataset.table`.
    #
    # ### Return:
    #     - {:ok, list of {String, String}} | {:error, String} | Exception. Columns as `{name, type}`. Error if the table does not exist. Raises an exception if the query fails.
    #
    defp table_columns(pid, table) do
        {dataset, [name]} = table |> String.split(".") |> Enum.split(-1)

        query =
            "SELECT column_name, data_type FROM `#{Enum.join(dataset, ".")}.INFORMATION_SCHEMA.COLUMNS` " <>
            "WHERE table_name = '#{name}' AND is_hidden = 'NO' ORDER BY ordinal_position"

        Odbc.select(pid, query)
        |> case do
            [] -> {:error, "La tabla no existe: #{table}"}
            rows -> {:ok, Enum.map(rows, &{&1[:column_name], &1[:data_type]})}
        end
    end

    #
    # Builds the column list of the `LOAD DATA` statement.
    #
    # ### Parameters:
    #     - columns: list of {String, String}. Columns as `{name, type}`.
    #
    # ### Return:
    #     - String. ` (name TYPE, ...)`, or `""` if there are no columns.
    #
    defp column_list([]), do:
        ""
    defp column_list(columns), do:
        " (#{Enum.map_join(columns, ", ", fn {name, type} -> "`#{name}` #{type}" end)})"

    #
    # Converts the reason of an ODBC, connection or pool error to a message.
    #
    # ### Parameters:
    #     - error: String | Charlist | Atom | t(). Error reason.
    #
    # ### Return:
    #     - String. Error message.
    #
    defp error_message(error) when is_binary(error) or is_list(error) or is_atom(error), do:
        to_string(error)
    defp error_message(error), do:
        inspect(error)

    #
    # Adds the `skip_leading_rows` option to the `LOAD DATA` options. It only applies to CSV files and positive values.
    #
    # ### Parameters:
    #     - options: list of String. Options of the `FROM FILES` clause.
    #     - format: Atom. File format.
    #     - rows: Integer. Header rows to skip.
    #
    # ### Return:
    #     - list of String. Options, with `skip_leading_rows` added when it applies.
    #
    defp add_skip_leading_rows(options, :csv, rows) when is_integer(rows) and rows > 0, do:
        options ++ ["skip_leading_rows = #{rows}"]
    defp add_skip_leading_rows(options, _format, _rows), do:
        options

    #
    # Validates the destination table name (`dataset.table` or `project.dataset.table`), to avoid breaking or injecting SQL.
    #
    # ### Parameters:
    #     - table: String. Table name.
    #
    # ### Return:
    #     - nil | Exception. Raises `ArgumentError` if the name is invalid.
    #
    defp validate_table!(table) do
        if not (is_binary(table) and Regex.match?(@table_regex, table)) do
            raise(ArgumentError, "Nombre de tabla inválido: #{inspect(table)}. Se espera dataset.tabla o proyecto.dataset.tabla")
        end
    end

    #
    # Validates a GCS URI (`gs://bucket/object`), to avoid breaking or injecting SQL.
    #
    # ### Parameters:
    #     - uri: String. GCS URI.
    #
    # ### Return:
    #     - nil | Exception. Raises `ArgumentError` if the URI is invalid.
    #
    defp validate_uri!(uri) do
        if not (is_binary(uri) and Regex.match?(@uri_regex, uri)) do
            raise(ArgumentError, "URI de GCS inválida: #{inspect(uri)}. Se espera gs://bucket/objeto")
        end
    end

end
