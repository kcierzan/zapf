//! We aren't include a ParamEvent type here because we intend to apply
//! param changes to values at the adapter level automatically. This should
//! lighten the load a bit on framework consumers who would otherwise need
//! to do some version of this manually. Given the divergences in param
//! handling between the target plugin formats, this would be a huge pain.

const std = @import("std");
const t = std.testing;

pub const PluginEvent = struct {
    time: u32,
    data: Data,

    pub const Data = union(enum) {
        note_on: NoteEvent,
        note_off: NoteEvent,
        midi: MidiEvent,
        unknown: void,
    };
};

pub const NoteEvent = struct {
    note_id: i32,
    port_index: i16,
    channel: i16,
    velocity: f64,
    key: i16,
};

pub const MidiEvent = struct {
    port_index: u16,
    data: [3]u8,
};

pub fn isEventIterator(comptime T: type) bool {
    if (!@hasDecl(T, "next")) return false;
    if (!@hasDecl(T, "reset")) return false;
    // verify return type of next
    const next_info = @typeInfo(@TypeOf(T.next));
    if (next_info != .@"fn") return false;
    if (next_info.@"fn".return_type != ?PluginEvent) return false;
    return true;
}

pub const SliceEventIterator = struct {
    events_buf: []const PluginEvent,
    index: u32 = 0,

    pub fn next(self: *SliceEventIterator) ?PluginEvent {
        if (self.index >= self.events_buf.len) return null;
        const event = self.events_buf[self.index];
        self.index += 1;
        return event;
    }

    pub fn reset(self: *SliceEventIterator) void {
        self.index = 0;
    }

    pub const empty: SliceEventIterator = .{ .events_buf = &.{} };
};

test "SliceEventIterator is an event iterator" {
    try t.expect(isEventIterator(SliceEventIterator));
}

const NonIterator = struct {
    pub fn next(self: *NonIterator) i32 {
        _ = self;
        return 22;
    }

    pub fn reset(self: *NonIterator) bool {
        _ = self;
        return false;
    }
};

test "isEventIterator returns false for a non-iterator" {
    try t.expect(!isEventIterator(NonIterator));
}

test "isEventIterator returns false for an empty struct" {
    try t.expect(!isEventIterator(struct {}));
}

test "SliceEventIterator yields all events in slice order" {
    const ev = [_]PluginEvent{ .{ .time = 0, .data = .{ .note_on = .{
        .note_id = 1,
        .port_index = 0,
        .channel = 0,
        .key = 60,
        .velocity = 0.8,
    } } }, .{ .time = 60, .data = .{ .note_off = .{
        .note_id = 1,
        .port_index = 0,
        .channel = 0,
        .key = 60,
        .velocity = 0.0,
    } } } };

    var iter = SliceEventIterator{ .events_buf = &ev };

    const first = iter.next().?;
    try t.expectEqual(@as(i16, 60), first.data.note_on.key);
    try t.expectEqual(@as(i16, 0), first.time);
}
