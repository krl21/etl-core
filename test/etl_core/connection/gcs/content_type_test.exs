defmodule Connection.Gcs.ContentTypeTest do
    use ExUnit.Case, async: true

    alias Connection.Gcs.ContentType

    test "every extension in all/0 resolves to itself via from_path/1" do
        for {ext, mime} <- ContentType.all() do
            assert ContentType.from_path("file#{ext}") == mime
            assert ContentType.from_path("file#{String.upcase(ext)}") == mime
        end
    end

    test "an unknown extension falls back to the default content type" do
        assert ContentType.from_path("file.unknown-extension") == ContentType.default()
    end

    test "a path with no extension also falls back to the default" do
        assert ContentType.from_path("README") == ContentType.default()
    end

    test "matching is based only on the extension, not the full path" do
        assert ContentType.from_path("documents/nested/report.pdf") == "application/pdf"
    end
end
