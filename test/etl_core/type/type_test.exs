defmodule Type.TypeTest do
    use ExUnit.Case, async: true

    alias Type.Type

    describe "convert/2" do
        test "integer -> float" do
            assert Type.convert(2, :float) == 2.0
        end

        test "string -> integer" do
            assert Type.convert("2", :integer) == 2
        end

        test "string -> string is a no-op" do
            assert Type.convert("chain", :string) == "chain"
        end

        test "float -> integer truncates" do
            assert Type.convert(2.9, :integer) == 2
        end

        test "atom -> string" do
            assert Type.convert(:hello, :string) == "hello"
        end

        test "nil passes through regardless of target type" do
            assert Type.convert(nil, :integer) == nil
            assert Type.convert(nil, :string) == nil
        end

        test "a non-JSON string requested as :map raises (goes through Poison.decode!/1)" do
            assert_raise Poison.ParseError, fn -> Type.convert("chain", :map) end
        end

        test "-1 is special-cased to nil for :datetime/:timestamp" do
            assert Type.convert(-1, :datetime) == nil
            assert Type.convert(-1, :timestamp) == nil
        end

        test "integer millisecond epoch -> datetime" do
            assert %DateTime{} = Type.convert(1668036600542, :timestamp)
        end
    end

    describe "convert_for_bigquery/1" do
        test "escapes backslashes, quotes and control characters in strings" do
            assert Type.convert_for_bigquery("it's") == "'it\\'s'"
            assert Type.convert_for_bigquery("a\\b") == "'a\\\\b'"
            assert Type.convert_for_bigquery("a\nb") == "'a\\nb'"
        end

        test "nil becomes the literal NULL" do
            assert Type.convert_for_bigquery(nil) == "NULL"
        end

        test "a DateTime becomes a TIMESTAMP(...) literal" do
            {:ok, dt, _offset} = DateTime.from_iso8601("2024-01-01T10:00:00Z")
            assert Type.convert_for_bigquery(dt) == "TIMESTAMP('#{to_string(dt)}')"
        end

        test "a Date becomes a DATE(...) literal" do
            date = ~D[2024-01-01]
            assert Type.convert_for_bigquery(date) == "DATE('#{to_string(date)}')"
        end

        test "a plain map falls back to an escaped, quoted JSON literal" do
            encoded = Poison.encode!(%{a: 1})
            assert Type.convert_for_bigquery(%{a: 1}) == "JSON '#{encoded}'"
        end

        test "any other value falls back to Type.convert(x, :string) verbatim (not quoted)" do
            assert Type.convert_for_bigquery(42) == "42"
        end
    end

    describe "convert_from_bigquery/1" do
        test "is currently a passthrough for binaries" do
            assert Type.convert_from_bigquery("hello") == "hello"
        end
    end
end
