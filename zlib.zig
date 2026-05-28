//! Builds zlib as a static library from the pristine upstream source tree.
//! Used so the toolchain can cross-compile without a system libz (binutils and
//! cc1 both link zlib). zlib ships a ready-to-use zconf.h/zlib.h, so no
//! configure step is needed -- we just compile the C sources directly.
//! SPDX-License-Identifier: Zlib

const std = @import("std");

const zlib_srcs = [_][]const u8{
    "adler32.c", "crc32.c",    "deflate.c",  "infback.c",
    "inffast.c", "inflate.c",  "inftrees.c", "trees.c",
    "zutil.c",   "compress.c", "uncompr.c",  "gzclose.c",
    "gzlib.c",   "gzread.c",   "gzwrite.c",
};

/// Build a static `libz.a` from the zlib source rooted at `zlib_root`,
/// targeting `target`. The returned artifact also exposes zlib.h/zconf.h as
/// installed headers, so dependents that `linkLibrary` it can `#include <zlib.h>`.
pub fn addZlib(
    b: *std.Build,
    zlib_root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "z",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // zlib's own feature macros. Windows has no <unistd.h>/large-file API; the
    // POSIX targets do. HAVE_HIDDEN lets zlib mark internal symbols hidden.
    const flags: []const []const u8 = if (target.result.os.tag == .windows)
        &.{ "-DHAVE_STDARG_H", "-DHAVE_SYS_TYPES_H" }
    else
        &.{ "-D_LARGEFILE64_SOURCE=1", "-DHAVE_UNISTD_H", "-DHAVE_STDARG_H", "-DHAVE_HIDDEN" };

    lib.root_module.addCSourceFiles(.{
        .root = zlib_root,
        .files = &zlib_srcs,
        .flags = flags,
    });
    lib.root_module.addIncludePath(zlib_root);
    lib.installHeadersDirectory(zlib_root, "", .{
        .include_extensions = &.{ "zlib.h", "zconf.h" },
    });
    return lib;
}
