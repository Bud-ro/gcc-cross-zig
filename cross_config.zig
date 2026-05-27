//! Shared configuration types for gcc-cross-zig toolchain builds.
//! SPDX-License-Identifier: GPL-2.0-or-later

const std = @import("std");

/// Configuration for a cross-toolchain target.
/// Provided by the consumer (e.g. gcc-rl78-zig) to the shared build modules.
pub const CrossConfig = struct {
    /// Target triple, e.g. "rl78-elf"
    target_triple: []const u8,
    /// Target CPU name, e.g. "rl78"
    target_cpu: []const u8,
    /// Canonical target triple, e.g. "rl78-unknown-elf"
    target_canonical: []const u8,
    /// Target OS component, e.g. "elf"
    target_os: []const u8,
    /// Target vendor component, e.g. "unknown"
    target_vendor: []const u8,

    /// Binutils version for config headers
    binutils_version: std.SemanticVersion,
    /// GCC version string, e.g. "14.2.0"
    gcc_version: []const u8,
    /// GCC datestamp, e.g. "20240801"
    gcc_datestamp: []const u8,

    // -----------------------------------------------------------------
    // BFD configuration (libbfd target vector selection)
    // -----------------------------------------------------------------

    /// Default BFD vector, e.g. "rl78_elf32_vec"
    bfd_default_vector: []const u8,
    /// Extra BFD vectors to select (HAVE_xxx macros)
    bfd_select_vectors: []const []const u8,
    /// Formatted SELECT_VECS string, e.g. "&rl78_elf32_vec,&elf32_le_vec,&elf32_be_vec"
    bfd_select_vecs_str: []const u8,
    /// Formatted SELECT_ARCHITECTURES string, e.g. "&bfd_rl78_arch"
    bfd_select_archs_str: []const u8,

    /// BFD ELF target source files (relative to bfd/ in upstream), e.g. "elf32-rl78.c"
    bfd_elf_target_srcs: []const []const u8,
    /// BFD CPU architecture file, e.g. "cpu-rl78.c"
    bfd_cpu_arch_src: []const u8,

    // -----------------------------------------------------------------
    // Opcodes configuration
    // -----------------------------------------------------------------

    /// Opcodes target source files
    opcodes_target_srcs: []const []const u8,
    /// Opcodes architecture flag, e.g. "-DARCH_rl78"
    opcodes_arch_flag: []const u8,

    // -----------------------------------------------------------------
    // GAS (assembler) configuration
    // -----------------------------------------------------------------

    /// gas target-specific source files (relative to gas/config/ in upstream)
    gas_target_srcs: []const []const u8,
    /// DEFAULT_ARCH macro value for gas, e.g. "rl78"
    gas_default_arch: []const u8,

    // -----------------------------------------------------------------
    // LD (linker) configuration
    // -----------------------------------------------------------------

    /// LD default emulation, e.g. "elf32rl78"
    ld_default_emulation: []const u8,
    /// Path to vendored LD emulation file (relative to consumer repo)
    ld_emulation_file: std.Build.LazyPath,

    // -----------------------------------------------------------------
    // GCC cc1 configuration
    // -----------------------------------------------------------------

    /// Path to generated/ dir for this target (relative to consumer repo)
    generated_dir: std.Build.LazyPath,
    /// Path to config/<target>/ dir (relative to consumer repo)
    config_dir: std.Build.LazyPath,
    /// Path to config/libcpp/ dir
    libcpp_config_dir: std.Build.LazyPath,
    /// Path to config/libdecnumber/ dir
    libdecnumber_config_dir: std.Build.LazyPath,
    /// Path to config/backtrace-stub.cc
    backtrace_stub: std.Build.LazyPath,
    /// Path to config/libcody-config.h
    libcody_config: std.Build.LazyPath,

    /// GCC target-specific source files (relative to gcc/ in upstream)
    gcc_target_srcs: []const []const u8,

    // -----------------------------------------------------------------
    // Include paths for binutils (gas, ld, tools)
    // -----------------------------------------------------------------

    /// Path to include/ directory with targmatch.h, targ-cpu.h, etc.
    include_dir: std.Build.LazyPath,
    /// Path to vendor/ld/ directory for emulation include
    vendor_ld_dir: std.Build.LazyPath,

    /// Path to find_replace.zig tool (from gcc-cross-zig)
    find_replace_zig: std.Build.LazyPath,
};

/// Shared library artifacts built by binutils_libs and passed to executables.
pub const Libs = struct {
    iberty: *std.Build.Step.Compile,
    libsframe: *std.Build.Step.Compile,
    bfd: *std.Build.Step.Compile,
    bfd_header: *std.Build.Step.ConfigHeader,
    bfdver_header: *std.Build.Step.ConfigHeader,
    libbfd_config_header: *std.Build.Step.ConfigHeader,
    libopcodes: *std.Build.Step.Compile,
};
