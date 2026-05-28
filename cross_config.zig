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
    /// Default byte order of the target (for GAS TARGET_BYTES_BIG_ENDIAN)
    target_big_endian: bool = false,

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
    /// Extra BFD CPU architecture files (e.g. "cpu-v850_rh850.c" for v850)
    bfd_extra_cpu_arch_srcs: []const []const u8 = &.{},

    // -----------------------------------------------------------------
    // Opcodes configuration
    // -----------------------------------------------------------------

    /// Opcodes target source files
    opcodes_target_srcs: []const []const u8,
    /// Opcodes architecture flag, e.g. "-DARCH_rl78"
    opcodes_arch_flag: []const u8,
    /// Extra opcodes architecture flags (e.g. "-DARCH_v850_rh850" for v850)
    opcodes_extra_arch_flags: []const []const u8 = &.{},

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
    /// Extra vendored LD emulation files (for targets with multiple emulations)
    ld_extra_emulation_files: []const std.Build.LazyPath = &.{},

    // -----------------------------------------------------------------
    // GCC cc1 configuration
    // -----------------------------------------------------------------

    /// Path to vendored generated/ dir (relative to consumer repo). Optional:
    /// targets that set up build-time generation (gtyp_input_list etc.) leave
    /// this null and generate everything from source instead.
    generated_dir: ?std.Build.LazyPath = null,
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
    /// Target-specific .opt files (relative to gcc/ in upstream), e.g.
    /// "config/rx/rx.opt". Used by the options generator (opth-gen.awk).
    gcc_target_opt_files: []const []const u8 = &.{},
    /// gengtype input manifest (the GTFILES list) with the source root spelled
    /// as the literal token @GCCSRC@. Rebased at build time. Build-input only.
    gtyp_input_list: ?std.Build.LazyPath = null,
    /// Source headers (paths relative to gcc/) to copy verbatim into the
    /// build-time generated dir at the same relative path. Used for patched
    /// headers like config/<cpu>/<cpu>-opts.h that the upstream-sourced driver
    /// must see in its patched form (resolved via the generated include dir).
    gcc_generated_extra_headers: []const []const u8 = &.{},
    /// Arguments to gcc/genmultilib (from the target's t-<cpu> fragment) to
    /// generate multilib.h. Empty means a no-multilib target (genmultilib is
    /// still invoked with empty args). Order matches GCC's genmultilib recipe.
    multilib_genargs: []const []const u8 = &.{ "", "", "", "", "", "", "", "", "", "", "no" },
    /// GCC common_out_file override (default: "common/config/default-common.cc").
    /// Set to "" to skip (when providing the common file via gcc_extra_source_files).
    gcc_common_out_file: []const u8 = "common/config/default-common.cc",

    // -----------------------------------------------------------------
    // Include paths for binutils (gas, ld, tools)
    // -----------------------------------------------------------------

    /// Path to include/ directory with targmatch.h, targ-cpu.h, etc.
    include_dir: std.Build.LazyPath,
    /// Path to vendor/ld/ directory for emulation include
    vendor_ld_dir: std.Build.LazyPath,

    /// Path to find_replace.zig tool (from gcc-cross-zig)
    find_replace_zig: std.Build.LazyPath,

    /// Override for GCC source root. When set, cc1 compilation uses this
    /// directory instead of gcc_src.path("."). Use with addWriteFiles +
    /// addCopyDirectory to create a patched source tree.
    gcc_source_root_override: ?std.Build.LazyPath = null,

    /// Override for binutils source root. When set, all binutils compilation
    /// uses this directory instead of binutils_src.path(".").
    binutils_source_root_override: ?std.Build.LazyPath = null,

    // -----------------------------------------------------------------
    // Source override support (optional)
    // -----------------------------------------------------------------

    /// Extra include directories added BEFORE upstream GCC includes,
    /// so that patched headers shadow the originals.
    gcc_extra_include_dirs: []const std.Build.LazyPath = &.{},

    /// Extra source files compiled alongside the target-specific sources.
    /// Use for patched .cc files that replace upstream originals, or for
    /// entirely new source files (e.g. rx-pragma.c).
    gcc_extra_source_files: []const ExtraSourceFile = &.{},

    /// Upstream target source paths to EXCLUDE from compilation because
    /// they are superseded by entries in gcc_extra_source_files.
    /// Paths are relative to gcc/ in the upstream source (must match
    /// entries in gcc_target_srcs exactly).
    gcc_exclude_target_srcs: []const []const u8 = &.{},

    /// Upstream OBJS paths to EXCLUDE from compilation because they are
    /// superseded by entries in gcc_extra_source_files.
    /// Paths are relative to gcc/ in the upstream source (must match
    /// entries in the objs_files list exactly).
    gcc_exclude_objs: []const []const u8 = &.{},

    /// Extra source files for the C frontend. Same semantics as
    /// gcc_extra_source_files but compiled with IN_GCC_FRONTEND flags.
    gcc_extra_frontend_source_files: []const ExtraSourceFile = &.{},

    /// Upstream C frontend paths to EXCLUDE from compilation.
    /// Paths are relative to gcc/ in the upstream source (must match
    /// entries in the c_frontend_files list exactly).
    gcc_exclude_frontend_srcs: []const []const u8 = &.{},

    pub const ExtraSourceFile = struct {
        /// The replacement or new source file.
        file: std.Build.LazyPath,
        /// Extra compile flags for this file (beyond the common flags).
        flags: []const []const u8 = &.{},
    };
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
