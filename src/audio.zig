const std = @import("std");
const t = std.testing;

pub const AudioPortConfig = struct {
    input_channels: u32 = 2,
    output_channels: u32 = 2,
    name: [:0]const u8 = "Audio",
};

test "AudioPortConfig has sensible defaults" {
    const cfg = AudioPortConfig{};

    try t.expectEqual(cfg.input_channels, 2);
    try t.expectEqual(cfg.output_channels, 2);
    try t.expectEqual(cfg.name, "Audio");
}
