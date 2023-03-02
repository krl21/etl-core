
defmodule Connection.NodeService do
    @moduledoc"""
    Work with Node Service
    """

    alias Connection.Ticket
    alias Connection.Http

    #todo: obtener los detalles usando llamados a los genservers de node_service

    @doc"""
    Returns details of a node

    ### Parameter:

        - node: String. Node/document identifier.

        - url: String. URL of the service. It is assumed that the url contains 2 parameters to replace them: <unique_id>, <ticket>.

        - node: String. Node/document identifier.

        - headers

        - username: String. Username required to generate a ticket.

        - password: String. Password required to generate a ticket.

    ### Return:

        -  {:ok, details} | {:error, message} | Exception

    """
    def get_details(node, url, headers, {url_ticket, headers_ticket, username, password})
        when is_binary(node) and is_binary(url) and
            is_list(headers) and is_binary(url_ticket) and
            is_binary(username) and is_binary(password) do

        Ticket.get(
            url_ticket,
            headers_ticket,
            username,
            password
        )
        |> case do
            {:error, error} ->
                {:error, error}

            {:ok, ticket} ->
                url
                |> String.replace("<unique_id>", node)
                |> String.replace("<ticket>", ticket)
                |> Http.get(headers)
                |> case do
                    {:error, error} ->
                        {:error, error}

                    {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
                        Poison.decode(body)
                        |> case do
                            {:error, error} ->
                                {:error, error}

                            {:ok, body} when status_code == 200 ->
                                {:ok, body}

                            {:ok, body} ->
                                {:error, body}
                        end
                end
        end
    end



end
