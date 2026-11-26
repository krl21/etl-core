
defmodule DataModel.Schema.Migrator do
    @moduledoc """
    Applies pending schema migrations (written by `DataModel.Schema.Generator`)
    against BigQuery: for each entity, ensures the control table exists, finds
    migration files numbered above the last applied version, turns their
    operations into DDL via `DataModel.Schema.DdlBuilder`, and runs each
    statement through `Connection.Odbc.execute/2`.

    Every change is applied automatically — there is no manual-approval gate.
    BigQuery itself still rejects some unsafe changes at execution time (e.g.
    narrowing a column's type, or adding `NOT NULL` to a column with existing
    rows); when that happens, the real BigQuery error is recorded as-is and the
    run stops, rather than this module trying to work around it (no automatic
    backfill/recreate pipeline).

    Callable directly (e.g. from an `iex` session attached to a running
    release, or a one-off script) or through the `mix schema.migrate` task
    — both paths run this exact code.
    """

    require Logger
    alias DataModel.Schema.{Introspector, ControlTable, DdlBuilder}

    @migration_file_regex ~r/^(\d+)_/

    @doc """
    Applies every pending migration for a single entity, in version order.
    Stops at the first failing migration.

    ### Parameters:
        - pid: Process. ODBC connection to BigQuery.
        - module: Atom. A module implementing `Cleaning.CleanableTable` and `DataModel.Behaviour`.
        - priv_dir: String. Path to the consuming project's `priv/schema_migrations` directory.
        - control_table: String. Fully-qualified control table name (`dataset.table`).
        - opts: Keyword list. Passed through to `DataModel.Schema.DdlBuilder.build/3` (e.g. `:batch_size`).

    ### Returns:
        - `{:ok, [pos_integer()]}`. Versions applied, in order (possibly empty).
        - `{:error, pos_integer(), String.t()}`. The first version that failed, and BigQuery's error message.
    """
    @spec migrate(pid(), module(), String.t(), String.t(), keyword()) ::
        {:ok, [pos_integer()]} | {:error, pos_integer(), String.t()}
    def migrate(pid, module, priv_dir, control_table, opts \\ []) when is_pid(pid) and is_atom(module) do
        ControlTable.ensure_exists!(pid, control_table)

        business_key = Introspector.business_key(module)
        entity_table = Introspector.table_id(module)
        dir = Path.join(priv_dir, to_string(business_key))
        applied_version = ControlTable.last_applied_version(pid, control_table, business_key) || 0

        dir
        |> pending_migrations(applied_version)
        |> Enum.reduce_while({:ok, []}, fn {version, path}, {:ok, applied_so_far} ->
            case apply_migration(pid, control_table, business_key, entity_table, version, path, opts) do
                :ok -> {:cont, {:ok, [version | applied_so_far]}}
                {:error, reason} -> {:halt, {:error, version, reason}}
            end
        end)
        |> case do
            {:ok, applied} -> {:ok, Enum.reverse(applied)}
            error -> error
        end
    end

    @doc """
    Runs `migrate/5` for every module in `modules`, stopping at the first
    entity whose migration fails (fail-fast, so a CI pipeline step reliably
    blocks the deploy).

    ### Parameters:
        - pid: Process. ODBC connection to BigQuery.
        - modules: [module()].
        - priv_dir: String. See `migrate/5`.
        - control_table: String. See `migrate/5`.
        - opts: Keyword list. See `migrate/5`.

    ### Returns:
        - `{:ok, [{module(), [pos_integer()]}]}`. Versions applied per entity.
        - `{:error, module(), pos_integer(), String.t()}`. The entity, version and error that stopped the run.
    """
    @spec migrate_all(pid(), [module()], String.t(), String.t(), keyword()) ::
        {:ok, [{module(), [pos_integer()]}]} | {:error, module(), pos_integer(), String.t()}
    def migrate_all(pid, modules, priv_dir, control_table, opts \\ []) when is_pid(pid) and is_list(modules) do
        modules
        |> Enum.reduce_while({:ok, []}, fn module, {:ok, results} ->
            case migrate(pid, module, priv_dir, control_table, opts) do
                {:ok, applied} -> {:cont, {:ok, [{module, applied} | results]}}
                {:error, version, reason} -> {:halt, {:error, module, version, reason}}
            end
        end)
        |> case do
            {:ok, results} -> {:ok, Enum.reverse(results)}
            error -> error
        end
    end


    ################
    ### Helper functions
    ################

    #
    # Lists migration files in `dir` numbered above `applied_version`, sorted
    # ascending.
    #
    # ### Parameters:
    #     - dir: String.t(). The entity's migrations directory.
    #     - applied_version: non_neg_integer().
    #
    # ### Returns:
    #     - [{pos_integer(), String.t()}]. `{version, full_path}` pairs. `[]` if the directory doesn't exist yet.
    #
    defp pending_migrations(dir, applied_version) do
        case File.ls(dir) do
            {:ok, files} ->
                files
                |> Enum.map(&parse_migration_file/1)
                |> Enum.filter(& &1)
                |> Enum.filter(fn {version, _file} -> version > applied_version end)
                |> Enum.sort_by(fn {version, _file} -> version end)
                |> Enum.map(fn {version, file} -> {version, Path.join(dir, file)} end)

            {:error, :enoent} ->
                []
        end
    end

    #
    # Extracts the leading version number from a migration file's name.
    #
    # ### Parameters:
    #     - file: String.t(). A file name (not a full path) under an entity's migrations directory.
    #
    # ### Returns:
    #     - {pos_integer(), String.t()} | nil. `nil` for anything that doesn't start with `<digits>_`.
    #
    defp parse_migration_file(file) do
        case Regex.run(@migration_file_regex, file) do
            [_match, number] -> {String.to_integer(number), file}
            nil -> nil
        end
    end

    #
    # Loads a single migration file, builds its DDL statements and executes them
    # in order, recording the outcome (applied or failed) in the control table.
    #
    # ### Parameters:
    #     - pid: Process. ODBC connection to BigQuery.
    #     - control_table: String.t(). Fully-qualified control table name (`dataset.table`).
    #     - business_key: Atom.
    #     - entity_table: String.t(). The entity's own BigQuery table name.
    #     - version: pos_integer().
    #     - path: String.t(). Full path to the migration file.
    #     - opts: Keyword list. See `migrate/5`.
    #
    # ### Returns:
    #     - :ok.
    #     - {:error, String.t()}. BigQuery's (or `DdlBuilder`'s) error message.
    #
    defp apply_migration(pid, control_table, business_key, entity_table, version, path, opts) do
        {migration, _bindings} = Code.eval_file(path)
        statements = DdlBuilder.build(entity_table, migration.operations, opts)

        Enum.each(statements, &EtlCore.Deps.odbc().execute(pid, &1))
        ControlTable.record_applied(pid, control_table, business_key, version, entity_table, length(statements))
        :ok
    rescue
        error ->
            message = Exception.message(error)
            Logger.error("Migración #{version} de #{business_key} falló: #{message}")
            ControlTable.record_failed(pid, control_table, business_key, version, entity_table, message)
            {:error, message}
    end



end
