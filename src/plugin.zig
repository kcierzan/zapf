const std = @import("std");

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
