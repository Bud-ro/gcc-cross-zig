//! Builds GMP 6.3.0 as a static library from the pristine upstream source,
//! using only the Zig build system (no ./configure, no make).
//!
//! Configuration mirrors `./configure --disable-assembly` on a 64-bit host:
//! every mpn routine comes from mpn/generic/, GMP_LIMB_BITS = 64, nail = 0.
//! The handful of build-time generator programs (gen-fib, gen-bases, ...) are
//! compiled for and run on the native build machine to emit the lookup-table
//! headers; the library objects are compiled for `host_target`.
//!
//! Linked into GCC's cc1 so the toolchain can target a host (Windows/macOS)
//! that has no system libgmp.
//! SPDX-License-Identifier: LGPL-3.0-or-later

const std = @import("std");

/// Generic mpn sources present in the tree but never selected for a
/// generic (assembly-disabled) build -- they are alternate implementations
/// chosen only on specific assembly CPUs.
const excluded_generic = [_][]const u8{
    "div_qr_1n_pi2.c",
    "div_qr_1u_pi2.c",
    "udiv_w_sdiv.c",
};

/// mpn/generic sources that hold several functions selected by -DOPERATION_*.
/// Each is compiled once per operation, producing one object per function.
const MultiFunc = struct { file: []const u8, ops: []const []const u8 };
const multi_funcs = [_]MultiFunc{
    .{ .file = "logops_n.c", .ops = &.{ "and_n", "andn_n", "nand_n", "ior_n", "iorn_n", "nior_n", "xor_n", "xnor_n" } },
    .{ .file = "popham.c", .ops = &.{ "popcount", "hamdist" } },
    .{ .file = "sec_aors_1.c", .ops = &.{ "sec_add_1", "sec_sub_1" } },
    .{ .file = "sec_div.c", .ops = &.{ "sec_div_qr", "sec_div_r" } },
    .{ .file = "sec_pi1_div.c", .ops = &.{ "sec_pi1_div_qr", "sec_pi1_div_r" } },
};

/// Top-level library objects (libgmp_la_SOURCES + the reentrant TMP object).
const toplevel_srcs = [_][]const u8{
    "assert.c",       "compat.c",   "errno.c",      "extract-dbl.c",
    "invalid.c",      "memory.c",   "mp_bpl.c",     "mp_clz_tab.c",
    "mp_dv_tab.c",    "mp_minv_tab.c", "mp_get_fns.c", "mp_set_fns.c",
    "version.c",      "nextprime.c", "primesieve.c", "tal-reent.c",
};

/// Subdirectories whose every .c file is a library object.
const lib_subdirs = [_][]const u8{ "mpz", "mpq", "mpf", "printf", "scanf", "rand" };

