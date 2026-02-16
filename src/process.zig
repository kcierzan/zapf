const std = @import("std");
const t = std.testing;
const events = @import("events.zig");

pub const ProcessResult = enum {
    @"error",
    @"continue",
    continue_if_not_quiet,
    tail,
    sleep,
};

pub fn ProcessContext(comptime EventIter: type) type {
    if (!events.isEventIterator(EventIter)) {
        @compileError("ProcessContext requires an event iterator type with " ++
            "'pub fn next(self: *Self) ?PluginEvent' and " ++
            "'pub fn reset(self: *Self) void' got " ++ @typeName(EventIter));
    }

    return struct {
        /// Input audio buffers: input[channel][sample]
        input: []const []const f32,
        /// Output audio buffers: output[channel][sample]
        output: [][]f32,
        /// the length of the input buffer across all channels in samples
        /// this value in controlled by the host and is typically between
        /// 64 and 2048 samples depending on the host's buffer size.
        /// for clap at least, we can declare the bound in the `min_frames` /
        /// `max_frames` declarations that occur in `activate`.
        frame_count: u32,
        /// sample rate in Hz
        sample_rate: f64,
        /// monotonically increasing steady-state time in samples
        steady_time: i64,
        /// Iterator over input events populated by the adapter
        events: EventIter,
    };
}

test "ProcessContext can be instantiated with SliceEventIterator" {
    const Ctx = ProcessContext(events.SliceEventIterator);
    const ctx = Ctx{
        .input = &.{},
        .output = &.{},
        .frame_count = 0,
        .sample_rate = 44100.0,
        .steady_time = 0,
        .events = events.SliceEventIterator.empty,
    };
    _ = ctx;
}
