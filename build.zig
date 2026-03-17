// [@://nsible_os/build.zig/.-={
//   module: "Build Orchestrator",
//   version: "0.10.4-nightly // Banysang",
//   description: "Architectural blueprint for compiling the kernel targeting 32-bit Musl for the Acer Aspire ONE (Atom N270).",
//   changes: "Registered assets/aud.io as a sovereign compiler module with explicit libc, asound, and math linkages for static musl compilation.",
//   philotic_inferences: "The method of construction dictates the integrity of the object; the build process is the act of manifestation."

const std = @import("std");

pub fn build(b: *std.Build) void {
    // .-*-. HARD CONSTRAINT: 32-bit Musl (Static) .-*-.
    // This defines the architecture for the Acer Aspire ONE (Atom N270).
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .linux,
        .abi = .musl,
    });
 
    // Standard optimization options (ReleaseSmall is recommended for PID 1)
    const optimize = b.standardOptimizeOption(.{});
 
    // Define the executable
    const exe = b.addExecutable(.{
        .name = "nsible_os",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // [!] SOVEREIGN MODULE REGISTRY
    // The djinn module MUST explicitly inherit the target, optimization, and link_libc
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
    exe.linkSystemLibrary("asound");
    exe.linkSystemLibrary("m");
 
    // Install the artifact to zig-out/bin
    b.installArtifact(exe);
 
    // --- Developer Tools below (Run/Test) ---
    
    // Allow 'zig build run'
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
