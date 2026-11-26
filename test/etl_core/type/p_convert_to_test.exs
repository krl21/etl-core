defmodule Type.PConvertToTest do
    use ExUnit.Case, async: true

    alias Type.PConvertTo, as: A

    describe "Atom" do
        test "atom -> atom, string, and the nil short-circuit" do
            assert A.convert_to(:x, :atom) == :x
            assert A.convert_to(:x, :string) == "x"
            assert A.convert_to(nil, :anything) == nil
        end

        test "atom -> boolean only accepts :true/:false" do
            assert A.convert_to(:true, :boolean) == true
            assert A.convert_to(:false, :boolean) == false
            assert_raise RuntimeError, fn -> A.convert_to(:maybe, :boolean) end
        end
    end

    describe "Integer" do
        test "integer -> integer/float/string" do
            assert A.convert_to(5, :integer) == 5
            assert A.convert_to(5, :float) == 5.0
            assert A.convert_to(5, :string) == "5"
        end

        test "-1 -> nil for :datetime/:timestamp, any other integer -> DateTime" do
            assert A.convert_to(-1, :datetime) == nil
            assert A.convert_to(-1, :timestamp) == nil
            assert %DateTime{} = A.convert_to(0, :timestamp)
        end
    end

    describe "Float" do
        test "float -> float/integer(truncated)/string" do
            assert A.convert_to(5.9, :float) == 5.9
            assert A.convert_to(5.9, :integer) == 5
            assert A.convert_to(5.5, :string) == "5.5"
        end
    end

    describe "BitString (what real Elixir strings/binaries actually dispatch to)" do
        test "string -> binary/bitstring/string are all identity" do
            assert A.convert_to("x", :binary) == "x"
            assert A.convert_to("x", :bitstring) == "x"
            assert A.convert_to("x", :string) == "x"
        end

        test "string -> integer: parses, strips spaces/dots, nil on failure" do
            assert A.convert_to("123", :integer) == 123
            assert A.convert_to("1.234", :integer) == 1234
            assert A.convert_to("12 34", :integer) == 1234
            assert A.convert_to("abc", :integer) == nil
        end

        test "\"0\" -> float is specifically 0.0" do
            assert A.convert_to("0", :float) == 0.0
        end

        test "string -> float handles a trailing .0 and a comma decimal separator" do
            assert A.convert_to("5.0", :float) == 5.0
            assert A.convert_to("5,5", :float) == 5.5
        end

        test "string -> list/map decodes JSON, empty string is nil" do
            assert A.convert_to("", :map) == nil
            assert A.convert_to("", :list) == nil
            assert A.convert_to(~s({"a":1}), :map) == %{"a" => 1}
            assert A.convert_to("[1,2]", :list) == [1, 2]
        end

        test "string -> date/time parses ISO8601, raises on bad input" do
            assert A.convert_to("2024-01-01", :date) == ~D[2024-01-01]
            assert A.convert_to("10:30:00", :time) == ~T[10:30:00]
            assert_raise RuntimeError, fn -> A.convert_to("not-a-date", :date) end
        end

        test "\"\"/\"'\"/\"0\" are nil for :datetime, everything else parses" do
            assert A.convert_to("", :datetime) == nil
            assert A.convert_to("'", :datetime) == nil
            assert A.convert_to("0", :datetime) == nil
            assert A.convert_to("2024-01-01T10:00:00Z", :datetime) != nil
        end

        test "string -> boolean/atom" do
            assert A.convert_to("true", :boolean) == true
            assert A.convert_to("x", :atom) == :x
        end
    end

    describe "List" do
        test "list -> list is identity, list -> string joins chars" do
            assert A.convert_to([1, 2], :list) == [1, 2]
            assert A.convert_to(~c"abc", :string) == "abc"
        end
    end

    describe "Map" do
        test "map -> map is identity, map -> string encodes JSON" do
            assert A.convert_to(%{a: 1}, :map) == %{a: 1}
            assert A.convert_to(%{a: 1}, :string) == Poison.encode!(%{a: 1})
        end
    end

    describe "DateTime" do
        test "datetime -> datetime/timestamp is identity, -> date truncates" do
            dt = DateTime.utc_now()
            assert A.convert_to(dt, :datetime) == dt
            assert A.convert_to(dt, :timestamp) == dt
            assert A.convert_to(dt, :date) == DateTime.to_date(dt)
        end
    end

    describe "Date" do
        test "date -> date is identity, nil stays nil" do
            date = ~D[2024-01-01]
            assert A.convert_to(date, :date) == date
            assert A.convert_to(nil, :date) == nil
        end
    end
end
