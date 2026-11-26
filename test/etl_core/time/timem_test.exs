defmodule Time.TimemTest do
    use ExUnit.Case, async: true

    alias Time.Timem

    describe "notification_frequency/1" do
        test "converts day/hour/minute/second into milliseconds" do
            assert Timem.notification_frequency(%{day: 0, hour: 0, minute: 0, second: 1}) == 1000
            assert Timem.notification_frequency(%{day: 0, hour: 0, minute: 1, second: 0}) == 60_000
            assert Timem.notification_frequency(%{day: 1, hour: 0, minute: 0, second: 0}) == 86_400_000
        end

        test "missing or invalid fields default to 0" do
            assert Timem.notification_frequency(%{}) == 1000
            assert Timem.notification_frequency(%{day: -1, hour: 0, minute: 0, second: 0}) == 1000
        end

        test "the result never goes below 1000ms (1 second floor)" do
            assert Timem.notification_frequency(%{day: 0, hour: 0, minute: 0, second: 0}) == 1000
        end
    end

    describe "is_holiday?/1" do
        test "returns false for an ordinary working day" do
            refute Timem.is_holiday?(%{year: 2024, month: 6, day: 15})
        end

        test "returns false entirely for a year with no known holidays" do
            refute Timem.is_holiday?(%{year: 1899, month: 1, day: 1})
        end

        test "an out-of-range month number is simply treated as no holidays, not an error" do
            refute Timem.is_holiday?(%{year: 2024, month: 13, day: 1})
        end
    end

    describe "by_intervals/3" do
        test "requires a strictly positive step" do
            assert_raise FunctionClauseError, fn ->
                Timem.by_intervals(Timex.now(), Timex.now(), 0)
            end
        end

        test "a valid start date with an invalid end date is reported, not raised" do
            invalid_end = %Date{year: 2024, month: 13, day: 1}
            assert Timem.by_intervals(Timex.now(), invalid_end, 1) == {:error, :invalid_date}
        end

        test "start_date == end_date yields no intervals at all" do
            now = Timex.now()
            assert Timem.by_intervals(now, now, 1) == {:ok, []}
        end

        test "splits a range into consecutive, non-overlapping step-day intervals" do
            start_date = Timex.to_datetime({2024, 1, 1})
            end_date = Timex.to_datetime({2024, 1, 10})

            assert {:ok, intervals} = Timem.by_intervals(start_date, end_date, 3)

            assert length(intervals) == 3
            assert intervals |> List.first() |> elem(0) == start_date
            assert intervals |> List.last() |> elem(1) == end_date

            # Each interval's end is the next interval's start (no gaps/overlaps).
            Enum.chunk_every(intervals, 2, 1, :discard)
            |> Enum.each(fn [{_, prev_end}, {next_start, _}] ->
                assert prev_end == next_start
            end)
        end
    end
end
