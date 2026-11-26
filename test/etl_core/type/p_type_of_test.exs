defmodule Type.PTypeOfTest do
    use ExUnit.Case, async: true

    alias Type.PTypeOf

    test "dispatches to the right type atom for every supported kind of value" do
        assert PTypeOf.type_of(1) == :integer
        assert PTypeOf.type_of(1.5) == :float
        assert PTypeOf.type_of("string") == :binary
        assert PTypeOf.type_of([1, 2]) == :list
        assert PTypeOf.type_of(%{a: 1}) == :map
        assert PTypeOf.type_of({:a, :b}) == :tuple
        assert PTypeOf.type_of(self()) == :pid
        assert PTypeOf.type_of(make_ref()) == :reference
        assert PTypeOf.type_of(fn -> :ok end) == :function
    end

    test "nil is its own type, distinct from other atoms" do
        assert PTypeOf.type_of(nil) == :nil
        assert PTypeOf.type_of(:some_atom) == :atom
    end

    test "DateTime and NaiveDateTime are both :timestamp, Date is :date" do
        assert PTypeOf.type_of(DateTime.utc_now()) == :timestamp
        assert PTypeOf.type_of(NaiveDateTime.utc_now()) == :timestamp
        assert PTypeOf.type_of(Date.utc_today()) == :date
    end
end
