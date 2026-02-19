const std = @import("std");
const t = std.testing;
const clap = @import("../../api/clap.zig");
const params_mod = @import("../../params.zig");
const plugin_mod = @import("../../plugin.zig");

pub fn ParamsExtension(comptime PluginType: type) type {
    return struct {
        pub const ext = clap.PluginParams{
            .count = paramsCount,
            .get_info = paramsGetInfo,
            .get_value = paramsGetValue,
            .value_to_text = paramsValueToText,
            .text_to_value = paramsTextToValue,
            .flush = paramsFlush,
        };

        pub const extension_name = &clap.EXT_PARAMS;

        fn paramsCount(plugin: [*c]const clap.Plugin) callconv(.c) u32 {
            _ = plugin;
            return PluginType.params.len;
        }

        fn paramsGetInfo(
            plugin: [*c]const clap.Plugin,
            param_index: u32,
            info: [*c]clap.ParamInfo,
        ) callconv(.c) bool {
            _ = plugin;
            if (param_index >= PluginType.params.len) return false;
            const param = PluginType.params[param_index];
            info.*.id = param.id;
            info.*.min_value = param.min;
            info.*.max_value = param.max;
            info.*.default_value = param.default;
            info.*.flags = 0;

            if (param.flags.automatable) info.*.flags |= clap.ParamMasks.AUTOMATABLE;
            @memcpy(info.*.name[0..param.name.len], param.name);
            info.*.name[param.name.len] = 0;
            return true;
        }

        fn paramsGetValue(
            plugin: [*c]const clap.Plugin,
            param_id: u32,
            out_value: [*c]f64,
        ) callconv(.c) bool {
            const instance: *PluginType = @ptrCast(@alignCast(plugin.*.plugin_data));
            const PV = params_mod.ParamValues(PluginType.params.len);
            const idx = PV.indexFromId(PluginType.params, param_id) orelse return false;
            out_value.* = instance.param_values.get(idx);
            return true;
        }

        fn paramsValueToText(
            plugin: [*c]const clap.Plugin,
            param_id: u32,
            value: f64,
            out_buf: [*c]u8,
            out_buf_size: u32,
        ) callconv(.c) bool {
            _ = plugin;
            _ = param_id;
            const buf = out_buf[0..out_buf_size];
            const result = std.fmt.bufPrint(buf, "{d:.2}", .{value}) catch return false;
            buf[result.len] = 0;
            return true;
        }

        fn paramsTextToValue(
            plugin: [*c]const clap.Plugin,
            param_id: u32,
            text: [*c]const u8,
            out_value: [*c]f64,
        ) callconv(.c) bool {
            _ = plugin;
            _ = param_id;
            const str = std.mem.span(text);
            out_value.* = std.fmt.parseFloat(f64, str) catch return false;
            return true;
        }

        fn paramsFlush(
            plugin: [*c]const clap.Plugin,
            in_events: [*c]const clap.InputEvents,
            out_events: [*c]const clap.OutputEvents,
        ) callconv(.c) void {
            _ = out_events;
            const instance: *PluginType = @ptrCast(@alignCast(plugin.*.plugin_data));
            const ie: *const clap.InputEvents = in_events orelse return;
            const size_fn = ie.*.size orelse return;
            const get_fn = ie.*.get orelse return;
            const event_count = size_fn(ie);

            for (0..event_count) |i| {
                const header: *const clap.EventHeader = get_fn(ie, @intCast(i));
                if (header.space_id == clap.CORE_EVENT_SPACE_ID and
                    header.type == clap.Event.EVENT_PARAM_VALUE)
                {
                    const ev: *const clap.EventParam = @ptrCast(@alignCast(header));
                    const PV = params_mod.ParamValues(PluginType.params.len);
                    if (PV.indexFromId(PluginType.params, ev.param_id)) |idx| {
                        instance.param_values.set(idx, ev.value, PluginType.params);
                    }
                }
            }
        }
    };
}

const TestPluginWithParams = struct {
    pub const descriptor = plugin_mod.PluginDescriptor{
        .id = "com.test.params",
        .name = "Params Test",
        .vendor = "Test",
        .version = "1.0.0",
    };

    pub const params = &[_]params_mod.Param{
        .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5, .flags = .{ .automatable = true } },
        .{ .id = 1, .name = "Pain", .min = -1.0, .max = 1.0, .default = 0.0 },
    };
    pub const audio_ports = @import("../../audio.zig").AudioPortConfig{};

    param_values: params_mod.ParamValues(params.len) = .{},

    pub fn init(self: *@This(), sample_rate: f64) void {
        _ = sample_rate;
        self.params.reset(params);
    }

    pub fn process(self: *@This(), ctx: anytype) @import("../../process.zig").ProcessResult {
        _ = self;
        _ = ctx;
        return .@"continue";
    }
};

test "params extension reports correct count" {
    const Ext = ParamsExtension(TestPluginWithParams);
    try t.expectEqual(@as(u32, 2), Ext.paramsCount(undefined));
}

const TestPluginEmpty = struct {
    pub const params = &[_]params_mod.Param{};
};

test "params extension reports 0 for no params" {
    const Ext = ParamsExtension(TestPluginEmpty);
    try t.expectEqual(@as(u32, 0), Ext.paramsCount(undefined));
}
