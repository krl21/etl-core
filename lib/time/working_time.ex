
defmodule Time.WorkingTime do
    @moduledoc"""
    Module oriented to the calculation of working time, according to the business
    """

    alias Type.Type
    import Time.WorkingTimeForBusiness

    @doc"""
    Calculates the working time elapsed between two dates. Depending on the business, hours vary.

    To add a new business and its particular hours, you must:
        1. Define a module with the name of the business.
        2. Implement the Time.WorkingTimeForBusiness protocol, to define particular hours. Use the following template:

        ```
        define Time.WorkingTimeForBusiness, for: Atom do
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

        - change_timezone: Boolean. Indicate if you have to change the dates to the time use defined in the configuration.

    ### Return:

        - {:ok, integer} | {:error, string}

    """
    def elapsed_time(start_date, end_date, business, change_timezone \\ true)

    def elapsed_time(start_date, end_date, _business, _change_timezone)
        when is_nil(start_date) or is_nil(end_date)
        do
            {:error, "One of the dates has null value. Start date: #{start_date}. End date: #{end_date}."}
    end

    def elapsed_time(start_date, end_date, business, change_timezone)
        when is_binary(start_date) or is_binary(end_date)
        do
            start_date = if is_binary(start_date) do
                Type.convert(start_date, :DateTime)
            else
                start_date
            end

            end_date = if is_binary(end_date) do
                Type.convert(end_date, :DateTime)
            else
                end_date
            end

            elapsed_time(start_date, end_date, business, change_timezone)
    end

    def elapsed_time(start_date, end_date, business, change_timezone)
        when business in [:new_vehicles, :credit_course] do

            if not Timex.is_valid?(start_date) do
                {:error, "Not valid init date #{inspect start_date}"}

            else if not Timex.is_valid?(end_date) do
                {:error, "Not valid end date #{inspect end_date}"}

            else if Timex.diff(end_date, start_date, :seconds) < 0 do
                {:error, "Start date #{inspect start_date} is later than end date #{inspect end_date}"}

            else
                start_date = convert_to_business_hours(start_date, business, change_timezone)
                end_date = convert_to_business_hours(end_date, business, change_timezone)

                result = Timex.diff(end_date, start_date, :seconds) - get_non_working_time(start_date, end_date, business)
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
    # ### Returns:
    #
    #     - Integer
    #
    defp get_non_working_time(%{year: year, month: month, day: day}, %{year: year, month: month, day: day}, _business) do
        0
    end

    defp get_non_working_time(start_date, end_date, business) do
        tomorrow = Timex.shift(start_date, days: 1)
        {{start_hour, start_minute, start_second}, {end_hour, end_minute, end_second}} = working_hours(start_date, business)

        # It is assumed that the start time is the same for all work days
        if not is_working_day?(tomorrow, business) do
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
        |> Kernel.+(get_non_working_time(tomorrow, end_date, business))
    end

    #
    # Given a date, it returns the next date such that it is skilled in the defined working hours. Can return the same date.
    #
    # ### Parameter:
    #
    #     - date: DateTime. Date.
    #
    #     - business: Atom. Business.
    #
    #     - change_timezone: Boolean. Indicate if you have to change the dates to the time use defined in the configuration.
    #
    # ### Return:
    #
    #     - DateTime
    #
    defp convert_to_business_hours(date, business, true) do
        date
        |> Timex.Timezone.convert(Application.get_env(:data_pipeline_bigquery, :timezone))
        |> convert_to_business_hours(business, false)
    end

    defp convert_to_business_hours(%{hour: hour, minute: minute, second: seconds} = date, business, false) do
        is_working_hours = is_working_hours?(date, business)
        is_working_day = is_working_day?(date, business)

        {{start_hour, start_minute, start_second} = start_time, _} = working_hours(date, business)

        case {is_working_day, is_working_hours} do
            {false, _} ->
                date
                |> next_working_day(business)
                |> Timex.set([hour: start_hour, minute: start_minute, second: start_second, microsecond: 0])

            {true, false} ->
                if {0, 0, 0} <= {hour, minute, seconds} and {hour, minute, seconds} <= start_time do
                    date

                else
                    date
                    |> next_working_day(business)
                end
                |> Timex.set([hour: start_hour, minute: start_minute, second: start_second, microsecond: 0])

            {true, true} ->
                date
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
    # ### Return:
    #
    #     - Timex.DateTime
    #
    defp next_working_day(date, business) do
        tomorrow = Timex.shift(date, days: 1)
        if is_working_day?(tomorrow, business) do
            tomorrow
        else
            next_working_day(tomorrow, business)
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
    #  ### Return:
    #
    #     - Boolean.
    #
    defp is_working_hours?(%{hour: hour, minute: minute, second: second} = date, business) do
        {start_time, end_time} = working_hours(date, business)
        start_time <= {hour, minute, second} and {hour, minute, second} <= end_time
    end







end

"""
Possible values:

:new_vehicles
    - Aimed at the New Vehicles business
    - Business days: Monday to Friday, not holidays
    - Business hours: 9:00 - 18:00

:credit_course
    - Aimed at the Credit Course business
    - Working days (usual): from Monday to Friday, not holidays
    - Business hours (usual): 8:15 to 18:00
    - The last 2 days of the month are worked from 8:15 to 21:00; if it falls on a Sunday or a holiday, then the hours are 8:15 to 16:00

"""
