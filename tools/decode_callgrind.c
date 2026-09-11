#include <valgrind/callgrind.h>
void profile_begin(void) { CALLGRIND_START_INSTRUMENTATION; CALLGRIND_ZERO_STATS; }
void profile_end(void) { CALLGRIND_DUMP_STATS; CALLGRIND_STOP_INSTRUMENTATION; }
