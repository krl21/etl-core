defmodule StuffTest do
    use ExUnit.Case, async: true

    describe "integer_to_string_with_2_digits/1" do
        test "pads single digits (1-9) with a leading zero" do
            assert Stuff.integer_to_string_with_2_digits(1) == "01"
            assert Stuff.integer_to_string_with_2_digits(9) == "09"
        end

        test "does not pad 0 or two-digit-and-above numbers" do
            assert Stuff.integer_to_string_with_2_digits(0) == "0"
            assert Stuff.integer_to_string_with_2_digits(10) == "10"
            assert Stuff.integer_to_string_with_2_digits(123) == "123"
        end
    end

    describe "convert_seconds_to_humans/1" do
        test "formats as \"XhYmZs\"" do
            assert Stuff.convert_seconds_to_humans(0) == "0h 0m 0s"
            assert Stuff.convert_seconds_to_humans(59) == "0h 0m 59s"
            assert Stuff.convert_seconds_to_humans(61) == "0h 1m 1s"
            assert Stuff.convert_seconds_to_humans(3661) == "1h 1m 1s"
        end

        test "handles multiple days worth of seconds" do
            assert Stuff.convert_seconds_to_humans(90_000) == "25h 0m 0s"
        end
    end

    describe "list_subtraction/2" do
        test "removes pairs present with the same value in both lists" do
            assert Stuff.list_subtraction([{:a, 1}, {:b, 2}], [{:a, 1}]) == [{:b, 2}]
        end

        test "keeps a key whose value differs between the two lists" do
            assert Stuff.list_subtraction([{:a, 1}], [{:a, 2}]) == [{:a, 1}]
        end

        test "list/map values are compared after sorting, so order doesn't matter" do
            assert Stuff.list_subtraction([{:a, [2, 1]}], [{:a, [1, 2]}]) == []
            assert Stuff.list_subtraction([{:a, [1, 2]}], [{:a, [1, 3]}]) == [{:a, [1, 2]}]
        end

        test "a key only in the second list is dropped, not added" do
            assert Stuff.list_subtraction([{:a, 1}], [{:b, 2}]) == [{:a, 1}]
        end

        test "an empty second list leaves the first untouched" do
            assert Stuff.list_subtraction([{:a, 1}], []) == [{:a, 1}]
        end

        test "an empty first list always yields an empty result" do
            assert Stuff.list_subtraction([], [{:a, 1}]) == []
        end
    end

    describe "get_firsts/2" do
        test "splits the list after n elements" do
            assert Stuff.get_firsts([1, 2, 3], 2) == {[1, 2], [3]}
        end

        test "n == 0 returns everything in the remainder" do
            assert Stuff.get_firsts([1, 2], 0) == {[], [1, 2]}
        end

        test "n greater than the list length returns the whole list with an empty remainder" do
            assert Stuff.get_firsts([1, 2], 5) == {[1, 2], []}
        end

        test "an empty list always yields {[], []}" do
            assert Stuff.get_firsts([], 3) == {[], []}
        end
    end

    describe "random_string_generate/1" do
        test "generates a string of the requested length, from the expected alphabet" do
            result = Stuff.random_string_generate(12)
            assert String.length(result) == 12
            assert result =~ ~r/^[0-9a-z]+$/
        end

        test "requires a strictly positive length" do
            assert_raise FunctionClauseError, fn -> Stuff.random_string_generate(0) end
        end
    end
end
