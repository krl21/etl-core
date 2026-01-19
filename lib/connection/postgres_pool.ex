
defmodule Connection.PostgresPool do
    @moduledoc """
    PostgreSQL operations using a named connection pool.
    """

    require Logger
    alias Connection.PostgresHelpers

    @unanalyzed_state "sin_analizar"
    @state_analyzed_in_bq "analizado_en_bq"
    @state_with_problems "con_problemas"

    ############
    # TABLE OPERATIONS
    ############

    @doc """
    Checks if a table exists in the database.

    ### Parameters
        - pool_name: Atom. Pool name
        - table_name: String. Table name to check

    ### Returns
        - {:ok, true} - Table exists
        - {:ok, false} - Table does not exist
        - {:error, reason} - Error checking the table
    """
    def table_exists?(pool_name, table_name) do
        query = """
        SELECT EXISTS (
            SELECT FROM information_schema.tables
            WHERE table_schema = 'public'
                AND table_name = $1
        );
        """

        Pool.Postgres.query_read(
            pool_name,
            query,
            [table_name]
        )
        |> case do
            {:ok, %{rows: [[exists]]}} ->
                {:ok, exists}

            {:error, reason} = error ->
                Logger.error("Error al verificar tabla #{table_name}: #{inspect(reason)}")
                error
        end
    end

    @doc """
    Creates the table if it does not exist, using default column comments.

    ### Parameters
        - pool_name: Atom. Pool name
        - table_name: String. Table name to create

    ### Returns
        - :ok - Table created or already existed
        - {:error, reason} - Creation error
    """
    def create_table_if_not_exists(pool_name, table_name) do
        create_table_if_not_exists(pool_name, table_name, PostgresHelpers.default_column_comments())
    end

    @doc """
    Creates the table if it does not exist, with custom column comments.

    ### Parameters
        - pool_name: Atom. Pool name
        - table_name: String. Table name to create
        - column_comments: Map. Column comments

    ### Returns
        - :ok - Table created or already existed
        - {:error, reason} - Creation error
    """
    def create_table_if_not_exists(pool_name, table_name, column_comments) do
        sanitized_name = PostgresHelpers.sanitize_identifier(table_name)

        query = """
        CREATE TABLE IF NOT EXISTS #{sanitized_name} (
            id SERIAL PRIMARY KEY,
            id_nodo VARCHAR(100) NOT NULL,
            tipo VARCHAR(100),
            informacion JSONB NOT NULL,
            fecha_creado TIMESTAMP NOT NULL,
            estado_analisis VARCHAR(20) DEFAULT 'sin_analizar'
        );
        """

        tipo_index_query = """
        CREATE INDEX IF NOT EXISTS idx_#{sanitized_name}_tipo
        ON #{sanitized_name} (tipo);
        """

        estado_index_query = """
        CREATE INDEX IF NOT EXISTS idx_#{sanitized_name}_estado_analisis
        ON #{sanitized_name} (estado_analisis)
        WHERE estado_analisis != '#{@state_analyzed_in_bq}';
        """

        result = Pool.Postgres.transaction(
            pool_name,
            fn conn ->
                with {:ok, _} <- Postgrex.query(conn, query, []),
                    {:ok, _} <- Postgrex.query(conn, tipo_index_query, []),
                    {:ok, _} <- Postgrex.query(conn, estado_index_query, []),
                    :ok <- add_column_comments(conn, sanitized_name, column_comments) do
                    Logger.info("Tabla #{table_name} creada/verificada exitosamente")
                    :ok
                else
                    {:error, reason} ->
                    Logger.error("Error al crear tabla #{table_name}: #{inspect(reason)}")
                    Postgrex.rollback(conn, reason)
                end
            end
        )

        case result do
            {:ok, :ok} -> :ok
            {:error, reason} -> {:error, reason}
        end
    end

    #
    # Adds descriptive comments to each column
    #
    # ### Parameters:
    #     - conn: pid. Connection
    #     - table_name: String. Table name
    #     - comments: Map. Column comments
    #
    # ### Returns:
    #     - :ok - Successful comments added
    #     - {:error, reason} - Error adding comments
    #
    defp add_column_comments(conn, table_name, comments) when is_map(comments) do
        results =
            comments
            |> Enum.map(fn {column, description} ->
                escaped = PostgresHelpers.escape_sql_string(to_string(description))
                comment_query = "COMMENT ON COLUMN #{table_name}.#{column} IS '#{escaped}';"
                Postgrex.query(conn, comment_query, [])
            end)

        Enum.find(results, fn result -> match?({:error, _}, result) end)
        |> case do
            nil -> :ok
            error -> error
        end
    end

    @doc """
    Deletes a table from the database.

    ### Parameters
        - pool_name: Atom. Pool name
        - table_name: String. Table name to delete

    ### Returns
        - :ok - Table deleted successfully
        - {:error, reason} - Error deleting the table
    """
    def drop_table(pool_name, table_name) do
        sanitized_name = PostgresHelpers.sanitize_identifier(table_name)
        query = "DROP TABLE IF EXISTS #{sanitized_name};"

        Pool.Postgres.query(pool_name, query, [])
        |> case do
            {:ok, _} -> :ok
            {:error, reason} = error ->
                Logger.error("Error al eliminar tabla #{table_name}: #{inspect(reason)}")
                error
        end
    end

    ############
    # INSERT OPERATIONS
    ############

    @doc """
    Inserts a new record into the table.

    ### Parameters
        - pool_name: Atom. Pool name
        - table_name: String. Table name
        - record: Map. Record data with:
            - :id_nodo: String. Node UUID (required)
            - :tipo: String. Type/category (optional)
            - :informacion: Map. JSON data (required)

    ### Returns
        - {:ok, count} - Number of records inserted
        - {:error, reason} - Insert error
    """
    def insert(pool_name, table_name, record) do
        insert_many(pool_name, table_name, [record])
    end

    @doc """
    Inserts multiple records into the table efficiently.

    ### Parámetros
        - pool_name: Atom. Pool name
        - table_name: String. Table name
        - records: List. List of maps with data (same structure as `insert/3`)

    ### Returns
        - {:ok, count} - Number of records inserted
        - {:error, reason} - Insert error
    """
    def insert_many(pool_name, table_name, records) when is_list(records) do
        if Enum.empty?(records) do
            {:ok, 0}
        else
            try do
                sanitized_name = PostgresHelpers.sanitize_identifier(table_name)

                {values_sql, params, _} =
                    records
                    |> Enum.reduce(
                        {"", [], 1},
                        fn record, {sql, params, idx} ->
                            id_nodo = Map.fetch!(record, :id_nodo)
                            tipo = Map.get(record, :tipo)
                            informacion = PostgresHelpers.to_json(Map.fetch!(record, :informacion))
                            fecha_creado = DateTime.utc_now()
                            estado_analisis = @unanalyzed_state

                            value_sql = "($#{idx}, $#{idx + 1}, $#{idx + 2}::jsonb, $#{idx + 3}, $#{idx + 4})"
                            new_sql = if sql == "", do: value_sql, else: "#{sql}, #{value_sql}"

                            {new_sql, params ++ [id_nodo, tipo, informacion, fecha_creado, estado_analisis], idx + 5}
                        end
                    )

                query = """
                INSERT INTO #{sanitized_name} (id_nodo, tipo, informacion, fecha_creado, estado_analisis)
                VALUES #{values_sql};
                """

                Pool.Postgres.query(pool_name, query, params)
                |> case do
                    {:ok, %{num_rows: count}} ->
                        {:ok, count}

                    {:error, reason} = error ->
                        Logger.error("Error al insertar múltiples registros en #{table_name}: #{inspect(reason)}")
                        error
                end
            rescue
                error ->
                    Logger.error("Error al insertar registros: #{inspect(error)}")
                    {:error, error}
            end
        end
    end

    # ============================================
    # READ OPERATIONS
    # ============================================

    @doc """
    Obtains all records pending to be sent to BigQuery.

    ### Parameters
        - `pool_name` (atom) - Pool name
        - `table_name` (String) - Table name
        - `register_type` (String | nil, optional) - Filter by type. If nil, returns all.

    ### Returns
        - {:ok, records} - List of maps with records
        - {:error, reason} - Query error
    """
    def get_pending_bq(pool_name, table_name, register_type \\ nil) do
        sanitized_name = PostgresHelpers.sanitize_identifier(table_name)

        {query, params} =
        case register_type do
            nil ->
            {"""
            SELECT id, id_nodo, tipo, informacion, fecha_creado, estado_analisis
            FROM #{sanitized_name}
            WHERE estado_analisis = '#{@unanalyzed_state}'
            ORDER BY id_nodo, fecha_creado DESC;
            """, []}

            _ ->
            {"""
            SELECT id, id_nodo, tipo, informacion, fecha_creado, estado_analisis
            FROM #{sanitized_name}
            WHERE tipo = $1 AND estado_analisis = '#{@unanalyzed_state}'
            ORDER BY id_nodo, fecha_creado DESC;
            """, [register_type]}
        end

        case Pool.Postgres.query_read(pool_name, query, params) do
        {:ok, result} ->
            {:ok, PostgresHelpers.parse_query_result(result)}

        {:error, reason} = error ->
            Logger.error("Error al obtener registros pendientes de #{table_name}: #{inspect(reason)}")
            error
        end
    end

    @doc """
    Obtains all records from the table.

    ### Parameters
        - `pool_name` (atom) - Pool name
        - `table_name` (String) - Table name
        - `limit` (Integer | nil, optional) - Limit of records. If nil, returns all.

    ### Returns
        - {:ok, records} - List of maps with records
        - {:error, reason} - Query error
    """
    def get_all(pool_name, table_name, limit \\ nil) do
        sanitized_name = PostgresHelpers.sanitize_identifier(table_name)

        query =
        case limit do
            nil ->
            """
            SELECT id, id_nodo, tipo, informacion, fecha_creado, estado_analisis
            FROM #{sanitized_name}
            ORDER BY id_nodo, fecha_creado DESC;
            """

            _ ->
            """
            SELECT id, id_nodo, tipo, informacion, fecha_creado, estado_analisis
            FROM #{sanitized_name}
            ORDER BY id_nodo, fecha_creado DESC
            LIMIT #{limit};
            """
        end

        Pool.Postgres.query_read(pool_name, query, [])
        |> case do
        {:ok, result} ->
            {:ok, PostgresHelpers.parse_query_result(result)}

        {:error, reason} = error ->
            Logger.error("Error al obtener registros de #{table_name}: #{inspect(reason)}")
            error
        end
    end

    @doc """
    Deletes records by a list of IDs.

    ### Parameters
        - `pool_name` (atom) - Pool name
        - `table_name` (String) - Table name
        - `ids` (List) - List of IDs to delete

    ### Returns
        - {:ok, count} - Number of deleted records
        - {:error, reason} - Delete error
    """
    def delete_by_ids(pool_name, table_name, ids) when is_list(ids) do
        Enum.empty?(ids)
        |> if do
            {:ok, 0}
        else
            PostgresHelpers.sanitize_identifier(table_name)
            |> then(fn sanitized_name ->
                placeholders = PostgresHelpers.build_placeholders(length(ids))

                query = """
                DELETE FROM #{sanitized_name}
                WHERE id IN (#{placeholders});
                """

                Pool.Postgres.query(pool_name, query, ids)
                |> case do
                    {:ok, %{num_rows: count}} ->
                        {:ok, count}

                    {:error, reason} = error ->
                        Logger.error("Error al eliminar registros de #{table_name}: #{inspect(reason)}")
                        error
                end
            end)
        end
    end

    @doc """
    Marks records as successfully sent to BigQuery.

    ### Parameters
        - `pool_name` (atom) - Pool name
        - `table_name` (String) - Table name
        - `ids` (List) - List of IDs to update

    ### Returns
        - {:ok, count} - Number of updated records
        - {:error, reason} - Update error
    """
    def mark_as_sent_to_bq(pool_name, table_name, ids) when is_list(ids) do
        Enum.empty?(ids)
        |> if do
            {:ok, 0}
        else
            PostgresHelpers.sanitize_identifier(table_name)
            |> then(fn sanitized_name ->
                placeholders = PostgresHelpers.build_placeholders(length(ids))

                query = """
                UPDATE #{sanitized_name}
                SET estado_analisis = '#{@state_analyzed_in_bq}'
                WHERE id IN (#{placeholders});
                """

                Pool.Postgres.query(pool_name, query, ids)
                |> case do
                    {:ok, %{num_rows: count}} ->
                        {:ok, count}

                    {:error, reason} = error ->
                        Logger.error("Error al actualizar estado_analisis en #{table_name}: #{inspect(reason)}")
                        error
                end
            end)
        end
    end

    @doc """
    Marks records as problematic (with errors).

    ### Parameters
        - `pool_name` (atom) - Pool name
        - `table_name` (String) - Table name
        - `ids` (List) - List of IDs to mark as problematic

    ### Retorna
        - {:ok, count} - Number of updated records
        - {:error, reason} - Update error
    """
    def mark_as_with_problems(pool_name, table_name, ids) when is_list(ids) do
        Enum.empty?(ids)
        |> if do
            {:ok, 0}
        else
            sanitized_name = PostgresHelpers.sanitize_identifier(table_name)
            placeholders = PostgresHelpers.build_placeholders(length(ids))

            query = """
            UPDATE #{sanitized_name}
            SET estado_analisis = '#{@state_with_problems}'
            WHERE id IN (#{placeholders});
            """

            case Pool.Postgres.query(pool_name, query, ids) do
                {:ok, %{num_rows: count}} ->
                    Logger.warning("#{count} registros marcados como error (con problema) en #{table_name}")
                    {:ok, count}

                {:error, reason} = error ->
                    Logger.error("Error al marcar registros como error en #{table_name}: #{inspect(reason)}")
                    error
            end
        end
    end

    @doc """
    Deletes records that have been analyzed and sent to BigQuery.

    ### Parameters

    - `pool_name` (atom) - Pool name
    - `table_name` (String) - Table name
    - `opts` (Keyword, optional) - Options:
        - `:register_type` (String | nil) - If provided, only deletes records with this type
        - `:include_with_problems` (Boolean) - If true, also deletes records with problems (default: true)

    ### Retorna
        - {:ok, count} - Number of deleted records
        - {:error, reason} - Delete error
    """
    def delete_analyzed_records(pool_name, table_name, opts \\ []) do
        sanitized_name = PostgresHelpers.sanitize_identifier(table_name)
        include_with_problems = Keyword.get(opts, :include_with_problems, true)
        register_type = Keyword.get(opts, :register_type, nil)

        estado_condition =
            if include_with_problems do
                "estado_analisis IN ('#{@state_analyzed_in_bq}', '#{@state_with_problems}')"
            else
                "estado_analisis = '#{@state_analyzed_in_bq}'"
            end

        tipo_condition =
            if register_type do
                " AND tipo = '#{register_type}'"
            else
                ""
            end

        query = """
        DELETE FROM #{sanitized_name}
        WHERE #{estado_condition}#{tipo_condition};
        """

        Pool.Postgres.query(pool_name, query, [])
        |> case do
        {:ok, %{num_rows: count}} ->
            {:ok, count}

        {:error, reason} = error ->
            Logger.error("Error al eliminar registros analizados de #{table_name}: #{inspect(reason)}")
            error
        end
    end

    @doc """
    Executes a flexible SELECT query with configurable fields, DISTINCT and WHERE conditions.

    ### Parameters
        - `pool_name` (atom) - Pool name
        - `table_name` (String) - Table name
        - `opts` (Keyword) - Query options:
            - `:select` (List) - Fields to select. Each element can be:
            - String/Atom: field name
            - Tuple {field, :distinct}: applies DISTINCT
            - Tuple {field, alias}: renames the field
            - Tuple {field, alias, :distinct}: DISTINCT with alias
            - `:where` (List) - WHERE conditions. Each element is:
            - {field, :eq, value} - field = value
            - {field, :neq, value} - field != value
            - {field, :in, list} - field IN (list)
            - {field, :not_null} - field IS NOT NULL
        - {field, :is_null} - field IS NULL

    ### Retorna
        - `{:ok, rows}` - Lista de filas resultado
        - `{:error, :empty_select}` - No se especificaron campos
        - `{:error, reason}` - Error de query
    """
    def query_flexible(pool_name, table_name, opts \\ []) do
        select_fields = Keyword.get(opts, :select, [])
        where_conditions = Keyword.get(opts, :where, [])

        with :ok <- validate_table_name(table_name),
            :ok <- validate_select_fields(select_fields) do

        sanitized_name = PostgresHelpers.sanitize_identifier(table_name)
        {select_sql, has_distinct} = build_select_clause(select_fields)
        {where_sql, params} = build_where_clause(where_conditions)
        distinct_keyword = if has_distinct, do: "DISTINCT ", else: ""

        query = """
        SELECT #{distinct_keyword}#{select_sql}
        FROM #{sanitized_name}
        #{where_sql}
        """

        Pool.Postgres.query_read(pool_name, query, params)
        |> case do
            {:ok, %{rows: rows}} ->
                {:ok, rows}

            {:error, reason} = error ->
                Logger.error("Error en consulta flexible en #{table_name}: #{inspect(reason)}")
                error
            end
        end
    end

    # Validation and construction of queries (copied from Connection.Postgres)

    defp validate_table_name(nil), do: {:error, :invalid_table_name}
    defp validate_table_name(""), do: {:error, :invalid_table_name}
    defp validate_table_name(name) when is_binary(name) do
        if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, name) do
            :ok
        else
            {:error, :invalid_table_name}
        end
    end
    defp validate_table_name(_), do: {:error, :invalid_table_name}

    defp validate_select_fields([]), do: {:error, :empty_select}
    defp validate_select_fields(fields) when is_list(fields) do
        valid? = Enum.all?(
            fields,
            fn
                field when is_atom(field) or is_binary(field) -> true
                {field, :distinct} when is_atom(field) or is_binary(field) -> true
                {field, alias} when (is_atom(field) or is_binary(field)) and is_binary(alias) -> true
                {field, alias, :distinct} when (is_atom(field) or is_binary(field)) and is_binary(alias) -> true
                _ -> false
            end
        )

        if valid?, do: :ok, else: {:error, :invalid_select_format}
    end
    defp validate_select_fields(_), do: {:error, :invalid_select_format}

    defp build_select_clause(fields) do
        {parts, has_distinct} =
        fields
        |> Enum.reduce({[], false}, fn field, {acc, distinct_flag} ->
            case field do
            {f, :distinct} ->
                {acc ++ [to_string(f)], true}

            {f, alias, :distinct} ->
                {acc ++ ["#{to_string(f)} AS #{alias}"], true}

            {f, alias} when is_binary(alias) ->
                {acc ++ ["#{to_string(f)} AS #{alias}"], distinct_flag}

            f ->
                {acc ++ [to_string(f)], distinct_flag}
            end
        end)

        {Enum.join(parts, ", "), has_distinct}
    end

    defp build_where_clause([]), do: {"", []}

    defp build_where_clause(conditions) do
        {clauses, params, _idx} =
        conditions
        |> Enum.reduce({[], [], 1}, fn condition, {clauses_acc, params_acc, idx} ->
            case condition do
            {field, :eq, value} ->
                {
                clauses_acc ++ ["#{to_string(field)} = $#{idx}"],
                params_acc ++ [value],
                idx + 1
                }

            {field, :neq, value} ->
                {
                clauses_acc ++ ["#{to_string(field)} != $#{idx}"],
                params_acc ++ [value],
                idx + 1
                }

            {field, :in, list} ->
                {
                clauses_acc ++ ["#{to_string(field)} = ANY($#{idx})"],
                params_acc ++ [list],
                idx + 1
                }

            {field, :not_null} ->
                {
                clauses_acc ++ ["#{to_string(field)} IS NOT NULL"],
                params_acc,
                idx
                }

            {field, :is_null} ->
                {
                clauses_acc ++ ["#{to_string(field)} IS NULL"],
                params_acc,
                idx
                }
            end
        end)

        where_sql = "WHERE " <> Enum.join(clauses, " AND ")
        {where_sql, params}
    end


end
