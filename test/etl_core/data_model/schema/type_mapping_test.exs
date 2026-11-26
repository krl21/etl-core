defmodule DataModel.Schema.TypeMappingTest do
    use ExUnit.Case, async: true

    alias DataModel.Schema.TypeMapping

    describe "resolve/1" do
        test "resolves every type with an unambiguous BigQuery equivalent" do
            assert TypeMapping.resolve(:string) == "STRING"
            assert TypeMapping.resolve(:integer) == "INT64"
            assert TypeMapping.resolve(:float) == "FLOAT64"
            assert TypeMapping.resolve(:boolean) == "BOOL"
            assert TypeMapping.resolve(:timestamp) == "TIMESTAMP"
            assert TypeMapping.resolve(:date) == "DATE"
            assert TypeMapping.resolve(:datetime) == "DATETIME"
            assert TypeMapping.resolve(:decimal) == "NUMERIC"
        end

        test "resolves the manually-defined entries for :map and :list" do
            assert TypeMapping.resolve(:map) == "JSON"
            assert TypeMapping.resolve(:list) == "STRING"
        end

        test "raises a clear, actionable error for a type with no entry" do
            assert_raise ArgumentError, ~r/No hay mapeo BigQuery para el tipo :unknown_type/, fn ->
                TypeMapping.resolve(:unknown_type)
            end
        end
    end
end
