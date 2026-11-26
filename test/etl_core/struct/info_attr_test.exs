defmodule Struct.InfoAttrTest do
    use ExUnit.Case, async: true

    alias Struct.InfoAttr

    test "defaults: nullable, with the expected default field values" do
        attr = %InfoAttr{}

        assert attr.id == ""
        assert attr.id_payload == ""
        assert attr.type == nil
        assert attr.keys_to_search == []
        assert attr.default_value == nil
        assert attr.description == nil
        assert attr.constraint == :nullable
    end

    test "String.Chars renders every field, including the new ones" do
        attr = %InfoAttr{id: :rut, id_payload: "rut", type: :string, description: "RUT", constraint: :required}

        rendered = to_string(attr)

        assert rendered =~ "id: rut"
        assert rendered =~ "id_payload: rut"
        assert rendered =~ "type: string"
        assert rendered =~ "description: \"RUT\""
        assert rendered =~ "constraint: required"
    end
end
