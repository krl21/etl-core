defmodule Time.WorkingTimeTest do
    use ExUnit.Case, async: true

    alias Time.WorkingTime

    # `Time.PWorkingTimeForBusiness.is_working_day?/working_hours` dispatch on
    # their FIRST argument (`date`), not on `business` — so the impl has to be
    # `for: DateTime` (the type every date in this test actually is), pattern-matching
    # on `business` as the second argument. No implementation of this protocol
    # exists anywhere in etl-core itself (confirmed).
    defimpl Time.PWorkingTimeForBusiness, for: DateTime do
        def is_working_day?(date, :test_business, _params), do: Timex.weekday(date) in 1..5
        def working_hours(_date, :test_business, _params), do: {{9, 0, 0}, {18, 0, 0}}
    end

    describe "elapsed_time/5 — error paths" do
        test "either date being nil is an error, not a crash" do
            assert {:error, _} = WorkingTime.elapsed_time(nil, Timex.now(), :test_business, nil)
            assert {:error, _} = WorkingTime.elapsed_time(Timex.now(), nil, :test_business, nil)
        end

        test "an invalid date is an error" do
            invalid = %Date{year: 2024, month: 13, day: 1}
            assert {:error, msg} = WorkingTime.elapsed_time(invalid, Timex.now(), :test_business, nil, false)
            assert msg =~ "Not valid init date"
        end

        test "a start date after the end date is an error" do
            start_date = Timex.to_datetime({{2024, 1, 10}, {10, 0, 0}})
            end_date = Timex.to_datetime({{2024, 1, 1}, {10, 0, 0}})

            assert {:error, msg} = WorkingTime.elapsed_time(start_date, end_date, :test_business, nil, false)
            assert msg =~ "is later than end date"
        end
    end

    describe "elapsed_time/5 — happy path" do
        test "same working day, both within working hours: elapsed time is the plain difference" do
            # 2024-01-08 is a Monday.
            start_date = Timex.to_datetime({{2024, 1, 8}, {10, 0, 0}})
            end_date = Timex.to_datetime({{2024, 1, 8}, {14, 0, 0}})

            assert WorkingTime.elapsed_time(start_date, end_date, :test_business, nil, false) == {:ok, 4 * 3600}
        end
    end
end
