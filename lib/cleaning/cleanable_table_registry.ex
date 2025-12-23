
defmodule Cleaning.CleanableTableRegistry do
    @moduledoc """
    Registry for all modules implementing CleanableTable behaviour.

    Provides global access to cleaning configurations defined across the application.

    ## Usage

    ```elixir
    # Get all registered modules
    Cleaning.CleanableTableRegistry.all()

    # Get all enabled modules
    Cleaning.CleanableTableRegistry.enabled()

    # Get module by business key
    Cleaning.CleanableTableRegistry.get(:record)

    # Get BigQuery configs for all enabled tables
    Cleaning.CleanableTableRegistry.bigquery_configs()

    # Get PostgreSQL configs for all enabled tables
    Cleaning.CleanableTableRegistry.postgres_configs()
    ```
    """

    use GenServer
    require Logger

    @table_name :cleanable_tables_registry

    # ============================================
    # PUBLIC API
    # ============================================

    @doc """
    Starts the registry GenServer.
    """
    def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @doc """
    Registers a module that implements CleanableTable.
    Called automatically via @after_compile hook.
    """
    def register_module(_env, _bytecode) do
        # This is called at compile time, so we use persistent_term or ETS
        # For compile-time registration, we'll collect modules differently
        :ok
    end

    @doc """
    Manually registers a module implementing CleanableTable.
    Use this at application startup.
    """
    def register(module) when is_atom(module) do
        GenServer.call(__MODULE__, {:register, module})
    end

    @doc """
    Registers multiple modules at once.
    """
    def register_all(modules) when is_list(modules) do
        Enum.each(modules, &register/1)
    end

    @doc """
    Returns all registered modules.
    """
    def all do
        GenServer.call(__MODULE__, :all)
    end

    @doc """
    Returns all enabled modules (where enabled?() returns true).
    """
    def enabled do
        all()
        |> Enum.filter(fn module ->
            function_exported?(module, :enabled?, 0) && module.enabled?()
        end)
    end

    @doc """
    Gets a module by its business key.
    """
    def get(business_key) when is_atom(business_key) do
        all()
        |> Enum.find(fn module ->
            module.business_key() == business_key
        end)
    end

    @doc """
    Returns BigQuery configurations for all enabled tables.
    """
    def bigquery_configs do
        enabled()
        |> Enum.map(fn module ->
            {module.business_key(), module.bigquery_config()}
        end)
        |> Map.new()
    end

    @doc """
    Returns PostgreSQL configurations for all enabled tables.
    """
    def postgres_configs do
        enabled()
        |> Enum.map(fn module ->
            {module.business_key(), module.postgres_config()}
        end)
        |> Map.new()
    end

    @doc """
    Returns a summary of all registered cleanable tables.
    Useful for debugging and logging.
    """
    def summary do
        enabled()
        |> Enum.map(fn module ->
            bq = module.bigquery_config()
            pg = module.postgres_config()

            %{
                module: module,
                business_key: module.business_key(),
                bigquery: %{
                    table: bq.table,
                    id_fields: bq.id_fields,
                    timestamp_field: bq.timestamp_field
                },
                postgres: %{
                    table: pg.table,
                    id_fields: pg[:id_fields],
                    timestamp_field: pg[:timestamp_field]
                }
            }
        end)
    end

    # ============================================
    # GENSERVER CALLBACKS
    # ============================================

    @impl true
    def init(_opts) do
        :ets.new(@table_name, [:set, :named_table, :public])
        {:ok, %{}}
    end

    @impl true
    def handle_call({:register, module}, _from, state) do
        if implements_behaviour?(module) do
            :ets.insert(@table_name, {module, true})
            Logger.debug("Registered cleanable table: #{inspect(module)}")
            {:reply, :ok, state}
        else
            Logger.warning("Module #{inspect(module)} does not implement CleanableTable behaviour")
            {:reply, {:error, :not_cleanable_table}, state}
        end
    end

    @impl true
    def handle_call(:all, _from, state) do
        modules =
            :ets.tab2list(@table_name)
            |> Enum.map(fn {module, _} -> module end)

        {:reply, modules, state}
    end

    # ============================================
    # PRIVATE FUNCTIONS
    # ============================================

    defp implements_behaviour?(module) do
        Code.ensure_loaded(module)

        function_exported?(module, :bigquery_config, 0) &&
        function_exported?(module, :postgres_config, 0) &&
        function_exported?(module, :business_key, 0)
    end
end
