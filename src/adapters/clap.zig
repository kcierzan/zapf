const std = @import("std");
const t = std.testing;

const clap = @import("../api/clap.zig");
const events = @import("../events.zig");
const params_mod = @import("../params.zig");
const process_mod = @import("../process.zig");
const plugin_mod = @import("../plugin.zig");

const audio_ports_ext = @import("../adapters/clap_extensions/audio_ports.zig");
const params_ext = @import("../adapters/clap_extensions/params.zig");

pub fn ClapAdapter(comptime PluginType: type) type {
    return struct {
        const Self = @This();
        const clap_desc = toClapDescriptor(PluginType.descriptor);
        const AudioPorts = audio_ports_ext.AudioPortsExtension(PluginType);
        const Params = params_ext.ParamsExtension(PluginType);

        /// The clap_plugin_t instance. Hosts receive a pointer to this.
        fn makePluginVtable(instance: *PluginType) clap.Plugin {
            return clap.Plugin{
                .desc = &clap_desc,
                .plugin_data = instance,
                .init = Self.pluginInit,
                .destroy = Self.pluginDestroy,
                .activate = Self.pluginActivate,
                .deactivate = Self.pluginDeactivate,
                .start_processing = Self.pluginStartProcessing,
                .stop_processing = Self.pluginStopProcessing,
                .reset = Self.pluginReset,
                .process = Self.pluginProcess,
                .get_extension = Self.pluginGetExtension,
                .on_main_thread = Self.pluginOnMainThread,
            };
        }

        fn pluginInit(plugin: [*c]const clap.Plugin) callconv(.c) bool {
            _ = plugin;
            // NOTE: most setup work happens in activate where we get an actual
            // sample rate in the arguments. Letting this no-op for now.
            return true;
        }

        fn pluginDestroy(plugin: [*c]const clap.Plugin) callconv(.c) void {
            const instance: *PluginType = @ptrCast(@alignCast(plugin.*.plugin_data));
            if (@hasDecl(PluginType, "deinit")) {
                instance.deinit();
            }
            const allocator = std.heap.page_allocator;
            allocator.destroy(instance);
            // plugin itself was also heap-allocated in createPlugin
            allocator.destroy(@constCast(plugin));
        }

        fn pluginActivate(
            plugin: [*c]const clap.Plugin,
            sample_rate: f64,
            min_frames: u32,
            max_frames: u32,
        ) callconv(.c) bool {
            _ = min_frames;
            _ = max_frames;
            const instance: *PluginType = @ptrCast(@alignCast(plugin.*.plugin_data));
            instance.init(sample_rate);
            return true;
        }

        fn pluginDeactivate(plugin: [*c]const clap.Plugin) callconv(.c) void {
            _ = plugin;
        }

        fn pluginStartProcessing(plugin: [*c]const clap.Plugin) callconv(.c) bool {
            _ = plugin;
            return true;
        }

        fn pluginReset(plugin: [*c]const clap.Plugin) callconv(.c) void {
            const instance: *PluginType = @ptrCast(@alignCast(plugin.*.plugin_data));
            if (@hasDecl(PluginType, "reset")) {
                instance.reset();
            }
        }

        fn pluginProcess(
            plugin: [*c]const clap.Plugin,
            process: [*c]const clap.Process,
        ) callconv(.c) i32 {
            const instance: *PluginType = @ptrCast(@alignCast(plugin.*.plugin_data));

            const p = process.*;
            const frame_count = p.frames_count;

            // TODO: slicing buffer slices by event offsets would happen here!
            // we should make this a generic behavior to re-use it across adapters

            // build input channel slices
            var input_slices: [16][]const f32 = undefined;
            var in_channels: u32 = 0;
            if (p.audio_inputs) |in_buf| {
                in_channels = in_buf.channel_count;
                for (0..in_channels) |ch| {
                    input_slices[ch] = in_buf.data32[ch][0..frame_count];
                }
            }

            var output_slices: [16][]f32 = undefined;
            var out_channels: u32 = 0;
            if (p.audio_outputs) |out_buf| {
                out_channels = out_buf.channel_count;
                for (0..out_channels) |ch| {
                    output_slices[ch] = out_buf.data32[ch][0..frame_count];
                }
            }

            // apply parameter events directly to the plugins ParamValues
            const in_events = p.in_events;
            const event_count: u32 = if (in_events) |ie|
                if (ie.size) |size_fn| size_fn(ie) else 0
            else
                0;

            for (0..event_count) |i| {
                const get_fn = in_events.?.get orelse continue;
                const header = get_fn(in_events.?, @intCast(i));
                if (header.space_id == clap.CORE_EVENT_SPACE_ID and header.type == clap.Event.EVENT_PARAM_VALUE) {
                    const ev: *const clap.EventParam = @ptrCast(@alignCast(header));
                    const PV = params_mod.ParamValues(PluginType.params.len);
                    if (PV.indexFromId(PluginType.params, ev.param_id)) |idx| {
                        instance.param_values.set(idx, ev.value, PluginType.params);
                    }
                }
            }

            // Construct the generic ProcessContext - ClapEventIterator skips param events
            const Context = process_mod.ProcessContext(ClapEventIterator);
            const ctx = Context{
                .input = input_slices[0..in_channels],
                .output = output_slices[0..out_channels],
                .frame_count = frame_count,
                .sample_rate = 0, // filled in from `activate`
                .steady_time = p.steady_time,
                .events = ClapEventIterator{
                    .input_events = in_events.?,
                    .count = event_count,
                },
            };

            const result = instance.process(ctx);
            return toClapProcessResult(result);
        }

        fn pluginGetExtension(
            plugin: [*c]const clap.Plugin,
            id: [*c]const u8,
        ) callconv(.c) ?*const anyopaque {
            _ = plugin;
            // TODO: add more extensions here
            const ext_id = std.mem.span(id);

            if (std.mem.eql(u8, ext_id, AudioPorts.extension_name)) {
                return @ptrCast(&AudioPorts.ext);
            }
            if (std.mem.eql(u8, ext_id, Params.extension_name)) {
                return @ptrCast(&Params.ext);
            }
            return null;
        }

        fn pluginOnMainThread(plugin: [*c]const clap.Plugin) callconv(.c) void {
            _ = plugin;
        }
    };
}

