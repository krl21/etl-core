defmodule Statement.SqlTest do
    use ExUnit.Case, async: true

    alias Statement.Sql

    describe "get_operator/1 and get_function/1" do
        test "map the documented atoms to their SQL text" do
            assert Sql.get_operator(:eq) == " = "
            assert Sql.get_operator(:neq) == " <> "
            assert Sql.get_operator(:in) == " IN "
            assert Sql.get_operator(:like) == " LIKE "
            assert Sql.get_function(:timestamp) == "TIMESTAMP"
            assert Sql.get_function(:date) == "DATE"
        end
    end

    test "generate_uuid/0 returns a SELECT GENERATE_UUID() statement" do
        assert Sql.generate_uuid() =~ "SELECT GENERATE_UUID() AS uuid;"
    end

    describe "insert/2" do
        test "builds an INSERT with matching column/value lists, in order" do
            assert Sql.insert("t", [{:a, 1}, {:b, "x"}]) == "INSERT INTO t (a, b) VALUES (1, 'x');"
        end
    end

    describe "merge_inserts/1" do
        test "combines several single-row INSERTs sharing the same prefix into one" do
            queries = [
                "INSERT INTO t (a, b) VALUES (1, 'x');",
                "INSERT INTO t (a, b) VALUES (2, 'y');"
            ]

            assert Sql.merge_inserts(queries) == "INSERT INTO t (a, b) VALUES (1, 'x'), (2, 'y');"
        end

        test "a single query round-trips unchanged" do
            query = "INSERT INTO t (a) VALUES (1);"
            assert Sql.merge_inserts([query]) == query
        end
    end

    describe "select/4" do
        test "defaults to SELECT * with no WHERE clause" do
            assert Sql.select("t") == "SELECT * FROM t ;"
        end

        test "an explicit column list is comma-joined" do
            assert Sql.select("t", [:a, :b]) == "SELECT a, b FROM t ;"
        end

        test "a single condition is wrapped in parentheses after WHERE" do
            assert Sql.select("t", :all, [[{:id, 1, :eq}]], []) == "SELECT * FROM t WHERE (id = 1);"
        end

        test "an :in condition renders the value list" do
            result = Sql.select("t", :all, [[{:status, ["a", "b"], :in}]], [])
            assert result =~ "status IN ("
            assert result =~ "'a'"
            assert result =~ "'b'"
        end

        test "multiple conditions inside one group are joined by the internal operator" do
            result = Sql.select("t", :all, [[{:a, 1, :eq}, {:b, 2, :eq}]], [:and])
            assert result == "SELECT * FROM t WHERE (a = 1 AND b = 2);"
        end

        test "multiple condition groups are joined by the external operator" do
            result = Sql.select("t", :all, [[{:a, 1, :eq}], [{:b, 2, :eq}]], [:and, :or])
            assert result == "SELECT * FROM t WHERE (a = 1) OR (b = 2);"
        end
    end

    describe "update/4" do
        test "builds a SET clause from the change list, without a WHERE by default" do
            assert Sql.update("t", [{:a, 1}]) == "UPDATE t SET a = 1 ;"
        end

        test "includes a WHERE clause when conditions are given" do
            assert Sql.update("t", [{:a, 1}], [[{:id, 7, :eq}]], []) == "UPDATE t SET a = 1 WHERE (id = 7);"
        end
    end

    describe "delete/1 and delete/2" do
        test "delete/1 truncates the whole table" do
            assert Sql.delete("t") == "TRUNCATE TABLE t;"
        end

        test "delete/2 deletes by condition" do
            assert Sql.delete("t", [[{:id, 7, :eq}]], []) == "DELETE FROM t WHERE (id = 7);"
        end
    end
end
