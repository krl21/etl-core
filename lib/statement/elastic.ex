
defmodule Statement.Elastic do
    @moduledoc"""
    Module oriented to the creation of queries to Elastic
    """

    @doc"""
    Returns the most generic query possible: all nodes with their indexed terms

    ### Parameter:

        - size: Integer. Number of records to return.

    ### Return:

        - String

    """
    def build_query(size)
        when is_integer(size) and size >=0 do
            """
            {
                "query": {
                  "match_all": {}
                },
                "size": #{size}
            }
            """
    end

    @doc"""
    Returns a query, where it is defined to return only an indexed field, filters those such that the field deleted=false and a certain field is in a range

    ### Parameters:

        - index_to_return: String. Indexed field that will only contain the response.

        - index_for_range: String. indexed field that will be used to establish a search range.

        - lower_bound: String. Lower bound of the range.

        - upper_bound: String. Upper bound of the range.

        - from: Integer. Position, after obtaining the ordered response, by which the values to be displayed will begin to be taken.

        - size: Integer. Amount of values to take, after the defined position.

    ### Return:

        - String

    """
    def build_query(index_to_return, index_for_range, lower_bound, upper_bound, from \\ 0, size \\ 100)
        when is_binary(index_to_return) and is_binary(index_for_range) and
            is_binary(lower_bound) and is_binary(upper_bound) and
            is_integer(from) and is_integer(size) and
            from >= 0 and size > 0 do
        """
        {
            "_source": ["#{index_to_return}"],
            "query":{
                "bool": {
                    "must": [
                        {
                            "range": {
                                "#{index_for_range}": {
                                    "gte": "#{lower_bound}",
                                    "lte": "#{upper_bound}"
                                }
                            }
                        },
                        {
                            "bool": {
                                "must_not": [
                                    {
                                        "term": {
                                            "deleted": true
                                        }
                                    }
                                ]
                            }
                        }
                    ]
                }
            },
            "from": #{from},
            "size": #{size}
        }
        """
    end

    @doc"""
    Returns a query that will be used within another. Particular case for the New Vehicles service

    ### Parameters:

        - index_for_range: String. indexed field that will be used to establish a search range.

        - lower_bound: String. Lower bound of the range.

        - upper_bound: String. Upper bound of the range.

    ### Return:

        - String

    """
    def build_query_inside(index_for_range, lower_bound, upper_bound)
        when is_binary(index_for_range) and is_binary(lower_bound) and
            is_binary(upper_bound) do
        """
            {
                "bool": {
                    "must": [
                        {
                            "range": {
                                "#{index_for_range}": {
                                    "gte": "#{lower_bound}",
                                    "lte": "#{upper_bound}"
                                }
                            }
                        },
                        {
                            "bool": {
                                "must_not": [
                                    {
                                        "term": {
                                            "deleted": true
                                        }
                                    }
                                ]
                            }
                        }
                    ]
                }
            }
        """
    end




end
