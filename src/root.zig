//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const clap = @import("api/clap.zig");
pub const plugin = @import("plugin.zig");
pub const PluginDescriptor = plugin.PluginDescriptor;

test {
    // force test evaluation
    _ = @import("plugin.zig");
    _ = @import("params.zig");
}
