
defmodule Genserver.ForcedLoad do
    @moduledoc"""
    Genserver orientado a la carga de los datos
    """

    use GenServer
    require Logger
    import Genserver.Utils.PForcedLoad

    def start_link(business) do
        GenServer.start_link(__MODULE__, business, name: :"#{__MODULE__}.#{business}")
    end

    def init(business) do
        Logger.info("#{to_string(__MODULE__)}. Initializing. Business: ---#{to_string(business)}---")
        :erlang.send_after(10_000, self(), :update)
        {:ok, {business}}
    end

    def handle_info(:update, {business}) do
        Logger.debug("#{to_string(__MODULE__)}. Applying duplicate/stale row cleanup in ---#{business}---")

        run(business)

        {:noreply, {business}}
    end



end
