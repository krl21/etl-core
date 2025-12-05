
defmodule Entity.RecordBase do
    @moduledoc """
    Base module for main entities (Records) that process and store data.
    """

    @doc """
    Callback invoked when `use Entity.RecordBase` is called.

    Sets up the module with the necessary behaviour, aliases, and imports.
    Also registers a `@before_compile` hook to validate configuration.
    """
    defmacro __using__(_opts) do
        quote do
            @behaviour Entity.Behaviour

            alias Struct.InfoAttr
            alias Common.Payload
            alias Connection.Odbc
            alias Statement.Sql
            alias Timex

            import Entity.RecordBase.Macro
            import unquote(__MODULE__)

            @before_compile unquote(__MODULE__)
        end
    end

    @doc """
    Callback invoked before the module is compiled.

    Validates that `entity_config/1` has been called with the required options.
    Raises an error if the configuration is missing.
    """
    defmacro __before_compile__(_env) do
        quote do
            # Validate that required configurations have been defined
            unless Module.has_attribute?(__MODULE__, :entity_config) do
                raise "Entity.RecordBase requires entity_config/1 to be called with app, table_key, batch_size_key, and unique_id"
            end
        end
    end



end
