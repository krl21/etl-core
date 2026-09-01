
defmodule Genserver.ForcedLoad do
    @moduledoc"""
    Genserver orientado a la carga de los datos
    """

    use GenServer
    require Logger
    import Genserver.Protocols.PForcedLoad
    alias Genserver.Monitor


    def start_link({business, _params} = info) do
        GenServer.start_link(__MODULE__, info, name: :"#{__MODULE__}.#{business}")
    end

    def init({business, _params} = info) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business))

        Logger.info("#{to_string(__MODULE__)}. Initializing. Business: ---#{to_string(business)}---")

        :erlang.send_after(10_000, self(), :update)
        {:ok, info}
    end

    def handle_info(:update, {business, params}) do
        Logger.debug("#{to_string(__MODULE__)}. Forced load in ---#{business}---")

        run(business, params)

        {:stop, :normal, {business, params}}
    end



end
