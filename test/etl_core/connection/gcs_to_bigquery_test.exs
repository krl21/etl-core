defmodule Connection.GcsToBigQueryTest do
    use ExUnit.Case, async: true

    alias Connection.GcsToBigQuery, as: GcsToBq

    describe "build_load_statement/4" do
        test "defaults to append mode, no column list, wrapped in BEGIN/END" do
            statement = GcsToBq.build_load_statement("dataset.table", "gs://bucket/object.json", [], format: :ndjson)

            assert statement == "BEGIN LOAD DATA INTO `dataset.table` FROM FILES (format = 'NEWLINE_DELIMITED_JSON', " <>
                "uris = ['gs://bucket/object.json']); END;"
        end

        test "accepts a plain string or a list of URIs" do
            single = GcsToBq.build_load_statement("dataset.table", "gs://b/a.json", [], format: :ndjson)
            list = GcsToBq.build_load_statement("dataset.table", ["gs://b/a.json"], [], format: :ndjson)

            assert single == list
        end

        test "multiple URIs are comma-joined, each quoted" do
            statement = GcsToBq.build_load_statement("dataset.table", ["gs://b/a.json", "gs://b/b.json"], [], format: :ndjson)
            assert statement =~ "uris = ['gs://b/a.json', 'gs://b/b.json']"
        end

        test "mode: :overwrite renders OVERWRITE instead of INTO" do
            statement = GcsToBq.build_load_statement("dataset.table", "gs://b/a.json", [], format: :ndjson, mode: :overwrite)
            assert statement =~ "LOAD DATA OVERWRITE `dataset.table`"
        end

        test "an explicit column list is rendered as `name TYPE, ...`" do
            statement = GcsToBq.build_load_statement("dataset.table", "gs://b/a.json", [{"id", "STRING"}, {"n", "INT64"}], format: :ndjson)
            assert statement =~ "`dataset.table` (`id` STRING, `n` INT64) FROM FILES"
        end

        test "skip_leading_rows only applies to the csv format, and only when positive" do
            csv = GcsToBq.build_load_statement("dataset.table", "gs://b/a.csv", [], format: :csv, skip_leading_rows: 1)
            assert csv =~ "skip_leading_rows = 1"

            csv_zero = GcsToBq.build_load_statement("dataset.table", "gs://b/a.csv", [], format: :csv, skip_leading_rows: 0)
            refute csv_zero =~ "skip_leading_rows"

            ndjson = GcsToBq.build_load_statement("dataset.table", "gs://b/a.json", [], format: :ndjson, skip_leading_rows: 1)
            refute ndjson =~ "skip_leading_rows"
        end

        test "every documented format resolves to its BigQuery name" do
            for {format, bq_name} <- [csv: "CSV", ndjson: "NEWLINE_DELIMITED_JSON", jsonl: "NEWLINE_DELIMITED_JSON", parquet: "PARQUET", avro: "AVRO", orc: "ORC"] do
                statement = GcsToBq.build_load_statement("dataset.table", "gs://b/a", [], format: format)
                assert statement =~ "format = '#{bq_name}'"
            end
        end

        test "an invalid table name raises, before anything else" do
            assert_raise ArgumentError, ~r/Nombre de tabla inválido/, fn ->
                GcsToBq.build_load_statement("not a table", "gs://b/a.json", [], format: :ndjson)
            end
        end

        test "an invalid URI raises" do
            assert_raise ArgumentError, ~r/URI de GCS inválida/, fn ->
                GcsToBq.build_load_statement("dataset.table", "not-a-uri", [], format: :ndjson)
            end
        end

        test "an unsupported format raises" do
            assert_raise ArgumentError, ~r/Formato no soportado/, fn ->
                GcsToBq.build_load_statement("dataset.table", "gs://b/a.json", [], format: :xlsx)
            end
        end

        test "an unsupported mode raises" do
            assert_raise ArgumentError, ~r/Modo no soportado/, fn ->
                GcsToBq.build_load_statement("dataset.table", "gs://b/a.json", [], format: :ndjson, mode: :upsert)
            end
        end

        test "missing :format raises a KeyError" do
            assert_raise KeyError, fn ->
                GcsToBq.build_load_statement("dataset.table", "gs://b/a.json", [], [])
            end
        end
    end
end
