const std = @import("std");
const zapf = @import("zapf");

const GainPlugin = struct {
    pub const descriptor = zapf.PluginDescriptor{ .id = "com.example.gain", .name = "Zapf Example Gain", .vendor = "Example Audio", .version = "0.1.0", .url = "https://example.com", .description = "A simple gain plugin", .features = &.{
        zapf.PluginFeatures.AUDIO_EFFECT,
        zapf.PluginFeatures.UTILITY,
    } };

    pub const params = &[_]zapf.Param{
        .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 1.0,
            .default = 0.5,
            .flags = .{ .automatable = true },
        },
    };

    pub const audio_ports = zapf.AudioPortConfig{
        .input_channels = 2,
        .output_channels = 2,
    };

    param_values: zapf.ParamValues(params.len),
    sample_rate: f64,

    // REAPER seems to call this on transport start (stop?)
    pub fn init(self: *GainPlugin, sample_rate: f64) void {
        self.sample_rate = sample_rate;
    }

    pub fn process(self: *GainPlugin, ctx: anytype) zapf.ProcessResult {
        const gain: f32 = @floatCast(self.param_values.getById(params, 0) orelse 0.5);

        const frames = ctx.frame_count;
        for (0..frames) |i| {
            ctx.output[0][i] = ctx.input[0][i] * gain;
            ctx.output[1][i] = ctx.input[1][i] * gain;
        }

        return .continue_if_not_quiet;
    }

    pub fn reset(self: *GainPlugin) void {
        _ = self;
    }

    pub fn deinit(self: *GainPlugin) void {
        _ = self;
    }
};

comptime {
    zapf.exportClapPlugin(GainPlugin);
}
