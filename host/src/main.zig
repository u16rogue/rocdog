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

/// Roc linking namespace. Pub functions will be auto force eval'd to ensure they dont
/// get shaken off by the optimizer (?).
/// `roc.*`          = roc calls/links
/// `roc.provides.*` = host calls/links
const roc = struct {
    const provides = struct {
        const main = @extern(*const fn () callconv(.c) void, .{ .name = "roc_main" });
    };

    /// Provides a memory allocator implementation to roc
    pub fn alloc(size: usize, alignment: usize) callconv(.c) ?[*]u8 {
        comptime @export(&alloc, .{ .name = "roc_alloc", .linkage = .strong, .visibility = .hidden });
        _ = .{alignment};
        const buffer = RocdogAllocator.proxyAlloc(g_alloc_instance.allocator(), RocdogAllocator.meta.castToUsize(usize, size)) catch |err| {
            std.log.err("platform#rocAlloc: {s}", .{ @errorName(err) });
            return null;
        };
        return @ptrCast(buffer);
    }

    /// Provides a memory free implementation to roc
    pub fn free(ptr: ?[*]u8, alignment: usize) callconv(.c) void {
        _ = .{alignment};
        comptime @export(&free, .{ .name = "roc_dealloc", .linkage = .strong, .visibility = .hidden });
        std.debug.assert(ptr != null);
        return RocdogAllocator.proxyFree(g_alloc_instance.allocator(), ptr.?);
    }

    /// Provides a memory reallocation implementation to roc
    pub fn realloc(ptr: ?[*]u8, new_size: usize, alignment: usize) callconv(.c) ?[*]u8 {
        _ = .{alignment};
        comptime @export(&realloc, .{ .name = "roc_realloc", .linkage = .strong, .visibility = .hidden });
        std.debug.assert(ptr != null);
        const new_buffer = RocdogAllocator.proxyReAlloc(g_alloc_instance.allocator(), ptr.?, RocdogAllocator.meta.castToUsize(usize, new_size)) catch |err| {
            std.log.err("platform#rocReAlloc: {s}", .{ @errorName(err) });
            return null;
        };
        return @ptrCast(new_buffer);
    }

    /// Provides a debug output implementation to roc
    pub fn logDbg(bytes: ?[*]u8, len: usize) callconv(.c) void {
        comptime @export(&logDbg, .{ .name = "roc_dbg", .linkage = .strong, .visibility = .hidden });
        std.debug.assert(bytes != null);
        std.debug.assert(len != 0);
        return std.log.debug("platform#debug: {s}", .{ bytes.?[0..len] });
    }

    /// Provides a expect fail output implementation to roc
    pub fn logExpectFailed(bytes: ?[*]u8, len: usize) callconv(.c) void {
        comptime @export(&logExpectFailed, .{ .name = "roc_expect_failed", .linkage = .strong, .visibility = .hidden });
        std.debug.assert(bytes != null);
        std.debug.assert(len != 0);
        return std.log.err("platform#expect: {s}", .{ bytes.?[0..len] });
    }

    /// Provides an irrecoverable crash handler implementation to roc
    pub fn handlerCrash(bytes: ?[*]u8, len: usize) callconv(.c) noreturn {
        comptime @export(&handlerCrash, .{ .name = "roc_crashed", .linkage = .strong, .visibility = .hidden });
        std.debug.assert(bytes != null);
        std.debug.assert(len != 0);
        std.log.err("platform#crashed: {s}", .{ bytes.?[0..len] });
        return std.process.exit(1);
    }

    comptime { for (@typeInfo(@This()).@"struct".decl_names) |decl_name| _ = &@field(@This(), decl_name); } // Forces eval of `roc.*` to ensure the compiler doesn't shake them and skip.
};

test {
    _ = .{
        RocdogAllocator,
    };
}
