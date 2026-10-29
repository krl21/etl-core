
defmodule Connection.Gcs.Helpers do
    @moduledoc"""
    Helper functions for `Connection.Gcs`: HTTP requests to the GCS JSON API, access token handling, retries and validations.

    """

    require Logger

    alias Connection.Gcs

    @max_attempts 5
    @base_backoff_ms 500
    @max_backoff_ms 30_000
    @retryable_status [408, 429, 500, 502, 503, 504]

    # :persistent_term keys, namespaced under the public module (Connection.Gcs)
    @credentials_key {Connection.Gcs, :credentials}
    @token_key {Connection.Gcs, :token}
    # Seconds before expiration in which the token is renewed
    @token_refresh_margin 300

    @api_url "https://storage.googleapis.com/storage/v1/b"
    @upload_url "https://storage.googleapis.com/upload/storage/v1/b"


    ################
    ### Functions
    ################

    @doc"""
    Builds a Tesla client authenticated with the current token. Uses hackney as adapter (already a dependency through httpoison), which verifies TLS certificates.

    ### Parameters:
        - None.

    ### Return:
        - Tesla.Client.t() | Exception. Raises an exception if a token cannot be obtained.
    """
    def conn() do
        Tesla.client(
            [{Tesla.Middleware.Headers, [{"authorization", "Bearer #{token()}"}]}],
            Tesla.Adapter.Hackney
        )
    end

    @doc"""
    Uploads an object with `uploadType=media`: the content goes in the body and the name in the query string.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - object: String. Full name of the object.
        - body: Binary | Stream. Content to upload.
        - headers: list of {String, String}. Request headers (`content-type` and, for streams, `content-length`).

    ### Return:
        - {:ok, Tesla.Env.t()} | {:error, Tesla.Env.t() | term()}
    """
    def media_upload(bucket, object, body, headers) do
        request(:post, "#{@upload_url}/#{encode_path(bucket)}/o",
            query: [uploadType: "media", name: object],
            headers: headers,
            body: body
        )
    end

    @doc"""
    Executes a request against the GCS API.

    ### Parameters:
        - method: Atom. HTTP method (`:get`, `:post`, `:delete`, ...).
        - url: String. Full URL of the endpoint.
        - opts: Keyword. `:query` (keyword), `:headers` (list of {String, String}) and `:body` (binary or stream).

    ### Return:
        - {:ok, Tesla.Env.t()} for 2xx responses | {:error, Tesla.Env.t()} for other statuses | {:error, term()} for network errors
    """
    def request(method, url, opts \\ []) do
        conn()
        |> Tesla.request(
            method: method,
            url: url,
            query: Keyword.get(opts, :query, []),
            headers: Keyword.get(opts, :headers, []),
            body: Keyword.get(opts, :body)
        )
        |> case do
            {:ok, %Tesla.Env{status: status} = env} when status in 200..299 -> {:ok, env}
            {:ok, env} -> {:error, env}
            error -> error
        end
    end

    @doc"""
    Builds the GCS JSON API URL of a bucket.

    ### Parameters:
        - bucket: String. Name of the bucket.

    ### Return:
        - String. `https://storage.googleapis.com/storage/v1/b/{bucket}`
    """
    def bucket_url(bucket), do:
        "#{@api_url}/#{encode_path(bucket)}"

    @doc"""
    Builds the GCS JSON API URL of an object.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - object: String. Full name of the object.

    ### Return:
        - String. `https://storage.googleapis.com/storage/v1/b/{bucket}/o/{object}`
    """
    def object_url(bucket, object), do:
        "#{bucket_url(bucket)}/o/#{encode_path(object)}"

    @doc"""
    Encodes a value as a single URL path segment. Object names may contain `/` and other characters that must be encoded.

    ### Parameters:
        - value: String. Value to encode.

    ### Return:
        - String. Encoded value (e.g. `docs/a b.pdf` -> `docs%2Fa%20b.pdf`).
    """
    def encode_path(value), do:
        URI.encode(value, &URI.char_unreserved?/1)

    @doc"""
    Stores the service account credentials for the whole node and discards the cached token.

    ### Parameters:
        - credentials: Map. Decoded service account credentials.

    ### Return:
        - :ok
    """
    def store_credentials(credentials) when is_map(credentials) do
        :persistent_term.put(@credentials_key, credentials)
        :persistent_term.erase(@token_key)
        :ok
    end

    @doc"""
    Returns the cached access token, or requests a new one if there is none or it is about to expire (less than `@token_refresh_margin` seconds).

    ### Parameters:
        - None.

    ### Return:
        - String | Exception. Access token.
    """
    def token() do
        now = System.system_time(:second)

        case :persistent_term.get(@token_key, nil) do
            %Goth.Token{token: token, expires: expires} when expires - @token_refresh_margin > now ->
                token

            _ ->
                %Goth.Token{token: token} = new_token = fetch_token!()
                :persistent_term.put(@token_key, new_token)
                token
        end
    end

    @doc"""
    Requests a new access token to Google with the credentials stored by `Connection.Gcs.configure/1`.

    ### Parameters:
        - None.

    ### Return:
        - Goth.Token.t() | Exception. Raises an exception if `Connection.Gcs.configure/1` was not called or the token request fails.
    """
    def fetch_token!() do
        credentials =
            :persistent_term.get(@credentials_key, nil)
            || raise("Credenciales de GCS no configuradas. Llamar primero a Connection.Gcs.configure/1")

        case Goth.Token.fetch(source: {:service_account, credentials}) do
            {:ok, token} -> token
            {:error, error} -> raise("Error al obtener token de GCS. Error: #{inspect(error)}")
        end
    end

    @doc"""
    Loads the service account credentials.

    ### Parameters:
        - credentials: String | Map. Path to the JSON file, the JSON content, or the already decoded map.

    ### Return:
        - Map | Exception. Decoded credentials.
    """
    def load_credentials!(credentials) when is_map(credentials), do:
        credentials

    def load_credentials!(credentials) when is_binary(credentials) do
        json =
            if String.starts_with?(String.trim_leading(credentials), "{"),
                do: credentials,
                else: File.read!(credentials)

        Jason.decode!(json)
    end

    def load_credentials!(credentials), do:
        raise(ArgumentError, "Credenciales de GCS inválidas: se espera la ruta al JSON, el JSON o un mapa. Valor: #{inspect(credentials)}")

    @doc"""
    Lists one page of objects and keeps requesting the next ones while there is a `nextPageToken`.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - prefix: String. Prefix of the object names.
        - page_token: String | nil. Token of the page to request. `nil` for the first page.
        - acc: list of String. Object names accumulated from previous pages.

    ### Return:
        - list of String | Exception. Names of every object with the prefix.
    """
    def list_page(bucket, prefix, page_token, acc) do
        query =
            [prefix: prefix, pageToken: page_token, fields: "items(name),nextPageToken"]
            |> Enum.reject(fn {_, value} -> is_nil(value) end)

        %Tesla.Env{body: body} =
            with_retry("list_objects #{Gcs.gcs_uri(bucket, prefix)}", fn ->
                request(:get, "#{bucket_url(bucket)}/o", query: query)
            end)

        page = Jason.decode!(body)
        acc = acc ++ Enum.map(Map.get(page, "items", []), & &1["name"])

        case Map.get(page, "nextPageToken") do
            nil -> acc
            token -> list_page(bucket, prefix, token, acc)
        end
    end

    @doc"""
    Executes a GCS request. Transient errors are retried with exponential backoff and jitter, up to `@max_attempts` attempts. Any other error raises an exception.

    ### Parameters:
        - operation: String. Description of the operation, used in logs and error messages.
        - fun: Function. Zero-arity function that executes the request and returns `{:ok, value}` or `{:error, reason}`.
        - attempt: Integer. Current attempt number. Default: `1`.

    ### Return:
        - t() | Exception. The `value` of `{:ok, value}`.
    """
    def with_retry(operation, fun, attempt \\ 1) do
        case fun.() do
            {:ok, value} ->
                value

            {:error, reason} ->
                if retryable?(reason) and attempt < @max_attempts do
                    delay = backoff(attempt)
                    Logger.warning("GCS #{operation}: intento #{attempt} falló (#{format_error(reason)}). Reintentando en #{delay} ms")
                    Process.sleep(delay)
                    with_retry(operation, fun, attempt + 1)
                else
                    raise("Error en GCS #{operation}. Error: #{format_error(reason)}")
                end
        end
    end

    @doc"""
    Checks if an error is transient and the request can be retried: HTTP 408, 429 and 5xx, and network errors from the adapter (`:timeout`, `:econnrefused`, `{:closed, _}`, ...). Exceptions (e.g. decoding errors) are not transient.

    ### Parameters:
        - reason: Tesla.Env.t() | term(). Error returned by the request.

    ### Return:
        - boolean
    """
    def retryable?(%Tesla.Env{status: status}), do: status in @retryable_status
    # Exceptions (e.g. decoding errors) are not transient
    def retryable?(%_{}), do: false
    # Network errors from the adapter (:timeout, :econnrefused, {:closed, _}, ...)
    def retryable?(_network_error), do: true

    @doc"""
    Calculates the wait before the next attempt: exponential (`@base_backoff_ms * 2^(attempt - 1)`, up to `@max_backoff_ms`) plus a random jitter.

    ### Parameters:
        - attempt: Integer. Number of the attempt that failed.

    ### Return:
        - Integer. Milliseconds to wait.
    """
    def backoff(attempt) do
        delay = min(@base_backoff_ms * Integer.pow(2, attempt - 1), @max_backoff_ms)
        delay + :rand.uniform(@base_backoff_ms)
    end

    @doc"""
    Builds a readable description of an error.

    ### Parameters:
        - reason: Tesla.Env.t() | term(). Error returned by the request.

    ### Return:
        - String
    """
    def format_error(%Tesla.Env{status: status, body: body}), do:
        "HTTP #{status}: #{inspect(body)}"
    def format_error(reason), do:
        inspect(reason)

    @doc"""
    Adds the trailing `/` to a folder path if it is missing.

    ### Parameters:
        - folder: String. Folder path.

    ### Return:
        - String. Folder path ending with `/`.
    """
    def ensure_trailing_slash(folder) do
        if String.ends_with?(folder, "/"), do: folder, else: folder <> "/"
    end

    @doc"""
    Validates that a value is a non-empty string.

    ### Parameters:
        - value: term(). Value to validate.
        - field: String. Name of the field, used in the error message.

    ### Return:
        - nil | Exception. Raises `ArgumentError` if the value is not a non-empty string.
    """
    def validate_name!(value, field) do
        if not is_binary(value) or String.trim(value) == "" do
            raise(ArgumentError, "Valor inválido para #{field}: #{inspect(value)}")
        end
    end




end
