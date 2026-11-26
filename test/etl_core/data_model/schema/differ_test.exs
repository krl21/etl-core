defmodule DataModel.Schema.DifferTest do
    use ExUnit.Case, async: true

    alias DataModel.Schema.Differ

    @column_a %{name: "a", type: "STRING", mode: "NULLABLE", description: nil}
    @column_b %{name: "b", type: "INT64", mode: "NULLABLE", description: "b column"}

    test "an empty previous schema produces a single create_table operation" do
        assert Differ.diff([], [@column_a, @column_b]) == [
            %{op: :create_table, columns: [@column_a, @column_b]}
        ]
    end

    test "identical schemas produce no operations" do
        assert Differ.diff([@column_a, @column_b], [@column_a, @column_b]) == []
    end

    test "a new column produces add_column" do
        assert Differ.diff([@column_a], [@column_a, @column_b]) == [
            %{op: :add_column, column: @column_b}
        ]
    end

    test "a removed column produces drop_column" do
        assert Differ.diff([@column_a, @column_b], [@column_a]) == [
            %{op: :drop_column, name: "b"}
        ]
    end

    test "a changed type produces alter_column_type" do
        changed = %{@column_a | type: "INT64"}

        assert Differ.diff([@column_a], [changed]) == [
            %{op: :alter_column_type, name: "a", type: "INT64"}
        ]
    end

    test "a changed mode produces alter_column_mode" do
        changed = %{@column_a | mode: "REQUIRED"}

        assert Differ.diff([@column_a], [changed]) == [
            %{op: :alter_column_mode, name: "a", mode: "REQUIRED"}
        ]
    end

    test "a changed description produces alter_column_description" do
        changed = %{@column_a | description: "new description"}

        assert Differ.diff([@column_a], [changed]) == [
            %{op: :alter_column_description, name: "a", description: "new description"}
        ]
    end

    test "drops, alters and adds are ordered drop -> alter -> add" do
        previous = [@column_a, @column_b]
        desired = [%{@column_a | mode: "REQUIRED"}, %{name: "c", type: "BOOL", mode: "NULLABLE", description: nil}]

        assert Differ.diff(previous, desired) == [
            %{op: :drop_column, name: "b"},
            %{op: :alter_column_mode, name: "a", mode: "REQUIRED"},
            %{op: :add_column, column: %{name: "c", type: "BOOL", mode: "NULLABLE", description: nil}}
        ]
    end

    test "a column with several changed attributes produces one operation per attribute" do
        changed = %{@column_a | type: "INT64", mode: "REQUIRED", description: "now required"}

        assert Differ.diff([@column_a], [changed]) == [
            %{op: :alter_column_type, name: "a", type: "INT64"},
            %{op: :alter_column_mode, name: "a", mode: "REQUIRED"},
            %{op: :alter_column_description, name: "a", description: "now required"}
        ]
    end
end