const TestPlugin = struct {
    pub const descriptor = plugin_mod.PluginDescriptor{
        .id = "com.test.adapter",
        .name = "Adapter test",
        .vendor = "test",
        .version = "1.0.0",
    };
    pub const params = &[_]params_mod.Param{};
    pub const audio_ports = @import("../audio.zig").AudioPortConfig{};

    initialized: bool = false,
    process_count: u32 = 0,
    param_values: params_mod.ParamValues(params.len) = .{},

    pub fn init(self: *TestPlugin, sample_rate: f64) void {
        _ = sample_rate;
        self.initialized = true;
    }

    pub fn process(self: *TestPlugin, ctx: anytype) process.ProcessResult {
        _ = ctx;
        self.process_count += 1;
        return .@"continue";
    }

    pub fn reset(self: *TestPlugin) void {
        self.process_count = 0;
    }
};

test "ClapAdapter generates a valid vtable type" {
    const Adapter = ClapAdapter(TestPlugin);
    try t.expectEqual(@TypeOf(Adapter.clap_desc), clap.PluginDescriptor);
}

test "pluginGetExtension returns audio-ports extension" {
    const Adapter = ClapAdapter(TestPlugin);
    const audio_ptr = Adapter.pluginGetExtension(undefined, &clap.EXT_AUDIO_PORTS);
    try t.expect(audio_ptr != null);
}

