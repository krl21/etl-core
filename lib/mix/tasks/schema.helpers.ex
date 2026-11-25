
defmodule Mix.Tasks.SchemaHelpers do
    @moduledoc """
    Shared helpers for the `mix schema.*` tasks. Not a task itself — just
    the bits that `schema.bootstrap`, `schema.generate` and
    `schema.migrate` would otherwise each duplicate.
    """

    alias DataModel.Schema.EntityDiscovery

    @doc """
    Resolves which entity modules a `mix schema.*` task should act on.

    ### Parameters:
        - otp_app: Atom. The consuming app's OTP application name.
        - module_name: String.t() | nil. The `--module` flag's raw value, if given.

    ### Returns:
        - [module()]. Either `[the given module]`, or every module configured
          via `config :otp_app, :schema_migrations, modules: [...]` (`EntityDiscovery.modules/1`).

    ### Raises:
        - Mix.Error. If `--module` doesn't name a module exposing `attr_list/0`.

    """
    @spec resolve_modules(atom(), String.t() | nil) :: [module()]
    def resolve_modules(otp_app, nil), do: EntityDiscovery.modules(otp_app)

    def resolve_modules(_otp_app, module_name) when is_binary(module_name) do
        module = Module.concat([module_name])
        Code.ensure_loaded(module)

        if not function_exported?(module, :attr_list, 0) do
            Mix.raise("#{module_name} no implementa attr_list/0 — ¿el nombre del módulo está bien escrito?")
        end

        [module]
    end

    @doc """
    The consuming project's `priv/schema_migrations` directory.

    Deliberately the source-tree path (`File.cwd!/0`), not `:code.priv_dir/1`
    (which points inside `_build`) — these files are meant to be committed to
    git, not treated as a build artifact.

    ### Returns:
        - String.t().

    """
    @spec schema_migrations_dir() :: String.t()
    def schema_migrations_dir, do: Path.join(File.cwd!(), "priv/schema_migrations")

    @doc """
    Resolves the fully-qualified schema-migrations control table name from the
    consuming app's own config, exactly like any other BigQuery table in this
    codebase (`config :otp_app, :bigquery, table: [schema_migrations: "..."]`,
    itself normally fed by an app-specific environment variable).

    ### Parameters:
        - otp_app: Atom. The consuming app's OTP application name.

    ### Returns:
        - String.t().

    ### Raises:
        - Mix.Error. If no `:schema_migrations` key is configured under `:bigquery, :table`.

    """
    @spec control_table_name(atom()) :: String.t()
    def control_table_name(otp_app) do
        Application.get_env(otp_app, :bigquery, [])[:table][:schema_migrations] ||
            Mix.raise(
                "No hay tabla de control configurada en " <>
                "`config :#{otp_app}, :bigquery, table: [schema_migrations: \"...\"]`"
            )
    end
end
