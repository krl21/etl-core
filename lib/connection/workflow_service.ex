
defmodule Connection.WorkflowService do
    @moduledoc"""
    Work with Workflow Service
    """

    import Connection.Http, only: [get: 2]


    @doc"""
    Returns the tasks associated with a record

    ### Parameter:

        - url: String. URL of the service. It is assumed that the url contains 3 parameters to replace them: <type_documentary>, <contentref>, <ticket>.

        - headers: List.

        - type_documentary: String. Associated documentary type.

        - contentref: String. Node/document identifier.

        - ticket: String: Ticket.

    ### Return:

        -  {:ok, details} | {:error, message} | Exception

    """
    def get_details(url, headers, type_documentary, contentref, ticket)
        when is_binary(url) and is_list(headers) and
            is_binary(type_documentary) and is_binary(contentref) and
            is_binary(ticket) do

            url
            |> String.replace("<type_documentary>", type_documentary)
            |> String.replace("<contentref>", contentref)
            |> String.replace("<ticket>", ticket)
            |> get(headers)
            |> case do
                {:error, _error} = error ->
                    error

                {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
                    #    %{"success" => false, "response" => responde}} ->
                    body
                    |> Poison.decode()
                    |> case do
                        {:error, error} ->
                            {:error, error}

                        {:ok, %{"success" => false, "response" => responde}} when status_code == 200 ->
                            {:error, responde}

                        {:ok, %{"success" => true, "response" => %{"workflow_details" => workflow_details}}} when status_code == 200 ->
                            {:ok, workflow_details}

                        {:ok, body} ->
                            {:error, body}
                    end
            end
    end


end