test "pluginGetExtension returns params extension" {
    const Adapter = ClapAdapter(TestPlugin);
    const params_ptr = Adapter.pluginGetExtension(undefined, &clap.EXT_PARAMS);
    try t.expect(params_ptr != null);
}

test "pluginGetExtension with unknown extension returns null" {
    const Adapter = ClapAdapter(TestPlugin);
    const unknown_ptr = Adapter.pluginGetExtension(undefined, "clap.unknown-ext");
    try t.expectEqual(unknown_ptr, null);
}

fn toClapProcessResult(comptime result: process_mod.ProcessResult) i32 {
    return switch (result) {
        .@"error" => clap.ProcessResult.ERROR,
        .@"continue" => clap.ProcessResult.CONTINUE,
        .continue_if_not_quiet => clap.ProcessResult.CONTINUE_IF_NOT_QUIET,
        .tail => clap.ProcessResult.TAIL,
        .sleep => clap.ProcessResult.SLEEP,
    };
}

test "toClapProcessResult returns the expected return codes" {
    const err = process_mod.ProcessResult.@"error";
    const cont = process_mod.ProcessResult.@"continue";
    try t.expectEqual(toClapProcessResult(err), 0);
    try t.expectEqual(toClapProcessResult(cont), 1);
}

fn toClapDescriptor(comptime desc: plugin_mod.PluginDescriptor) clap.PluginDescriptor {
    const feature_ptrs = comptime blk: {
        var ptrs: [desc.features.len + 1][*c]const u8 = undefined;
        for (desc.features, 0..) |f, i| {
            ptrs[i] = f.ptr;
        }
        ptrs[desc.features.len] = null;
        break :blk ptrs;
    };
    return clap.PluginDescriptor{
        // TODO: what version should we hardcode here?
        .clap_version = .{ .major = 1, .minor = 2, .revision = 2 },
        .id = desc.id.ptr,
        .name = desc.name.ptr,
        .vendor = desc.vendor.ptr,
        .url = desc.url.ptr,
        .manual_url = desc.manual_url.ptr,
        .support_url = desc.support_url.ptr,
        .version = desc.version.ptr,
        .description = desc.description.ptr,
        .features = &feature_ptrs,
    };
}

test "toClapDescriptor converts fields correctly" {
    const desc = plugin_mod.PluginDescriptor{
        .id = "com.test.convert",
        .name = "Convert Test",
        .vendor = "Test",
        .version = "1.0.0",
        .url = "https://example.com",
        .description = "Test conversion",
        .features = &.{ "audio-effect", "utility" },
    };

    const clap_desc = comptime toClapDescriptor(desc);

    try t.expectEqualStrings(
        "com.test.convert",
        std.mem.span(clap_desc.id),
    );
    try t.expectEqualStrings(
        "Convert Test",
        std.mem.span(clap_desc.name),
    );

    // Check features array is null-terminated
    try t.expect(clap_desc.features[2] == null);
}

const ClapEventIterator = struct {
    input_events: *const clap.InputEvents,
    index: u32 = 0,
    count: u32,

    pub fn next(self: *ClapEventIterator) ?events.PluginEvent {
        while (self.index < self.count) : (self.index += 1) {
            const get_fn = self.input_events.get orelse return null;
            const header: *const clap.EventHeader = get_fn(self.input_events, self.index);
            // skip param value events as we will handle them separately and apply them ourselves
            if (header.space_id == clap.CORE_EVENT_SPACE_ID and header.type == clap.Event.EVENT_PARAM_VALUE) continue;
            return toPluginEvent(header);
        }
        return null;
    }

    fn reset(self: *ClapEventIterator) void {
        self.index = 0;
    }

    /// Map the clap-specific plugin event to the user-facing events.PluginEvent type.
    fn toPluginEvent(header: *const clap.EventHeader) events.PluginEvent {
        if (header.space_id != clap.CORE_EVENT_SPACE_ID) return .{ .time = header.time, .data = .unknown };

        return switch (header.type) {
            clap.Event.EVENT_NOTE_ON => .{ .time = header.time, .data = .{ .note_on = noteFromHeader(header) } },
            clap.Event.EVENT_NOTE_OFF => .{ .time = header.time, .data = .{ .note_off = noteFromHeader(header) } },
            clap.Event.EVENT_MIDI => blk: {
                const ev: *const clap.EventMidi = @ptrCast(@alignCast(header));
                break :blk .{ .time = header.time, .data = .{ .midi = .{
                    .port_index = ev.port_index,
                    .data = ev.data,
                } } };
            },
            else => .{ .time = header.time, .data = .unknown },
        };
    }

    fn noteFromHeader(header: *const clap.EventHeader) events.NoteEvent {
        const ev: *const clap.EventNote = @ptrCast(@alignCast(header));
        return .{
            .note_id = ev.note_id,
            .port_index = ev.port_index,
            .channel = ev.channel,
            .key = ev.key,
            .velocity = ev.velocity,
        };
    }
};

