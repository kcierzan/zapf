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

            comptime {
                const name_capacity = @typeInfo(@TypeOf(@as(clap.ParamInfo, undefined).name)).array.len;
                const module_capacity = @typeInfo(@TypeOf(@as(clap.ParamInfo, undefined).module)).array.len;
                for (PluginType.params) |p| {
                    if (p.name.len >= name_capacity)
                        @compileError("param name '" ++ p.name ++ "' exceeds CLAP_NAME_SIZE");
                    if (p.module.len >= module_capacity)
                        @compileError("param module '" ++ p.module ++ "' exceeds CLAP_PATH_SIZE");
                }
            }

            info.*.id = param.id;
            info.*.min_value = param.min;
            info.*.max_value = param.max;
            info.*.default_value = param.default;
            info.*.flags = 0;
            if (param.flags.automatable) info.*.flags |= clap.ParamMasks.AUTOMATABLE;
            if (param.flags.modulatable) info.*.flags |= clap.ParamMasks.MODULATABLE;
            if (param.flags.stepped) info.*.flags |= clap.ParamMasks.STEPPED;
            if (param.flags.hidden) info.*.flags |= clap.ParamMasks.HIDDEN;
            if (param.flags.readonly) info.*.flags |= clap.ParamMasks.READONLY;
            if (param.flags.bypass) info.*.flags |= clap.ParamMasks.BYPASS;
            @memcpy(info.*.name[0..param.name.len], param.name);
            info.*.name[param.name.len] = 0;
            @memcpy(info.*.module[0..param.module.len], param.module);
            info.*.module[param.module.len] = 0;
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
            const result = std.fmt.bufPrint(buf[0 .. out_buf_size - 1], "{d:.2}", .{value}) catch return false;
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
            applyParamEvents(PluginType, instance, ie);
        }
    };
}

pub fn applyParamEvents(comptime PluginType: type, instance: *PluginType, ie: *const clap.InputEvents) void {
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
        self.param_values.reset(params);
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

test "paramsGetInfo populates name, range, default, and flags" {
    const Ext = ParamsExtension(TestPluginWithParams);
    var info: clap.ParamInfo = undefined;
    try t.expect(Ext.paramsGetInfo(undefined, 0, &info));
    try t.expectEqual(@as(u32, 0), info.id);
    try t.expectEqual(@as(f64, 0.0), info.min_value);
    try t.expectEqual(@as(f64, 1.0), info.max_value);
    try t.expectEqual(@as(f64, 0.5), info.default_value);
    try t.expect(info.flags & clap.ParamMasks.AUTOMATABLE != 0);
    try t.expectEqualStrings("Gain", info.name[0..4]);
}

test "paramsGetInfo returns false for out-of-bounds index" {
    const Ext = ParamsExtension(TestPluginWithParams);
    var info: clap.ParamInfo = undefined;
    try t.expect(!Ext.paramsGetInfo(undefined, 99, &info));
}

test "paramsGetValue returns default after reset" {
    const Ext = ParamsExtension(TestPluginWithParams);
    var instance = TestPluginWithParams{};
    instance.param_values.reset(TestPluginWithParams.params);
    var plugin = clap.Plugin{
        .desc = undefined,
        .plugin_data = &instance,
        .init = undefined,
        .destroy = undefined,
        .activate = undefined,
        .deactivate = undefined,
        .start_processing = undefined,
        .stop_processing = undefined,
        .reset = undefined,
        .process = undefined,
        .get_extension = undefined,
        .on_main_thread = undefined,
    };
    var value: f64 = undefined;
    try t.expect(Ext.paramsGetValue(&plugin, 0, &value));
    try t.expectEqual(@as(f64, 0.5), value);
}

test "paramsGetValue returns false for unknown param id" {
    const Ext = ParamsExtension(TestPluginWithParams);
    var instance = TestPluginWithParams{};
    var plugin = clap.Plugin{
        .desc = undefined,
        .plugin_data = &instance,
        .init = undefined,
        .destroy = undefined,
        .activate = undefined,
        .deactivate = undefined,
        .start_processing = undefined,
        .stop_processing = undefined,
        .reset = undefined,
        .process = undefined,
        .get_extension = undefined,
        .on_main_thread = undefined,
    };
    var value: f64 = undefined;
    try t.expect(!Ext.paramsGetValue(&plugin, 999, &value));
}

test "paramsValueToText and paramsTextToValue round-trip" {
    const Ext = ParamsExtension(TestPluginWithParams);
    var buf: [64]u8 = undefined;
    try t.expect(Ext.paramsValueToText(undefined, 0, 0.75, &buf, buf.len));
    const text = std.mem.sliceTo(&buf, 0);
    var result: f64 = undefined;
    try t.expect(Ext.paramsTextToValue(undefined, 0, text.ptr, &result));
    try t.expectEqual(@as(f64, 0.75), result);
}
