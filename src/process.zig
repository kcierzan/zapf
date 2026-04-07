const std = @import("std");
const t = std.testing;

const audio = @import("audio.zig");
const events = @import("events.zig");
const params_mod = @import("params.zig");

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

pub fn processWithSplitting(
    comptime PluginType: type,
    plugin: *PluginType,
    input: []const []const f32,
    output: [][]f32,
    frame_count: u32,
    sample_rate: f64,
    steady_time: i64,
    param_changes: []const params_mod.ParamChangeEvent,
    event_iter: anytype,
) ProcessResult {
    const EventIter = @TypeOf(event_iter);
    const SubIter = events.SubBlockEventIterator(EventIter);
    const Ctx = ProcessContext(SubIter);

    // Fast path: no param changes, process the full buffer in one call
    if (param_changes.len == 0) {
        const sub_iter = SubIter{
            .inner = event_iter,
            .block_start = 0,
            .block_end = frame_count,
        };
        var ctx = Ctx{
            .input = input,
            .output = output,
            .frame_count = frame_count,
            .sample_rate = sample_rate,
            .steady_time = steady_time,
            .events = sub_iter,
        };
        return plugin.process(&ctx);
    }

    // Build deduplicated split points from param change timestamps
    var splits: [max_splits]u32 = undefined;
    var num_splits: usize = 0;

    for (param_changes) |pc| {
        if (pc.time > 0 and pc.time < frame_count) {
            if (num_splits == 0 or splits[num_splits - 1] != pc.time) {
                if (num_splits < max_splits) {
                    splits[num_splits] = pc.time;
                    num_splits += 1;
                }
            }
        }
    }

    // Build block boundaries: [0, split0, split1, ..., frame_count]
    var boundaries: [max_splits + 2]u32 = undefined;
    boundaries[0] = 0;
    for (0..num_splits) |i| {
        boundaries[i + 1] = splits[i];
    }
    boundaries[num_splits + 1] = frame_count;
    const num_blocks = num_splits + 1;

    var sub_iter = SubIter{
        .inner = event_iter,
        .block_start = 0,
        .block_end = 0,
    };

    var result: ProcessResult = .@"continue";
    var param_idx: usize = 0;

    for (0..num_blocks) |block_i| {
        const block_start = boundaries[block_i];
        const block_end = boundaries[block_i + 1];
        const block_len = block_end - block_start;

        if (block_len == 0) continue;

        // Apply all param changes at this block's start offset
        while (param_idx < param_changes.len and param_changes[param_idx].time <= block_start) {
            params_mod.applyParamChange(
                @TypeOf(plugin.params),
                &plugin.params,
                param_changes[param_idx],
            );
            param_idx += 1;
        }

        // Sub-slice input buffers
        var in_slices: [audio.max_channels][]const f32 = undefined;
        for (0..input.len) |ch| {
            in_slices[ch] = input[ch][block_start..block_end];
        }

        // Sub-slice output buffers
        var out_slices: [audio.max_channels][]f32 = undefined;
        for (0..output.len) |ch| {
            out_slices[ch] = output[ch][block_start..block_end];
        }

        sub_iter.setBlock(block_start, block_end);

        var ctx = Ctx{
            .input = in_slices[0..input.len],
            .output = out_slices[0..output.len],
            .frame_count = block_len,
            .sample_rate = sample_rate,
            .steady_time = steady_time + @as(i64, @intCast(block_start)),
            .events = sub_iter,
        };

        const block_result = plugin.process(&ctx);
        result = worstResult(result, block_result);

        // Preserve iterator state (including peeked event) for next block
        sub_iter = ctx.events;
    }

    // Apply any remaining param changes (e.g. at frame_count)
    while (param_idx < param_changes.len) {
        params_mod.applyParamChange(
            @TypeOf(plugin.params),
            &plugin.params,
            param_changes[param_idx],
        );
        param_idx += 1;
    }

    return result;
}

const max_splits = 512;

