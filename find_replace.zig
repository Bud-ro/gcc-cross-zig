const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
});

pub fn main(init: std.process.Init.Minimal) !void {
    var it = std.process.Args.Iterator.init(init.args);
    _ = it.next(); // skip argv[0]
    const input_path = it.next() orelse return error.MissingArg;
    const output_path = it.next() orelse return error.MissingArg;
    const needle = it.next() orelse return error.MissingArg;
    const replacement = it.next() orelse return error.MissingArg;

    // Read input file using page_allocator + posix primitives
    const allocator = std.heap.page_allocator;

    // Read file contents
    const input = blk: {
        const fp = c.fopen(input_path.ptr, "rb") orelse return error.OpenFailed;
        defer _ = c.fclose(fp);
        _ = c.fseek(fp, 0, c.SEEK_END);
        const pos = c.ftell(fp);
        if (pos < 0) return error.TellFailed;
        const size: usize = @intCast(pos);
        _ = c.fseek(fp, 0, c.SEEK_SET);
        const buf = try allocator.alloc(u8, size);
        const n = c.fread(buf.ptr, 1, size, fp);
        break :blk buf[0..n];
    };

    // Replace
    const output = std.mem.replaceOwned(u8, allocator, input, needle, replacement) catch @panic("OOM");

    // Write output file
    const fp = c.fopen(output_path.ptr, "wb") orelse return error.OpenFailed;
    defer _ = c.fclose(fp);
    const written = c.fwrite(output.ptr, 1, output.len, fp);
    if (written != output.len) return error.WriteFailed;
}
