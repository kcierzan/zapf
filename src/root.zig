const std = @import("std");

const clap = @import("api/clap.zig");
const plugin = @import("plugin.zig");
const params_mod = @import("params.zig");
const audio_mod = @import("audio.zig");
const process_mod = @import("process.zig");
const clap_adapter = @import("adapters/clap.zig");

pub const PluginDescriptor = plugin.PluginDescriptor;
// TODO: we probably want a generic plugin features module rather
// than exposing CLAP values directly
pub const PluginFeatures = clap.PluginFeatures;
pub const Float = params_mod.Float;
pub const ParamOpts = params_mod.ParamOpts;
pub const ParamFlags = params_mod.ParamFlags;
pub const AudioPortConfig = audio_mod.AudioPortConfig;
pub const ProcessContext = process_mod.ProcessContext;
pub const ProcessResult = process_mod.ProcessResult;
pub const exportClapPlugin = clap_adapter.exportEntry;

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
    _ = @import("adapters/clap_extensions/state.zig");
    _ = @import("tests/mock_host.zig");
}
