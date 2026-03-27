
defmodule DataModel.Attribute.Macro do
    @moduledoc """
    Macros for defining attribute lists in sub-entities.

    Generates getter functions for each defined attribute automatically.

    ## Usage

    This module is automatically imported when using `DataModel.Attribute.Provider`.

    ```elixir
    defmodule MyApp.Record.Buyer do
        use DataModel.Attribute.Provider

        @name %Struct.InfoAttr{id: :nombre, type: :string}
        @rut %Struct.InfoAttr{id: :rut, type: :string}

        attr_list [
            @name,
            @rut
        ]
    end
    ```

    This generates:
    - `attr_list/0` - Returns the list of attributes
    - `name/0` - Returns the `@name` attribute
    - `rut/0` - Returns the `@rut` attribute
    """

    @doc """
    Macro to define the list of attributes that the entity will return.

    ### Parameters:
        - `attributes`: List of module attributes (e.g., `[@name, @rut]`)

    ### Example:
        attr_list [
            @name,
            @rut
        ]

    This will generate:
        - `attr_list/0` - Returns the list of attributes
        - `name/0` - Returns the `@name` attribute
        - `rut/0` - Returns the `@rut` attribute
    """
    defmacro attr_list(attributes) do
        getter_functions = generate_getter_functions(attributes)

        quote do
            @attr_list unquote(attributes)

            @doc """
            Returns the list of attributes/columns

            ### Return:
                - List of Struct.InfoAttr
            """
            def attr_list(), do: @attr_list

            unquote_splicing(getter_functions)
        end
    end

    # ============================================
    # PRIVATE HELPER FUNCTIONS
    # ============================================

    #
    # Generates getter functions for each attribute in the list.
    #
    # ### Parameters:
    #     - `attributes`: AST representation of the attributes list
    #
    # ### Return:
    #     - List of AST nodes representing the generated getter functions
    #
    @doc false
    defp generate_getter_functions(attributes) do
        case attributes do
            {:__block__, _, list} when is_list(list) ->
                process_attribute_list(list)

            list when is_list(list) ->
                process_attribute_list(list)

            _ ->
                []
        end
    end

    #
    # Processes a list of module attributes and generates getter functions for each one.
    #
    # ### Parameters:
    #     - `list`: List of AST nodes representing module attributes
    #
    # ### Return:
    #     - List of AST nodes representing the generated getter functions
    #
    @doc false
    defp process_attribute_list(list) do
        list
        |> Enum.filter(fn
            {:@, _, [{name, _, _}]} when is_atom(name) -> true
            _ -> false
        end)
        |> Enum.map(fn
            {:@, _, [{name, _, _}]} ->
                function_name = name
                attr_ast = {:@, [], [{name, [], nil}]}

                quote do
                    @doc """
                    Returns the `#{unquote(function_name)}` attribute.

                    ### Return:
                        - Struct.InfoAttr
                    """
                    def unquote(function_name)() do
                        unquote(attr_ast)
                    end
                end

            _ ->
                nil
        end)
        |> Enum.filter(&(!is_nil(&1)))
    end


end
