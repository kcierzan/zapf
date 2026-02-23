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

        pub fn getById(self: *const Self, comptime param_list: []const Param, id: u32) ?f64 {
            const index = indexFromId(param_list, id) orelse return null;
            return self.values[index];
        }

        pub fn setById(self: *Self, comptime param_list: []const Param, id: u32, value: f64) bool {
            if (comptime param_list.len == 0) return false;
            const index = indexFromId(param_list, id) orelse return false;
            self.values[index] = std.math.clamp(value, param_list[index].min, param_list[index].max);
            return true;
        }

        fn indexFromId(comptime param_list: []const Param, id: u32) ?usize {
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

    try t.expectEqual(@as(?f64, 0.5), vals.getById(test_params, 0));
    try t.expectEqual(@as(?f64, 0.0), vals.getById(test_params, 1));
}

test "ParamValues getById returns null for unknown ID" {
    var vals: ParamValues(test_params.len) = .{};
    vals.reset(test_params);

    try t.expectEqual(@as(?f64, null), vals.getById(test_params, 10));
}

test "ParamValues setById sets and clamps value" {
    var vals: ParamValues(test_params.len) = .{};
    vals.reset(test_params);

    try t.expect(vals.setById(test_params, 0, 5.0));
    try t.expectEqual(@as(?f64, 1.0), vals.getById(test_params, 0));

    vals.reset(test_params);
    try t.expect(vals.setById(test_params, 1, -10.0));
    try t.expectEqual(@as(?f64, -1.0), vals.getById(test_params, 1));

    try t.expect(!vals.setById(test_params, 99, 1.0));
}

test "ParamFlags defaults are all false" {
    const flags = ParamFlags{};
    try t.expect(!flags.automatable);
    try t.expect(!flags.modulatable);
    try t.expect(!flags.stepped);
}
