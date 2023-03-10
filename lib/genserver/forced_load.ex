
defmodule Genserver.ForcedLoad do
    @moduledoc"""
    Genserver orientado a la carga de los datos
    """

    use GenServer
    require Logger
    import Genserver.Utils.PForcedLoad

    def start_link({business, _params} = info) do
        GenServer.start_link(__MODULE__, info, name: :"#{__MODULE__}.#{business}")
    end

    def init({business, _params} = info) do
        Logger.info("#{to_string(__MODULE__)}. Initializing. Business: ---#{to_string(business)}---")
        :erlang.send_after(10_000, self(), :update)
        {:ok, info}
    end

    def handle_info(:update, {business, params}) do
        Logger.debug("#{to_string(__MODULE__)}. Forced load in ---#{business}---")

        run(business, params)

        :erlang.send_after(2_937_600_000, self(), :update)
        {:noreply, {business, params}}
    end



end
