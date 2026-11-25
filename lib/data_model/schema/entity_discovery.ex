
defmodule DataModel.Schema.EntityDiscovery do
    @moduledoc """
    Resolves the list of entity modules a consuming app wants schema migrations
    managed for.

    Deliberately does not introduce a second compile-time registry: it either
    reads an explicit, config-declared list (the only option that works for a
    standalone `mix` task, which never boots the app's full supervision tree),
    or delegates to the existing `Cleaning.CleanableTableRegistry` when the app
    is already running. Nothing here is named after "Cleanable" — that family of
    names is about table cleaning, not schema migrations.
    """

    @doc """
    Reads the explicit list of entity modules configured for schema migrations.

    ### Parameters:
        - otp_app: Atom. The consuming app's OTP application name.

    Expected configuration, declared once per consuming app:

        config :my_app, :schema_migrations, modules: [MyApp.Entity.Record, MyApp.Entity.Task]

    ### Returns:
        - [module()].

    ### Raises:
        - ArgumentError. If `:schema_migrations, :modules` is missing or empty —
          this is always a configuration mistake, never a legitimate empty state.

    """
    @spec modules(atom()) :: [module()]
    def modules(otp_app) when is_atom(otp_app) do
        otp_app
        |> Application.get_env(:schema_migrations, [])
        |> Keyword.get(:modules, [])
        |> case do
            [] ->
                raise ArgumentError,
                    "No hay módulos configurados en `config :#{otp_app}, :schema_migrations, modules: [...]`"
            modules ->
                modules
        end
    end

    @doc """
    Delegates to `Cleaning.CleanableTableRegistry.all/0`.

    Only meaningful when the full OTP application is already running (e.g. an
    `iex` session attached to a live release) — a standalone `mix` task should
    use `modules/1` instead.

    ### Returns:
        - [module()].

    """
    @spec modules_from_registry() :: [module()]
    def modules_from_registry, do: Cleaning.CleanableTableRegistry.all()
end
