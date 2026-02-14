//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub export fn hello() callconv(.c) void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    stdout.print("hello world.\n", .{}) catch {};

    defer stdout.flush() catch {}; // Don't forget to flush!
}
