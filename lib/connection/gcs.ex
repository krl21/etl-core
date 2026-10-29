
defmodule Connection.Gcs do
    @moduledoc"""
    Module for working with Google Cloud Storage (GCS) buckets. Calls the GCS JSON API with `Tesla` (hackney adapter) and authenticates with `Goth`.

    ### Authentication:
        Call `configure/1` once, with the service account JSON credentials, before using any other function.

    ### Errors and retries:
        Functions raise an exception if the operation fails. Transient errors (HTTP 408, 429, 5xx and network errors) are retried with exponential backoff.

    """

    require Logger

    alias Connection.Gcs.ContentType
    import Connection.Gcs.Helpers, only: [
        load_credentials!: 1, store_credentials: 1, token: 0, media_upload: 4, resumable_upload: 4, request: 2, request: 3,
        bucket_url: 1, object_url: 2, list_page: 4, upload_one: 4, with_retry: 2, ensure_trailing_slash: 1, validate_name!: 2
    ]

    # Size of the chunks read from disk when uploading a file
    @upload_chunk_bytes 256 * 1024
    # Files larger than this are uploaded with a resumable upload
    @resumable_threshold_bytes 8 * 1024 * 1024
    # Files uploaded at the same time by upload_files/4
    @default_max_concurrency 4


    ################
    ### Functions
    ################

    @doc"""
    Stores the service account credentials used by every function of this module. It must be called once (e.g. when the application starts), before any other function. Calling it again replaces the credentials.

    ### Parameter:
        - credentials: String | Map. Path to the service account JSON file, the JSON content as a string, or the already decoded map.

    ### Return:
        - :ok | Exception. Raises an exception if the credentials are invalid or a token cannot be obtained with them.
    """
    def configure(credentials) do
        credentials = load_credentials!(credentials)

        store_credentials(credentials)

        # Validates the credentials right away
        token()

        Logger.debug("Credenciales de GCS configuradas para #{credentials["client_email"]}")
        :ok
    end

    @doc"""
    Creates a virtual folder in a bucket. It uploads an empty object whose name ends with `/`.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - folder: String. Folder path (e.g. `documents/2023/`).

    ### Return:
        - String | Exception. GCS URI of the folder (`gs://bucket/folder/`).
    """
    def create_folder(bucket, folder) do
        validate_name!(bucket, "bucket")
        validate_name!(folder, "folder")

        folder = ensure_trailing_slash(folder)
        upload_binary(bucket, "", folder, "application/x-directory")

        Logger.debug("Carpeta creada: #{gcs_uri(bucket, folder)}")
        gcs_uri(bucket, folder)
    end

    @doc"""
    Uploads a local file to a folder of the bucket, keeping its file name.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - path: String. Local path of the file (pdf, jsonl, csv, etc.).
        - folder: String. Destination folder in the bucket.
        - opts: Keyword. Same options as `upload_file/5`.

    ### Return:
        - String | Exception. GCS URI of the uploaded file.

    """
    def upload_to_folder(bucket, path, folder, opts \\ []) do
        validate_name!(folder, "folder")

        object = ensure_trailing_slash(folder) <> Path.basename(path)
        upload_file(bucket, path, object, opts)
    end

    @doc"""
    Uploads several local files to a folder of the bucket, keeping their file names. When there is more than one file, they are uploaded in parallel (up to `:max_concurrency` at a time). A failed file does not stop the others.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - paths: list of String. Local paths of the files.
        - folder: String. Destination folder in the bucket.
        - opts: Keyword.
            - `:max_concurrency` - Integer. Files uploaded at the same time. Default: `4`.
            - `:content_type` - String. MIME type for every file. By default, it is detected from each file extension.

    ### Return:
        - list of {String, {:ok, String} | {:error, String}} | Exception. For each local path, in the same order as `paths`, the GCS URI of the uploaded file or the error message. Raises an exception if the parameters are invalid or two files have the same name (they would overwrite the same object).

    """
    def upload_files(bucket, paths, folder, opts \\ [])

    def upload_files(bucket, paths, folder, opts) when is_list(paths) and paths != [] do
        validate_name!(bucket, "bucket")
        validate_name!(folder, "folder")
        Enum.each(paths, &validate_name!(&1, "local path"))

        duplicated =
            paths
            |> Enum.frequencies_by(&Path.basename/1)
            |> Enum.filter(fn {_, count} -> count > 1 end)
            |> Enum.map(fn {name, _} -> name end)

        if duplicated != [] do
            raise(ArgumentError, "Hay archivos con el mismo nombre, se sobrescribirían en #{gcs_uri(bucket, ensure_trailing_slash(folder))}: #{inspect(duplicated)}")
        end

        {max_concurrency, upload_opts} = Keyword.pop(opts, :max_concurrency, @default_max_concurrency)

        case paths do
            [path] ->
                [{path, upload_one(bucket, path, folder, upload_opts)}]

            _ ->
                paths
                |> Task.async_stream(
                    fn path -> {path, upload_one(bucket, path, folder, upload_opts)} end,
                    max_concurrency: max_concurrency,
                    timeout: :infinity,
                    ordered: true
                )
                |> Enum.map(fn {:ok, result} -> result end)
        end
    end

    def upload_files(_bucket, paths, _folder, _opts), do:
        raise(ArgumentError, "Valor inválido para paths: se espera una lista no vacía de rutas locales. Valor: #{inspect(paths)}")

    @doc"""
    Uploads every file of a local directory to a folder of the bucket, keeping their file names. Files are uploaded in parallel with `upload_files/4`. Only the files directly inside the directory are uploaded: sub-directories are skipped.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - directory: String. Local directory.
        - folder: String. Destination folder in the bucket.
        - opts: Keyword. Same options as `upload_files/4`.

    ### Return:
        - list of {String, {:ok, String} | {:error, String}} | Exception. Same result as `upload_files/4`. Empty list if the directory has no files. Raises an exception if the directory does not exist.

    """
    def upload_directory(bucket, directory, folder, opts \\ []) do
        validate_name!(directory, "local directory")

        if not File.dir?(directory) do
            raise(File.Error, reason: :enoent, action: "upload directory to GCS", path: directory)
        end

        directory
        |> File.ls!()
        |> Enum.sort()
        |> Enum.map(&Path.join(directory, &1))
        |> Enum.filter(&File.regular?/1)
        |> case do
            [] ->
                Logger.debug("No hay archivos para subir en #{directory}")
                []
            paths ->
                upload_files(bucket, paths, folder, opts)
        end
    end

    @doc"""
    Uploads a local file to the bucket. The file is streamed from disk, it is not loaded into memory.

    Files up to 8 MiB are uploaded in a single request. Larger files use a resumable upload: they are sent in chunks and, if the connection fails, the upload resumes from the last byte stored by GCS instead of starting again.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - path: String. Local path of the file.
        - object: String. Full name of the object in the bucket, including the file name (e.g. `documents/report.pdf`).
        - opts: Keyword.
            - `:content_type` - String. MIME type. By default, it is detected from the file extension (`.pdf` -> `application/pdf`, `.jsonl` -> `application/jsonl`, etc.).

    ### Return:
        - String | Exception. GCS URI of the uploaded file.

    """
    def upload_file(bucket, path, object, opts \\ []) do
        validate_name!(bucket, "bucket")
        validate_name!(path, "local path")
        validate_name!(object, "object")

        if not File.regular?(path) do
            raise(File.Error, reason: :enoent, action: "upload to GCS", path: path)
        end

        content_type = Keyword.get_lazy(opts, :content_type, fn -> ContentType.from_path(path) end)
        %File.Stat{size: size} = File.stat!(path)

        if size > @resumable_threshold_bytes do
            resumable_upload(bucket, object, path, content_type)
        else
            with_retry(
                "upload_file #{gcs_uri(bucket, object)}",
                fn ->
                    body =
                        path
                        |> File.stream!([], @upload_chunk_bytes)
                        |> Stream.map(& &1)

                    media_upload(bucket, object, body, [{"content-type", content_type}, {"content-length", Integer.to_string(size)}])
                end
            )
        end

        Logger.debug("Archivo #{path} subido a #{gcs_uri(bucket, object)}")
        gcs_uri(bucket, object)
    end

    @doc"""
    Uploads in-memory content to the bucket.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - data: iodata. Content to upload.
        - object: String. Full name of the object in the bucket.
        - content_type: String. MIME type. Default: detected from the object extension.

    ### Return:
        - String | Exception. GCS URI of the uploaded object.

    """
    def upload_binary(bucket, data, object, content_type \\ nil) do
        validate_name!(bucket, "bucket")
        validate_name!(object, "object")

        content_type = content_type || ContentType.from_path(object)

        with_retry("upload_binary #{gcs_uri(bucket, object)}", fn ->
            media_upload(bucket, object, IO.iodata_to_binary(data), [{"content-type", content_type}])
        end)

        gcs_uri(bucket, object)
    end

    @doc"""
    Reads an object and returns its content in memory. It does not write anything to disk; to save the object to a local file use `download_file/3`.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - object: String. Full name of the object.

    ### Return:
        - Binary | Exception

    """
    def read_object(bucket, object) do
        validate_name!(bucket, "bucket")
        validate_name!(object, "object")

        %Tesla.Env{body: body} =
            with_retry("read_object #{gcs_uri(bucket, object)}", fn ->
                request(:get, object_url(bucket, object), query: [alt: "media"])
            end)

        body
    end

    @doc"""
    Downloads an object to a local file. Creates the parent directory if it does not exist.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - object: String. Full name of the object.
        - path: String. Local destination path. If it ends with `/`, it is treated as a directory and the file keeps the object name (e.g. object `docs/report.pdf` and path `/tmp/` -> `/tmp/report.pdf`).

    ### Return:
        - String | Exception. Local path of the downloaded file.

    """
    def download_file(bucket, object, path) do
        validate_name!(path, "local path")

        path =
            if String.ends_with?(path, "/"),
                do: Path.join(path, Path.basename(object)),
                else: path

        content = read_object(bucket, object)

        path |> Path.dirname() |> File.mkdir_p!()
        File.write!(path, content)

        Logger.debug("Descargado: #{gcs_uri(bucket, object)} -> #{path}")
        path
    end

    @doc"""
    Downloads every file of a folder to a local directory. Sub-folder markers (names ending with `/`) are skipped, and files are saved flat, with their base name.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - folder: String. Folder in the bucket.
        - directory: String. Local destination directory.

    ### Return:
        - list of String | Exception. Local paths of the downloaded files. Empty list if the folder has no files.

    """
    def download_folder(bucket, folder, directory) do
        validate_name!(folder, "folder")
        validate_name!(directory, "local directory")

        File.mkdir_p!(directory)

        bucket
        |> list_objects(ensure_trailing_slash(folder))
        |> Enum.reject(&String.ends_with?(&1, "/"))
        |> case do
            [] ->
                Logger.debug("No hay archivos en #{gcs_uri(bucket, ensure_trailing_slash(folder))}")
                []
            objects ->
                Enum.map(objects, fn object ->
                    download_file(bucket, object, Path.join(directory, Path.basename(object)))
                end)
        end
    end

    @doc"""
    Lists the names of the objects of a bucket that start with a prefix. Handles pagination.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - prefix: String. Prefix of the object names. Default: `""` (whole bucket).

    ### Return:
        - list of String | Exception

    """
    def list_objects(bucket, prefix \\ "") do
        validate_name!(bucket, "bucket")
        list_page(bucket, prefix, nil, [])
    end

    @doc"""
    Checks if a folder has at least one object.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - folder: String. Folder in the bucket.

    ### Return:
        - boolean | Exception

    """
    def folder_exists?(bucket, folder) do
        validate_name!(bucket, "bucket")
        validate_name!(folder, "folder")

        prefix = ensure_trailing_slash(folder)

        %Tesla.Env{body: body} =
            with_retry("folder_exists? #{gcs_uri(bucket, prefix)}", fn ->
                request(:get, "#{bucket_url(bucket)}/o", query: [prefix: prefix, maxResults: 1, fields: "items(name)"])
            end)

        body
        |> Jason.decode!()
        |> Map.get("items", [])
        |> Kernel.!=([])
    end

    @doc"""
    Checks if an object exists.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - object: String. Full name of the object.

    ### Return:
        - boolean | Exception

    """
    def exists?(bucket, object) do
        validate_name!(bucket, "bucket")
        validate_name!(object, "object")

        with_retry("exists? #{gcs_uri(bucket, object)}", fn ->
            request(:get, object_url(bucket, object), query: [fields: "name"])
            |> case do
                {:error, %Tesla.Env{status: 404}} -> {:ok, false}
                {:ok, _} -> {:ok, true}
                error -> error
            end
        end)
    end

    @doc"""
    Deletes an object. Deleting an object that does not exist is not an error.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - object: String. Full name of the object.

    ### Return:
        - :ok | Exception

    """
    def delete_object(bucket, object) do
        validate_name!(bucket, "bucket")
        validate_name!(object, "object")

        with_retry("delete_object #{gcs_uri(bucket, object)}", fn ->
            request(:delete, object_url(bucket, object))
            |> case do
                {:error, %Tesla.Env{status: 404}} -> {:ok, :not_found}
                result -> result
            end
        end)

        Logger.debug("Eliminado: #{gcs_uri(bucket, object)}")
        :ok
    end

    @doc"""
    Deletes a folder and every object inside it.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - folder: String. Folder in the bucket.

    ### Return:
        - integer | Exception. Number of deleted objects.

    """
    def delete_folder(bucket, folder) do
        validate_name!(folder, "folder")

        bucket
        |> list_objects(ensure_trailing_slash(folder))
        |> Enum.map(&delete_object(bucket, &1))
        |> length()
    end

    @doc"""
    Builds the GCS URI of an object.

    ### Parameters:
        - bucket: String. Name of the bucket.
        - object: String. Full name of the object.

    ### Return:
        - String. `gs://bucket/object`

    """
    def gcs_uri(bucket, object), do:
        "gs://#{bucket}/#{object}"

end