fn worstResult(a: ProcessResult, b: ProcessResult) ProcessResult {
    const a_val = @intFromEnum(a);
    const b_val = @intFromEnum(b);
    return @enumFromInt(@min(a_val, b_val));
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

test "worstResult picks the lower-priority result" {
    try t.expectEqual(worstResult(.@"continue", .sleep), .@"continue");
    try t.expectEqual(worstResult(.@"error", .@"continue"), .@"error");
    try t.expectEqual(worstResult(.tail, .tail), .tail);
}

const SplitTestPlugin = struct {
    params: Params = .{},
    call_count: u32 = 0,
    frame_counts: [16]u32 = undefined,
    gain_at_call: [16]f32 = undefined,

    const Params = struct {
        gain: params_mod.Float(.{
            .name = "Gain",
            .min = 0.0,
            .max = 1.0,
            .default = 0.5,
            .flags = .{ .automatable = true },
        }) = .{},
    };

    pub fn process(self: *SplitTestPlugin, ctx: anytype) ProcessResult {
        if (self.call_count < 16) {
            self.frame_counts[self.call_count] = ctx.frame_count;
            self.gain_at_call[self.call_count] = self.params.gain.get();
        }
        self.call_count += 1;
        return .@"continue";
    }
};

test "processWithSplitting: no param changes calls process once with full buffer" {
    var plugin = SplitTestPlugin{};
    var in_data = [_]f32{0} ** 128;
    var out_data = [_]f32{0} ** 128;
    var in_slice = [_][]const f32{&in_data};
    var out_slice = [_][]f32{&out_data};

    const result = processWithSplitting(
        SplitTestPlugin,
        &plugin,
        &in_slice,
        &out_slice,
        128,
        44100.0,
        0,
        &.{},
        events.SliceEventIterator.empty,
    );

    try t.expectEqual(result, .@"continue");
    try t.expectEqual(@as(u32, 1), plugin.call_count);
    try t.expectEqual(@as(u32, 128), plugin.frame_counts[0]);
}

test "processWithSplitting: one param change at sample 64 splits into two blocks" {
    var plugin = SplitTestPlugin{};
    var in_data = [_]f32{0} ** 128;
    var out_data = [_]f32{0} ** 128;
    var in_slice = [_][]const f32{&in_data};
    var out_slice = [_][]f32{&out_data};

    const gain_id = comptime params_mod.hashFieldName("gain");
    const changes = [_]params_mod.ParamChangeEvent{
        .{ .time = 64, .param_id = gain_id, .value = 0.8 },
    };

    const result = processWithSplitting(
        SplitTestPlugin,
        &plugin,
        &in_slice,
        &out_slice,
        128,
        44100.0,
        0,
        &changes,
        events.SliceEventIterator.empty,
    );

    try t.expectEqual(result, .@"continue");
    try t.expectEqual(@as(u32, 2), plugin.call_count);
    try t.expectEqual(@as(u32, 64), plugin.frame_counts[0]);
    try t.expectEqual(@as(u32, 64), plugin.frame_counts[1]);
    // First block uses default gain (0.5), second uses new gain (0.8)
    try t.expectEqual(@as(f32, 0.5), plugin.gain_at_call[0]);
    try t.expectEqual(@as(f32, 0.8), plugin.gain_at_call[1]);
}

test "processWithSplitting: param change at sample 0 applies before first block" {
    var plugin = SplitTestPlugin{};
    var in_data = [_]f32{0} ** 128;
    var out_data = [_]f32{0} ** 128;
    var in_slice = [_][]const f32{&in_data};
    var out_slice = [_][]f32{&out_data};

    const gain_id = comptime params_mod.hashFieldName("gain");
    const changes = [_]params_mod.ParamChangeEvent{
        .{ .time = 0, .param_id = gain_id, .value = 0.9 },
    };

    _ = processWithSplitting(
        SplitTestPlugin,
        &plugin,
        &in_slice,
        &out_slice,
        128,
        44100.0,
        0,
        &changes,
        events.SliceEventIterator.empty,
    );

    // Only one block since time=0 doesn't create a split
    try t.expectEqual(@as(u32, 1), plugin.call_count);
    try t.expectEqual(@as(u32, 128), plugin.frame_counts[0]);
    // Param applied before first block
    try t.expectEqual(@as(f32, 0.9), plugin.gain_at_call[0]);
}

test "processWithSplitting: multiple param changes at same offset produce one split" {
    var plugin = SplitTestPlugin{};
    var in_data = [_]f32{0} ** 128;
    var out_data = [_]f32{0} ** 128;
    var in_slice = [_][]const f32{&in_data};
    var out_slice = [_][]f32{&out_data};

    const gain_id = comptime params_mod.hashFieldName("gain");
    const changes = [_]params_mod.ParamChangeEvent{
        .{ .time = 64, .param_id = gain_id, .value = 0.3 },
        .{ .time = 64, .param_id = gain_id, .value = 0.7 },
    };

    _ = processWithSplitting(
        SplitTestPlugin,
        &plugin,
        &in_slice,
        &out_slice,
        128,
        44100.0,
        0,
        &changes,
        events.SliceEventIterator.empty,
    );

    try t.expectEqual(@as(u32, 2), plugin.call_count);
    // Second value wins (applied in order)
    try t.expectEqual(@as(f32, 0.7), plugin.gain_at_call[1]);
}
