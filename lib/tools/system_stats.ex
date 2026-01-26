
defmodule Tools.SystemStats do
    @moduledoc """
    Module to retrieve system memory usage and disk usage information in a human-readable format.
    """

    @doc """
    Gets the system's memory usage in a human-readable format (KB, MB, GB).

    ### Returns:
        - Map with `:used` and `:free` keys containing the memory usage in a human-readable format.

    """
    def get_memory_info() do
        case :os.type() do
        {:unix, _} ->
            {output, 0} = System.cmd("free", ["-m"])
            [_header, mem | _] = String.split(output, "\n")
            [_total, used, free | _] = String.split(mem)

            %{
            used: humanize_bytes(String.to_integer(used) * 1_048_576),
            free: humanize_bytes(String.to_integer(free) * 1_048_576)
            }

        {:win32, _} ->
            {output, 0} = System.cmd("wmic", ["OS", "get", "FreePhysicalMemory,TotalVisibleMemorySize", "/VALUE"])
            values = String.split(output, "\n") |> Enum.filter(&(&1 != ""))
            free = String.split(Enum.at(values, 0), "=") |> Enum.at(1) |> String.trim() |> String.to_integer()
            total = String.split(Enum.at(values, 1), "=") |> Enum.at(1) |> String.trim() |> String.to_integer()
            used = div(total - free, 1024)
            free = div(free, 1024)

            %{
            used: humanize_bytes(used * 1_048_576),
            free: humanize_bytes(free * 1_048_576)
            }

        _ ->
            %{error: "Could not retrieve memory usage"}
        end
    end

    @doc"""
    Gets the system's disk usage in a human-readable format.

    ### Returns:
        - Map containing `:used` and `:free` disk space in human-readable format.

    """
    def get_disk_info() do
        case System.cmd("df", ["-h", "."]) do
        {output, 0} ->
            [_header, disk_info | _] = String.split(output, "\n")
            [_fs, _size, used, free | _] = String.split(disk_info)
            %{
            used: used,
            free: free
            }

        _ ->
            %{used: "unknown", free: "unknown"}
        end
    end

    #
    # Convert bytes into human-readable format B, KB, MB, GB
    #
    # ### Parameters:
    #   - bytes: Integer. The number of bytes to convert.
    #
    # ### Returns:
    #   - String. The human-readable format of the byte value (e.g., "1.23 GB").
    #
    defp humanize_bytes(bytes) when bytes >= 1_000_000_000 do
        "#{Float.round(bytes / 1_000_000_000, 2)} GB"
    end

    defp humanize_bytes(bytes) when bytes >= 1_000_000 do
        "#{Float.round(bytes / 1_000_000, 2)} MB"
    end

    defp humanize_bytes(bytes) when bytes >= 1_000 do
        "#{Float.round(bytes / 1_000, 2)} KB"
    end

    defp humanize_bytes(bytes), do: "#{bytes} B"

end
