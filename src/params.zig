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

pub const ParamOpts = struct {
    name: [:0]const u8,
    module: [:0]const u8 = "",
    min: f64 = 0.0,
    max: f64 = 1.0,
    default: f64 = 0.0,
    flags: ParamFlags = .{},
    id: ?u32 = null,
};

pub fn Float(comptime opts: ParamOpts) type {
    return struct {
        value: std.atomic.Value(f64) = .{ .raw = opts.default },

        pub const param_meta: ParamOpts = opts;

        pub fn get(self: *const @This()) f32 {
            // intentionally defaulting to a loss of precision here as
            // f32 is more common in DSP code
            return @floatCast(self.value.load(.monotonic));
        }

        pub fn set(self: *@This(), v: f64) void {
            self.value.store(std.math.clamp(v, opts.min, opts.max), .monotonic);
        }

        pub fn reset(self: *@This()) void {
            self.value.store(opts.default, .monotonic);
        }

        pub fn getRaw(self: *const @This()) f64 {
            return self.value.load(.monotonic);
        }
    };
}

pub const DiscoveredParam = struct {
    id: u32,
    field_name: [:0]const u8,
    meta: ParamOpts,
};

pub fn discoverParams(comptime ParamsType: type) []const DiscoveredParam {
    comptime {
        const fields = std.meta.fields(ParamsType);

        var count: usize = 0;
        for (fields) |field| {
            if (@typeInfo(field.type) == .@"struct" and @hasDecl(field.type, "param_meta")) {
                count += 1;
            }
        }

        var result: [count]DiscoveredParam = undefined;
        var i: usize = 0;
        for (fields) |field| {
            if (@typeInfo(field.type) == .@"struct" and @hasDecl(field.type, "param_meta")) {
                const meta: ParamOpts = field.type.param_meta;
                const id = meta.id orelse hashFieldName(field.name);

                result[i] = .{
                    .id = id,
                    .field_name = field.name,
                    .meta = meta,
                };
                i += 1;
            }
        }

        for (0..count) |a| {
            for (a + 1..count) |b| {
                if (result[a].id == result[b].id) {
                    @compileError("param ID collision between '" ++
                        result[a].field_name ++ "' and '" ++
                        result[b].field_name ++ "' (both resolve to ID " ++
                        std.fmt.comptimePrint("{d}", .{result[a].id}) ++ ")");
                }
            }
        }

        return &result;
    }
}

/// Deterministic hash of a field name to a u32 param ID.
/// FNV-1a: fast, non-cryptographic, good distribution for short strings
pub fn hashFieldName(comptime name: [:0]const u8) u32 {
    comptime {
        var h: u32 = 2166136261; // FNV offset basis
        for (name) |byte| {
            h ^= byte;
            h *%= 16777619; // FNV prime
        }
        return h;
    }
}

test "ParamFlags defaults are all false" {
    const flags = ParamFlags{};
    try t.expect(!flags.automatable);
    try t.expect(!flags.modulatable);
    try t.expect(!flags.stepped);
}

test "Float default initialization" {
    var gain: Float(.{ .name = "Gain", .default = 0.5 }) = .{};
    try t.expectEqual(@as(f64, 0.5), gain.getRaw());
    try t.expectEqual(@as(f32, 0.5), gain.get());
}

test "Float set clamps to range" {
    var gain: Float(.{ .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5 }) = .{};
    gain.set(5.0);
    try t.expectEqual(@as(f64, 1.0), gain.getRaw());
    gain.set(-1.0);
    try t.expectEqual(@as(f64, 0.0), gain.getRaw());
}

test "Float reset restores default" {
    var gain: Float(.{ .name = "Gain", .default = 0.5 }) = .{};
    gain.set(0.9);
    try t.expectEqual(@as(f64, 0.9), gain.getRaw());
    gain.reset();
    try t.expectEqual(@as(f64, 0.5), gain.getRaw());
}

test "Float getRaw returns f64 precision" {
    var param: Float(.{ .name = "P", .default = 0.123456789012345 }) = .{};
    try t.expectEqual(@as(f64, 0.123456789012345), param.getRaw());
}

test "discoverParams finds param fields" {
    const Params = struct {
        gain: Float(.{ .name = "Gain", .default = 0.5 }) = .{},
        pan: Float(.{ .name = "Pan", .min = -1.0, .max = 1.0 }) = .{},
    };
    const discovered = comptime discoverParams(Params);
    try t.expectEqual(@as(usize, 2), discovered.len);
    try t.expectEqualStrings("gain", discovered[0].field_name);
    try t.expectEqualStrings("pan", discovered[1].field_name);
}

test "discoverParams returns empty for zero-param struct" {
    const discovered = comptime discoverParams(struct {});
    try t.expectEqual(@as(usize, 0), discovered.len);
}

test "discoverParams uses explicit id when provided" {
    const Params = struct {
        level: Float(.{ .name = "Level", .id = 42 }) = .{},
    };
    const discovered = comptime discoverParams(Params);
    try t.expectEqual(@as(u32, 42), discovered[0].id);
}

test "discoverParams hashes field name when no explicit id" {
    const Params = struct {
        gain: Float(.{ .name = "Gain" }) = .{},
    };
    const discovered = comptime discoverParams(Params);
    try t.expectEqual(comptime hashFieldName("gain"), discovered[0].id);
}

test "discoverParams skips non-param fields" {
    const Params = struct {
        gain: Float(.{ .name = "Gain" }) = .{},
        scratch: f64 = 0,
    };
    const discovered = comptime discoverParams(Params);
    try t.expectEqual(@as(usize, 1), discovered.len);
    try t.expectEqualStrings("gain", discovered[0].field_name);
}
