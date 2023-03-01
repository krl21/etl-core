
defmodule Time.Timem do
    @moduledoc"""
    It expands functionalities that Timex library does not present
    """

    import Stuff, only: [integer_to_string_with_2_digits: 1]


    #
    # Url where the information of the holidays was extracted
    #     2021 => "https://www.chile.gob.cl/buenos-aires/feriados-2021",
    #     2022 => "https://www.feriados.cl/index.php",
    #     2023 => "https://www.feriados.cl/2023.htm",
    #
    @holidays %{
        2021 => %{
            january:    [1],
            february:   [15, 16],
            march:      [24],
            april:      [2],
            may:        [21, 24, 25],
            june:       [21],
            july:       [9],
            august:     [16],
            september:  [17],
            october:    [8, 11],
            november:   [22],
            december:   [8]
        },
        2022 => %{
            january:    [1],
            february:   [],
            march:      [],
            april:      [15, 16],
            may:        [1, 21],
            june:       [21, 27],
            july:       [16],
            august:     [15],
            september:  [4, 16, 18, 19],
            october:    [10, 31],
            november:   [1],
            december:   [8, 25]
        },
        2023 => %{
            january:    [1, 2],
            february:   [],
            march:      [],
            april:      [7, 8],
            may:        [1, 21],
            june:       [21, 26],
            july:       [16],
            august:     [15],
            september:  [18, 19],
            october:    [9, 27],
            november:   [1],
            december:   [8, 25]
        },

    }



    @doc"""
    Search the time defined in the configuration, for sending notifications

    ### Parameter:

        - info. Map. Information about the time. It is expected to have the format
            ```%{
                day: value_0,
                hours: value_1,
                minute: value_2,
                second: value_3,
            }
            ```
            If no time measurement is found or they are invalid, it will be taken as 0.

    ### Return:

        - Integer. Time in milliseconds. The smallest possible return value is 1000 (1 second).
    """
    def notification_frequency(info) do
        # amount of         hours,                minutes,                 seconds
        (((get_day(info) * 24 + get_hour(info)) * 60 + get_minute(info)) * 60 + get_second(info))
        |> max(1)
        |> Kernel.*(1000)

    end

    defp get_day(%{day: day})
        when is_integer(day) and 0 <= day
        do
            day
    end

    defp get_day(_) do
        0
    end

    defp get_hour(%{hour: hour})
        when is_integer(hour) and 0 <= hour and hour <= 59
        do
            hour
    end

    defp get_hour(_) do
        0
    end

    defp get_minute(%{minute: minute})
        when is_integer(minute) and 0 <= minute and minute <= 59
        do
            minute
    end

    defp get_minute(_) do
        0
    end

    defp get_second(%{second: second})
        when is_integer(second) and 0 <= second and second <= 59
        do
            second
    end

    defp get_second(_) do
        0
    end

    @doc"""
    Determine given the month and day, if it is a holiday

    ### Parameter:

        - date: Timex.DateTime.

    # Return:

        - boolean. True if day is a holiday, false otherwise.

    """
    def is_holiday?(%{year: year, month: month, day: day} = _date) do
        year
        |> get_holidays_of_year()
        |> get_holidays_of_month(month)
        |> Enum.any?(fn elem -> day == elem end)
    end

    #
    # Gets the holidays of the defined year
    #
    # ### Parameter:
    #
    #     - year: Integer. Year.
    #
    # ### Return:
    #
    #     - Map where the keys are the months and the associated value is the list of holidays. If it is null, then the holidays of the defined year are not known.
    #
    defp get_holidays_of_year(year) do
        Map.get(@holidays, year, %{})
    end

    #
    # Returns the list of holidays of the defined month
    #
    # ### Parameters:
    #
    #     - data: Map. Holidays of the year, divided by each month.
    #
    #     - month. Integer | String. Month. It can be identified by a number or name, in Spanish or English.
    #
    # ### Return:
    #
    #     - List.
    #
    defp get_holidays_of_month(data, month) when is_binary(month) do
        month
        |> String.downcase()
        |> case do
            "enero"     ->      get_holidays_of_month(data, 1)
            "january"   ->      get_holidays_of_month(data, 1)

            "febrero"   ->      get_holidays_of_month(data, 2)
            "february"  ->      get_holidays_of_month(data, 2)

            "marzo"     ->      get_holidays_of_month(data, 3)
            "march"     ->      get_holidays_of_month(data, 3)

            "abril"     ->      get_holidays_of_month(data, 4)
            "april"     ->      get_holidays_of_month(data, 4)

            "mayo"      ->      get_holidays_of_month(data, 5)
            "may"       ->      get_holidays_of_month(data, 5)

            "junio"     ->      get_holidays_of_month(data, 6)
            "june"      ->      get_holidays_of_month(data, 6)

            "julio"     ->      get_holidays_of_month(data, 7)
            "july"      ->      get_holidays_of_month(data, 7)

            "agosto"    ->      get_holidays_of_month(data, 8)
            "august"    ->      get_holidays_of_month(data, 8)

            "septiembre" ->     get_holidays_of_month(data, 9)
            "september"  ->     get_holidays_of_month(data, 9)

            "octubre"   ->      get_holidays_of_month(data, 10)
            "october"   ->      get_holidays_of_month(data, 10)

            "noviembre" ->      get_holidays_of_month(data, 11)
            "november"  ->      get_holidays_of_month(data, 11)

            "diciembre" ->      get_holidays_of_month(data, 12)
            "december"  ->      get_holidays_of_month(data, 12)

            _ -> get_holidays_of_month(data, 0)
        end
    end

    defp get_holidays_of_month(data, month) when is_integer(month) do
        month =
            case month do
                1 ->    :january
                2 ->    :february
                3 ->    :march
                4 ->    :april
                5 ->    :may
                6 ->    :june
                7 ->    :july
                8 ->    :august
                9 ->    :september
                10 ->   :october
                11 ->   :november
                12 ->   :december
                _ ->    nil
            end
        Map.get(data, month, [])
    end

    @doc"""
    Returns the current time in YYYY-MM-DDformat

    ### Return:

        - String

    """
    def get_date_with_string_format() do
        %{day: day, month: month, year: year} = Timex.now()
        day = day |> integer_to_string_with_2_digits()
        month = month |> integer_to_string_with_2_digits()
        year = year |> integer_to_string_with_2_digits()

        "#{year}-#{month}-#{day}"
    end

    @doc"""
    Returns the current date in HH:MM:SS format

    ### Return:

        - String

    """
    def get_time_with_string_format() do
        %{hour: hour, minute: minute, second: second} = Timex.now()
        hour = hour |> integer_to_string_with_2_digits()
        minute = minute |> integer_to_string_with_2_digits()
        second = second |> integer_to_string_with_2_digits()

        "#{hour}:#{minute}:#{second}"
    end




end
