
defmodule Decoratorm do
    @moduledoc"""
    Module for the definition of internal decorators to the project
    """

    use Decorator.Define, [retry: 0]


    @doc"""
    Decorator function for retrying the call of the same function with the same parameters. Stops retries when it gets a value other than an exception or when the number of retries exceeds 10.

    ### Parameters:

        - body:

        - context:

    ### Return:

        - t() | Exception

    """
    def retry(body, _context) do
        quote do
            return =
                0
                |> Stream.iterate(&(&1 + 1))
                |> Stream.map(fn n ->
                    try do
                        {n, unquote(body)}
                    rescue
                        error -> {n, error}
                    end
                end)
                |> Stream.take_while(fn {x, _} ->
                    x < 10
                end)
                |> Stream.filter(fn {_, y} ->
                    not is_exception(y)
                end)
                |> Enum.take(1)

            if return == [] do
                unquote(body)
            else
                return
                |> hd()
                |> elem(1)
            end
        end
    end

end
