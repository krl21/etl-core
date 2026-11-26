defmodule Common.PayloadTest do
    use ExUnit.Case, async: true

    alias Common.Payload
    alias Struct.InfoAttr

    describe "extract_data/4" do
        test "a nil payload returns the default value immediately" do
            assert Payload.extract_data(nil, "x", [], :default) == :default
        end

        test "with no path, reads the tag directly off the payload" do
            assert Payload.extract_data(%{"x" => 1}, "x") == 1
            assert Payload.extract_data(%{}, "x", [], :missing) == :missing
        end

        test "descends through each key in the path before reading the tag" do
            payload = %{"data" => %{"nested" => %{"x" => 42}}}
            assert Payload.extract_data(payload, "x", ["data", "nested"]) == 42
        end

        test "a missing intermediate key yields the default, not an error" do
            payload = %{"data" => %{}}
            assert Payload.extract_data(payload, "x", ["data", "missing"], :default) == :default
        end
    end

    describe "extract_with_format/3" do
        test "extracts and type-converts each attribute, keyed by id" do
            attrs = [
                %InfoAttr{id: :name, id_payload: "name", type: :string},
                %InfoAttr{id: :age, id_payload: "age", type: :integer}
            ]

            payload = %{"name" => "Carlos", "age" => "30"}

            assert Payload.extract_with_format(payload, attrs) == [name: "Carlos", age: 30]
        end

        test "filters out nil values by default, but keeps them when asked not to" do
            attrs = [%InfoAttr{id: :missing, id_payload: "missing", type: :string}]

            assert Payload.extract_with_format(%{}, attrs) == []
            assert Payload.extract_with_format(%{}, attrs, false) == [missing: nil]
        end

        test "a conversion error is re-raised with the field and attribute in the message" do
            attrs = [%InfoAttr{id: :bad, id_payload: "bad", type: :map}]
            payload = %{"bad" => "not-json"}

            assert_raise RuntimeError, ~r/Field: `bad`/, fn ->
                Payload.extract_with_format(payload, attrs)
            end
        end
    end

    describe "reduce_by/2" do
        test "groups payloads sharing the same value in the given field" do
            fields = [%InfoAttr{id: :tipo, id_payload: "tipo", keys_to_search: []}]
            payloads = [%{"tipo" => "a"}, %{"tipo" => "a"}, %{"tipo" => "b"}]

            {grouped, keys} = Payload.reduce_by(payloads, fields)

            assert Enum.sort(keys) == ["a", "b"]
            assert grouped["a"] == [%{"tipo" => "a"}, %{"tipo" => "a"}]
            assert grouped["b"] == [%{"tipo" => "b"}]
        end

        test "multiple fields are joined with a double underscore" do
            fields = [
                %InfoAttr{id: :a, id_payload: "a", keys_to_search: []},
                %InfoAttr{id: :b, id_payload: "b", keys_to_search: []}
            ]

            {grouped, keys} = Payload.reduce_by([%{"a" => "x", "b" => "y"}], fields)

            assert keys == ["x__y"]
            assert Map.has_key?(grouped, "x__y")
        end

        test "an empty list produces an empty map and no keys" do
            assert Payload.reduce_by([], []) == {%{}, []}
        end
    end
end
