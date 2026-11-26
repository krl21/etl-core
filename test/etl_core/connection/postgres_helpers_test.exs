defmodule Connection.PostgresHelpersTest do
    use ExUnit.Case, async: true

    alias Connection.PostgresHelpers, as: H

    describe "sanitize_identifier/1" do
        test "lowercases and passes through already-safe identifiers" do
            assert H.sanitize_identifier("My_Table1") == "my_table1"
        end

        test "accepts atoms" do
            assert H.sanitize_identifier(:my_table) == "my_table"
        end

        test "strips SQL-injection-style characters instead of rejecting them" do
            assert H.sanitize_identifier("table; DROP TABLE users;--") == "tabledroptableusers"
        end

        test "a name that is only special characters raises" do
            assert_raise ArgumentError, fn -> H.sanitize_identifier("!!!") end
        end

        test "nil raises a clear, specific error" do
            assert_raise ArgumentError, ~r/environment variable may not be set/, fn ->
                H.sanitize_identifier(nil)
            end
        end
    end

    describe "atomize_keys/1" do
        test "converts string keys to atoms, leaves atom keys untouched" do
            assert H.atomize_keys(%{"a" => 1, :b => 2}) == %{a: 1, b: 2}
        end
    end

    describe "escape_sql_string/1" do
        test "doubles single quotes" do
            assert H.escape_sql_string("O'Brien") == "O''Brien"
        end
    end

    describe "build_placeholders/2" do
        test "defaults to starting at $1" do
            assert H.build_placeholders(3) == "$1, $2, $3"
        end

        test "accepts a custom starting index" do
            assert H.build_placeholders(2, 5) == "$5, $6"
        end
    end

    describe "to_json/1" do
        test "a binary passes through unchanged" do
            assert H.to_json("already json") == "already json"
        end

        test "anything else is JSON-encoded" do
            assert H.to_json(%{a: 1}) == Poison.encode!(%{a: 1})
        end
    end

    describe "build_connection_opts/2" do
        test "applies defaults for port/ssl/pool_size and required fields from config" do
            config = %{database: "db", username: "u", password: "p"}

            assert H.build_connection_opts(config, "myhost") == [
                hostname: "myhost",
                port: 5432,
                database: "db",
                username: "u",
                password: "p",
                ssl: false,
                pool_size: 5
            ]
        end

        test "config overrides the defaults" do
            config = %{database: "db", username: "u", password: "p", port: 1234, ssl: true, pool_size: 10}

            opts = H.build_connection_opts(config, "myhost")
            assert Keyword.get(opts, :port) == 1234
            assert Keyword.get(opts, :ssl) == true
            assert Keyword.get(opts, :pool_size) == 10
        end

        test "raises if a required field is missing" do
            assert_raise KeyError, fn -> H.build_connection_opts(%{}, "myhost") end
        end
    end

    describe "parse_query_result/1" do
        test "zips columns with each row and atomizes the keys" do
            result = %{columns: ["id", "name"], rows: [[1, "a"], [2, "b"]]}

            assert H.parse_query_result(result) == [%{id: 1, name: "a"}, %{id: 2, name: "b"}]
        end
    end

    describe "default_column_comments/0" do
        test "covers every column of the generic buffer table" do
            comments = H.default_column_comments()
            assert Map.keys(comments) |> Enum.sort() == [
                :estado_analisis, :fecha_creado, :id, :id_nodo, :informacion, :tipo
            ]
        end
    end

    describe "pending_bq_query/4" do
        test "no type, no limit: a plain WHERE on estado_analisis" do
            {query, params} = H.pending_bq_query("t", nil, "sin_analizar", [])
            assert params == []
            assert query =~ "WHERE estado_analisis = 'sin_analizar'"
            refute query =~ "tipo ="
        end

        test "type only: filters by tipo as a bound parameter" do
            {query, params} = H.pending_bq_query("t", "expediente", "sin_analizar", [])
            assert params == ["expediente"]
            assert query =~ "WHERE tipo = $1 AND estado_analisis = 'sin_analizar'"
        end

        test "limit only: adds a LIMIT-bound subquery" do
            {query, params} = H.pending_bq_query("t", nil, "sin_analizar", limit: 50)
            assert params == [50]
            assert query =~ "LIMIT $1"
        end

        test "type and limit together: both parameters, in order" do
            {query, params} = H.pending_bq_query("t", "expediente", "sin_analizar", limit: 50)
            assert params == ["expediente", 50]
            assert query =~ "LIMIT $2"
        end
    end
end
