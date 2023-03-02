
defmodule Connection.Http do
    @moduledoc"""
    Module for working with the HTTP protocol
    """


    @doc"""
    POST request

    ### Parameters:

        - body: String.

        - url: String.

        - headers: List of tuple.

        - recv_timeout: Integer.

    ### Return:

        - {:ok, data} | {:error, data}

    """
    def post(body, url, headers, recv_timeout \\ 15000)
        when is_binary(body) and is_binary(url) and
            is_list(headers) and is_integer(recv_timeout) do
            HTTPoison.post(
                url,
                body,
                headers,
                recv_timeout: recv_timeout
            )
    end

    @doc"""
    GET request

    ### Parameters:

        - body: Map.

        - url: String.

        - headers: List of tuple.

        - timeout: Integer.

        - recv_timeout: Integer.

    ### Return:

        - {:ok, data} | {:error, data}

    """
    def get(url, headers \\ [{"Accept", "application/json"}], timeout \\ 15000, recv_timeout \\ 15000)
        when is_binary(url) and is_list(headers) and
            is_integer(timeout) and is_integer(recv_timeout) do
            HTTPoison.get(
                url,
                headers,
                timeout: timeout,
                recv_timeout: recv_timeout
            )
    end


end
