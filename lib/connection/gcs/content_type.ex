
defmodule Connection.Gcs.ContentType do
    @moduledoc"""
    MIME types by file extension, used by `Connection.Gcs` to set the `contentType` of the uploaded objects.

    To support a new extension, add it to `@content_types` (lowercase, with the leading dot). Extensions not listed are uploaded as `application/octet-stream`.

    """

    @content_types %{
        # Documents
        ".pdf" => "application/pdf",
        ".doc" => "application/msword",
        ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xls" => "application/vnd.ms-excel",
        ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".ppt" => "application/vnd.ms-powerpoint",
        ".pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        ".odt" => "application/vnd.oasis.opendocument.text",
        ".ods" => "application/vnd.oasis.opendocument.spreadsheet",
        ".odp" => "application/vnd.oasis.opendocument.presentation",
        ".rtf" => "application/rtf",
        ".epub" => "application/epub+zip",

        # Data
        ".json" => "application/json",
        ".jsonl" => "application/jsonl",
        ".ndjson" => "application/x-ndjson",
        ".csv" => "text/csv",
        ".tsv" => "text/tab-separated-values",
        ".xml" => "application/xml",
        ".yaml" => "application/yaml",
        ".yml" => "application/yaml",
        ".parquet" => "application/vnd.apache.parquet",
        ".avro" => "application/avro",
        ".orc" => "application/octet-stream",
        ".sql" => "application/sql",

        # Text
        ".txt" => "text/plain",
        ".log" => "text/plain",
        ".md" => "text/markdown",
        ".html" => "text/html",
        ".htm" => "text/html",
        ".css" => "text/css",
        ".js" => "text/javascript",
        ".ics" => "text/calendar",
        ".vcf" => "text/vcard",

        # Images
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".png" => "image/png",
        ".gif" => "image/gif",
        ".bmp" => "image/bmp",
        ".webp" => "image/webp",
        ".svg" => "image/svg+xml",
        ".tif" => "image/tiff",
        ".tiff" => "image/tiff",
        ".ico" => "image/vnd.microsoft.icon",
        ".heic" => "image/heic",
        ".heif" => "image/heif",
        ".avif" => "image/avif",

        # Audio
        ".mp3" => "audio/mpeg",
        ".wav" => "audio/wav",
        ".ogg" => "audio/ogg",
        ".oga" => "audio/ogg",
        ".m4a" => "audio/mp4",
        ".aac" => "audio/aac",
        ".flac" => "audio/flac",
        ".weba" => "audio/webm",
        ".opus" => "audio/opus",

        # Video
        ".mp4" => "video/mp4",
        ".m4v" => "video/mp4",
        ".mov" => "video/quicktime",
        ".avi" => "video/x-msvideo",
        ".mkv" => "video/x-matroska",
        ".webm" => "video/webm",
        ".ogv" => "video/ogg",
        ".mpeg" => "video/mpeg",
        ".3gp" => "video/3gpp",

        # Compressed files
        ".zip" => "application/zip",
        ".gz" => "application/gzip",
        ".tgz" => "application/gzip",
        ".tar" => "application/x-tar",
        ".bz2" => "application/x-bzip2",
        ".7z" => "application/x-7z-compressed",
        ".rar" => "application/vnd.rar",

        # Email and signatures
        ".eml" => "message/rfc822",
        ".msg" => "application/vnd.ms-outlook",
        ".p7s" => "application/pkcs7-signature",
        ".p7m" => "application/pkcs7-mime",
        ".xades" => "application/xml",

        # Fonts
        ".ttf" => "font/ttf",
        ".otf" => "font/otf",
        ".woff" => "font/woff",
        ".woff2" => "font/woff2",

        # Binaries
        ".bin" => "application/octet-stream",
        ".exe" => "application/octet-stream"
    }
    @default_content_type "application/octet-stream"


    ################
    ### Functions
    ################

    @doc"""
    Returns the MIME type of a file from its extension. The extension is compared in lowercase.

    ### Parameter:

        - path: String. File path or object name (e.g. `documents/report.PDF`).

    ### Return:

        - String. MIME type, or `application/octet-stream` if the extension is not listed.

    ### Examples:

        iex> Connection.Gcs.ContentType.from_path("documents/report.pdf")
        "application/pdf"

        iex> Connection.Gcs.ContentType.from_path("data/rows.JSONL")
        "application/jsonl"

        iex> Connection.Gcs.ContentType.from_path("file.unknown")
        "application/octet-stream"

    """
    def from_path(path) when is_binary(path) do
        extension = path |> Path.extname() |> String.downcase()
        Map.get(@content_types, extension, @default_content_type)
    end

    @doc"""
    Returns the full map of supported extensions and their MIME types.

    ### Return:

        - Map. `%{".pdf" => "application/pdf", ...}`

    """
    def all(), do:
        @content_types

    @doc"""
    Returns the MIME type used for extensions not listed.

    ### Return:

        - String. `application/octet-stream`

    """
    def default(), do:
        @default_content_type

end