/// Build a static libgmp.a. `host_target` is the toolchain's host (where cc1
/// runs); the generator programs always build+run natively.
pub fn addGmp(
    b: *std.Build,
    gmp_root: std.Build.LazyPath,
    host_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const native = b.resolveTargetQuery(.{});
    const is_windows = host_target.result.os.tag == .windows;

    // gmp.h from gmp-h.in. Only the limb type differs across our 64-bit hosts:
    // x86_64-windows-gnu is LLP64 (32-bit long), so the limb must be declared
    // as `unsigned long long` via _LONG_LONG_LIMB; elsewhere `unsigned long`
    // is already 64-bit.
    const defn_limb: []const u8 = if (is_windows)
        "#define _LONG_LONG_LIMB 1"
    else
        "/* #undef _LONG_LONG_LIMB */";
    const gmp_h = b.addConfigHeader(.{
        .style = .{ .autoconf_at = gmp_root.path(b, "gmp-h.in") },
        .include_path = "gmp.h",
    }, .{
        .HAVE_HOST_CPU_FAMILY_power = @as(i64, 0),
        .HAVE_HOST_CPU_FAMILY_powerpc = @as(i64, 0),
        .GMP_LIMB_BITS = @as(i64, 64),
        .GMP_NAIL_BITS = @as(i64, 0),
        .DEFN_LONG_LONG_LIMB = defn_limb,
        .LIBGMP_DLL = @as(i64, 0),
        .CC = @as([]const u8, "zig cc"),
        .CFLAGS = @as([]const u8, "-O2"),
    });

    // Generated include dir: hand-written config.h + empty gmp-mparam.h plus
    // the lookup tables emitted by the generator programs.
    const gen = b.addWriteFiles();
    _ = gen.add("config.h", configH(b, host_target));
    _ = gen.add("gmp-mparam.h", "/* generic target: no special parameters */\n");

    // Generator programs run natively and write their tables to stdout. The
    // two "table" forms become C sources, so they need a .c basename.
    const fib_h = runGen(b, buildGen(b, gmp_root, native, "gen-fib", false), &.{ "header", "64", "0" }, "fib_table.h");
    const fib_c = runGen(b, buildGen(b, gmp_root, native, "gen-fib", false), &.{ "table", "64", "0" }, "fib_table.c");
    const bases_h = runGen(b, buildGen(b, gmp_root, native, "gen-bases", true), &.{ "header", "64", "0" }, "mp_bases.h");
    const bases_c = runGen(b, buildGen(b, gmp_root, native, "gen-bases", true), &.{ "table", "64", "0" }, "mp_bases.c");
    const fac_h = runGen(b, buildGen(b, gmp_root, native, "gen-fac", false), &.{ "64", "0" }, "fac_table.h");
    const sieve_h = runGen(b, buildGen(b, gmp_root, native, "gen-sieve", false), &.{"64"}, "sieve_table.h");
    const trial_h = runGen(b, buildGen(b, gmp_root, native, "gen-trialdivtab", true), &.{ "64", "8000" }, "trialdivtab.h");
    const jacobi_h = runGen(b, buildGen(b, gmp_root, native, "gen-jacobitab", false), &.{}, "jacobitab.h");
    const perfsqr_h = runGen(b, buildGen(b, gmp_root, native, "gen-psqr", true), &.{ "64", "0" }, "perfsqr.h");

    _ = gen.addCopyFile(fib_h, "fib_table.h");
    _ = gen.addCopyFile(bases_h, "mp_bases.h");
    _ = gen.addCopyFile(fac_h, "fac_table.h");
    _ = gen.addCopyFile(sieve_h, "sieve_table.h");
    _ = gen.addCopyFile(trial_h, "trialdivtab.h");
    _ = gen.addCopyFile(jacobi_h, "mpn/jacobitab.h");
    _ = gen.addCopyFile(perfsqr_h, "mpn/perfsqr.h");
    const gen_dir = gen.getDirectory();

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "gmp",
        .root_module = b.createModule(.{
            .target = host_target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const mod = lib.root_module;

    // Include order: generated dir (config.h/gmp.h/tables) first, then the
    // source root (gmp-impl.h, longlong.h) and the mpn-local generated headers.
    mod.addConfigHeader(gmp_h);
    mod.addIncludePath(gen_dir);
    mod.addIncludePath(gen_dir.path(b, "mpn"));
    mod.addIncludePath(gmp_root);
    mod.addIncludePath(gmp_root.path(b, "mpn"));

    const base_flags = [_][]const u8{ "-DHAVE_CONFIG_H", "-D__GMP_WITHIN_GMP" };

    // The two generated table sources compile straight into the library.
    mod.addCSourceFile(.{ .file = fib_c, .flags = &base_flags });
    mod.addCSourceFile(.{ .file = bases_c, .flags = &base_flags });

    // mpn/generic: every selected file, each with its -DOPERATION_<fn>.
    const generic_dir = gmp_root.path(b, "mpn/generic");
    for (collectCFiles(b, generic_dir)) |f| {
        if (isExcluded(f) or isMultiFunc(f)) continue;
        const op = f[0 .. f.len - 2]; // strip ".c"
        mod.addCSourceFile(.{
            .file = generic_dir.path(b, f),
            .flags = opFlags(b, &base_flags, op),
        });
    }
    for (multi_funcs) |mf| {
        for (mf.ops) |op| {
            mod.addCSourceFile(.{
                .file = generic_dir.path(b, mf.file),
                .flags = opFlags(b, &base_flags, op),
            });
        }
    }

    // Top-level objects.
    mod.addCSourceFiles(.{ .root = gmp_root, .files = &toplevel_srcs, .flags = &base_flags });

    // Whole-directory objects.
    for (lib_subdirs) |sub| {
        const dir = gmp_root.path(b, sub);
        mod.addCSourceFiles(.{
            .root = dir,
            .files = collectCFiles(b, dir),
            .flags = &base_flags,
        });
    }

    // mpf/get_d etc. use frexp/ldexp; pull in libm (propagates to cc1).
    if (!is_windows) mod.linkSystemLibrary("m", .{});

    lib.installConfigHeader(gmp_h);
    return lib;
}

fn opFlags(b: *std.Build, base: []const []const u8, op: []const u8) []const []const u8 {
    const out = b.allocator.alloc([]const u8, base.len + 1) catch @panic("OOM");
    @memcpy(out[0..base.len], base);
    out[base.len] = b.fmt("-DOPERATION_{s}", .{op});
    return out;
}

fn isExcluded(name: []const u8) bool {
    for (excluded_generic) |e| if (std.mem.eql(u8, e, name)) return true;
    return false;
}

fn isMultiFunc(name: []const u8) bool {
    for (multi_funcs) |mf| if (std.mem.eql(u8, mf.file, name)) return true;
    return false;
}

/// Build one generator program for the native build machine.
fn buildGen(
    b: *std.Build,
    gmp_root: std.Build.LazyPath,
    native: std.Build.ResolvedTarget,
    name: []const u8,
    needs_libm: bool,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .target = native,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
    });
    // gen-*.c #include "bootstrap.c" which #includes "mini-gmp/mini-gmp.c";
    // both resolve relative to the source root.
    exe.root_module.addCSourceFile(.{
        .file = gmp_root.path(b, b.fmt("{s}.c", .{name})),
        .flags = &.{},
    });
    exe.root_module.addIncludePath(gmp_root);
    if (needs_libm) exe.root_module.linkSystemLibrary("m", .{});
    return exe;
}

