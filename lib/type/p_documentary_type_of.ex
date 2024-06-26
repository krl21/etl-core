
defprotocol Type.PDocumentaryTypeOf do
    @moduledoc"""
    Protocol for the work of documentaries in NodeService
    """

    @doc"""
    Returns the type of documentary, given the business

    ### Parameter:

        - business: String. Business.

    ### Return:

        - String

    """
    @spec documentary_type_of(atom) :: binary
    def documentary_type_of(business)

end
