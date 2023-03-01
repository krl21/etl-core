
defprotocol Type.Documentary do
    @moduledoc"""
    Module for the work of documentaries in NodeService

    """

    @doc"""
    Returns the type of documentary, given the business

    ### Parameter:

        - business: String. Business.

    ### Return:

        - String

    """
    def type_documentary(business)

end
