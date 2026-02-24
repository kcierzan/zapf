const std = @import("std");
const t = std.testing;
const clap = @import("../../api/clap.zig");
const params_mod = @import("../../params.zig");
const plugin_mod = @import("../../plugin.zig");
const adapter = @import("../clap.zig");

const discoverParams = params_mod.discoverParams;
const Float = params_mod.Float;

fn flagsToClap(flags: params_mod.ParamFlags) u32 {
    var result: u32 = 0;
    if (flags.automatable) result |= clap.ParamMasks.AUTOMATABLE;
    if (flags.modulatable) result |= clap.ParamMasks.MODULATABLE;
    if (flags.stepped) result |= clap.ParamMasks.STEPPED;
    if (flags.hidden) result |= clap.ParamMasks.HIDDEN;
    if (flags.readonly) result |= clap.ParamMasks.READONLY;
    if (flags.bypass) result |= clap.ParamMasks.BYPASS;
    return result;
}

pub fn ParamsExtension(comptime PluginType: type) type {
    const Instance = adapter.InstanceData(PluginType);

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
            const discovered = comptime discoverParams(@TypeOf(@as(PluginType, undefined).params));
            return discovered.len;
        }

        fn paramsGetInfo(
            plugin: [*c]const clap.Plugin,
            param_index: u32,
            info: [*c]clap.ParamInfo,
        ) callconv(.c) bool {
            _ = plugin;
            const discovered = comptime discoverParams(@TypeOf(@as(PluginType, undefined).params));
            if (param_index >= discovered.len) return false;

            comptime var idx: u32 = 0;

            inline for (discovered) |d| {
                if (idx == param_index) {
                    info.*.id = d.id;
                    info.*.min_value = d.meta.min;
                    info.*.max_value = d.meta.max;
                    info.*.default_value = d.meta.default;
                    info.*.flags = flagsToClap(d.meta.flags);
                    @memcpy(info.*.name[0..d.meta.name.len], d.meta.name);
                    info.*.name[d.meta.name.len] = 0;
                    @memcpy(info.*.module[0..d.meta.module.len], d.meta.module);
                    info.*.module[d.meta.module.len] = 0;
                    return true;
                }
                idx += 1;
            }
            return false;
        }

        fn paramsGetValue(
            plugin: [*c]const clap.Plugin,
            param_id: u32,
            out_value: [*c]f64,
        ) callconv(.c) bool {
            const data: *Instance = getInstance(plugin);
            const discovered = comptime discoverParams(
                @TypeOf(@as(PluginType, undefined).params),
            );

            inline for (discovered) |d| {
                if (d.id == param_id) {
                    out_value.* = @field(&data.plugin.params, d.field_name).getRaw();
                    return true;
                }
            }
            return false;
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
            if (out_buf_size == 0) return false;
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
            const data: *Instance = @ptrCast(@alignCast(plugin.*.plugin_data));
            const ie: *const clap.InputEvents = in_events orelse return;
            applyParamEvents(PluginType, &data.plugin, ie);
        }

        fn getInstance(plugin: [*c]const clap.Plugin) *Instance {
            return @ptrCast(@alignCast(plugin.*.plugin_data));
        }
    };
}

pub fn applyParamEvents(comptime PluginType: type, instance: *PluginType, ie: *const clap.InputEvents) void {
    const size_fn = ie.*.size orelse return;
    const get_fn = ie.*.get orelse return;
    const event_count = size_fn(ie);

    const discovered = comptime discoverParams(
        @TypeOf(@as(PluginType, undefined).params),
    );

    for (0..event_count) |i| {
        const header: *const clap.EventHeader = get_fn(ie, @intCast(i));
        if (header.space_id == clap.CORE_EVENT_SPACE_ID and
            header.type == clap.Event.EVENT_PARAM_VALUE)
        {
            const ev: *const clap.EventParam = @ptrCast(@alignCast(header));
            inline for (discovered) |d| {
                if (d.id == ev.param_id) {
                    @field(&instance.params, d.field_name).set(ev.value);
                }
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

    params: Params = .{},

    const Params = struct {
        gain: Float(.{
            .name = "Gain",
            .min = 0.0,
            .default = 0.5,
            .flags = .{ .automatable = true },
        }) = .{},
        pan: Float(.{
            .name = "Pan",
            .min = -1.0,
            .max = 1.0,
            .default = 0.0,
        }) = .{},
    };

    pub const audio_ports = @import("../../audio.zig").AudioPortConfig{};

    pub fn init(self: *@This(), sample_rate: f64) void {
        _ = self;
        _ = sample_rate;
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
    params: struct {} = .{},
};

test "params extension reports 0 for no params" {
    const Ext = ParamsExtension(TestPluginEmpty);
    try t.expectEqual(@as(u32, 0), Ext.paramsCount(undefined));
}

test "paramsGetInfo populates name, range, default, and flags" {
    const Ext = ParamsExtension(TestPluginWithParams);
    var info: clap.ParamInfo = undefined;
    try t.expect(Ext.paramsGetInfo(undefined, 0, &info));
    try t.expectEqual(comptime params_mod.hashFieldName("gain"), info.id);
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

fn makeTestPlugin(data: *adapter.InstanceData(TestPluginWithParams)) clap.Plugin {
    return clap.Plugin{
        .desc = undefined,
        .plugin_data = data,
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
}

test "paramsGetValue returns default after init" {
    const Ext = ParamsExtension(TestPluginWithParams);
    var data = adapter.InstanceData(TestPluginWithParams){ .plugin = .{} };
    var plugin = makeTestPlugin(&data);
    var value: f64 = undefined;
    try t.expect(Ext.paramsGetValue(&plugin, comptime params_mod.hashFieldName("gain"), &value));
    try t.expectEqual(@as(f64, 0.5), value);
}

test "paramsGetValue returns false for unknown param id" {
    const Ext = ParamsExtension(TestPluginWithParams);
    var data = adapter.InstanceData(TestPluginWithParams){ .plugin = .{} };
    var plugin = makeTestPlugin(&data);
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

test "paramsValueToText returns false for zero-size buffer" {
    const Ext = ParamsExtension(TestPluginWithParams);
    var buf: [1]u8 = undefined;
    try t.expect(!Ext.paramsValueToText(undefined, 0, 0.75, &buf, 0));
}

test "paramsValueToText null-terminates within exact-fit buffer" {
    const Ext = ParamsExtension(TestPluginWithParams);
    // "0.75" is 4 chars; buffer of 5 fits the text + null exactly
    var buf: [5]u8 = .{ 0xff, 0xff, 0xff, 0xff, 0xff };
    try t.expect(Ext.paramsValueToText(undefined, 0, 0.75, &buf, buf.len));
    try t.expectEqualStrings("0.75", std.mem.sliceTo(&buf, 0));
}

test "paramsValueToText returns false when buffer is too small for value" {
    const Ext = ParamsExtension(TestPluginWithParams);
    // "0.75" needs 4 chars + null = 5 bytes; buffer of 2 (1 usable) is too small
    var buf: [2]u8 = undefined;
    try t.expect(!Ext.paramsValueToText(undefined, 0, 0.75, &buf, buf.len));
}

test "applyParamEvents is a no-op with null function pointers" {
    var instance = TestPluginWithParams{};
    const empty = clap.InputEvents{
        .ctx = null,
        .size = null,
        .get = null,
    };
    // should return early without touching param values
    applyParamEvents(TestPluginWithParams, &instance, &empty);
    try t.expectEqual(@as(f64, 0.5), instance.params.gain.getRaw());
    try t.expectEqual(@as(f64, 0.0), instance.params.pan.getRaw());
}
