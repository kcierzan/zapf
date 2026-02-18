const std = @import("std");
const params_mod = @import("params.zig");
const audio = @import("audio.zig");
const events = @import("events.zig");

pub const PluginDescriptor = struct {
    id: [:0]const u8,
    name: [:0]const u8,
    vendor: [:0]const u8,
    version: [:0]const u8,
    url: [:0]const u8 = "",
    manual_url: [:0]const u8 = "",
    support_url: [:0]const u8 = "",
    description: [:0]const u8 = "",
    features: []const [:0]const u8 = &.{},
};

pub fn validatePlugin(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError("Plugin must be a struct, got " ++ @typeName(T));
    }

    const required = .{ "descriptor", "params", "audio_ports", "init", "process" };
    inline for (required) |name| {
        if (!@hasDecl(T, name)) {
            @compileError("Plugin '" ++ @typeName(T) ++ "' missing required declaration '" ++ name ++ "'");
        }
    }
}

test "PluginDescriptor can be created at comptime" {
    const desc = PluginDescriptor{
        .id = "com.test.plugin",
        .name = "Test Plugin",
        .vendor = "Test Vendor",
        .version = "1.0.0",
        .url = "https://example.com",
        .description = "A test plugin",
        .features = &.{ "audio effect", "utility" },
    };

    try std.testing.expectEqualStrings("com.test.plugin", desc.id);
    try std.testing.expectEqualStrings("Test Plugin", desc.name);
    try std.testing.expectEqual(@as(usize, 2), desc.features.len);
}

test "PluginDescriptor defaults are sensible" {
    const desc = PluginDescriptor{
        .id = "com.test.minimal",
        .name = "Minimal",
        .vendor = "Test",
        .version = "0.0.1",
    };

    try std.testing.expectEqualStrings("", desc.url);
    try std.testing.expectEqualStrings("", desc.description);
    try std.testing.expectEqual(@as(usize, 0), desc.features.len);
}

const ValidPlugin = struct {
    pub const descriptor = PluginDescriptor{
        .id = "com.test.valid",
        .name = "Valid",
        .vendor = "Test",
        .version = "1.0.0",
    };
    pub const params = &[_]params_mod.Param{};
    pub const audio_ports = audio.AudioPortConfig{};

    pub fn init(self: *ValidPlugin, sample_rate: f64) void {
        _ = self;
        _ = sample_rate;
    }

    pub fn process(self: *ValidPlugin, ctx: anytype) process.ProcessResult {
        _ = self;
        _ = ctx;
        return .@"continue";
    }
};

test "validatePlugin accepts a valid plugin" {
    comptime validatePlugin(ValidPlugin);
}
