
defmodule Genserver.Utils.ForcedLoad do
    @moduledoc"""
    Module oriented to the instructions necessary to load data in a forced way
    """

    require Logger
    import Notification.Notify, only: [notify_slack: 4]
    import Connection.ElasticSearch, only: [get_from_range: 8, mode: 0]
    import Connection.NodeService


    @doc"""
    Historical load. The information is queried from ElasticSearch.

    ### Parameters:

        - business: Atom. Business to which the process will be applied.

        - type_documentary: String. Type of documentary with which to work.

        - queue: String. Queue to which the records will be sent.

        - start_date: Tuple. Lower limit date, to filter by the "inserted_at" field. Expected structure {{year, month, day}, {hour, minute, second}}, where each inner value is numeric.

        - end_date: Tuple. Upper limit date, to filter by the "inserted_at" field. The structure matches the `start_date` field.

        - config_amqp: List. Configuration to establish the connection with the AMQP queues.

        - config_notification: {String, List, String}. Configuration for sending notifications. The order of the elements corresponds to: url, headers, environment.

        - config_error_notification: {String, List, String}. Configuration for sending error notifications. The order of the elements corresponds to: url, headers, environment.

        - config_elastic: {String, List}. Configuration for the use of the ElasticSearch service. The order corresponds to: url, headers.

        - config_nodesearch: {String, List}. Configuration for the use of the NodeService service. The order corresponds to: url, headers.

        - config_ticket: {String, List, String, String}. Configuration to obtain valid tickets. The order corresponds to: url, headers, username, password.

    """
    def record_historical_load(
            business,
            type_documentary,
            queue,
            start_date,
            end_date,
            config_amqp,
            config_notification,
            config_error_notification,
            config_elastic,
            config_nodesearch,
            config_ticket
        )
        when
            is_atom(business) and
            is_binary(type_documentary) and
            is_binary(queue) and
            is_tuple(start_date) and
            is_tuple(end_date) and
            is_list(config_amqp) and
            is_tuple(config_notification) and tuple_size(config_notification) == 3 and
            is_tuple(config_error_notification) and tuple_size(config_error_notification) == 3 and
            is_tuple(config_elastic) and tuple_size(config_elastic) == 2 and
            is_tuple(config_nodesearch) and tuple_size(config_nodesearch) == 2 and
            is_tuple(config_ticket) and tuple_size(config_ticket) == 4
        do

                step = 10

                upper_deadline = Timex.to_datetime(end_date)
                start_date = Timex.to_datetime(start_date)
                end_date = Timex.shift(start_date, days: step)

                {:ok, connection} = config_amqp |> AMQP.Connection.open()
                {:ok, channel} = AMQP.Channel.open(connection)

                Logger.info("Historic Records. Business: #{to_string(business)}. Start date: #{to_string(start_date)}. End date: #{to_string(upper_deadline)}")

                send_of_historical_records(
                    business,
                    type_documentary,
                    queue,
                    start_date,
                    end_date,
                    upper_deadline,
                    step,
                    channel,
                    config_notification,
                    config_error_notification,
                    config_elastic,
                    config_nodesearch,
                    config_ticket
                )

                Logger.info("#{to_string(__MODULE__)}. Historic Records. Business: #{to_string(business)}. FIN!!!")
    end

    # """
    # Send to the rabbitMQ queue, the files included in a period of time
    #
    # ### Parameters:
    #
    #     - business: Atom. Business to which the process will be applied.
    #
    #     - type_documentary: String. Type of documentary with which to work.
    #
    #     - queue: String. Queue to which the records will be sent.
    #
    #     - start_date: Timex.DateTime. Start date of the time interval to obtain the files.
    #
    #     - end_date: Timex.DateTime. Final date of the time interval to obtain the files.
    #
    #     - upper_deadline: Timex.DateTime. Final date of the time interval to obtain the files.
    #
    #     -step: Integer. Number of days per period.
    #
    #     - channel: AMQP.Channel. channel for sending messages to the AMQP queue.
    #
    #     - config_notification: {String, List, String}. Configuration for sending notifications. The order of the elements corresponds to: url, headers, environment.
    #
    #     - config_error_notification: {String, List, String}. Configuration for sending error notifications. The order of the elements corresponds to: url, headers, environment.
    #
    #     - config_elastic: {String, List}. Configuration for the use of the ElasticSearch service. The order corresponds to: url, headers.
    #
    #     - config_nodesearch: {String, List, String, String}. Configuration for the use of the NodeService service. The order corresponds to: url, headers, username, password.
    #
    #     - config_ticket: {String, List, String, String}. Configuration to obtain valid tickets. The order corresponds to: url, headers, username, password.
    #
    defp send_of_historical_records(
            _business,
            _type_documentary,
            _queue,
            end_date,
            end_date,
            end_date,
            _step,
            _channel,
            _config_notification,
            _config_error_notification,
            _config_elastic,
            _config_nodesearch,
            _config_ticket
        ) do
        :ok
    end

    defp send_of_historical_records(
            business,
            type_documentary,
            queue,
            start_date,
            end_date,
            upper_deadline,
            step,
            channel,
            {url, headers, env} = config_notification,
            config_error_notification,
            config_elastic,
            config_nodesearch,
            config_ticket
        )
        do

            msg = "Historic records. Business: #{to_string(business)}. Records to be processed from #{to_string(start_date)} to #{to_string(end_date)}"
            Logger.info(msg)
            notify_slack(url, headers, env, msg)

            count = send(
                business,
                type_documentary,
                queue,
                start_date,
                end_date,
                channel,
                config_error_notification,
                config_elastic,
                config_nodesearch,
                config_ticket
            )

            msg = "Historic records. Business: #{to_string(business)}. END! Records sent to the queue #{queue}. Total: #{to_string(count)}"
            Logger.info(msg)
            notify_slack(url, headers, env, msg)

            start_date = end_date
            end_date = Timex.shift(end_date, days: step)
            end_date =
                if Timex.diff(end_date, upper_deadline, :second) <= 0 do
                    end_date
                else
                    upper_deadline
                end

            send_of_historical_records(
                business,
                type_documentary,
                queue,
                start_date,
                end_date,
                upper_deadline,
                step,
                channel,
                config_notification,
                config_error_notification,
                config_elastic,
                config_nodesearch,
                config_ticket
            )
    end

    #
    #
    #
    defp send(
            business,
            type_documentary,
            queue,
            start_date,
            end_date,
            channel,
            {url_error, headers_error, env},
            {url_elastic, headers_elastic},
            {url_nodesearch, headers_nodesearch},
            config_ticket
        )
        do
            {:ok, result} = get_from_range(
                url_elastic,
                headers_elastic,
                type_documentary,
                mode(),
                start_date,
                end_date,
                "inserted_at",
                "unique_id"
            )

            result
            |> Enum.chunk_every(20)
            |> Enum.each(fn ids ->
                ids
                |> Enum.each(fn id ->
                    try do
                    get_details(id, url_nodesearch, headers_nodesearch, config_ticket)
                    |> case do
                        {:ok, %{"response" => %{"msg" => payload}}} ->
                            try do
                                msg = %{"action" => "poblar_datos", "current" => payload} |> Poison.encode!()
                                AMQP.Basic.publish(channel, queue, "", msg)
                            rescue
                                error ->
                                    msg = "#{to_string(__MODULE__)}. #{to_string(__ENV__.function)}. Business: #{to_string(business)}. Unique_id: #{to_string(id)}. Error al enviarlo a la cola. #{inspect error}"
                                    Logger.error(msg)
                                    notify_slack(url_error, headers_error, env, msg)
                            end

                        error ->
                            msg = "#{to_string(__MODULE__)}. Error NodeService. Business: #{to_string(business)}. Unique_id: #{to_string(id)}. Error: #{inspect error}"
                            Logger.error(msg)
                            notify_slack(url_error, headers_error, env, msg)
                    end

                    rescue
                        error ->
                            msg = "#{to_string(__MODULE__)}. Error NodeService. Business: #{to_string(business)}. Unique_id: #{to_string(id)}. Error: #{inspect error}"
                            Logger.error(msg)
                            notify_slack(url_error, headers_error, env, msg)
                    end

                end)
                :timer.sleep(2000)
            end)

            Kernel.length(result)
    end






end
