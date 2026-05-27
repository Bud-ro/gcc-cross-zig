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
    // Build libraries
    const iberty = binutils_libs.addLibiberty(b, binutils_src, host_target, optimize);
    const libsframe = binutils_libs.addLibsframe(b, binutils_src, host_target, optimize, config);
    const bfd_result = binutils_libs.addLibbfd(b, binutils_src, host_target, optimize, iberty, libsframe, config);
    const libopcodes = binutils_libs.addLibopcodes(b, binutils_src, host_target, optimize, bfd_result.bfd_header, config);

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
    const gas = binutils_gas.addGas(b, binutils_src, host_target, optimize, libs, config);
    const ld = binutils_ld.addLd(b, binutils_src, host_target, optimize, libs, config);
    const ar = binutils_tools.addTools(b, binutils_src, host_target, optimize, libs, config);

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
}

pub fn build(b: *std.Build) void {
    _ = b;
}
