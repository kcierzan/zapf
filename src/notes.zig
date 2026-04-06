const std = @import("std");
const clap_api = @import("api/clap.zig");
const t = std.testing;

pub const NotePortConfig = struct {
    id: u32 = 0,
    // bitfield of NoteDialects
    supported_dialects: u32 = 0,
    preferred_dialect: u32 = 0,
    name: [:0]const u8 = "Note input",
};

pub const NotePortsConfig = struct {
    inputs: []const NotePortConfig = &.{},
    outputs: []const NotePortConfig = &.{},
};

// FIXME: this is inherently a CLAP concept AFAIK so this is coupled
// to the CLAP bit values for note dialects here
pub const NoteDialect = enum(u32) {
    clap = clap_api.NoteDialect.CLAP,
    midi = clap_api.NoteDialect.MIDI,
    midi_mpe = clap_api.NoteDialect.MIDI_MPE,
    midi2 = clap_api.NoteDialect.MIDI2,
};

test "NotePortConfig has sensible defaults" {
    const cfg = NotePortConfig{};

    try t.expectEqual(cfg.id, 0);
    try t.expectEqual(cfg.supported_dialects, 0);
    try t.expectEqualStrings(cfg.name, "Note input");
}

test "NotePortsConfig defaults to no ports" {
    const cfg = NotePortsConfig{};

    try t.expectEqual(cfg.inputs.len, 0);
    try t.expectEqual(cfg.outputs.len, 0);
}
