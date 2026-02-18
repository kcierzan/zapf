const std = @import("std");
const t = std.testing;
const clap = @import("../../api/clap.zig");
const audio = @import("../../audio.zig");

pub fn AudioPortsExtension(comptime PluginType: type) type {
    return struct {
        pub const ext = clap.PluginAudioPorts{
            .count = audioPortsCount,
            .get = audioPortsGet,
        };

        pub const extension_name = &clap.EXT_AUDIO_PORTS;

        fn audioPortsCount(
            plugin: [*c]const clap.Plugin,
            is_input: bool,
        ) callconv(.c) u32 {
            _ = plugin;
            return if (is_input)
                @intFromBool(PluginType.audio_ports.input_channels > 0)
            else
                @intFromBool(PluginType.audio_ports.output_channels > 0);
        }

        fn audioPortsGet(
            plugin: [*c]const clap.Plugin,
            index: u32,
            is_input: bool,
            info: [*c]clap.AudioPortInfo,
        ) callconv(.c) bool {
            _ = plugin;
            if (index != 0) return false;
            info.*.id = 0;
            info.*.channel_count = if (is_input)
                PluginType.audio_ports.input_channels
            else
                PluginType.audio_ports.output_channels;

            const name = PluginType.audio_ports.name;
            @memcpy(info.*.name[0..name.len], name);
            info.*.name[name.len] = 0;

            info.*.flags = clap.AUDIO_PORT_IS_MAIN;
            info.*.in_place_pair = clap.INVALID_ID;
            return true;
        }
    };
}

const TestPluginStereo = struct {
    pub const audio_ports = audio.AudioPortConfig{
        .input_channels = 2,
        .output_channels = 2,
    };
};

const TestPluginNoInput = struct {
    pub const audio_ports = audio.AudioPortConfig{
        .input_channels = 0,
        .output_channels = 2,
    };
};

test "audio-ports has the expected name" {
    const Ext = AudioPortsExtension(TestPluginStereo);
    try t.expectEqualStrings("clap.audio-ports", Ext.extension_name);
}

test "audio-ports reports correct port count for stereo" {
    const Ext = AudioPortsExtension(TestPluginStereo);

    try t.expectEqual(@as(u32, 1), Ext.audioPortsCount(undefined, true));
    try t.expectEqual(@as(u32, 1), Ext.audioPortsCount(undefined, false));
}

test "audio-ports reports 0 input ports when no inputs" {
    const Ext = AudioPortsExtension(TestPluginNoInput);
    try t.expectEqual(@as(u32, 0), Ext.audioPortsCount(undefined, true));
    try t.expectEqual(@as(u32, 1), Ext.audioPortsCount(undefined, false));
}
