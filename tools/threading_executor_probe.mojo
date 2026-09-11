"""Check the installed MAX executor's per-call concurrency limit on Linux."""
from std.ffi import external_call
from std.time import perf_counter_ns
from std.testing import assert_equal
from max.algorithm import parallelize


def main() raises:
    for workers in [1, 2, 4, 8]:
        var starts = List[Int](length=64, fill=0)
        var ends = List[Int](length=64, fill=0)
        var start_ptr = starts.unsafe_ptr()
        var end_ptr = ends.unsafe_ptr()

        def work(i: Int) {start_ptr, end_ptr}:
            start_ptr[unsafe_offset=i] = Int(perf_counter_ns())
            _ = external_call["usleep", Int32](UInt32(1000))
            end_ptr[unsafe_offset=i] = Int(perf_counter_ns())

        parallelize(work, 64, workers)
        var maximum = 0
        for i in range(64):
            var active = 0
            for j in range(64):
                if starts[j] <= starts[i] and ends[j] > starts[i]:
                    active += 1
            maximum = max(maximum, active)
        assert_equal(maximum <= workers, True)
        assert_equal(maximum > 0, True)
        print(workers, maximum)
