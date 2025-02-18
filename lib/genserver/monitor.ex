
defmodule Genserver.Monitor do
    @moduledoc """
    Monitors registered GenServers and reports their status to a webhook.
    """

    use GenServer
    require Logger
    alias Notification.Notify
    alias Tools.SystemStats

    # Public API to start the monitor with webhook URL and environment
    def start_link({webhook_url, environment}) do
        GenServer.start_link(__MODULE__, %{webhook_url: webhook_url, environment: environment, servers: %{}}, name: __MODULE__)
    end

    def init(state) do
        Logger.info("#{to_string(__MODULE__)}. Initializing.")

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
        updated_servers = monitor_system(servers, webhook_url, env)
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
    # Monitors the system by sending project status and checking active servers.
    #
    # ### Parameters:
    #   - servers (Map): A map where keys are GenServer names and values are their PIDs.
    #   - webhook_url (String): The URL to send notifications.
    #   - env (String): The environment in which the application is running.
    #
    # ### Returns:
    #     - Map: An updated map with only active GenServers.
    #
    def monitor_system(servers, webhook_url, env) do
        send_project_status(webhook_url, env)
        check_servers(servers, webhook_url, env)
    end

    #
    # Sends the system's memory and disk usage status to the webhook.
    #
    # ### Parameters:
    #   - webhook_url (String): The URL to send notifications.
    #   - env (String): The environment in which the application is running.
    #
    # ### Returns:
    #   - None. Sends a JSON message with the system status.
    #
    defp send_project_status(webhook_url, env) do
        memory_info = SystemStats.get_memory_info()
        disk_info = SystemStats.get_disk_info()

        message = """
        *Project Status*
        \tRAM Used: #{memory_info[:used]}
        \tRAM Free: #{memory_info[:free]}
        \tDisk Used: #{disk_info[:used]}
        \tDisk Free: #{disk_info[:free]}
        """

        Notify.notify_slack(webhook_url, [{"Content-type", "application/json"}], env, message)
    end

    #
    # Checks the status of registered GenServers and updates the server list.
    #
    # ### Parameters:
    #   - servers (Map): A map where keys are GenServer names and values are their PIDs.
    #   - webhook_url (String): The URL to send notifications.
    #   - env (String): The environment in which the application is running.
    #
    # ### Returns:
    #     - Map: An updated map with only active GenServers.
    #
    defp check_servers(servers, webhook_url, env) do
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
    # Schedules the next heartbeat message to be sent at a randomly generated time.
    #
    # ### Return:
    #    - None. Sends a delayed message to self to trigger the heartbeat.
    #
    defp schedule_heartbeat() do
        now = Timex.now()
        random_hour = generate_random_hour()

        next_run = find_next_run_time(now, random_hour)

        delay = Timex.diff(next_run, now, :milliseconds)
        :erlang.send_after(delay, self(), :heartbeat)
    end

    #
    # Generates a random hour and minute within a specified range.
    #
    # ### Returns:
    #     - A tuple `{hour, minute}` representing a random time between 8:00 AM and 6:00 PM.
    #
    defp generate_random_hour() do
        hour = Enum.random(8..18)
        minute = Enum.random(0..59)
        {hour, minute}
    end

    #
    # Finds the next valid scheduled time for the heartbeat based on the current time and a randomly generated time.

    # ### Parameters:
    #     - now (DateTime): The current time.
    #     - time (tuple): A tuple `{hour, minute}` representing the randomly generated time.
    #
    # ### Returns:
    #     - DateTime: The next valid scheduled time.
    #
    defp find_next_run_time(now, {hour, minute}) do
        now
        |> Timex.set([hour: hour, minute: minute, second: 0])
        |> Timex.shift(days: 1)
    end

    # #
    # # Schedules the next heartbeat message to be sent at 8:00 AM, 1:00 PM and 6:00 PM.
    # #
    # # ### Return:
    # #
    # #     - None. Sends a delayed message to self to trigger the heartbeat.
    # #
    # # defp schedule_heartbeat() do
    # #     now = Timex.now()

    # #     next_run = Timex.set(now, [hour: 8, minute: 0, second: 0])
    # #     next_run = if Timex.after?(now, next_run) do
    # #         Timex.shift(next_run, days: 1)
    # #     else
    # #         next_run
    # #     end

    # #     delay = Timex.diff(next_run, now, :milliseconds)
    # #     :erlang.send_after(max(delay, 1), self(), :heartbeat)
    # # end
    # defp schedule_heartbeat() do
    #     now = Timex.now()

    #     # List of times at which the heartbeat should be triggered
    #     times = [
    #         {8, 0},  # 8:00 AM
    #         {13, 0}, # 1:00 PM
    #         {18, 0}  # 6:00 PM
    #     ]

    #     # Find the next scheduled time for the heartbeat
    #     next_run = find_next_run_time(now, times)

    #     # Calculate the delay and schedule the next heartbeat message
    #     delay = Timex.diff(next_run, now, :milliseconds)
    #     :erlang.send_after(delay, self(), :heartbeat)
    # end

    # #
    # # Finds the next valid scheduled time for the heartbeat based on the current time
    # # and the list of predefined times.
    # #
    # # ### Parameters:
    # #   - now (DateTime): The current time.
    # #   - times (List): A list of tuples with hour and minute of the scheduled times.
    # #
    # # ### Returns:
    # #   - DateTime: The next valid scheduled time.
    # #
    # defp find_next_run_time(now, times) do

    #     # Find the first future time that hasn't passed yet
    #     Enum.find(times, fn {hour, minute} ->
    #         next_run = Timex.set(now, [hour: hour, minute: minute, second: 0])
    #         Timex.after?(now, next_run) == false
    #     end)
    #     |> case do
    #         nil ->
    #             # If all times have passed for today, shift to the next day and use the first time in `times`
    #             {hour, minute} = hd(times)  # Get the first time from the list
    #             Timex.set(Timex.shift(now, days: 1), [hour: hour, minute: minute, second: 0])  # Set it for the next day

    #         {hour, minute} ->
    #             # If a future time is found, set the next run to that time
    #             Timex.set(now, [hour: hour, minute: minute, second: 0])
    #     end
    # end

end
