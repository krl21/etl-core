defmodule DataModel.Schema.IntrospectorTest do
    use ExUnit.Case, async: true

    alias DataModel.Schema.Introspector
    alias Struct.InfoAttr

    defmodule FakeEntity do
        @moduledoc false

        def attr_list do
            [
                %InfoAttr{id: :nombre, id_payload: "nombre", type: :string, description: "Nombre"},
                %InfoAttr{id: :rut, id_payload: "rut", type: :string, constraint: :required},
                %InfoAttr{id: :email, id_payload: "email", type: :string, description: "Email", constraint: :required}
            ]
        end

        def bigquery_config, do: %{table: "dataset.fake_entity"}
        def business_key, do: :fake_entity
    end

    defmodule InconsistentEntity do
        @moduledoc false

        def attr_list do
            [
                %InfoAttr{id: :x, type: :string},
                %InfoAttr{id: :x, type: :integer}
            ]
        end
    end

    describe "to_bigquery_column/1" do
        test "a :nullable attribute resolves to mode NULLABLE and the plain description" do
            attr = %InfoAttr{id: :x, type: :string, description: "desc"}

            assert Introspector.to_bigquery_column(attr) == %{
                name: "x",
                type: "STRING",
                mode: "NULLABLE",
                description: "desc"
            }
        end

        test "a :required attribute resolves to mode REQUIRED" do
            attr = %InfoAttr{id: :x, type: :integer, constraint: :required}

            assert %{mode: "REQUIRED"} = Introspector.to_bigquery_column(attr)
        end
    end

    describe "desired_schema/1" do
        test "maps every attribute from attr_list/0, always honouring :required" do
            schema = Introspector.desired_schema(FakeEntity)

            assert schema == [
                %{name: "nombre", type: "STRING", mode: "NULLABLE", description: "Nombre"},
                %{name: "rut", type: "STRING", mode: "REQUIRED", description: nil},
                %{name: "email", type: "STRING", mode: "REQUIRED", description: "Email"}
            ]
        end

        test "raises when two attributes share the same name with inconsistent definitions" do
            assert_raise ArgumentError, ~r/Atributos inconsistentes/, fn ->
                Introspector.desired_schema(InconsistentEntity)
            end
        end
    end

    describe "table_id/1 and business_key/1" do
        test "delegate to Cleaning.CleanableTable's own callbacks" do
            assert Introspector.table_id(FakeEntity) == "dataset.fake_entity"
            assert Introspector.business_key(FakeEntity) == :fake_entity
        end
    end
end
