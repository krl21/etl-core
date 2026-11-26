defmodule DataModel.AttributeTest do
    use ExUnit.Case, async: true

    alias Struct.InfoAttr

    defmodule FixtureSubentity do
        @moduledoc false
        use DataModel.Attribute.Provider

        @nombre %InfoAttr{id: :nombre, type: :string}
        @rut %InfoAttr{id: :rut, type: :string}

        attr_list [
            @nombre,
            @rut
        ]
    end

    defmodule EmptyFixtureSubentity do
        @moduledoc false
        use DataModel.Attribute.Provider

        attr_list []
    end

    test "use DataModel.Attribute.Provider injects the DataModel.Behaviour contract" do
        assert {:module, _} = Code.ensure_compiled(FixtureSubentity)
        assert function_exported?(FixtureSubentity, :attr_list, 0)
    end

    test "attr_list/0 returns exactly the attributes passed in, in order" do
        assert FixtureSubentity.attr_list() == [
            %InfoAttr{id: :nombre, type: :string},
            %InfoAttr{id: :rut, type: :string}
        ]
    end

    test "one getter function is generated per attribute, named after its module attribute (@nombre -> nombre/0)" do
        assert FixtureSubentity.nombre() == %InfoAttr{id: :nombre, type: :string}
        assert FixtureSubentity.rut() == %InfoAttr{id: :rut, type: :string}
    end

    test "an empty attribute list is valid and yields no getters beyond attr_list/0" do
        assert EmptyFixtureSubentity.attr_list() == []
    end
end
