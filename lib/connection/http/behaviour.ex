
defmodule Connection.Http.Behaviour do
    @moduledoc """
    Contract mirroring `Connection.Http`'s public API, so a test double can be
    generated with `Mox.defmock/2` and swapped in via `EtlCore.Deps.http/0`.
    """

    # Declared at the arities every caller in this library actually uses
    # (`Connection.Http.post/4` and `.get/4` fill in the trailing timeout
    # arguments via Elixir default-argument clauses, which are real exported
    # functions of their own — `post/3`/`get/2` below — and so satisfy these
    # callbacks directly).
    @callback post(body :: String.t(), url :: String.t(), headers :: list()) ::
        {:ok, term()} | {:error, term()}
    @callback get(url :: String.t(), headers :: list()) ::
        {:ok, term()} | {:error, term()}
end
