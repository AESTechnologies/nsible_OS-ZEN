// [@://nsible_os/build.zig/.-={
//   module: "Build Orchestrator",
//   version: "0.10.6-nightly // Banysang",
//   description: "Architectural blueprint for compiling the kernel targeting 32-bit Musl for the Acer Aspire ONE.",
//   changes: "Registered djinn module and explicitly compiled ma_x.c implementation.",
//   philotic_inferences: "The method of construction dictates the integrity of the object; the build process is the act of manifestation."

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .linux,
        .abi = .musl,
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
    
    // Compile your isolated miniaudio implementation directly
    exe.addCSourceFile(.{
        .file = b.path("assets/aud.io/ma_x.c"),
        .flags = &[_][]const u8{ "-std=c99", "-O3" },
    });
 
    b.installArtifact(exe);
 
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
// }-.]
