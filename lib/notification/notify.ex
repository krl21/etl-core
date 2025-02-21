
defmodule Notification.Notify do
    @moduledoc"""
    Module responsible for sending notifications to other spaces: Slack, Email, etc.
    """

    @doc """
    Sends a message to Slack, splitting it into chunks of up to 3000 characters.

    ### Parameters:
        - url: String. The Slack webhook URL.
        - headers: List. The HTTP headers for the request.
        - env: String. The environment where the message is sent from.
        - info: String. The message content to be sent.

    """
    def notify_slack(url, headers, env, info)
        when is_binary(url) and is_list(headers)
            and is_binary(env) and is_binary(info) do

            info
            |> chunk_text(3000)
            |> Enum.with_index()
            |> Enum.each(fn {message, index} ->
                text = if index == 0 do
                        "<!here> \n" <>
                        "Environment: #{inspect env} \n" <>
                        message
                    else
                        message
                    end

                %{"text" => text}
                |> Poison.encode!()
                |> Connection.Http.post(url, headers)
            end)
    end

    #
    # Splits a given string into chunks of a specified size
    #
    # ### Parameters:
    #     - text: String. The input text to be split.
    #     - size: Integer. The maximum number of characters per chunk.
    #
    # ## Returns:
    #   - A list of strings, each containing up to size characters.
    #
    defp chunk_text(text, size) do
        text
        |> String.graphemes()
        |> Enum.chunk_every(size)
        |> Enum.map(&Enum.join/1)
    end



    @doc"""
    Send notifications to Slack

    ### Parameter:

        - url: String. Url to send the notification.

        - headers: List.

        - env: String.

        - msg: Map.

        - error: Exception.

    """
    def notify_slack(url, headers, env, msg, %ArgumentError{} = error)
        when is_binary(url) and is_list(headers) and is_binary(env) and is_binary(msg) do
            %{"text" =>
                "<!here> \n" <>
                "Environment: #{inspect env} \n" <>
                "Error: #{inspect error} \n" <>
                "Message: #{inspect(msg, limit: :infinity)} \n"
            }
            |> Poison.encode!()
            |> Connection.Http.post(
                url,
                headers
            )
    end

    def notify_slack(url, headers, env, msg, error)
        when is_binary(url) and is_list(headers) and is_binary(env) and is_map(msg) do
            records_current = Map.get(msg, "current")

            %{"text" =>
                "<!here|here> \n" <>
                "Environment: #{inspect env} \n" <>
                "Error: #{inspect(error, limit: :infinity)} \n" <>
                "Records current: #{inspect(records_current, limit: :infinity)} \n"
            }
            |> Poison.encode!()
            |> Connection.Http.post(
                url,
                headers
            )

            # %{"text" =>
            #     "Message: #{inspect(msg, limit: :infinity)} \n"
            # }
            # |> Poison.encode!()
            # |> Connection.Http.post(
            #     url,
            #     headers
            # )
    end




end
