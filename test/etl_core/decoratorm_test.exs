defmodule DecoratormTest do
    use ExUnit.Case, async: false

    defmodule Fixture do
        @moduledoc false
        use Decoratorm

        @decorate retry()
        def call(agent) do
            attempt = Agent.get_and_update(agent, fn %{n: n} = s -> {n, %{s | n: n + 1}} end)
            fail_until = Agent.get(agent, & &1.fail_until)

            if attempt < fail_until do
                raise "attempt #{attempt} fails"
            else
                {:ok, attempt}
            end
        end
    end

    defp start_counter(fail_until) do
        {:ok, agent} = Agent.start_link(fn -> %{n: 0, fail_until: fail_until} end)
        agent
    end

    test "succeeds on the first try when the wrapped call doesn't raise" do
        agent = start_counter(0)
        assert Fixture.call(agent) == {:ok, 0}
    end

    test "retries until the wrapped call stops raising, within the retry budget" do
        agent = start_counter(3)
        assert Fixture.call(agent) == {:ok, 3}
    end

    test "if every attempt (including the final, un-caught one) raises, the exception propagates" do
        agent = start_counter(999)
        assert_raise RuntimeError, fn -> Fixture.call(agent) end
    end
end
