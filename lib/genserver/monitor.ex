
defmodule Genserver.Monitor do
    @moduledoc """
    Monitors registered GenServers and reports their status to a webhook.
    """

    use GenServer
    require Logger
    alias Notification.Notify

    # Public API to start the monitor with webhook URL and environment
    def start_link({webhook_url, environment}) do
        GenServer.start_link(__MODULE__, %{webhook_url: webhook_url, environment: environment, servers: %{}}, name: __MODULE__)
    end

    def init(state) do
        schedule_heartbeat()
        {:ok, state}
    end

    # Register a GenServer for monitoring
    def register(pid, name) do
        GenServer.cast(__MODULE__, {:register, pid, name})
    end

    # Unregister a GenServer when it stops
    def unregister(name) do
        GenServer.cast(__MODULE__, {:unregister, name})
    end

    # Handle process registration
    def handle_cast({:register, pid, name}, %{servers: servers, webhook_url: webhook_url, environment: env} = state) do
        Process.monitor(pid)
        Notify.notify_slack(webhook_url, [{"Content-type", "application/json"}], env, "GenServer *#{name}* registered successfully.")
        {:noreply, %{state | servers: Map.put(servers, name, pid)}}
    end

    def handle_cast({:unregister, name}, %{servers: servers} = state) do
        {:noreply, %{state | servers: Map.delete(servers, name)}}
    end

    # Send daily status notifications at 8 AM
    def handle_info(:heartbeat, %{servers: servers, webhook_url: webhook_url, environment: env} = state) do
        updated_servers = check_servers(servers, webhook_url, env)
        schedule_heartbeat()
        {:noreply, %{state | servers: updated_servers}}
    end

    # Handle crashed processes and notify
    def handle_info({:DOWN, _ref, :process, pid, reason}, %{servers: servers, webhook_url: webhook_url, environment: env} = state) do
        case Enum.find(servers, fn {_name, monitored_pid} -> monitored_pid == pid end) do
            {name, _} ->
                # Log the error and notify Slack
                Logger.error("GenServer #{name} crashed: #{inspect(reason)}")
                Notify.notify_slack(webhook_url, [{"Content-type", "application/json"}], env, "GenServer *#{name}* crashed: #{inspect(reason)}")

                # Remove from the list of monitored servers
                {:noreply, %{state | servers: Map.delete(servers, name)}}

            _ ->
                # Process was not registered or it's not found in the list of servers
                {:noreply, state}
        end
    end

    #
    # Checks the status of registered GenServers and updates the server list.
    #
    # ### Parameters:
    #   - servers (Map): A map where keys are GenServer names and values are their PIDs.
    #   - webhook_url (String): The URL to send notifications.
    #   - env (String): The environment in which the application is running.
    #
    # ## Returns:
    #     - Map:  An updated map with only active GenServers.
    #
    def check_servers(servers, webhook_url, env) do
        servers
        |> Enum.reduce(%{}, fn {name, pid}, acc ->
            if Process.alive?(pid) do
                Notify.notify_slack(webhook_url, [{"Content-type", "application/json"}], env, "GenServer *#{name}* is alive.")
                Map.put(acc, name, pid)
            else
                Logger.error("GenServer *#{name}* is not alive!")
                Notify.notify_slack(webhook_url, [{"Content-type", "application/json"}], env, "GenServer *#{name}* is not responding")
                acc  # Do not include the dead GenServer in the new map
            end
        end)
    end

    #
    # Schedules the next heartbeat message to be sent at 8:00 AM.
    #
    # ### Return:
    #
    #     - None. Sends a delayed message to self to trigger the heartbeat.
    #
    defp schedule_heartbeat() do
        now = Timex.now()

        next_run = Timex.set(now, [hour: 8, minute: 0, second: 0])
        next_run = if Timex.after?(now, next_run) do
            Timex.shift(next_run, days: 1)
        else
            next_run
        end

        delay = Timex.diff(next_run, now, :milliseconds)
        :erlang.send_after(max(delay, 1), self(), :heartbeat)
    end


end
