
defprotocol Time.WorkingTimeForBusiness do
    @moduledoc"""
    Module oriented to the specification of each business with its schedules
    """

    @doc"""
    Check if the defined date is a working day

    ### Parameter:

        - date: Timex.DateTime. Date.

    ### Return:

        - Boolean.

    """
    def is_working_day?(date)

    @doc"""
    Check if the defined date is a working hours

    ### Parameter:

        - date: Timex.DateTime. Date.

     ### Return:

        - Boolean.

    """
    def is_working_hours?(date)

    @doc"""
    Returns the working hours of a day, given the business

    ### Parameter:

        - date: Timex.DateTime. Date.

    ### Return:

        - {start_time, end_time}, where each element is {hour, minute, second}

    """
    def working_hours(date)

    @doc"""
    Returns the closest business day after the defined date

    ### Parameter:

        - date: Timex.DateTime. Date.

    ### Return:

        - Timex.DateTime

    """
    def next_working_day(date)


end
