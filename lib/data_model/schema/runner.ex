
defmodule DataModel.Schema.Runner do
    @moduledoc """
    Orchestrates the full schema pipeline for one or more entities: generates
    a migration file if the entity's desired schema changed since the last
    snapshot, then applies every pending migration against BigQuery — logging
    each step.

    Thin glue over `DataModel.Schema.Generator` and `DataModel.Schema.Migrator`,
    meant for driving the two steps together from an `iex` session (or a
    one-off script) instead of calling each module separately.
    """

    require Logger
    alias DataModel.Schema.{Generator, Migrator}
    alias Pool.BigQuery

    @typedoc """
    Either an already-open ODBC connection, or the name of a `Pool.BigQuery`
    pool to check a connection out of (and back into) for the migrate step.
    """
    @type connection :: pid() | atom()

    @doc """
    Runs `generate/2` followed by `migrate/5` for a single entity module.

    ### Parameters:
        - connection: `t:connection/0`. An open ODBC connection (`pid()`), or the
          name of a `Pool.BigQuery` pool (e.g. `:bigquery_pool`) to borrow one from.
        - module: Atom. A module implementing `Cleaning.CleanableTable` and `DataModel.Behaviour`.
        - priv_dir: String. Path to the consuming project's `priv/schema_migrations` directory.
        - control_table: String. Fully-qualified control table name (`dataset.table`).
        - opts: Keyword. Passed through to `Generator.generate/2` (e.g. `:name`) and to
          `Migrator.migrate/5` / `DataModel.Schema.DdlBuilder.build/3` (e.g. `:batch_size`).

    ### Returns:
        - `:ok`. The entity's schema was generated (or had no changes) and every pending migration was applied.
        - `{:error, {module(), pos_integer(), String.t()}}`. The migration version that failed and BigQuery's error message.
    """
    @spec run(connection(), module(), String.t(), String.t(), keyword()) :: :ok | {:error, {module(), pos_integer(), String.t()}}
    def run(connection, module, priv_dir, control_table, opts \\ []) when is_atom(module) do

        Logger.info("[#{inspect(module)}] calculando el esquema deseado y comparándolo con el último snapshot...")

        case Generator.generate(module, Keyword.put(opts, :priv_dir, priv_dir)) do
            {:no_changes, business_key} ->
                Logger.info("[#{business_key}] sin cambios de esquema")

            {:generated, path} ->
                Logger.info("[#{inspect(module)}] migración generada: #{path}")
        end

        Logger.info("[#{inspect(module)}] aplicando migraciones pendientes contra BigQuery...")

        case migrate(connection, module, priv_dir, control_table, opts) do
            {:ok, []} ->
                Logger.info("[#{inspect(module)}] no había migraciones pendientes por aplicar")
                :ok

            {:ok, applied} ->
                Logger.info("[#{inspect(module)}] migraciones aplicadas: #{inspect(applied)}")
                :ok

            {:error, version, reason} ->
                Logger.error("[#{inspect(module)}] la migración #{version} falló: #{reason}")
                {:error, {module, version, reason}}
        end
    end

    @doc """
    Runs `run/5` for every module in `modules`, stopping at the first one that fails.

    ### Parameters:
        - connection: `t:connection/0`. See `run/5`.
        - modules: [module()].
        - priv_dir: String. See `run/5`.
        - control_table: String. See `run/5`.
        - opts: Keyword. See `run/5`.

    ### Returns:
        - `:ok`. Every entity in `modules` was generated and migrated successfully.
        - `{:error, {module(), pos_integer(), String.t()}}`. The entity, version and error that stopped the run.
    """
    @spec run_all(connection(), [module()], String.t(), String.t(), keyword()) :: :ok | {:error, {module(), pos_integer(), String.t()}}
    def run_all(connection, modules, priv_dir, control_table, opts \\ []) when is_list(modules) do

        Enum.reduce_while(modules, :ok, fn module, :ok ->
            case run(connection, module, priv_dir, control_table, opts) do
                :ok -> {:cont, :ok}
                {:error, _reason} = error -> {:halt, error}
            end
        end)

    end


    ################
    ### Helper functions
    ################

    #
    # Dispatches `Migrator.migrate/5` on an already-open connection directly,
    # or on one borrowed from (and returned to) a `Pool.BigQuery` pool.
    #
    # ### Parameters:
    #     - connection: `t:connection/0`.
    #     - module: Atom.
    #     - priv_dir: String.t().
    #     - control_table: String.t().
    #     - opts: Keyword. See `run/5`.
    #
    # ### Returns:
    #     - See `DataModel.Schema.Migrator.migrate/5`.
    #
    defp migrate(pid, module, priv_dir, control_table, opts) when is_pid(pid) do
        Migrator.migrate(pid, module, priv_dir, control_table, opts)
    end

    defp migrate(pool_name, module, priv_dir, control_table, opts) when is_atom(pool_name) and not is_nil(pool_name) do
        BigQuery.with_connection(pool_name, fn pid -> Migrator.migrate(pid, module, priv_dir, control_table, opts) end)
    end




end
