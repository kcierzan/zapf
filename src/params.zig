const std = @import("std");
const t = std.testing;

pub const ParamFlags = struct {
    automatable: bool = false,
    modulatable: bool = false,
    stepped: bool = false,
    hidden: bool = false,
    readonly: bool = false,
    bypass: bool = false,
};

pub const Param = struct {
    id: u32,
    name: [:0]const u8,
    module: [:0]const u8 = "",
    min: f64 = 0.0,
    max: f64 = 0.0,
    default: f64 = 0.0,
    flags: ParamFlags = .{},
};

pub fn ParamValues(comptime count: usize) type {
    return struct {
        const Self = @This();
        // tricking zls which will substitute 0 for the comptime value `count`
        // and show errors for indexing into an empty array
        values: [@max(count, 1)]f64 = undefined,

        pub fn reset(self: *Self, comptime param_list: []const Param) void {
            inline for (param_list, 0..) |p, i| {
                self.values[i] = p.default;
            }
        }

        pub fn get(self: *const Self, index: usize) f64 {
            if (comptime count == 0) unreachable;
            return self.values[index];
        }

        pub fn set(self: *Self, index: usize, value: f64, comptime param_list: []const Param) void {
            if (comptime param_list.len == 0) return;
            self.values[index] = std.math.clamp(value, param_list[index].min, param_list[index].max);
        }

        pub fn indexFromId(comptime param_list: []const Param, id: u32) ?usize {
            inline for (param_list, 0..) |p, i| {
                if (p.id == id) return i;
            }
            return null;
        }
    };
}

const test_params = &[_]Param{
    .{
        .id = 0,
        .name = "Gain",
        .min = 0.0,
        .max = 1.0,
        .default = 0.5,
        .flags = .{ .automatable = true },
    },
    .{
        .id = 1,
        .name = "Pan",
        .min = -1.0,
        .max = 1.0,
        .default = 0.0,
    },
};

test "ParamValues reset defaults" {
    var vals: ParamValues(test_params.len) = .{};
    vals.reset(test_params);

    try t.expectEqual(@as(f64, 0.5), vals.get(0));
    try t.expectEqual(@as(f64, 0.0), vals.get(1));
}

test "ParamValues set clamps to range" {
    var vals: ParamValues(test_params.len) = .{};
    vals.reset(test_params);

    vals.set(0, 5.0, test_params); // max is 1.0
    try t.expectEqual(@as(f64, 1.0), vals.get(0));

    vals.set(1, -10.0, test_params); // min is -1.0
    try t.expectEqual(@as(f64, -1.0), vals.get(1));
}

test "ParamValues indexFromId finds correct index" {
    const idx = ParamValues(test_params.len).indexFromId(test_params, 1);
    try t.expectEqual(@as(?usize, 1), idx);
}

test "ParamValues indexFromId returns null for unknown ID" {
    const idx = ParamValues(test_params.len).indexFromId(test_params, 10);
    try t.expectEqual(@as(?usize, null), idx);
}

test "ParamFlags defaults are all false" {
    const flags = ParamFlags{};
    try t.expect(!flags.automatable);
    try t.expect(!flags.modulatable);
    try t.expect(!flags.stepped);
}
