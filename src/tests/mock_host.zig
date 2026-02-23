const std = @import("std");
const t = std.testing;

const audio_mod = @import("../audio.zig");
const events_mod = @import("../events.zig");
const params_mod = @import("../params.zig");
const plugin_mod = @import("../plugin.zig");
const process_mod = @import("../process.zig");

pub fn MockHost(comptime PluginType: type) type {
    return struct {
        const Self = @This();
        const max_frames = 4096;
        const max_channels = 2;
        const Context = process_mod.ProcessContext(events_mod.SliceEventIterator);

        plugin: PluginType,
        sample_rate: f64,

        input_buffers: [max_channels][max_frames]f32,
        output_buffers: [max_channels][max_frames]f32,

        pub fn init(sample_rate: f64) Self {
            var host = Self{
                .plugin = undefined,
                .sample_rate = sample_rate,
                .input_buffers = [_][max_frames]f32{[_]f32{0.0} ** max_frames} ** max_channels,
                .output_buffers = [_][max_frames]f32{[_]f32{0.0} ** max_frames} ** max_channels,
            };
            host.plugin.init(sample_rate);
            return host;
        }

        pub fn fillInput(self: *Self, channel: usize, value: f32, frames: usize) void {
            @memset(self.input_buffers[channel][0..frames], value);
        }

        pub fn fillInputSite(self: *Self, channel: usize, freq: f32, frames: usize) void {
            for (0..frames) |i| {
                const phase = @as(f32, @floatFromInt(i)) * freq / @as(f32, @floatCast(self.sample_rate));
                self.input_buffers[channel][i] = @sin(phase * 2.0 * std.math.pi);
            }
        }

        pub fn processBlockWithEvents(self: *Self, frames: u32, plugin_events: []const events_mod.PluginEvent) process_mod.ProcessResult {
            var input_slices: [max_channels][]const f32 = undefined;
            var output_slices: [max_channels][]f32 = undefined;

            const in_ch = PluginType.audio_ports.input_channels;
            const out_ch = PluginType.audio_ports.output_channels;

            for (0..in_ch) |ch| {
                input_slices[ch] = self.input_buffers[ch][0..frames];
            }

            for (0..out_ch) |ch| {
                output_slices[ch] = self.output_buffers[ch][0..frames];
            }

            var ctx = Context{
                .input = input_slices[0..in_ch],
                .output = output_slices[0..out_ch],
                .frame_count = frames,
                .steady_time = 0,
                .sample_rate = self.sample_rate,
                .events = events_mod.SliceEventIterator{
                    .events_buf = plugin_events,
                },
            };

            return self.plugin.process(&ctx);
        }

        pub fn processBlock(self: *Self, frames: u32) process_mod.ProcessResult {
            return self.processBlockWithEvents(frames, &.{});
        }

        pub fn getOutput(self: *const Self, channel: usize, frame: usize) f32 {
            return self.output_buffers[channel][frame];
        }
    };
}

const GainTestPlugin = struct {
    pub const descriptor = plugin_mod.PluginDescriptor{
        .id = "com.test.gain",
        .name = "Test Gain",
        .vendor = "test",
        .version = "1.0.0",
    };

    pub const params = &[_]params_mod.Param{
        .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5 },
    };

    pub const audio_ports = audio_mod.AudioPortConfig{
        .input_channels = 2,
        .output_channels = 2,
    };

    param_values: params_mod.ParamValues(params.len) = .{},

    pub fn init(self: *GainTestPlugin, sample_rate: f64) void {
        _ = sample_rate;
        self.param_values.reset(params);
    }

    pub fn process(self: *GainTestPlugin, ctx: anytype) process_mod.ProcessResult {
        const gain: f32 = @floatCast(self.param_values.getById(params, 0) orelse 1.0);
        const frames = ctx.frame_count;
        for (0..frames) |i| {
            ctx.output[0][i] = ctx.input[0][i] * gain;
            ctx.output[1][i] = ctx.input[1][i] * gain;
        }
        return .continue_if_not_quiet;
    }

    pub fn reset(self: *GainTestPlugin) void {
        self.param_values.reset(params);
    }
};

test "MockHost can process audio through a gain plugin" {
    var host = MockHost(GainTestPlugin).init(441000.0);

    host.fillInput(0, 1.0, 64);
    host.fillInput(1, 1.0, 64);

    const result = host.processBlock(64);
    try t.expectEqual(process_mod.ProcessResult.continue_if_not_quiet, result);
    try t.expectApproxEqAbs(@as(f32, 0.5), host.getOutput(0, 0), 0.001);
    try t.expectApproxEqAbs(@as(f32, 0.5), host.getOutput(1, 0), 0.001);
}
