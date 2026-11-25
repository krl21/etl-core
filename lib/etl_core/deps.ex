
defmodule EtlCore.Deps do
    @moduledoc """
    Single place resolving which module backs each external I/O boundary
    (ODBC/BigQuery, Postgres, Postgres pool, HTTP, AMQP), so those boundaries
    can be swapped for a `Mox` double in tests.

    Every function defaults to the real module. Unless a project explicitly
    sets `config :etl_core, :deps, odbc: SomeOtherModule` (no consuming app
    does today), behaviour is identical to calling the real module directly —
    this indirection changes nothing in production.
    """

    @doc "Resolves the module backing `Connection.Odbc.Behaviour`. Defaults to `Connection.Odbc`."
    @spec odbc() :: module()
    def odbc, do: Keyword.get(deps(), :odbc, Connection.Odbc)

    @doc "Resolves the module backing `Connection.Postgres.Behaviour`. Defaults to `Connection.Postgres`."
    @spec postgres() :: module()
    def postgres, do: Keyword.get(deps(), :postgres, Connection.Postgres)

    @doc "Resolves the module backing `Connection.PostgresPool.Behaviour`. Defaults to `Connection.PostgresPool`."
    @spec postgres_pool() :: module()
    def postgres_pool, do: Keyword.get(deps(), :postgres_pool, Connection.PostgresPool)

    @doc "Resolves the module backing `Connection.Http.Behaviour`. Defaults to `Connection.Http`."
    @spec http() :: module()
    def http, do: Keyword.get(deps(), :http, Connection.Http)

    @doc "Resolves the module backing `Genserver.Amqp.Behaviour`. Defaults to `Genserver.Amqp.Adapter`."
    @spec amqp() :: module()
    def amqp, do: Keyword.get(deps(), :amqp, Genserver.Amqp.Adapter)


    ################
    ### Helper functions
    ################

    #
    # Reads the `:etl_core, :deps` keyword list once per call (cheap: just an
    # Application env lookup), defaulting to `[]` when unconfigured.
    #
    # ### Returns:
    #     - Keyword list.
    #
    defp deps, do: Application.get_env(:etl_core, :deps, [])
end
