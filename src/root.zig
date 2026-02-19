const std = @import("std");

pub const clap = @import("api/clap.zig");
pub const plugin = @import("plugin.zig");
pub const PluginDescriptor = plugin.PluginDescriptor;

test {
    // force test evaluation
    _ = @import("plugin.zig");
    _ = @import("params.zig");
    _ = @import("audio.zig");
    _ = @import("events.zig");
    _ = @import("process.zig");
    _ = @import("adapters/clap.zig");
    _ = @import("adapters/clap_extensions/audio_ports.zig");
    _ = @import("adapters/clap_extensions/params.zig");
}
