const std = @import("std");

const clap = @import("../api/clap.zig");
const events = @import("../events.zig");
const process = @import("../process.zig");

const ClapEventIterator = struct {
    input_events: *const clap.InputEvents,
    index: u32 = 0,
    count: u32,

    pub fn next(self: *ClapEventIterator) ?events.PluginEvent {
        while (self.index < self.count) : (self.index += 1) {
            const get_fn = self.input_events.get orelse return null;
            const header: *const clap.EventHeader = get_fn(self.input_events, self.index);
            // skip param value events as we will handle them separately and apply them ourselves
            if (header.space_id == clap.CORE_EVENT_SPACE_ID and header.type == clap.Event.EVENT_PARAM_VALUE) continue;
            return toPluginEvent(header);
        }
        return null;
    }

    fn reset(self: *ClapEventIterator) void {
        self.index = 0;
    }

    /// Map the clap-specific plugin event to the user-facing events.PluginEvent type.
    /// The internal plugin event is almost 1:1 with clap event types but we implement
    /// and adapter here in the interest of main
    fn toPluginEvent(header: *const clap.EventHeader) events.PluginEvent {
        if (header.space_id != clap.CORE_EVENT_SPACE_ID) return .{ .time = header.time, .data = .unknown };

        return switch (header.type) {
            clap.Event.EVENT_NOTE_ON => blk: {
                const ev: *const clap.EventNote = @ptrCast(@alignCast(header));
                break :blk .{ .time = header.time, .data = .{ .note_on = .{
                    .note_id = ev.note_id,
                    .port_index = ev.port_index,
                    .channel = ev.channel,
                    .key = ev.key,
                    .velocity = ev.velocity,
                } } };
            },
            clap.Event.EVENT_NOTE_OFF => blk: {
                const ev: *const clap.EventNote = @ptrCast(@alignCast(header));
                break :blk .{ .time = header.time, .data = .{ .note_off = .{
                    .note_id = ev.note_id,
                    .port_index = ev.port_index,
                    .channel = ev.channel,
                    .key = ev.key,
                    .velocity = ev.velocity,
                } } };
            },
            clap.Event.EVENT_MIDI => blk: {
                const ev: *const clap.EventMidi = @ptrCast(@alignCast(header));
                break :blk .{ .time = header.time, .data = .{ .midi = .{
                    .port_index = ev.port_index,
                    .data = ev.data,
                } } };
            },
            else => .{ .time = header.time, .data = .unknown },
        };
    }
};