fn runGen(b: *std.Build, exe: *std.Build.Step.Compile, args: []const []const u8, basename: []const u8) std.Build.LazyPath {
    const run = b.addRunArtifact(exe);
    run.addArgs(args);
    return run.captureStdOut(.{ .basename = basename });
}

/// Hand-written config.h equivalent to `configure --disable-assembly` on a
/// 64-bit host. Only SIZEOF_UNSIGNED_LONG varies (LLP64 on Windows).
fn configH(b: *std.Build, host_target: std.Build.ResolvedTarget) []const u8 {
    const sizeof_long: u8 = if (host_target.result.os.tag == .windows) 4 else 8;
    return b.fmt(
        \\/* Generated by gcc-cross-zig: GMP 6.3.0, generic C, assembly disabled. */
        \\#define NO_ASM 1
        \\#define WANT_TMP_ALLOCA 1
        \\#define WANT_FFT 1
        \\#define SIZEOF_MP_LIMB_T 8
        \\#define SIZEOF_UNSIGNED_LONG {d}
        \\#define SIZEOF_UNSIGNED 4
        \\#define SIZEOF_UNSIGNED_SHORT 2
        \\#define SIZEOF_VOID_P 8
        \\#define HAVE_DOUBLE_IEEE_LITTLE_ENDIAN 1
        \\#define HAVE_LIMB_LITTLE_ENDIAN 1
        \\#define HAVE_ALLOCA 1
        \\#define HAVE_RAISE 1
        \\#define HAVE_STDINT_H 1
        \\#define HAVE_STDLIB_H 1
        \\#define HAVE_STRING_H 1
        \\#define HAVE_INTMAX_T 1
        \\#define HAVE_INTPTR_T 1
        \\#define HAVE_UINT_LEAST32_T 1
        \\#define HAVE_LONG_LONG 1
        \\#define HAVE_ATTRIBUTE_CONST 1
        \\#define HAVE_ATTRIBUTE_MALLOC 1
        \\#define HAVE_ATTRIBUTE_NORETURN 1
        \\#define HAVE_ATTRIBUTE_MODE 1
        \\#define HAVE_MEMSET 1
        \\#define HAVE_STRCHR 1
        \\#define HAVE_STRNLEN 1
        \\#define HAVE_VSNPRINTF 1
        \\#define HAVE_SYS_TYPES_H 1
        \\#define HAVE_UNISTD_H 1
        \\#define HAVE_INTTYPES_H 1
        \\#define STDC_HEADERS 1
        \\#define VERSION "6.3.0"
        \\#define PACKAGE_VERSION "6.3.0"
        \\
    , .{sizeof_long});
}

/// List the .c file names directly in `dir` (sorted, for deterministic builds).
/// Resolved at configure time via the shell -- the dependency tree is already
/// unpacked, and this avoids depending on the moving std filesystem API.
fn collectCFiles(b: *std.Build, dir: std.Build.LazyPath) []const []const u8 {
    const abs = dir.getPath(b);
    const out = b.run(&.{ "sh", "-c", b.fmt("cd '{s}' && ls *.c | LC_ALL=C sort", .{abs}) });

    var names: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, out, '\n');
    while (it.next()) |line| {
        const name = std.mem.trim(u8, line, " \t\r");
        if (name.len == 0) continue;
        names.append(b.allocator, b.dupe(name)) catch @panic("OOM");
    }
    return names.toOwnedSlice(b.allocator) catch @panic("OOM");
}
