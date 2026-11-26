
defmodule DataModel.Schema.Generator do
    @moduledoc """
    Generates migration files for an entity module.
    """

    require Logger
    alias DataModel.Schema.{Introspector, Differ}

    @snapshot_filename "_schema.json"
    @migration_file_regex ~r/^(\d+)_/

    @doc """
    Generates a migration file for `module` if its schema changed since the
    last generation, and updates the schema snapshot either way nothing changed
    or something did.

    `:required` only ever takes effect on an entity's very first `generate/2`
    (the one that produces its `:create_table`) or on a column that was already
    `REQUIRED` in the last snapshot — BigQuery only allows a `REQUIRED` column at
    table creation, never afterward, so a genuinely *new* required column, or an
    existing *nullable* one that code now marks `:required`, is downgraded to
    `NULLABLE` instead (logging a warning); a column that was already `REQUIRED`
    and still is produces no operation at all, since nothing actually changed.

    ### Parameters:
        - module: Atom. A module implementing `Cleaning.CleanableTable` and `DataModel.Behaviour`.
        - opts: Keyword list.
            - `:priv_dir` (required). Path to the consuming project's `priv/schema_migrations` directory.
            - `:name` (optional). Slug used in the generated file name; derived from the first operation otherwise.

    ### Returns:
        - `{:no_changes, business_key}` if the desired schema is identical to the last snapshot.
        - `{:generated, path}` if a migration file was written.
    """
    @spec generate(module(), keyword()) :: {:no_changes, atom()} | {:generated, String.t()}
    def generate(module, opts) when is_atom(module) and is_list(opts) do
        priv_dir = Keyword.fetch!(opts, :priv_dir)
        business_key = Introspector.business_key(module)
        dir = schema_dir(priv_dir, business_key)

        previous = read_schema_snapshot(dir)
        desired = previous |> enforce_required_only_at_creation(Introspector.desired_schema(module))
        operations = Differ.diff(previous, desired)

        case operations do
            [] ->
                {:no_changes, business_key}

            operations ->
                File.mkdir_p!(dir)
                version = next_version(dir)
                path = write_migration_file(dir, version, business_key, module, operations, opts)
                write_schema_snapshot(dir, desired)
                {:generated, path}
        end
    end

    @doc """
    Runs `generate/2` for every module in `modules`.

    ### Parameters:
        - modules: [module()].
        - opts: Keyword list. See `generate/2`.

    ### Returns:
        - [{module(), {:no_changes, atom()} | {:generated, String.t()}}].
    """
    @spec generate_all([module()], keyword()) :: [{module(), {:no_changes, atom()} | {:generated, String.t()}}]
    def generate_all(modules, opts) when is_list(modules) and is_list(opts) do
        Enum.map(modules, &{&1, generate(&1, opts)})
    end

    @doc """
    Establishes the schema snapshot baseline for an entity whose BigQuery table
    already exists (created manually, outside this system) — writes `_schema.json`
    as-is, without generating a migration file and without touching BigQuery.

    Must be run once per pre-existing entity before its first real `generate/2`;
    brand-new entities (no table yet) don't need it — their first `generate/2`
    naturally produces a `:create_table` migration.

    Always records every column as `NULLABLE`, even one defined as `:required`
    in code: this function never touches BigQuery, so it has no way to know
    whether the pre-existing table's real column actually is `REQUIRED` — and a
    column can only be made `REQUIRED` when a table is created, never on one
    that already exists, which is the only case this function is for. Recording
    `NULLABLE` is the conservative choice: at worst, the next `generate/2`
    proposes (and `generate/2` itself then rejects, with a warning) turning it
    `REQUIRED` — never an attempt against BigQuery that would just fail anyway.

    ### Parameters:
        - module: Atom. A module implementing `Cleaning.CleanableTable` and `DataModel.Behaviour`.
        - opts: Keyword list. `:priv_dir` (required), see `generate/2`.

    ### Returns:
        - `{:bootstrapped, business_key}`.
    """
    @spec bootstrap(module(), keyword()) :: {:bootstrapped, atom()}
    def bootstrap(module, opts) when is_atom(module) and is_list(opts) do
        priv_dir = Keyword.fetch!(opts, :priv_dir)
        business_key = Introspector.business_key(module)
        dir = schema_dir(priv_dir, business_key)

        File.mkdir_p!(dir)
        desired = module |> Introspector.desired_schema() |> Enum.map(&%{&1 | mode: "NULLABLE"})
        write_schema_snapshot(dir, desired)
        {:bootstrapped, business_key}
    end

    @doc """
    Computes the next sequential migration number for an entity's migrations
    directory: the highest existing leading number plus one, or `1` if none
    exist yet. Independent of whether `_schema.json` already exists — a
    bootstrapped entity that never wrote a migration file still starts at `1`.

    ### Parameters:
        - dir: String. The entity's `priv/schema_migrations/<business_key>` directory.

    ### Returns:
        - pos_integer().

    """
    @spec next_version(String.t()) :: pos_integer()
    def next_version(dir) do
        case File.ls(dir) do
            {:ok, files} ->
                files
                |> Enum.map(&Regex.run(@migration_file_regex, &1))
                |> Enum.filter(& &1)
                |> Enum.map(fn [_, number] -> String.to_integer(number) end)
                |> Enum.max(fn -> 0 end)
                |> Kernel.+(1)

            {:error, :enoent} ->
                1
        end
    end


    ################
    ### Helper functions
    ################

    #
    # Builds the path to an entity's migrations directory.
    #
    # ### Parameters:
    #     - priv_dir: String.t().
    #     - business_key: Atom.
    #
    # ### Returns:
    #     - String.t().
    #
    defp schema_dir(priv_dir, business_key), do: Path.join(priv_dir, to_string(business_key))

    #
    # Downgrades a `REQUIRED` column to `NULLABLE` unless this is the entity's
    # very first schema (`previous == []`, about to become a `:create_table`,
    # where `REQUIRED` is always fine) or the column was already `REQUIRED` in
    # `previous` (nothing is actually changing for it) — BigQuery only allows a
    # `REQUIRED` column at table creation, never afterward.
    #
    # ### Parameters:
    #     - previous: [DataModel.Schema.Introspector.column()]. `[]` for a brand-new entity.
    #     - desired: [DataModel.Schema.Introspector.column()].
    #
    # ### Returns:
    #     - [DataModel.Schema.Introspector.column()].
    #
    defp enforce_required_only_at_creation([], desired), do: desired

    defp enforce_required_only_at_creation(previous, desired) do
        previous_by_name = Map.new(previous, &{&1.name, &1})

        Enum.map(desired, fn
            %{mode: "REQUIRED", name: name} = column ->
                case Map.fetch(previous_by_name, name) do
                    {:ok, %{mode: "REQUIRED"}} ->
                        column

                    _ ->
                        Logger.warning("required ignorado en #{name}: solo se permite al crear la tabla")
                        %{column | mode: "NULLABLE"}
                end

            column ->
                column
        end)
    end

    #
    # Reads and decodes `_schema.json` from an entity's migrations directory.
    #
    # ### Parameters:
    #     - dir: String.t(). The entity's migrations directory.
    #
    # ### Returns:
    #     - [DataModel.Schema.Introspector.column()]. `[]` if the file doesn't exist yet.
    #
    defp read_schema_snapshot(dir) do
        path = Path.join(dir, @snapshot_filename)

        case File.read(path) do
            {:ok, content} -> Jason.decode!(content, keys: :atoms)
            {:error, :enoent} -> []
        end
    end

    #
    # Overwrites `_schema.json` with the current desired schema.
    #
    # ### Parameters:
    #     - dir: String.t(). The entity's migrations directory.
    #     - schema: [DataModel.Schema.Introspector.column()].
    #
    # ### Returns:
    #     - :ok.
    #
    defp write_schema_snapshot(dir, schema) do
        path = Path.join(dir, @snapshot_filename)
        File.write!(path, Jason.encode!(schema, pretty: true))
    end

    #
    # Writes the migration file itself, as a plain, pretty-printed Elixir map
    # literal (readable with `Code.eval_file/1`, no macros involved).
    #
    # ### Parameters:
    #     - dir: String.t(). The entity's migrations directory.
    #     - version: pos_integer().
    #     - business_key: Atom.
    #     - module: Atom. The entity module, used to resolve its current table name.
    #     - operations: [DataModel.Schema.Differ.operation()].
    #     - opts: Keyword list. See `generate/2`.
    #
    # ### Returns:
    #     - String.t(). The path written.
    #
    defp write_migration_file(dir, version, business_key, module, operations, opts) do
        slug = (Keyword.get(opts, :name) || default_slug(operations)) |> sanitize_slug()
        path = Path.join(dir, "#{version}_#{slug}.exs")

        migration = %{
            version: version,
            business_key: business_key,
            table: Introspector.table_id(module),
            generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
            operations: operations
        }

        File.write!(path, inspect(migration, pretty: true, limit: :infinity))
        path
    end

    #
    # Derives a human-readable slug from a migration's first operation, used
    # when the caller didn't pass `:name`.
    #
    # ### Parameters:
    #     - operations: [DataModel.Schema.Differ.operation()].
    #
    # ### Returns:
    #     - String.t().
    #
    defp default_slug([%{op: :create_table} | _]), do: "create_table"
    defp default_slug([%{op: op, name: name} | _]), do: "#{op}_#{name}"
    defp default_slug([%{op: op, column: %{name: name}} | _]), do: "#{op}_#{name}"
    defp default_slug(_operations), do: "migration"

    #
    # Normalizes a slug (caller-given or derived) into safe filename characters.
    #
    # ### Parameters:
    #     - slug: String.t() | atom().
    #
    # ### Returns:
    #     - String.t(). Lowercase, with any run of non `[a-z0-9_]` characters collapsed to `_`.
    #
    defp sanitize_slug(slug) do
        slug
        |> to_string()
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9_]+/, "_")
    end





end