/// Top-level function that plugin authors call in a `comptime` block
/// Generates and exports the `clap_entry` symbol
pub fn exportEntry(comptime PluginType: type) void {
    plugin_mod.validatePlugin(PluginType);

    const Adapter = ClapAdapter(PluginType);

    const EntryImpl = struct {
        var factory = clap.PluginFactory{
            .get_plugin_count = Self.getPluginCount,
            .get_plugin_descriptor = Self.getPluginDescriptor,
            .create_plugin = Self.createPlugin,
        };

        const Self = @This();

        fn getPluginCount(f: [*c]clap.PluginFactory) callconv(.c) u32 {
            _ = f;
            // NOTE: we do not support multi-plugin clap bundles for now
            return 1; // single-plugin library
        }

        fn getPluginDescriptor(
            f: [*c]const clap.PluginFactory,
            index: u32,
        ) callconv(.c) ?*const clap.PluginDescriptor {
            _ = f;
            if (index == 0) return &Adapter.clap_desc;
            return null;
        }

        fn createPlugin(
            f: [*c]const clap.PluginFactory,
            host: [*c]const clap.Host,
            plugin_id: [*c]const u8,
        ) callconv(.c) ?*const clap.Plugin {
            _ = f;
            _ = host;
            const id_str = std.mem.span(plugin_id);
            if (!std.mem.eql(u8, id_str, PluginType.descriptor.id)) return null;

            // Allocate a whole page as we can't pass in an allocator here due to clap ABI
            // constraints
            const allocator = std.head.page_allocator;
            const instance = allocator.create(PluginType) catch return null;
            const clap_plugin = allocator.create(clap.Plugin) catch {
                allocator.destroy(instance);
                return null;
            };

            clap_plugin.* = Adapter.makePluginVtable(instance);
            return clap_plugin;
        }

        fn entryInit(plugin_path: [*c]const u8) callconv(.c) bool {
            _ = plugin_path;
            return true;
        }

        fn entryDeinit() callconv(.c) void {}

        fn getFactory(factory_id: [*c]const u8) callconv(.c) ?*const anyopaque {
            const id_str = std.mem.span(factory_id);
            if (std.mem.eql(u8, id_str, "clap.plugin-factory")) {
                return @ptrCast(&factory);
            }
            return null;
        }

        pub const entry = clap.PluginEntry{
            .clap_version = .{ .major = 1, .minor = 2, .revision = 2 },
            .init = Self.entryInit,
            .deinit = Self.entryDeinit,
            .get_factory = Self.getFactory,
        };
    };

    // Export the entry symbol so the host can find `clap_entry`
    @export(&EntryImpl.entry, .{ .name = "clap_entry" });
}

test "exportEntry compiles for a valid plugin" {
    const Adapter = ClapAdapter(TestPlugin);
    try t.expectEqualStrings(
        "com.test.adapter",
        std.mem.span(Adapter.clap_desc.id),
    );
}
