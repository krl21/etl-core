
defmodule Genserver.Utils.ForcedLoad do
    @moduledoc"""
    Modulo orientado a las intrucciones necesarias para la carga de datos de manera forzada
    """

    require Logger


    @doc"""
    Historical load. The information is queried from ElasticSearch. To define a new load, redefine function get_data_from_elastic/4.

    ### Parameters:

        - business: Atom. Business to which the process will be applied.

        - queue: String. Queue to which the records will be sent.

        - start_date: Tuple. Lower limit date, to filter by the "inserted_at" field. Expected structure {{year, month, day}, {hour, minute, second}}, where each inner value is numeric.

        - end_date: Tuple. Upper limit date, to filter by the "inserted_at" field. La estructura coincide con el campo `start_date`.

        - configuration_amqp: List. Configuracion para la establecer la conexion con las colas de AMQP.

    """
    def record_historical_load(business, queue, start_date, end_date, configuration_amqp)
        when is_atom(business) and is_binary(queue) and
            is_tuple(start_date) and is_tuple(end_date) do

                step = 10

                upper_deadline = Timex.to_datetime(end_date)
                start_date = Timex.to_datetime(start_date)
                end_date = Timex.shift(start_date, days: step)

                {:ok, connection} = configuration_amqp |> AMQP.Connection.open()
                {:ok, channel} = AMQP.Channel.open(connection)

                Logger.info("Poblado de expedientes historicos. Negocio: #{to_string(business)}. Start date: #{to_string(start_date)}. End date: #{to_string(upper_deadline)}")



    end




end
