defmodule DataModel.Schema.DdlBuilderTest do
    use ExUnit.Case, async: true

    alias DataModel.Schema.DdlBuilder

    @table "dataset.my_table"

    test "create_table builds a CREATE TABLE IF NOT EXISTS with every column" do
        columns = [
            %{name: "id", type: "STRING", mode: "REQUIRED", description: nil},
            %{name: "nombre", type: "STRING", mode: "NULLABLE", description: "Nombre"}
        ]

        assert DdlBuilder.build(@table, [%{op: :create_table, columns: columns}]) == [
            "CREATE TABLE IF NOT EXISTS #{@table} (id STRING NOT NULL, nombre STRING OPTIONS(description=\"Nombre\"))"
        ]
    end

    test "add_column builds an ALTER TABLE ADD COLUMN" do
        column = %{name: "email", type: "STRING", mode: "NULLABLE", description: nil}

        assert DdlBuilder.build(@table, [%{op: :add_column, column: column}]) == [
            "ALTER TABLE #{@table} ADD COLUMN email STRING"
        ]
    end

    test "drop_column builds an ALTER TABLE DROP COLUMN" do
        assert DdlBuilder.build(@table, [%{op: :drop_column, name: "email"}]) == [
            "ALTER TABLE #{@table} DROP COLUMN email"
        ]
    end

    test "alter_column_type builds an ALTER TABLE ... SET DATA TYPE" do
        assert DdlBuilder.build(@table, [%{op: :alter_column_type, name: "monto", type: "FLOAT64"}]) == [
            "ALTER TABLE #{@table} ALTER COLUMN monto SET DATA TYPE FLOAT64"
        ]
    end

    test "alter_column_mode relaxing to NULLABLE builds DROP NOT NULL" do
        assert DdlBuilder.build(@table, [%{op: :alter_column_mode, name: "rut", mode: "NULLABLE"}]) == [
            "ALTER TABLE #{@table} ALTER COLUMN rut DROP NOT NULL"
        ]
    end

    test "alter_column_mode tightening to REQUIRED raises instead of emitting invalid DDL" do
        assert_raise ArgumentError, ~r/no soporta agregar NOT NULL/, fn ->
            DdlBuilder.build(@table, [%{op: :alter_column_mode, name: "rut", mode: "REQUIRED"}])
        end
    end

    test "alter_column_description builds an ALTER TABLE ... SET OPTIONS" do
        assert DdlBuilder.build(@table, [%{op: :alter_column_description, name: "rut", description: "RUT del titular"}]) == [
            "ALTER TABLE #{@table} ALTER COLUMN rut SET OPTIONS(description=\"RUT del titular\")"
        ]
    end

    test "alter_column_description with a nil description sets it to NULL" do
        assert DdlBuilder.build(@table, [%{op: :alter_column_description, name: "rut", description: nil}]) == [
            "ALTER TABLE #{@table} ALTER COLUMN rut SET OPTIONS(description=NULL)"
        ]
    end

    test "a description containing double quotes is escaped so the generated DDL stays valid" do
        # Built via concatenation (not a hand-escaped literal) so the expected
        # value is unambiguous: one backslash, one quote, "hi", one backslash, one quote.
        backslash = "\\"
        quote = "\""
        expected_escaped_hi = backslash <> quote <> "hi" <> backslash <> quote

        column = %{name: "x", type: "STRING", mode: "NULLABLE", description: ~s(say "hi")}
        [statement] = DdlBuilder.build(@table, [%{op: :add_column, column: column}])

        assert statement =~ expected_escaped_hi
    end

    test "a description containing a backslash is escaped so the generated DDL stays valid" do
        # Two literal backslashes: the escaped form of the single backslash in the description.
        expected_escaped_backslash = "\\" <> "\\"

        column = %{name: "x", type: "STRING", mode: "NULLABLE", description: "a" <> "\\" <> "b"}
        [statement] = DdlBuilder.build(@table, [%{op: :add_column, column: column}])

        assert statement =~ expected_escaped_backslash
    end

    test "a migration with several operations builds one statement per operation, in order" do
        operations = [
            %{op: :drop_column, name: "obsoleto"},
            %{op: :add_column, column: %{name: "nuevo", type: "STRING", mode: "NULLABLE", description: nil}}
        ]

        assert DdlBuilder.build(@table, operations) == [
            "ALTER TABLE #{@table} DROP COLUMN obsoleto",
            "ALTER TABLE #{@table} ADD COLUMN nuevo STRING"
        ]
    end

    describe "batching (:batch_size)" do
        test "add_column operations beyond batch_size are split into multiple statements" do
            ops = for n <- 1..5, do: %{op: :add_column, column: %{name: "c#{n}", type: "STRING", mode: "NULLABLE", description: nil}}

            assert DdlBuilder.build(@table, ops, batch_size: 2) == [
                "ALTER TABLE #{@table} ADD COLUMN c1 STRING, ADD COLUMN c2 STRING",
                "ALTER TABLE #{@table} ADD COLUMN c3 STRING, ADD COLUMN c4 STRING",
                "ALTER TABLE #{@table} ADD COLUMN c5 STRING"
            ]
        end

        test "drop_column operations beyond batch_size are split into multiple statements" do
            ops = for n <- 1..3, do: %{op: :drop_column, name: "c#{n}"}

            assert DdlBuilder.build(@table, ops, batch_size: 2) == [
                "ALTER TABLE #{@table} DROP COLUMN c1, DROP COLUMN c2",
                "ALTER TABLE #{@table} DROP COLUMN c3"
            ]
        end

        test "create_table columns beyond batch_size overflow into ADD COLUMN batches" do
            columns = for n <- 1..5, do: %{name: "c#{n}", type: "STRING", mode: "NULLABLE", description: nil}

            assert DdlBuilder.build(@table, [%{op: :create_table, columns: columns}], batch_size: 2) == [
                "CREATE TABLE IF NOT EXISTS #{@table} (c1 STRING, c2 STRING)",
                "ALTER TABLE #{@table} ADD COLUMN c3 STRING, ADD COLUMN c4 STRING",
                "ALTER TABLE #{@table} ADD COLUMN c5 STRING"
            ]
        end

        test "REQUIRED columns always go in the CREATE TABLE statement, even past batch_size" do
            columns = [
                %{name: "req1", type: "STRING", mode: "REQUIRED", description: nil},
                %{name: "req2", type: "STRING", mode: "REQUIRED", description: nil},
                %{name: "req3", type: "STRING", mode: "REQUIRED", description: nil},
                %{name: "opt1", type: "STRING", mode: "NULLABLE", description: nil}
            ]

            assert DdlBuilder.build(@table, [%{op: :create_table, columns: columns}], batch_size: 2) == [
                "CREATE TABLE IF NOT EXISTS #{@table} (req1 STRING NOT NULL, req2 STRING NOT NULL, req3 STRING NOT NULL)",
                "ALTER TABLE #{@table} ADD COLUMN opt1 STRING"
            ]
        end

        test "defaults to a batch size of 50" do
            ops = for n <- 1..51, do: %{op: :add_column, column: %{name: "c#{n}", type: "STRING", mode: "NULLABLE", description: nil}}

            assert [first, second] = DdlBuilder.build(@table, ops)
            assert first |> String.split(", ") |> length() == 50
            assert second == "ALTER TABLE #{@table} ADD COLUMN c51 STRING"
        end
    end
end
