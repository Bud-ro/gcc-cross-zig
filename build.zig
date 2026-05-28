//! Shared build logic for GNU Binutils + GCC cross-compiler toolchains.
//! This package provides reusable modules; it does not build anything on its own.
//! See gcc-rl78-zig (or similar target packages) for the actual build entry point.
//! SPDX-License-Identifier: GPL-2.0-or-later

const std = @import("std");

pub const cross_config = @import("cross_config.zig");
pub const binutils_libs = @import("binutils_libs.zig");
pub const binutils_gas = @import("binutils_gas.zig");
pub const binutils_ld = @import("binutils_ld.zig");
pub const binutils_tools = @import("binutils_tools.zig");
pub const gcc_cc1 = @import("gcc_cc1.zig");

pub const CrossConfig = cross_config.CrossConfig;
pub const Libs = cross_config.Libs;

/// Convenience: build the full toolchain from a CrossConfig.
pub fn buildToolchain(
    b: *std.Build,
    binutils_src: *std.Build.Dependency,
    gcc_src: *std.Build.Dependency,
    host_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: CrossConfig,
) void {
    // Resolve binutils source root: use override if provided, else upstream
    const binutils_root = if (config.binutils_source_root_override) |ovr|
        ovr
    else
        binutils_src.path(".");

    // Build libraries
    const iberty = binutils_libs.addLibiberty(b, binutils_root, host_target, optimize);
    const libsframe = binutils_libs.addLibsframe(b, binutils_root, host_target, optimize, config);
    const bfd_result = binutils_libs.addLibbfd(b, binutils_root, host_target, optimize, iberty, libsframe, config);
    const libopcodes = binutils_libs.addLibopcodes(b, binutils_root, host_target, optimize, bfd_result.bfd_header, config);

    const libs = Libs{
        .iberty = iberty,
        .libsframe = libsframe,
        .bfd = bfd_result.bfd,
        .bfd_header = bfd_result.bfd_header,
        .bfdver_header = bfd_result.bfdver_header,
        .libbfd_config_header = bfd_result.libbfd_config_header,
        .libopcodes = libopcodes,
    };

    // Build binutils executables
    const gas = binutils_gas.addGas(b, binutils_root, host_target, optimize, libs, config);
    const ld = binutils_ld.addLd(b, binutils_root, host_target, optimize, libs, config);
    const ar = binutils_tools.addTools(b, binutils_root, host_target, optimize, libs, config);

    // Build GCC cc1 and driver
    _ = gcc_cc1.addCc1(b, gcc_src, host_target, optimize, iberty, config);
    _ = gcc_cc1.addGccDriver(b, gcc_src, host_target, optimize, iberty, config);

    // Install tooldir layout: <target_canonical>/bin/{as,ld,ar}
    // The GCC driver searches for assembler/linker here via TOOLDIR_BASE_PREFIX.
    const tooldir = b.fmt("{s}/bin", .{config.target_canonical});
    inline for (.{
        .{ gas, "as" },
        .{ ld, "ld" },
        .{ ar, "ar" },
    }) |entry| {
        const install = b.addInstallArtifact(entry[0], .{
            .dest_dir = .{ .override = .{ .custom = tooldir } },
            .dest_sub_path = entry[1],
        });
        b.getInstallStep().dependOn(&install.step);
    }

    // Create lib/gcc/<target>/<version>/ (the GCC install prefix).
    // The driver resolves relative paths from this directory; it must exist.
    const lib_gcc_dir = b.fmt("lib/gcc/{s}/{s}", .{ config.target_canonical, config.gcc_version });
    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p" });
    mkdir_step.addArg(b.fmt("{s}/{s}", .{ b.install_path, lib_gcc_dir }));
    b.getInstallStep().dependOn(&mkdir_step.step);

    // Install GCC internal headers (stdarg.h, stddef.h, etc.) to
    // lib/gcc/<target>/<version>/include/ so the driver finds them
    // via -print-file-name=include.
    const include_dir = b.fmt("{s}/include", .{lib_gcc_dir});
    const ginclude_headers = [_][]const u8{
        "stdarg.h",    "stddef.h",      "stdbool.h",     "stdint-gcc.h",
        "stdatomic.h", "stdalign.h",    "stdnoreturn.h", "float.h",
        "iso646.h",    "stdfix.h",      "varargs.h",     "stdckdint.h",
        "tgmath.h",    "stdint-wrap.h",
    };
    for (ginclude_headers) |hdr| {
        const install_hdr = b.addInstallFile(
            gcc_src.path(b.fmt("gcc/ginclude/{s}", .{hdr})),
            b.fmt("{s}/{s}", .{ include_dir, hdr }),
        );
        b.getInstallStep().dependOn(&install_hdr.step);
    }

    // Install glimits.h as limits.h (GCC renames it during install)
    const install_limits = b.addInstallFile(
        gcc_src.path("gcc/glimits.h"),
        b.fmt("{s}/limits.h", .{include_dir}),
    );
    b.getInstallStep().dependOn(&install_limits.step);

    // Install stdint-gcc.h as stdint.h for freestanding (no newlib/libc)
    const install_stdint = b.addInstallFile(
        gcc_src.path("gcc/ginclude/stdint-gcc.h"),
        b.fmt("{s}/stdint.h", .{include_dir}),
    );
    b.getInstallStep().dependOn(&install_stdint.step);
}

pub fn build(b: *std.Build) void {
    _ = b;
}
