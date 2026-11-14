const std = @import("std");
const RocdogAllocator = @import("RocdogAllocator.zig");

var g_alloc_instance: std.heap.DebugAllocator(.{}) = .init;

pub fn main() callconv(.c) void {
    defer if (g_alloc_instance.deinit() == .leak) {
        std.log.err("rocdog#std.heap.DebugAllocator detected a leak", .{});
        std.process.exit(2);
    };
    return roc.provides.main();
}

/// Roc linking namespace.
/// `roc.*`          = roc calls/links
/// `roc.provides.*` = host calls/links
const roc = struct {
    const provides = struct {
        const main = @extern(*const fn () callconv(.c) void, .{ .name = "rocMain" });
    };

    /// Provides a memory allocator implementation to roc
    fn alloc(size: usize, alignment: usize) callconv(.c) ?[*]u8 {
        comptime @export(&alloc, .{ .name = "roc_alloc", .linkage = .strong, .visibility = .hidden });
        _ = .{alignment};
        std.debug.assert(size < std.math.maxInt(RocdogAllocator.USize)); // assert truncate value cast can fit
        const buffer = RocdogAllocator.proxyAlloc(g_alloc_instance.allocator(), @truncate(size)) catch |err| {
            std.log.err("platform#rocAlloc: {s}", .{ @errorName(err) });
            return null;
        };
        return @ptrCast(buffer);
    }

    /// Provides a memory free implementation to roc
    fn free(ptr: ?[*]u8, alignment: usize) callconv(.c) void {
        _ = .{alignment};
        comptime @export(&free, .{ .name = "roc_dealloc", .linkage = .strong, .visibility = .hidden });
        std.debug.assert(ptr != null);
        return RocdogAllocator.proxyFree(g_alloc_instance.allocator(), ptr.?);
    }

    /// Provides a memory reallocation implementation to roc
    fn realloc(ptr: ?[*]u8, new_size: usize, alignment: usize) callconv(.c) ?[*]u8 {
        _ = .{alignment};
        comptime @export(&realloc, .{ .name = "roc_realloc", .linkage = .strong, .visibility = .hidden });
        std.debug.assert(ptr != null);
        std.debug.assert(new_size < std.math.maxInt(RocdogAllocator.USize)); // assert truncate value cast can fit
        const new_buffer = RocdogAllocator.proxyReAlloc(g_alloc_instance.allocator(), ptr.?, @truncate(new_size)) catch |err| {
            std.log.err("platform#rocReAlloc: {s}", .{ @errorName(err) });
            return null;
        };
        return @ptrCast(new_buffer);
    }

    /// Provides a debug output implementation to roc
    fn logDbg(bytes: ?[*]u8, len: usize) callconv(.c) void {
        comptime @export(&logDbg, .{ .name = "roc_dbg", .linkage = .strong, .visibility = .hidden });
        std.debug.assert(bytes != null);
        std.debug.assert(len != 0);
        return std.log.debug("platform#debug: {s}", .{ bytes.?[0..len] });
    }

    /// Provides a expect fail output implementation to roc
    fn logExpectFailed(bytes: ?[*]u8, len: usize) callconv(.c) void {
        comptime @export(&logExpectFailed, .{ .name = "roc_expect_failed", .linkage = .strong, .visibility = .hidden });
        std.debug.assert(bytes != null);
        std.debug.assert(len != 0);
        return std.log.err("platform#expect: {s}", .{ bytes.?[0..len] });
    }

    /// Provides an irrecoverable crash handler implementation to roc
    fn handlerCrash(bytes: ?[*]u8, len: usize) callconv(.c) noreturn {
        comptime @export(&handlerCrash, .{ .name = "roc_crashed", .linkage = .strong, .visibility = .hidden });
        std.debug.assert(bytes != null);
        std.debug.assert(len != 0);
        std.log.err("platform#crashed: {s}", .{ bytes.?[0..len] });
        return std.process.exit(1);
    }
};

test {
    _ = .{
        RocdogAllocator,
    };
}
