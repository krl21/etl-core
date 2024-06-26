
defmodule Time.WorkingTime do
    @moduledoc"""
    Module oriented to the calculation of working time, according to the business
    """

    alias Type.Type
    import Time.PWorkingTimeForBusiness

    @doc"""
    Calculates the working time elapsed between two dates. Depending on the business, hours vary.

    To add a new business and its particular hours, you must:
        1. Define a module with the name of the business.
        2. Implement the Time.PWorkingTimeForBusiness protocol, to define particular hours. Use the following template:

        ```
        define Time.PWorkingTimeForBusiness, for: Atom do
            def function_name(date, <business_name>) do
                ...
            end

            ...

        end
        ```

    ### Parameter:

        - start_date: Timex.DateTime or String. Start date.

        - end_date: Timex.DateTime or String. End date.

        - business: Atom. Business.

        - params: t. Auxiliary parameters.

        - change_timezone: Boolean. Indicate if you have to change the dates to the time use defined in the configuration.

    ### Return:

        - {:ok, Integer (seconds)} | {:error, String}

    """
    def elapsed_time(start_date, end_date, business, params, change_timezone \\ true)

    def elapsed_time(start_date, end_date, _business, _params, _change_timezone)
        when is_nil(start_date) or is_nil(end_date)
        do
            {:error, "One of the dates has null value. Start date: #{start_date}. End date: #{end_date}."}
    end

    def elapsed_time(start_date, end_date, business, params, change_timezone)
        when
            (is_binary(start_date) and start_date != "") or
            (is_binary(end_date) and end_date != "")
        do
            start_date = try do
                    Type.convert(start_date, :DateTime)
                rescue
                    _ -> start_date
                end

            end_date = try do
                    Type.convert(end_date, :DateTime)
                rescue
                    _ -> end_date
                end

            elapsed_timep(start_date, end_date, business, params, change_timezone)
    end

    def elapsed_time(start_date, end_date, business, params, change_timezone) do
        elapsed_timep(start_date, end_date, business, params, change_timezone)
    end

    defp elapsed_timep(start_date, end_date, business, params, change_timezone) do
        if not Timex.is_valid?(start_date) do
            {:error, "Not valid init date #{inspect start_date}"}

        else if not Timex.is_valid?(end_date) do
            {:error, "Not valid end date #{inspect end_date}"}

        else if Timex.diff(end_date, start_date, :seconds) < 0 do
            {:error, "Start date #{inspect start_date} is later than end date #{inspect end_date}"}

        else
            start_date = convert_to_business_datetime(start_date, business, params, change_timezone)
            end_date = convert_to_business_datetime(end_date, business, params, change_timezone)

            result = Timex.diff(end_date, start_date, :seconds) - get_non_working_time(start_date, end_date, business, params)
            {:ok, result}
        end end end
    end

    #
    # Calculate the non-labor time between two dates, in seconds
    #
    # ### Parameters:
    #
    #     - start_date: Timex.DateTime. Start date.
    #
    #     - end_date: Timex.DateTime. End date.
    #
    #     - business: Atom. Business.
    #
    #     - params: t. Auxiliary parameters.
    #
    # ### Returns:
    #
    #     - Integer
    #
    defp get_non_working_time(%{year: year, month: month, day: day}, %{year: year, month: month, day: day}, _business, _params) do
        0
    end

    defp get_non_working_time(%{year: year, month: month, day: day}, %{year: year, month: month, day: day}, _business, _params, %{year: year, month: month, day: day}) do
        0
    end

    defp get_non_working_time(start_date, end_date, business, params) do
        get_non_working_time(start_date, end_date, business, params, start_date)
    end

    defp get_non_working_time(start_date, end_date, business, params, last_working_start_date) do
        tomorrow = Timex.shift(start_date, days: 1)
        {_, {end_hour, end_minute, end_second}} = working_hours(last_working_start_date, business, params)
        {{start_hour, start_minute, start_second}, _} = working_hours(end_date, business, params)

        # It is assumed that the start time is the same for all work days
        if not is_working_day?(tomorrow, business, params) do
            # time in seconds from the starting time, until the same time of next day
            24 * 3_600
        else
            # time in seconds between end_hour:00 and start_hour:00 next day
            rem(start_hour - end_hour + 24, 24) * 3_600 -
            # time in seconds of the shift of the initial time, which was assumed it is more
            end_minute * 60 - end_second +
            # time in seconds of the racing of the final hour, which was assumed it is less
            start_minute * 60 + start_second
        end
        |> Kernel.+(get_non_working_time(
            tomorrow,
            end_date,
            business,
            params,
            if is_working_day?(tomorrow, business, params) do
                tomorrow
            else
                last_working_start_date
            end
            )
        )
    end

    @doc """
    Given a date, it returns the next date such that it is skilled in the defined working hours. Can return the same date.

    ### Parameter:

        - date: DateTime. Date.

        - business: Atom. Business.

        - params: t. Auxiliary parameters.

        - change_timezone: Boolean. Indicate if you have to change the dates to the time use defined in the configuration.

    ### Return:

        - DateTime
    """
    def convert_to_business_datetime(date, business, params, true) do
        date
        |> Timex.Timezone.convert("America/Santiago")
        |> convert_to_business_datetime(business, params, false)
    end

    def convert_to_business_datetime(%{hour: hour, minute: minute, second: seconds} = date, business, params, false) do
        is_working_hours = is_working_hours?(date, business, params)
        is_working_day = is_working_day?(date, business, params)

        {start_time, _} = date |> working_hours(business, params)

        new_date =
            case {is_working_day, is_working_hours} do
                {false, _} ->
                    date
                    |> next_working_day(business, params)

                {true, false} ->
                    if {0, 0, 0} <= {hour, minute, seconds} and {hour, minute, seconds} <= start_time do
                        date

                    else
                        date
                        |> next_working_day(business, params)
                    end

                {true, true} ->
                    date
            end

        if not(is_working_day and is_working_hours) do
            {{start_hour, start_minute, start_second}, _} =
                new_date
                |> working_hours(business, params)

            new_date
            |> Timex.set([hour: start_hour, minute: start_minute, second: start_second, microsecond: 0])

        else
            new_date
        end
    end

    #
    # Returns the closest business day after the defined date
    #
    # ### Parameters:
    #
    #     - date: Timex.DateTime. Date.
    #
    #     - business: Atom. Business.
    #
    #     - params: t. Auxiliary parameters.
    #
    # ### Return:
    #
    #     - Timex.DateTime
    #
    defp next_working_day(date, business, params) do
        # try do para el caso de que existe un desplazamiento de una fecha, sobre un cambio de uso de horario
        tomorrow =
            try do
                tmp =
                    date
                    |> Timex.shift(days: 1)
                    |> Map.get(:after) # si no da error es por temp es del tipo AmbiguosDateTime

                # si es true es xq el día anterior fue del tipo AmbiguosDateTime, pero el actual es de tipo DateTime, por lo que tiene que calcularse con normalidad
                if is_nil(tmp) do
                    raise("")
                else
                    tmp
                end
            rescue
                _ -> Timex.shift(date, days: 1)
            end

        if is_working_day?(tomorrow, business, params) do
            tomorrow
        else
            next_working_day(tomorrow, business, params)
        end
    end

    #
    # Check if the defined date is a working hours
    #
    # ### Parameter:
    #
    #     - date: Timex.DateTime. Date.
    #
    #     - business: Atom. Business.
    #
    #     - params: t. Auxiliary parameters.
    #
    #  ### Return:
    #
    #     - Boolean.
    #
    defp is_working_hours?(%{hour: hour, minute: minute, second: second} = date, business, params) do
        {start_time, end_time} = working_hours(date, business, params)
        start_time <= {hour, minute, second} and {hour, minute, second} <= end_time
    end







end
