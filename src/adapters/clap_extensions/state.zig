const std = @import("std");
const t = std.testing;

const clap = @import("../../api/clap.zig");
const params_mod = @import("../../params.zig");
const discoverParams = params_mod.discoverParams;
const adapter = @import("../clap.zig");

pub fn StateExtension(comptime PluginType: type) type {
    const Instance = adapter.InstanceData(PluginType);

    return struct {
        pub const ext = clap.State{
            .save = stateSave,
            .load = stateLoad,
        };

        pub const extension_name = &clap.EXT_STATE;

        const Header = extern struct {
            magic: [4]u8,
            version: u32,
            param_count: u32,
        };

        fn stateSave(plugin: [*c]const clap.Plugin, ostream: [*c]const clap.Stream.Ostream) callconv(.c) bool {
            const data = getInstance(plugin);
            const discovered = comptime discoverParams(
                @TypeOf(@as(PluginType, undefined).params),
            );
            const header = Header{
                .magic = "ZAPF".*,
                .version = std.mem.nativeToLittle(u32, 1),
                .param_count = std.mem.nativeToLittle(u32, discovered.len),
            };
            if (!streamWriteAll(ostream, std.mem.asBytes(&header))) return false;

            inline for (discovered) |d| {
                const id_bytes = std.mem.nativeToLittle(u32, d.id);
                if (!streamWriteAll(ostream, std.mem.asBytes(&id_bytes)))
                    return false;

                const value = @field(&data.plugin.params, d.field_name).getRaw();
                const val_bytes = std.mem.nativeToLittle(f64, value);
                if (!streamWriteAll(ostream, std.mem.asBytes(&val_bytes)))
                    return false;
            }

            return true;
        }

        fn streamWriteAll(
            ostream: *const clap.Stream.Ostream,
            data: []const u8,
        ) bool {
            var offset: usize = 0;
            while (offset < data.len) {
                const written = ostream.write.?(
                    ostream,
                    data[offset..].ptr,
                    @intCast(data.len - offset),
                );
                if (written < 0) return false;
                offset += @intCast(written);
            }
            return true;
        }

        fn stateLoad(plugin: [*c]const clap.Plugin, istream: [*c]const clap.Stream.Istream) callconv(.c) bool {
            const data = getInstance(plugin);

            var header: Header = undefined;

            if (!streamReadAll(istream, std.mem.asBytes(&header))) return false;

            if (!std.mem.eql(u8, &header.magic, "ZAPF")) return false;

            const version = std.mem.littleToNative(u32, header.version);
            if (version != 1) return false;

            const saved_count = std.mem.littleToNative(u32, header.param_count);

            for (0..saved_count) |_| {
                var id_raw: u32 = undefined;
                if (!streamReadAll(istream, std.mem.asBytes(&id_raw))) return false;
                const id = std.mem.littleToNative(u32, id_raw);

                var val_raw: f64 = undefined;
                if (!streamReadAll(istream, std.mem.asBytes(&val_raw))) return false;
                const value = std.mem.littleToNative(f64, val_raw);

                params_mod.setById(&data.plugin.params, id, value);
            }

            return true;
        }

        fn streamReadAll(
            istream: *const clap.Stream.Istream,
            data: []u8,
        ) bool {
            var offset: usize = 0;
            while (offset < data.len) {
                const read = istream.read.?(
                    istream,
                    data[offset..].ptr,
                    @intCast(data.len - offset),
                );
                if (read <= 0) return false; // error or premature EOF
                offset += @intCast(read);
            }
            return true;
        }

        fn getInstance(plugin: [*c]const clap.Plugin) *Instance {
            return @ptrCast(@alignCast(plugin.*.plugin_data));
        }
    };
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const TestStatePlugin = struct {
    pub const descriptor = @import("../../plugin.zig").PluginDescriptor{
        .id = "com.test.state",
        .name = "State Test",
        .vendor = "Test",
        .version = "1.0.0",
    };

    pub const audio_ports = @import("../../audio.zig").AudioPortConfig{};

    params: Params = .{},

    const Params = struct {
        gain: params_mod.Float(.{
            .name = "Gain",
            .min = 0.0,
            .max = 1.0,
            .default = 0.5,
        }) = .{},
        pan: params_mod.Float(.{
            .name = "Pan",
            .min = -1.0,
            .max = 1.0,
            .default = 0.0,
        }) = .{},
    };

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

fn makeTestPlugin(data: *adapter.InstanceData(TestStatePlugin)) clap.Plugin {
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

/// In-memory buffer that implements both clap_ostream_t and clap_istream_t
/// for testing state save/load without a real host.
const MockStream = struct {
    const max_size = 4096;

    data: [max_size]u8 = undefined,
    len: usize = 0,
    read_pos: usize = 0,

    fn ostream(self: *MockStream) clap.Stream.Ostream {
        return .{ .ctx = self, .write = mockWrite };
    }

    fn istream(self: *MockStream) clap.Stream.Istream {
        return .{ .ctx = self, .read = mockRead };
    }

    fn bytes(self: *const MockStream) []const u8 {
        return self.data[0..self.len];
    }

    fn mockWrite(stream: [*c]const clap.Stream.Ostream, buffer: ?*const anyopaque, size: u64) callconv(.c) i64 {
        const self: *MockStream = @ptrCast(@alignCast(stream.*.ctx));
        const n: usize = @intCast(size);
        if (self.len + n > max_size) return -1;
        const src: [*]const u8 = @ptrCast(buffer.?);
        @memcpy(self.data[self.len..][0..n], src[0..n]);
        self.len += n;
        return @intCast(size);
    }

    fn mockRead(stream: [*c]const clap.Stream.Istream, buffer: ?*anyopaque, size: u64) callconv(.c) i64 {
        const self: *MockStream = @ptrCast(@alignCast(stream.*.ctx));
        const n: usize = @intCast(size);
        const available = self.len - self.read_pos;
        if (available == 0) return 0; // EOF
        const to_read = @min(n, available);
        const dst: [*]u8 = @ptrCast(buffer.?);
        @memcpy(dst[0..to_read], self.data[self.read_pos..][0..to_read]);
        self.read_pos += to_read;
        return @intCast(to_read);
    }
};

const Ext = StateExtension(TestStatePlugin);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "stateSave produces correct binary header" {
    var data = adapter.InstanceData(TestStatePlugin){ .plugin = .{} };
    var plugin = makeTestPlugin(&data);
    var stream = MockStream{};
    var os = stream.ostream();

    try t.expect(Ext.ext.save.?(&plugin, &os));

    const bytes = stream.bytes();
    // Header: 4 bytes magic + 4 bytes version + 4 bytes param_count = 12
    try t.expect(bytes.len >= 12);
    try t.expectEqualStrings("ZAPF", bytes[0..4]);
    try t.expectEqual(std.mem.littleToNative(u32, std.mem.bytesToValue(u32, bytes[4..8])), 1);
    try t.expectEqual(std.mem.littleToNative(u32, std.mem.bytesToValue(u32, bytes[8..12])), 2);
}

test "stateSave writes correct total size for two params" {
    var data = adapter.InstanceData(TestStatePlugin){ .plugin = .{} };
    var plugin = makeTestPlugin(&data);
    var stream = MockStream{};
    var os = stream.ostream();

    try t.expect(Ext.ext.save.?(&plugin, &os));

    // header (12) + 2 params * (4 byte id + 8 byte f64) = 12 + 24 = 36
    try t.expectEqual(@as(usize, 36), stream.bytes().len);
}

test "save then load round-trips param values" {
    var data = adapter.InstanceData(TestStatePlugin){ .plugin = .{} };
    var plugin = makeTestPlugin(&data);

    // Set non-default values
    data.plugin.params.gain.set(0.8);
    data.plugin.params.pan.set(-0.5);

    // Save
    var stream = MockStream{};
    var os = stream.ostream();
    try t.expect(Ext.ext.save.?(&plugin, &os));

    // Reset to defaults
    data.plugin.params.gain.reset();
    data.plugin.params.pan.reset();
    try t.expectEqual(@as(f64, 0.5), data.plugin.params.gain.getRaw());
    try t.expectEqual(@as(f64, 0.0), data.plugin.params.pan.getRaw());

    // Load from saved buffer
    var is = stream.istream();
    try t.expect(Ext.ext.load.?(&plugin, &is));

    try t.expectApproxEqAbs(@as(f64, 0.8), data.plugin.params.gain.getRaw(), 1e-10);
    try t.expectApproxEqAbs(@as(f64, -0.5), data.plugin.params.pan.getRaw(), 1e-10);
}

test "stateLoad rejects bad magic" {
    var data = adapter.InstanceData(TestStatePlugin){ .plugin = .{} };
    var plugin = makeTestPlugin(&data);

    // Save valid state first
    var stream = MockStream{};
    var os = stream.ostream();
    try t.expect(Ext.ext.save.?(&plugin, &os));

    // Corrupt magic
    stream.data[0] = 'X';

    var is = stream.istream();
    try t.expect(!Ext.ext.load.?(&plugin, &is));
}

test "stateLoad rejects wrong version" {
    var data = adapter.InstanceData(TestStatePlugin){ .plugin = .{} };
    var plugin = makeTestPlugin(&data);

    var stream = MockStream{};
    var os = stream.ostream();
    try t.expect(Ext.ext.save.?(&plugin, &os));

    // Overwrite version field (bytes 4..8) with version 2
    const v2 = std.mem.nativeToLittle(u32, 2);
    @memcpy(stream.data[4..8], std.mem.asBytes(&v2));

    var is = stream.istream();
    try t.expect(!Ext.ext.load.?(&plugin, &is));
}

test "save with non-default values then load restores them" {
    var data = adapter.InstanceData(TestStatePlugin){ .plugin = .{} };
    var plugin = makeTestPlugin(&data);

    data.plugin.params.gain.set(0.0);
    data.plugin.params.pan.set(1.0);

    var stream = MockStream{};
    var os = stream.ostream();
    try t.expect(Ext.ext.save.?(&plugin, &os));

    // Load into a fresh instance
    var data2 = adapter.InstanceData(TestStatePlugin){ .plugin = .{} };
    var plugin2 = makeTestPlugin(&data2);

    // Verify defaults
    try t.expectEqual(@as(f64, 0.5), data2.plugin.params.gain.getRaw());
    try t.expectEqual(@as(f64, 0.0), data2.plugin.params.pan.getRaw());

    var is = stream.istream();
    try t.expect(Ext.ext.load.?(&plugin2, &is));

    try t.expectApproxEqAbs(@as(f64, 0.0), data2.plugin.params.gain.getRaw(), 1e-10);
    try t.expectApproxEqAbs(@as(f64, 1.0), data2.plugin.params.pan.getRaw(), 1e-10);
}
