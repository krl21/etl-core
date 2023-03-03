
defmodule Genserver.ForcedLoad do
    @moduledoc"""
    Genserver orientado a la carga de los datos
    """

    use GenServer
    require Logger
    import Genserver.Utils.PForcedLoad

    def start_link({business, _data_source} = info) do
        GenServer.start_link(__MODULE__, info, name: :"#{__MODULE__}.#{business}")
    end

    def init(business) do
        Logger.info("#{inspect __MODULE__}. Initializing. Business: ---#{business}---")
        :erlang.send_after(10_000, self(), :update)
        {:ok, {business}}
    end

    def handle_info(:update, {business}) do
        Logger.debug("#{__MODULE__}. Applying duplicate/stale row cleanup in ---#{business}---")

        run(business)

        {:noreply, {business}}
    end



end
