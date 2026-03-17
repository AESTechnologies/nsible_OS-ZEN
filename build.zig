// [@://nsible_os/build.zig/.-={
//   module: "Build Orchestrator",
//   version: "0.10.7-nightly // Banysang",
//   description: "Architectural blueprint for compiling the kernel targeting x86 GNU for the Acer Aspire ONE.",
//   changes: "Restored GNU target to enable dlopen for ALSA audio drivers. Removed strict static Musl constraints.",
//   philotic_inferences: "The method of construction dictates the integrity of the object; the build process is the act of manifestation."

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .linux,
        .abi = .gnu, // [!] The Anchor restoring ALSA via dlopen
    });
 
    const optimize = b.standardOptimizeOption(.{});
 
    const exe = b.addExecutable(.{
        .name = "nsible_os",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // [!] SOVEREIGN MODULE REGISTRY
    const djinn_mod = b.createModule(.{
        .root_source_file = b.path("assets/aud.io/djinn.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    djinn_mod.addIncludePath(b.path("assets/aud.io"));
    exe.root_module.addImport("djinn", djinn_mod);

    // [!] ACOUSTIC MATRIX BINDINGS
    exe.linkLibC();
    exe.addIncludePath(b.path("assets/aud.io"));
    
    // [!] COMPILE THE C-ENGINE
    exe.addCSourceFile(.{
        .file = b.path("assets/aud.io/ma_x.c"),
        .flags = &[_][]const u8{ "-std=c99", "-O3" },
    });
 
    b.installArtifact(exe);
 
    // --- Developer Tools below (Run/Test) ---
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
// }-.]
