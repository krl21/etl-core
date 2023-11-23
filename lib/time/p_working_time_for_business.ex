
defprotocol Time.PWorkingTimeForBusiness do
    @moduledoc"""
    Module oriented to the specification of each business with its schedules
    """

    @doc"""
    Check if the defined date is a working day

    ### Parameters:

        - date: Timex.DateTime. Date.

        - business: Atom. Business.

        - params: t. Auxiliary parameters.

    ### Return:

        - Boolean.

    """
    def is_working_day?(date, business, params)

    @doc"""
    Returns the working hours of a day, given the business

    ### Parameters:

        - date: Timex.DateTime. Date.

        - business: Atom. Business.

        - params: t. Auxiliary parameters.

    ### Return:

        - {start_time, end_time}, where each element is {hour, minute, second}

    """
    def working_hours(date, business, params)



end
