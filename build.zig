const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const spsc_mod = b.addModule("spsc", .{
        .source_file = .{ .path = "src/spsc_queue.zig" },
    });

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/spsc_queue.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    const zig_bench_mod = b.createModule(.{
        .source_file = .{ .path = "./zig-bench/bench.zig" },
    });

    const bench = b.addTest(.{
        .root_source_file = .{ .path = "src/benchmarks.zig" },
        .target = target,
        .optimize = optimize,
    });
    bench.addModule("bench", zig_bench_mod);
    bench.addModule("spsc", spsc_mod);

    const run_benches = b.addRunArtifact(bench);
    if (b.args) |args| {
        run_benches.addArgs(args);
    }

    const bench_step = b.step("bench", "Run library benchmarks");
    bench_step.dependOn(&run_benches.step);

    const kcov = b.addSystemCommand(&.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output" });
    kcov.addArtifactArg(main_tests);
    const kcov_step = b.step("kcov", "Generate code coverage report");
    kcov_step.dependOn(&kcov.step);
}
