const std = @import("std");
 
pub fn build(b: *std.Build) void {
    // .-*-. HARD CONSTRAINT: 32-bit Musl (Static) .-*-.
    // This defines the architecture for the Acer Aspire ONE (Atom N270).
    // We use .musl to ensure no external shared libraries are needed.
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
 
    // Allow 'zig build test'
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
