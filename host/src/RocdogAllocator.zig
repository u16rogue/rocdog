/// This is a proxy/meta allocator specifically for rocdog to implement extra memory processing.
/// This covers the translation from a formal slice expected in zig into a simple pointer to a buffer
/// akin to C like platforms (and solving that exact issue of losing the slices' `len` metadata).
///
/// Term reference:
/// "Requested", `req-` - Refers to a slice or the literal memory that was requested as we
/// may allocate larger than the requested size.

const Self = @This();
const std = @import("std");

/// Fixed type to represent `size` for `RocdogAllocator`
pub const USize = u32; // surely no one is gonna allocate >= 4gb

pub const meta = struct {
    /// Truncates a `value` of type `Value` into `USize`. Upcast and downcasts are okay as
    /// long as `value`'s numeric representation fits into `USize` and therefore this function
    /// triggers an assertion for that.
    pub fn castToUsize(comptime Value: type, value: Value) USize {
        std.debug.assert(value <= std.math.maxInt(USize)); // assert truncated value stays the same
        return @truncate(value);
    }
};

/// Rocdog attaches this signature to memory allocations modified by the proxy as a signifier (NOT GUARANTEE) that
/// it retains integrity. (TODO: this is terribly worded. fix this.)
const signature_bytes = [_]u8 { 0x42, 0x41, 0x55, 0x00 };

const Metadata = extern struct {
    signature: [signature_bytes.len]u8,
    requested_size: USize,

    const type_size = @sizeOf(@This());
    comptime { if (type_size != 8) @compileError("Metadata is expected to be and must be 8 bytes."); }
};

/// This is a proxy allocator that applies rocdog related modifications into the memory allocation
/// request. The returned memory is the abstracted view of the requested memory, it is expected to be
/// casted into a `[*]u8` dropping its length and is therefore considered okay. Any callee modification should
/// not be visible from the caller and the implementation should guarantee that what the caller requests
/// is what they get.
///
/// ```zig
/// const x: [*]u8 = @ptrCast(try proxyAlloc(allocator, 256)); // safe. RocdogAllocator will track it itself.
/// ```
///
/// This proxy will:
///     * Allocate more than the `size` parameter to embed extra metadata that RocdogAllocator will
///     take advantage of. This metadata will not be included in the returned slice.
/// ┌───────────────────────────────────────┐
/// │buffer = try proxyAlloc(_, size)       │
/// │  ▲                         │          │
/// │  │                         ▼          │
/// │  │           ┌─────┬────┬─────┐       │
/// │  │   Metadata│Magic│Size│[_]u8│Buffer │
/// │  │           └─────┴────┴─────┘       │
/// │  │                         │          │
/// │  └─────────────────────────┘          │
/// └───────────────────────────────────────┘
pub fn proxyAlloc(allocator: std.mem.Allocator, size: USize) std.mem.Allocator.Error![]u8 {
    const buffer = try allocator.alloc(u8, Metadata.type_size + size);
    std.mem.bytesAsValue(Metadata, buffer[0..Metadata.type_size]).* = .{
        .signature = signature_bytes,
        .requested_size = size,
    };
    return buffer[Metadata.type_size..];
}

/// Free an allocated memory by `RocdogAllocator`
/// UNSAFE: passing a `ptr` that wasn't returned by `proxyAlloc` is undefined behavior.
pub fn proxyFree(allocator: std.mem.Allocator, req_ptr: [*]u8) void {
    allocator.free(translateReqErasedPtrToReal(req_ptr).asSclice());
}

/// Reallocate an allocated memory `ptr` by `RocdogAllocator` in `new_size` bytes.
/// UNSAFE: passing a `ptr` that wasn't returned by `proxyAlloc` is undefined behavior.
pub fn proxyReAlloc(allocator: std.mem.Allocator, req_ptr: [*]u8, new_size: USize) std.mem.Allocator.Error![]u8 {
    const real = translateReqErasedPtrToReal(req_ptr);
    const new_real_size = Metadata.type_size + new_size;
    const new_block = try allocator.realloc(real.asSclice(), new_real_size);
    // Doesn't matter if we got a new address or not our metadata block is at the beginning so it either
    // overwrites the existing block or it just writes the new block into the new address.
    std.mem.bytesAsValue(Metadata, new_block[0..Metadata.type_size]).* = Metadata {
        .signature = signature_bytes,
        .requested_size = new_size,
    };
    return new_block[Metadata.type_size..];
}

/// Given a `ptr` normalize it back to a slice containig a pair of `ptr` and `len` by resolving it
/// using RocdogAllocator's metadata. This should only be used with memory allocated through RocdogAllocator.
/// UNSAFE: passing a `ptr` that wasn't returned by `proxyAlloc` is undefined behavior.
pub fn normalize(req_ptr: [*]u8) []u8 {
    const real = translateReqErasedPtrToReal(req_ptr);
    return req_ptr[0..(real.metadataPtrGet().requested_size)];
}

const TranslatedReqPtr = struct {
    real_base: [*]u8,

    pub fn metadataPtrGet(self: TranslatedReqPtr) *Metadata {
        return @alignCast(std.mem.bytesAsValue(Metadata, self.real_base[0..Metadata.type_size]));
    }

    pub fn asSclice(self: TranslatedReqPtr) []u8 {
        return self.real_base[0..(Metadata.type_size + self.metadataPtrGet().requested_size)];
    }
};

/// Translates a requested memory pointer back to its real base address
/// contained in a helper type.
/// Asserts that the signature is valid.
fn translateReqErasedPtrToReal(req_ptr: [*]u8) TranslatedReqPtr {
    const real_base = req_ptr - Metadata.type_size;
    std.debug.assert(std.mem.eql(u8, real_base[0..signature_bytes.len], &signature_bytes));
    return TranslatedReqPtr { .real_base = real_base };
}

test {
    _ = @import("RocdogAllocator.test.zig");
}
