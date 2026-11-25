
defmodule Connection.Odbc.Behaviour do
    @moduledoc """
    Contract mirroring `Connection.Odbc`'s public API, so a test double can be
    generated with `Mox.defmock/2` and swapped in via `EtlCore.Deps.odbc/0`.
    """

    @callback start() :: :ok
    @callback stop() :: :ok
    @callback connect(data_source :: list()) :: pid()
    @callback disconnect(pid :: pid()) :: :ok
    @callback get_uuid(pid :: pid()) :: String.t()
    @callback insert(pid :: pid(), statement :: String.t()) :: term()
    @callback select(pid :: pid(), statement :: String.t()) :: list()
    @callback update(pid :: pid(), statement :: String.t()) :: term()
    @callback delete(pid :: pid(), statement :: String.t()) :: term()
    @callback execute(pid :: pid(), statement :: String.t()) :: term()
end
