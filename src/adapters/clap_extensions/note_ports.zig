const std = @import("std");
const clap = @import("../../api/clap.zig");
const notes = @import("../../notes.zig");

pub fn NotePortsExtension(comptime PluginType: type) type {
    return struct {
        pub const ext = clap.NotePorts{
            .count = notePortsCount,
            .get = notePortsGet,
        };

        pub const extension_name = &clap.EXT_NOTE_PORTS;

        fn notePortsCount(
            plugin: [*c]const clap.Plugin,
            is_input: bool,
        ) callconv(.c) u32 {
            _ = plugin;
            const ports = if (is_input) PluginType.note_ports.inputs else PluginType.note_ports.outputs;
            return @intCast(ports.len);
        }

        fn notePortsGet(
            plugin: [*c]const clap.Plugin,
            index: u32,
            is_input: bool,
            info: [*c]clap.NotePortInfo,
        ) callconv(.c) bool {
            _ = plugin;
            const ports = if (is_input) PluginType.note_ports.inputs else PluginType.note_ports.outputs;
            if (index >= ports.len) return false;
            const port = ports[index];
            info.*.id = port.id;
            info.*.supported_dialects = port.supported_dialects;
            info.*.preferred_dialect = port.preferred_dialect;
            const name = port.name;
            @memcpy(info.*.name[0..name.len], name);
            info.*.name[name.len] = 0;
            return true;
        }
    };
}

const TestPluginWithPorts = struct {
    pub const note_ports = notes.NotePortsConfig{
        .inputs = &.{
            .{ .id = 0, .name = "Note input" },
        },
        .outputs = &.{},
    };
};

const TestPluginNoPorts = struct {
    pub const note_ports = notes.NotePortsConfig{};
};

test "note-ports count reflects slice lengths" {
    const Ext = NotePortsExtension(TestPluginWithPorts);
    try std.testing.expectEqual(@as(u32, 1), Ext.notePortsCount(undefined, true));
    try std.testing.expectEqual(@as(u32, 0), Ext.notePortsCount(undefined, false));
}

test "note-ports count is zero when no ports configured" {
    const Ext = NotePortsExtension(TestPluginNoPorts);
    try std.testing.expectEqual(@as(u32, 0), Ext.notePortsCount(undefined, true));
    try std.testing.expectEqual(@as(u32, 0), Ext.notePortsCount(undefined, false));
}

test "note-ports get returns false for out-of-range index" {
    const Ext = NotePortsExtension(TestPluginNoPorts);
    var info: clap.NotePortInfo = undefined;
    try std.testing.expect(!Ext.notePortsGet(undefined, 0, true, &info));
}

const midi_and_mpe = @intFromEnum(notes.NoteDialect.midi) | @intFromEnum(notes.NoteDialect.midi_mpe);

const SynthPlugin = struct {
    pub const note_ports = notes.NotePortsConfig{
        .inputs = &.{.{
            .id = 0,
            .supported_dialects = midi_and_mpe,
            .preferred_dialect = @intFromEnum(notes.NoteDialect.midi),
            .name = "MIDI input",
        }},
        .outputs = &.{},
    };
};

test "synth note-ports: one input, no outputs" {
    const Ext = NotePortsExtension(SynthPlugin);
    try std.testing.expectEqual(@as(u32, 1), Ext.notePortsCount(undefined, true));
    try std.testing.expectEqual(@as(u32, 0), Ext.notePortsCount(undefined, false));
}

test "synth note-ports: get returns correct MIDI+MPE dialect config" {
    const Ext = NotePortsExtension(SynthPlugin);
    var info: clap.NotePortInfo = undefined;
    try std.testing.expect(Ext.notePortsGet(undefined, 0, true, &info));
    try std.testing.expectEqual(@as(u32, 0), info.id);
    try std.testing.expectEqual(midi_and_mpe, info.supported_dialects);
    try std.testing.expectEqual(@intFromEnum(notes.NoteDialect.midi), info.preferred_dialect);
}

test "synth note-ports: output get returns false" {
    const Ext = NotePortsExtension(SynthPlugin);
    var info: clap.NotePortInfo = undefined;
    try std.testing.expect(!Ext.notePortsGet(undefined, 0, false, &info));
}
