
defmodule Cleaning.CleaningSupervisor do
    @moduledoc """
    Supervisor for cleaning-related processes.

    Add this to your application supervision tree to enable the cleaning registry.

    ## Usage in Application

    ```elixir
    def start(_type, _args) do
        children = [
        # ... other children ...
        {Cleaning.CleaningSupervisor, cleanable_modules: [
            MyApp.Entity.Record,
            MyApp.Entity.Task
        ]}
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
    end
    ```
    """

    use Supervisor

    def start_link(opts) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(opts) do
        cleanable_modules = Keyword.get(opts, :cleanable_modules, [])

        children = [
        {Cleaning.CleanableTableRegistry, []},
        {Task, fn -> register_modules(cleanable_modules) end}
        ]

        Supervisor.init(children, strategy: :one_for_one)
    end

    defp register_modules(modules) do
        # Small delay to ensure registry is ready
        Process.sleep(100)
        Cleaning.CleanableTableRegistry.register_all(modules)
    end
end

