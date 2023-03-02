
defprotocol Time.WorkingTimeForBusiness do
    @moduledoc"""
    Module oriented to the specification of each business with its schedules
    """

    @doc"""
    Check if the defined date is a working day

    ### Parameters:

        - date: Timex.DateTime. Date.

        - business: Atom. Business.

    ### Return:

        - Boolean.

    """
    def is_working_day?(date, business)

    @doc"""
    Returns the working hours of a day, given the business

    ### Parameters:

        - date: Timex.DateTime. Date.

        - business: Atom. Business.

    ### Return:

        - {start_time, end_time}, where each element is {hour, minute, second}

    """
    def working_hours(date, business)



end
