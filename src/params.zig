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
    /// Host grouping path, e.g. "Envelope/Attack". Uses "/" as separator.
    /// Empty string means no grouping. Max 1023 bytes (CLAP_PATH_SIZE - 1).
    module: [:0]const u8 = "",
    min: f64 = 0.0,
    max: f64 = 1.0,
    default: f64 = 0.0,
    flags: ParamFlags = .{},
    id: ?u32 = null,
    /// When set, paramsValueToText will format values as "{value} {unit}",
    /// e.g. "440.00 Hz" or "-6.00 dB". When null, the host handles formatting.
    unit: ?[:0]const u8 = null,
    /// Snap step size for stepped params. Requires flags.stepped = true.
    /// When null and stepped is true, defaults to 1.0 (integer snapping).
    step: ?f64 = null,
};

pub fn Float(comptime opts: ParamOpts) type {
    comptime {
        if (opts.step != null and !opts.flags.stepped)
            @compileError("'step' requires 'flags.stepped = true'");
    }
    return struct {
        value: std.atomic.Value(f64) = .{ .raw = opts.default },

        pub const param_meta: ParamOpts = opts;

        pub fn get(self: *const @This()) f32 {
            // intentionally defaulting to a loss of precision here as
            // f32 is more common in DSP code
            return @floatCast(self.value.load(.monotonic));
        }

        pub fn set(self: *@This(), v: f64) void {
            var clamped = std.math.clamp(v, opts.min, opts.max);
            if (opts.flags.stepped) {
                const s = opts.step orelse 1.0;
                clamped = opts.min + @round((clamped - opts.min) / s) * s;
                clamped = std.math.clamp(clamped, opts.min, opts.max);
            }
            self.value.store(clamped, .monotonic);
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

        validateNoDuplicateIds(result[0..count]);
        validateAtMostOneBypass(result[0..count]);
        validateNameLengths(result[0..count]);

        return &result;
    }
}

/// Returns the raw f64 value of the param with the given ID, or null if not found.
/// `params` must be a pointer to the plugin's Params struct.
pub fn getById(params: anytype, id: u32) ?f64 {
    const ParamsType = @typeInfo(@TypeOf(params)).pointer.child;
    const discovered = comptime discoverParams(ParamsType);
    inline for (discovered) |d| {
        if (d.id == id) return @field(params, d.field_name).getRaw();
    }
    return null;
}

/// Sets the param with the given ID to value. No-op if the ID is not found.
/// `params` must be a mutable pointer to the plugin's Params struct.
pub fn setById(params: anytype, id: u32, value: f64) void {
    const ParamsType = @typeInfo(@TypeOf(params)).pointer.child;
    const discovered = comptime discoverParams(ParamsType);
    inline for (discovered) |d| {
        if (d.id == id) @field(params, d.field_name).set(value);
    }
}

/// Returns the DiscoveredParam metadata for the param with the given ID, or null.
pub fn metaById(comptime ParamsType: type, id: u32) ?DiscoveredParam {
    const discovered = comptime discoverParams(ParamsType);
    inline for (discovered) |d| {
        if (d.id == id) return d;
    }
    return null;
}

/// Returns the DiscoveredParam metadata for the param at the given index, or null.
pub fn metaByIndex(comptime ParamsType: type, index: u32) ?DiscoveredParam {
    const discovered = comptime discoverParams(ParamsType);
    comptime var idx: u32 = 0;
    inline for (discovered) |d| {
        if (idx == index) return d;
        idx += 1;
    }
    return null;
}

fn validateNoDuplicateIds(comptime params: []const DiscoveredParam) void {
    comptime {
        for (0..params.len) |a| {
            for (a + 1..params.len) |b| {
                if (params[a].id == params[b].id) {
                    @compileError("param ID collision between '" ++
                        params[a].field_name ++ "' and '" ++
                        params[b].field_name ++ "' (both resolve to ID " ++
                        std.fmt.comptimePrint("{d}", .{params[a].id}) ++ ")");
                }
            }
        }
    }
}

fn validateNameLengths(comptime params: []const DiscoveredParam) void {
    comptime {
        for (params) |d| {
            if (d.meta.name.len >= 256)
                @compileError("param '" ++ d.field_name ++ "' name exceeds CLAP_NAME_SIZE (256 bytes)");
            if (d.meta.module.len >= 1024)
                @compileError("param '" ++ d.field_name ++ "' module path exceeds CLAP_PATH_SIZE (1024 bytes)");
        }
    }
}

fn validateAtMostOneBypass(comptime params: []const DiscoveredParam) void {
    comptime {
        var bypass_count: usize = 0;
        var bypass_field: [:0]const u8 = "";
        for (params) |d| {
            if (d.meta.flags.bypass) {
                bypass_count += 1;
                if (bypass_count == 2)
                    @compileError("multiple bypass params: '" ++ bypass_field ++
                        "' and '" ++ d.field_name ++ "' — only one bypass param allowed");
                bypass_field = d.field_name;
            }
        }
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

test "Float stepped snaps to nearest integer by default" {
    var p: Float(.{ .name = "Steps", .min = 0.0, .max = 4.0, .flags = .{ .stepped = true } }) = .{};
    p.set(1.4);
    try t.expectEqual(@as(f64, 1.0), p.getRaw());
    p.set(1.6);
    try t.expectEqual(@as(f64, 2.0), p.getRaw());
}

test "Float stepped with explicit step size snaps to nearest step" {
    var p: Float(.{ .name = "Steps", .min = 0.0, .max = 1.0, .flags = .{ .stepped = true }, .step = 0.25 }) = .{};
    p.set(0.1);
    try t.expectEqual(@as(f64, 0.0), p.getRaw());
    p.set(0.15);
    try t.expectEqual(@as(f64, 0.25), p.getRaw());
    p.set(0.9);
    try t.expectEqual(@as(f64, 1.0), p.getRaw());
}

test "Float concurrent set/get produces no torn reads" {
    const XParam = Float(.{ .name = "X", .min = 0.0, .max = 1.0, .default = 0.5 });
    var param: XParam = .{};

    const writer_thread = try std.Thread.spawn(.{}, struct {
        fn run(p: *XParam) void {
            for (0..100_000) |i| {
                p.set(if (i % 2 == 0) 0.0 else 1.0);
            }
        }
    }.run, .{&param});

    for (0..100_000) |_| {
        const v = param.get();
        // A torn f64 write would produce a value outside [0, 1] or NaN,
        // causing this assertion to fail.
        try t.expect(v >= 0.0 and v <= 1.0);
    }

    writer_thread.join();
}
