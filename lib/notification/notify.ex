
defmodule Notification.Notify do
    @moduledoc"""
    Module responsible for sending notifications to other spaces: Slack, Email, etc.
    """

    @doc"""
    Send notifications to Slack

    ### Parameter:

        - url: String. Url to send the notification.

        - headers: List.

        - env: String.

        - error: Exception.

    """
    def notify_slack(url, headers, env, info)
        when is_binary(url) and is_list(headers)
            and is_binary(env) and is_binary(info) do
            %{"text" =>
                "<!here> \n" <>
                "Environment: #{inspect env} \n" <>
                info <> "\n"
            }
            |> Poison.encode!()
            |> Connection.Http.post(
                url,
                headers
            )
    end

    @doc"""
    Send notifications to Slack

    ### Parameter:

        - url: String. Url to send the notification.

        - headers: List.

        - env: String.

        - msg: String.

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
                "Error: #{inspect error} \n" <>
                "Records current: #{inspect(records_current, limit: :infinity)} \n"
            }
            |> Poison.encode!()
            |> Connection.Http.post(
                url,
                headers
            )

            %{"text" =>
                "Message: #{inspect(msg, limit: :infinity)} \n"
            }
            |> Poison.encode!()
            |> Connection.Http.post(
                url,
                headers
            )
    end




end
