
defmodule Connection.PostgresHelpers do
    @moduledoc """
    Helper functions for database operations.
    """

    @doc """
    Sanitizes a SQL identifier (table name, column, etc.) to prevent SQL injection.

    ### Parameters
        - name (String) - The identifier name to sanitize

    ### Returns
        - String - Sanitized identifier
    """
    def sanitize_identifier(nil) do
        raise ArgumentError, "Invalid identifier name: nil - check if table name is properly configured (environment variable may not be set)"
    end

    def sanitize_identifier(name) when is_atom(name) do
        name
        |> Atom.to_string()
        |> sanitize_identifier()
    end

    def sanitize_identifier(name) when is_binary(name) do
        sanitized =
            name
            |> String.replace(~r/[^a-zA-Z0-9_]/, "")
            |> String.downcase()

        if sanitized == "" do
            raise ArgumentError, "Invalid identifier name: #{name}"
        end

        sanitized
    end

    @doc """
    Converts map keys from strings to atoms.

    ### Parameters
        - map (Map) - Map with string or atom keys

    ### Returns
        - Map - Map with all keys as atoms
    """
    def atomize_keys(map) when is_map(map) do
        map
        |> Enum.map(fn
            {k, v} when is_binary(k) -> {String.to_atom(k), v}
            {k, v} -> {k, v}
        end)
        |> Enum.into(%{})
    end

    @doc """
    Escapes single quotes in a string for safe SQL usage.

    ### Parameters
        - str (String) - The string to escape

    ### Returns
        - String - String with escaped quotes
    """
    def escape_sql_string(str) when is_binary(str) do
        String.replace(str, "'", "''")
    end

    @doc """
    Builds SQL placeholders for a list of parameters.

    ### Parameters
        - count (Integer) - Number of placeholders to generate
        - start_idx (Integer, optional) - Starting index, defaults to 1

    ### Returns
        - String - Comma-separated placeholders
    """
    def build_placeholders(count, start_idx \\ 1) when is_integer(count) and count > 0 do
        start_idx..(start_idx + count - 1)
        |> Enum.map(&"$#{&1}")
        |> Enum.join(", ")
    end

    @doc """
    Converts a map or struct to a JSON string using Poison.

    ### Parameters
        - data (Map | List | Struct | String) - Data to convert

    ### Returns
        - String - JSON string
    """
    def to_json(data) when is_binary(data), do: data
    def to_json(data), do: Poison.encode!(data)

    @doc """
    Builds connection options for Postgrex.

    ### Parameters
        - config (Map) - Base configuration map with database credentials
        - hostname (String) - Host to use for the connection

    ### Returns
        - Keyword - List of options for Postgrex
    """
    def build_connection_opts(config, hostname) do
        [
            hostname: hostname,
            port: Map.get(config, :port, 5432),
            database: Map.fetch!(config, :database),
            username: Map.fetch!(config, :username),
            password: Map.fetch!(config, :password),
            ssl: Map.get(config, :ssl, false),
            pool_size: Map.get(config, :pool_size, 5)
        ]
    end

    @doc """
    Parses a Postgrex query result into a list of maps.

    ### Parameters
        - result (Postgrex.Result) - Result from Postgrex.query

    ### Returns
        - List - List of maps with atom keys
    """
    def parse_query_result(%{rows: rows, columns: columns}) do
        Enum.map(rows, fn row ->
            columns
            |> Enum.zip(row)
            |> Enum.into(%{})
            |> atomize_keys()
        end)
    end

    @doc """
    Returns default column comments for the buffer table.

    ### Returns
        - Map - Descriptions for each column
    """
    def default_column_comments do
        %{
            id: "Identificador único autoincremental",
            id_nodo: "UUID del nodo o registro",
            tipo: "Tipo o categoría del registro, o nombre de la tabla de destino en BigQuery",
            informacion: "Datos del registro transformados en formato JSON",
            fecha_creado: "Marca de tiempo de creación",
            estado_analisis: "Estado del análisis: sin_analizar (pendiente), analizado_en_bq (enviado a BigQuery), con_problemas (presenta errores)"
        }
    end



end
