
defmodule Genserver.ForcedLoad do
    @moduledoc"""
    Genserver orientado a la carga de los datos
    """

    use GenServer
    require Logger
    import Genserver.Utils.PForcedLoad

    def start_link({business, params}) do
        GenServer.start_link(__MODULE__, {business, params}, name: :"#{__MODULE__}.#{business}")
    end

    def init({business, params}) do
        Logger.info("#{to_string(__MODULE__)}. Initializing. Business: ---#{to_string(business)}---")
        :erlang.send_after(10_000, self(), :update)
        {:ok, {business, params}}
    end

    def handle_info(:update, {business, params}) do
        Logger.debug("#{to_string(__MODULE__)}. Applying duplicate/stale row cleanup in ---#{business}---")

        run(business, params)

        {:noreply, {business, params}}
    end



end
