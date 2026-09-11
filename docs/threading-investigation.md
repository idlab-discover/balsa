# Parallel validation investigation: closed

The investigation against `737874f` led to MAX-based validation in `06ee661`.
See [the implementation decision](threading-results.md) and the
[performance wrap-up](performance-plan.md) for the subsequent work.

An isolated C++ thread-pool prototype reached 3.6–3.7× faster validation with
eight workers on two 100,020-node forests. That experiment used warm persistent
pools and repeated 15-node trees; it established potential, not the performance
of a supported Mojo executor or general end-to-end loading speed.

The implementation path was completed: evaluate MAX's CPU executor, balance
contiguous batches by nodes, reuse private scratch, preserve deterministic
serial errors, measure cold dispatch and concurrent callers, then choose
activation thresholds. Production adopted four workers, at least 4,096 trees
and 65,536 nodes, and a guard against one tree holding over half the work.

The C++ pool was not retained. Eight workers were not adopted as the default;
small and uneven workloads showed scheduling variability. Parallel encoding
showed about 2× prototype potential but was deferred, and parsing stayed serial.

MAX's package and runtime costs were accepted after its own measurements showed
substantive validation and encode gains. The detailed crossover, packaging and
verification conclusions are summarized in the results document. Prototype
artifacts remain in ignored `benchmarking/threading-investigation/`.
