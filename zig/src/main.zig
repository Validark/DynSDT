// TODO: in the linked list version, we could put the scores directly into the DEPQ
// TODO: we could try making the depq_len decrement unconditional?

// TODO: When I get a Zen4 PC, we can use: VPCOMPRESSB / _mm512_mask_compress_epi8(term_newline_mask ^ newline_mask)
// TODO: maybe we could not require a newline at the end of the file?
// TODO: When instantiating the structure from a file, terms could be sorted lexicographically when they have the same score. This may improve cache coherence.

// This is an implementation of an Dynamic Score-Decomposed Trie.
// demo: https://validark.github.io/DynSDT/demo/
// paper: https://validark.github.io/DynSDT/

// This implementation does not support empty string queries, because they are probably not useful in practice.
// This particular implementation uses the LCRS-style of representing nodes.
// I.e., each node has a `next` and a `down` pointer to another node, instead of each node holding an array.

// The advantage to this implementation is that updating a particular term's score in the data structure will
// not perform any allocations. The only allocations that may occur are when adding genuinely new data.

// The disadvantage is that this structure would probably be less than ideal if it was to be shared in a
// multi-threaded setting. The best option in that setting might be to use multiple structures, or
// consider using a lock-free implementation that relies on arrays of nodes, such that the bottommost-
// changed array and its parents up to the root can be copied and then the root pointer can be updated
// atomically to the new copy, or the work can be repeated if another thread updated the structure first.
// I suppose one *could* dream up a similar scheme with the LCRS linked-lists, but that would be pretty crazy.

const std = @import("std");
const MultiArrayList = std.MultiArrayList;
// const MultiArrayList = @import("MultiArrayList.zig").MultiArrayList;
const builtin = @import("builtin");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const string = []const u8;
const score_int = u32;
const str_buf_int = u32;

// the code assumes term_len_int <= str_buf_int
const term_len_int = u16;
const node_index_int = u32;

fn BetterSlice(T: anytype) type {
    return struct {
        ptr: [*]T,
        end_ptr: *T,

        pub fn advance(self: *const @This()) bool {
            self.ptr += 1;
            return self.ptr >= self.end_ptr;
        }
    };
}

/// This switch makes us maintain our node list in sorted order by score in memory (sorted by first character).
/// This means that topK completion queries do not need to look at scores at all (improving query times).
/// There is always the issue of reducing cache misses, which is somewhat difficult to plan for when each query
/// needs a potentially completely different set of answers. At the moment, the most optimal queries are
/// single-character queries, as their answers are laid out directly next to each other in memory. However,
/// if k is predetermined I think it would be best to make 2 character queries the baseline, and precompute
/// 1-character queries and just store the answer in a lookup table. This would require relatively little
/// precomputation and may give a small boost to longer queries.
/// However, this also means that dynamically changing scores in our tree can potentially
/// cause many nodes to shift in memory (that start with the same character). Worst case,
/// shifting can be an O(n) operation where n is the number of nodes. However, I suspect in
/// most use cases there is no need to move a node from the bottom to the top or vice versa.
/// In real-world cases, scores typically follow a skewed power law distribution.
/// (See Hsu & Ottaviano, 2013: https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/TopKCompletion.pdf)
/// This means that if the scores just represented how many queries each term got, we would expect that
/// nodes would not move around that much relative to their neighbors. The only thing that might be troublesome
/// is that the vast majority of queries will have very low scores. This means a DDOS attack would be viable
/// if someone repeatedly queried for the extremely rare queries and they had to do a linear scan out of the
/// giant pool of terms at the bottom.
/// To combat this, we could allocate spaces specifically for this purpose, e.g. when a query's score goes from
/// 1 to 2, and there could be 100000 terms with a score of 1.
/// Another optimization this could enable is that scores could be stored more efficiently, like in https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/TopKCompletion.pdf
// Perhaps Elias-Fano will reduce the space used by scores.
const MAINTAIN_SORTED_ORDER_IN_MEMORY = false;

// These switches allow us to easily change strategies 😊

/// True increases code size, but may be faster on some machines?
const MOVE_FIRST_ITERATION_OF_TOPK_QUERY_OUT_OF_LOOP = false;

/// Increases the node size, but may improve cache complexity when finding the locus node for a given string.
/// May worsen cache complexity for the topK enumeration algorithm, but if your cache is already a lost cause it can't hurt.
const STORE_4_TERM_BYTES_IN_NODE = false;

const USE_SIMD_FOR_PARSING_FILES = true;
const MAIN_BUF_LEN: usize = 1 << 14;
const VEC_SIZE_FOR_POPCOUNT = 64;

const USE_SIMD_TO_FIND_LCP = false;
const VEC_SIZE_TO_FIND_LCP = 16;

/// Increases memory usage by 1 byte per string, but it makes ReleaseFast faster by eliminating the need to track lengths
/// when finding the longest common prefix
const USE_NULL_TERMINATED_STRINGS = true;
const BITWISE = false;
const PREFIX_SAVE = 0;

const SHOULD_PRINT = false;

fn printCommifiedNumber(num: anytype) void {
    var degree: @TypeOf(num) = 1;
    while (num >= degree * 1000) degree *= 1000;
    var x: @TypeOf(num) = num / degree;
    var num_term_pairs_print: @TypeOf(num) = x * degree;
    std.debug.print("{}", .{x});

    while (degree != 1) {
        degree /= 1000;
        x = (num - num_term_pairs_print) / degree;
        num_term_pairs_print += x * degree;
        std.debug.print(",{:0>3}", .{x});
    }
}

/// This function copies bytes from one region of memory to another.
///
/// dest must be a mutable slice, a mutable pointer to an array, or a mutable many-item pointer. It may have any alignment, and it may have any element type.
///
/// Likewise, source must be a mutable slice, a mutable pointer to an array, or a mutable many-item pointer. It may have any alignment, and it may have any element type.
///
/// The source element type must support Type Coercion into the dest element type. The element types may have different ABI size, however, that may incur a performance penalty.
///
/// Similar to for loops, at least one of source and dest must provide a length, and if two lengths are provided, they must be equal.
///
/// Finally, the two memory regions must not overlap.
fn memcpy(noalias dest: anytype, noalias source: anytype) void {
    @memcpy(switch (@typeInfo(@TypeOf(dest))) {
        .Pointer => |p| if (p.size == .Many) dest[0..source.len] else dest,
        else => dest,
    }, source);
}

/// Given a bitmask, will return a mask where the bits are filled in between.
/// On modern x86 and aarch64 CPU's, it should have a latency of 3 and a throughput of 1.
fn prefix_xor(bitmask: anytype) @TypeOf(bitmask) {
    comptime std.debug.assert(std.math.isPowerOfTwo(@bitSizeOf(@TypeOf(bitmask))));

    const has_native_carryless_multiply = @bitSizeOf(@TypeOf(bitmask)) <= 64 and switch (builtin.cpu.arch) {
        // There should be no such thing with a processor supporting avx but not clmul.
        .x86_64 => std.Target.x86.featureSetHas(builtin.cpu.features, .pclmul) and
            std.Target.x86.featureSetHas(builtin.cpu.features, .avx2),
        .aarch64 => std.Target.aarch64.featureSetHas(builtin.cpu.features, .aes),
        else => false,
    };

    if (@inComptime() or !has_native_carryless_multiply) {
        var x = bitmask;
        inline for (0..(@bitSizeOf(std.math.Log2Int(@TypeOf(bitmask))))) |i|
            x ^= x << comptime (1 << i);
        return x;
    }

    // do a carryless multiply by all 1's,
    // adapted from zig/lib/std/crypto/ghash_polyval.zig
    const x = @as(u128, @bitCast([2]u64{ @as(u64, bitmask), 0 }));
    const y = @as(u128, @bitCast(@splat(16, @as(u8, 0xff))));

    return @as(@TypeOf(bitmask), @truncate(switch (builtin.cpu.arch) {
        .x86_64 => asm (
            \\ vpclmulqdq $0x00, %[x], %[y], %[out]
            : [out] "=x" (-> @Vector(2, u64)),
            : [x] "x" (@as(@Vector(2, u64), @bitCast(x))),
              [y] "x" (@as(@Vector(2, u64), @bitCast(y))),
        ),

        .aarch64 => asm (
            \\ pmull %[out].1q, %[x].1d, %[y].1d
            : [out] "=w" (-> @Vector(2, u64)),
            : [x] "w" (@as(@Vector(2, u64), @bitCast(x))),
              [y] "w" (@as(@Vector(2, u64), @bitCast(y))),
        ),

        else => unreachable,
    }[0]));
}

// fn longestCommonPrefixASM(str1: @Vector(16, u8), str2: @Vector(16, u8)) u32 {
//     return asm (
//         \\ PcmpIstrI %[x], %[y], 011000b
//         : [out] "=w" (-> u32),
//         : [x] "w" (str1),
//           [y] "w" (str2),
//     );
// }

inline fn pdep(src: u64, mask: u64) u64 {
    return asm ("pdep %[mask], %[src], %[ret]"
        : [ret] "=r" (-> u64),
        : [src] "r" (src),
          [mask] "r" (mask),
    );
}

inline fn maskEvenBits(bitstring: u64) u64 {
    return bitstring & ~prefix_xor(bitstring);
    // return pdep(0xaaaaaaaaaaaaaaaa, bitstring);
}

// inline fn pext(src: u64, mask: u64) u64 {
//     return asm ("pext %[mask], %[src], %[ret]"
//         : [ret] "=r" (-> u64),
//         : [src] "r" (src),
//           [mask] "r" (mask),
//     );
// }

// fn BZHI(src: anytype, inx: std.math.Log2Int(@TypeOf(src))) @TypeOf(src) {
//     return src & (@as(@TypeOf(src), 1) << inx) - 1;
// }

// fn pext2(src: anytype, mask: @TypeOf(src)) @TypeOf(src) {
//     var result: @TypeOf(src) = 0;
//     var bit: @TypeOf(src) = 1;

//     while (true) {
//         const LSB = mask & -mask; // isolate LSB set bit
//         if (LSB == 0) return result;
//         mask ^= LSB; // clear it in mask
//         const value = src & LSB;

//         // convert isolated bit to mask

//         const mv = signExtend(-value);

//         // update result
//         result |= mv & bit;
//         bit <<= 1;
//     }

//     return result;
// }

/// Shifts and sign-extends the most significant bit.
/// Returns an integer with all 1's or all 0's depending on the most significant bit.
inline fn signExtend(x: anytype) @TypeOf(x) {
    const bits = @typeInfo(@TypeOf(x)).Int.bits;
    return @as(@TypeOf(x), @bitCast(@as(std.meta.Int(.signed, bits), @bitCast(x)) >> (bits - 1)));
}

pub const PackedCompareStringFlags = packed struct(u8) {
    size: enum(u1) { byte = 0, word = 1 } = .byte,
    signedness: enum(u1) { unsigned = 0, signed = 1 } = .unsigned,
    mode: enum(u2) { any_equal = 0, ranges = 1, all_equal = 2, substring = 3 } = .any_equal,
    polarity: enum(u1) { positive = 0, negative = 1 } = .positive,
    is_masked: bool = false,
    output_mode: enum(u1) { lsb = 0, msb = 1 } = .lsb,
    padding: u1 = 0,

    const LongestCommonPrefix = PackedCompareStringFlags{ .mode = .all_equal, .polarity = .negative };
};

pub inline fn _mm_cmpistri(str1: @Vector(16, u8), str2: @Vector(16, u8), comptime flags: PackedCompareStringFlags) u32 {
    return asm (std.fmt.comptimePrint("pcmpistri ${d}, %[b], %[a]", .{@as(u8, @bitCast(flags))})
        : [ret] "={ecx}" (-> u32),
        : [a] "x" (str1),
          [b] "x" (str2),
        : "cc"
    );
}

// Unfortunately, this seems slower than the alternatives on my current machine.
// It looks like this operation is very fast on Zen 4, so maybe it turns out to be faster on those machines?
fn longestCommonPrefixASM(LCP_: term_len_int, noalias str1: string, noalias str2: string) term_len_int {
    var LCP: u32 = LCP_;
    while (true) {
        const first_difference = _mm_cmpistri(str1[LCP..][0..16].*, str2[LCP..][0..16].*, PackedCompareStringFlags.LongestCommonPrefix);
        LCP += first_difference;
        if (first_difference != 16) return @as(term_len_int, @intCast(LCP));
    }
}

/// Calculates Longest Common Prefix between `term1` and `term2`, must not alias
fn longestCommonPrefix(LCP: term_len_int, noalias term1: string, noalias term2: string) term_len_int {
    @setCold(STORE_4_TERM_BYTES_IN_NODE);
    const len = @as(term_len_int, @intCast(@min(term1.len, term2.len)));
    var lcp = LCP;
    var str1_: string = term1;
    var str2_: string = term2;
    var first = lcp;
    // _ = std.math.sub(term_len_int, len, lcp) catch {
    //     std.debug.print("{} {} {} {s} {s}\n", .{term1.len, term2.len, lcp, term1, term2});
    // };
    while (USE_SIMD_TO_FIND_LCP) {
        str1_ = str1_[first..];
        str2_ = str2_[first..];
        const vec1: @Vector(VEC_SIZE_TO_FIND_LCP, u8) = str1_[0..VEC_SIZE_TO_FIND_LCP].*;
        const vec2: @Vector(VEC_SIZE_TO_FIND_LCP, u8) = str2_[0..VEC_SIZE_TO_FIND_LCP].*;
        const bitmask = @as(std.meta.Int(.unsigned, VEC_SIZE_TO_FIND_LCP), @bitCast(vec1 != vec2));
        first = @ctz(bitmask);
        lcp += first;
        if (first != VEC_SIZE_TO_FIND_LCP) break;
    } else while (lcp < len and term1[lcp] == term2[lcp]) lcp += 1;
    std.debug.assert(!(lcp < len and term1[lcp] == term2[lcp]));
    return lcp;
}

// pub inline fn writeVectorsFromFileIntoBuffer(file: std.fs.File, file_buf: []u8, writer: anytype) !void {
//     while (true) {
//         var consumable_characters: usize = try file.read(file_buf[0..MAIN_BUF_LEN]);
//         const is_last_iteration = consumable_characters < MAIN_BUF_LEN;

//         if (is_last_iteration) {
//             if (consumable_characters == 0) break;
//             const consumable_characters_aligned = std.mem.alignForward(consumable_characters, VEC_SIZE_FOR_POPCOUNT);
//             @memset(file_buf[consumable_characters..].ptr[0..VEC_SIZE_FOR_POPCOUNT], '\x00');
//             consumable_characters = consumable_characters_aligned;
//         }

//         const chunks = consumable_characters / VEC_SIZE_FOR_POPCOUNT;
//         var buf = file_buf;
//         for (0..chunks) |i| {
//             const write_output = writer.write(i, buf[0..VEC_SIZE_FOR_POPCOUNT].*);
//             buf = buf[VEC_SIZE_FOR_POPCOUNT..];
//             if (@typeInfo(@TypeOf(write_output)) == .ErrorUnion) try write_output;
//         }

//         const flush_output = writer.flush(chunks);
//         if (@typeInfo(@TypeOf(flush_output)) == .ErrorUnion) try flush_output;
//         if (is_last_iteration) break;
//         const clean_output = writer.clean();
//         if (@typeInfo(@TypeOf(clean_output)) == .ErrorUnion) try clean_output;
//     }
// }

const string_t = if (USE_NULL_TERMINATED_STRINGS) [:0]const u8 else []const u8;

const DynSDT = struct {
    roots: Buffer.roots_array,
    data: Buffer,
    map: if (PREFIX_SAVE > 0) std.StringHashMapUnmanaged(node_index_int) else void = if (PREFIX_SAVE > 0) .{},

    const uint = std.meta.Int(.unsigned, VEC_SIZE_FOR_POPCOUNT);

    const NULL: node_index_int = 0;

    const ScoredNode = struct { node: Node, score: score_int };

    // We shove all of our data into a single Buffer,that way each DynSDT only holds onto one allocation at once.
    const Buffer = struct {
        multilist: MultiArrayList(ScoredNode),
        byte_buffer_len: usize,
        characters: struct {
            len: str_buf_int,
            capacity: str_buf_int,
        },

        const roots_array = [256]node_index_int;
        const elem_bytes = elem_bytes: {
            comptime var sum: usize = 0;
            inline for (std.meta.fields(ScoredNode)) |field_info| sum += @sizeOf(field_info.type);
            break :elem_bytes sum;
        };

        pub fn str_buffer_slice(self: Buffer) []u8 {
            return self.multilist.bytes[elem_bytes * self.multilist.capacity ..][0..self.characters.len];
        }

        pub fn deinit(self: @This(), allocator: Allocator) void {
            _ = allocator;
            _ = self;
            // self.nodes.deinit(self.allocator);
            // self.scores.deinit(self.allocator);
            // self.string_buffer.deinit(self.allocator);
        }

        const BufferRequirements = struct {
            multilist_size: usize,
            strings_length: str_buf_int,
            num_term_pairs: node_index_int,
            total_size: usize,
        };

        pub fn calcNeededSize(file: std.fs.File, file_buf: []u8, comptime added_sentinels: u8) !BufferRequirements {
            var num_term_pairs: usize = 0;
            var strings_length: usize = 0;
            var state: uint = std.math.maxInt(uint); // maxInt -> matching strings first, 1 -> matching numbers first

            while (true) {
                var consumable_characters = try file.read(file_buf[0..MAIN_BUF_LEN]);
                const is_last_iteration = consumable_characters < MAIN_BUF_LEN;

                if (is_last_iteration) {
                    if (consumable_characters == 0) break;
                    const consumable_characters_aligned = std.mem.alignForward(usize, consumable_characters, VEC_SIZE_FOR_POPCOUNT);
                    strings_length -%= consumable_characters_aligned - consumable_characters;
                    @memset(file_buf[consumable_characters..][0..VEC_SIZE_FOR_POPCOUNT], '\x00');
                    consumable_characters = consumable_characters_aligned;
                }

                for (0..consumable_characters / VEC_SIZE_FOR_POPCOUNT) |i| {
                    const vec: @Vector(VEC_SIZE_FOR_POPCOUNT, u8) = file_buf[i * VEC_SIZE_FOR_POPCOUNT ..][0..VEC_SIZE_FOR_POPCOUNT].*;

                    // Note: we cannot just match digit characters because those characters can also appear in the string section.
                    const tab_mask = @as(uint, @bitCast(vec == @splat(VEC_SIZE_FOR_POPCOUNT, @as(u8, '\t'))));
                    const newline_mask = @as(uint, @bitCast(vec == @splat(VEC_SIZE_FOR_POPCOUNT, @as(u8, '\n'))));
                    const newline_tab_mask = tab_mask | newline_mask;

                    // (',' is our stand-in for \n, ' ' is our stand-in for \t)
                    // vec:               wikipedia 1220297,world 30978,women 28285,william 27706,west 178
                    // tab_mask:          0000000001000000000000010000000000010000000000000100000000001000 (5)
                    // newline_mask:      0000000000000000010000000000010000000000010000000000000100000000 (4)
                    // term_newline_mask: 1111111110000000011111100000011111100000011111111000000111110000
                    //                    LSB<-------------------------------------------------------->MSB

                    const term_newline_mask: uint = prefix_xor(newline_tab_mask) ^ state; // a mask where all the term characters and newlines are set to 1
                    // we don't worry about counting an extra newline per word because that will hold our \0 character in the final allocation

                    if ((term_newline_mask & tab_mask) != 0) return error.@"File does not alternate between tabs and newlines";

                    state = signExtend(term_newline_mask); // if the last character in the chunk was a newline or term character, we are matching that in the next iteration
                    num_term_pairs += @popCount(newline_mask);
                    // allow overflow because we might have underflowed earlier
                    strings_length +%= @popCount(term_newline_mask);
                }

                if (is_last_iteration) break;
            }

            if (state == 0) return error.@"Unable to match numeric characters at end-of-file.";

            const _strings_length = std.math.cast(str_buf_int, strings_length - if (USE_NULL_TERMINATED_STRINGS) 0 else num_term_pairs) orelse
                return error.@"Number of characters to allocate does not fit in str_buf_int";

            const _num_term_pairs = std.math.cast(node_index_int, num_term_pairs + added_sentinels) orelse
                return error.@"Number of completions does not fit in node_index_int";

            // var total_size_ = 0;
            // var total_size_max_ = 0;
            // _ = total_size_max_;
            // _ = total_size_;

            // const Sizer = struct {
            //     current_value: usize,
            //     // maximum_value: comptime_int,

            //     var maximum_value: comptime_int = 0;

            //     pub fn init(comptime value: comptime_int) @This() {
            //         maximum_value = value;
            //         return .{
            //             .current_value = value,
            //         };
            //     }

            //     pub fn mul(self: *@This(), value: anytype) void {
            //         self.maximum_value *= switch (@TypeOf(value)) {
            //             comptime_int => value,
            //             else => std.math.maxInt(value),
            //         };

            //         self.current_value = switch (comptime std.math.maxInt(usize) < self.maximum_value) {
            //             true => try std.math.mul(usize, self.current_value, value),
            //             false => self.current_value * value,
            //         };
            //     }
            // };

            // var sizey = Sizer.init(Buffer.elem_bytes);
            // sizey.mul(_num_term_pairs);

            const do = struct {
                fn do(acc: anytype, comptime op: @TypeOf(std.math.mul), value: anytype, comptime max_acc: *@TypeOf(acc)) if (@as(?@TypeOf(acc), op(@TypeOf(acc), switch (@TypeOf(value)) {
                    comptime_int => value,
                    else => std.math.maxInt(@TypeOf(value)),
                }, max_acc.*) catch null)) |_| (error{Overflow}!@TypeOf(acc)) else (@TypeOf(acc)) {
                    if (comptime @as(?@TypeOf(acc), op(@TypeOf(acc), switch (@TypeOf(value)) {
                        comptime_int => value,
                        else => std.math.maxInt(@TypeOf(value)),
                    }, max_acc.*) catch null)) |next_acc| {
                        max_acc.* = next_acc;
                        return op(@TypeOf(acc), acc, value);
                    } else {
                        max_acc.* = std.math.maxInt(@TypeOf(acc));
                        return op(@TypeOf(acc), acc, value) catch unreachable;
                    }
                }
            }.do;

            comptime var max_acc: usize = Buffer.elem_bytes;

            const _multilist_size = blk: {
                const _multilist_size = do(max_acc, std.math.mul, _num_term_pairs, &max_acc);
                break :blk if (@typeInfo(@TypeOf(_multilist_size)) == .ErrorUnion) try _multilist_size else _multilist_size;
            };

            const _multilist_size_with_chars = blk: {
                const _multilist_size_with_chars = do(_multilist_size, std.math.add, _strings_length, &max_acc);
                break :blk if (@typeInfo(@TypeOf(_multilist_size_with_chars)) == .ErrorUnion) try _multilist_size_with_chars else _multilist_size_with_chars;
            };

            const _multilist_size_with_chars_and_root = blk: {
                const _multilist_size_with_chars_and_root = do(_multilist_size_with_chars, std.math.add, @sizeOf(Buffer.roots_array), &max_acc);
                break :blk if (@typeInfo(@TypeOf(_multilist_size_with_chars_and_root)) == .ErrorUnion) try _multilist_size_with_chars_and_root else _multilist_size_with_chars_and_root;
            };

            // const max_multilist_size = Buffer.elem_bytes * std.math.maxInt(node_index_int);

            // const _multilist_size: usize = switch (comptime std.math.maxInt(usize) < max_multilist_size) {
            //     true => try std.math.mul(usize, Buffer.elem_bytes, _num_term_pairs),
            //     false => Buffer.elem_bytes * _num_term_pairs,
            // };

            // const max_total_size = max_multilist_size + std.math.maxInt(str_buf_int);

            // const total_size = switch (comptime std.math.maxInt(usize) < max_total_size) {
            //     true => try std.math.add(usize, _multilist_size, _strings_length),
            //     false => _multilist_size + _strings_length,
            // };

            // const max_total_size_with_roots = max_total_size + @sizeOf(Buffer.roots_array);

            // const total_size_with_roots = switch (comptime std.math.maxInt(usize) < max_total_size_with_roots) {
            //     true => try std.math.add(usize, total_size, @sizeOf(Buffer.roots_array)),
            //     false => total_size + @sizeOf(Buffer.roots_array),
            // };

            return .{
                .num_term_pairs = _num_term_pairs,
                .multilist_size = _multilist_size,
                .strings_length = _strings_length,
                .total_size = _multilist_size_with_chars_and_root,
            };
        }

        // pub fn allocatedSlice(self: Buffer) []u8 {
        //     return (self.multilist.bytes - self.characters.capacity)[0 .. elem_bytes * self.multilist.capacity +
        //         self.characters.capacity];
        // }

        // pub fn charactersSlice(self: Buffer) []u8 {
        //     return (self.multilist.bytes + elem_bytes * )[0..self.characters.capacity];
        // }
    };

    const Node = packed struct {
        // const @"down/term_len" = packed struct(u0) {};
        // const @"next/LCP" = packed struct(u0) {};

        LCP: term_len_int = 0,
        term_len: term_len_int,
        down: node_index_int = NULL,
        next: node_index_int = NULL,
        term_start: str_buf_int,

        // @"next/LCP": @"next/LCP",
        // @"down/term_len": @"down/term_len",
        next4chars: if (STORE_4_TERM_BYTES_IN_NODE) u32 else void,

        pub fn term(self: Node, buffer: string) [*:0]const u8 {
            return @as([*:0]const u8, @ptrCast(buffer[self.term_start..].ptr));
            // return buffer[self.term_start..][0..self.term_len :0].ptr;
        }

        pub fn init(term_start: str_buf_int, term_len: term_len_int) Node {
            return Node{
                .term_start = term_start,
                .term_len = term_len,
                // .@"next/LCP" = .{},
                // .@"down/term_len" = @"down/term_len"{ .term_len = term_len },
                .next4chars = if (STORE_4_TERM_BYTES_IN_NODE) 0,
            };
        }

        pub fn initSentinel(term_start: usize) Node { // FIXME: probably make the parameter a `str_buf_int`
            return Node{
                .term_start = @as(str_buf_int, @intCast(term_start)),
                .term_len = 0,
                // .@"down/term_len" = @"down/term_len"{ .term_len = 0 },
                // .@"next/LCP" = .{ .LCP = std.math.maxInt(term_len_int) },
                .LCP = std.math.maxInt(term_len_int),
                .next4chars = if (STORE_4_TERM_BYTES_IN_NODE) 0,
            };
        }

        pub fn getDown(self: Node) node_index_int {
            return self.down;
        }

        // pub fn getTermLen(self: Node) term_len_int {
        //     return self.@"down/term_len".term_len;
        // }

        pub fn getNext(self: Node) node_index_int {
            return self.next;
        }

        pub fn getLCP(self: Node) term_len_int {
            return self.LCP;
        }

        pub fn update_next4chars(self: *Node, string_buffer: string) void {
            const LCP = self.getLCP();
            const term_start = self.term_start + LCP;

            self.next4chars = non_zero_mask(std.mem.readIntLittle(u32, string_buffer[term_start..][0..4]));
            // std.debug.print("{s}\n", .{@bitCast([4]u8, self.next4chars)});
        }
    };

    const SlicedDynSDT = struct {
        roots: Buffer.roots_array,
        nodes: []Node,
        scores: []score_int,
        str_buffer: []u8,

        const CompletionTrie = struct {
            node_list: std.ArrayListUnmanaged(CompletionTrieNode),
            str_buffer: []u8,
            roots: [256]node_index_int,

            const CompletionTrieNode = struct {
                term_start: str_buf_int,
                term_len: term_len_int,
                score: score_int,
                next: node_index_int = NULL,
                down: node_index_int = NULL,
                // branch_points: []CompletionTrieNode,

                pub fn term(self: CompletionTrieNode, buffer: string) []const u8 {
                    return buffer[self.term_start..][0..self.term_len];
                }

                pub fn full_term(self: CompletionTrieNode, buffer: string, char_depth: term_len_int) []const u8 {
                    return buffer[self.term_start - char_depth ..][0 .. self.term_len + char_depth];
                }
            };

            pub fn deinit(self: *CompletionTrie, allocator: Allocator) void {
                self.node_list.deinit(allocator);
                self.* = undefined;
            }

            const DEPQ_TYPE = struct { index: node_index_int, char_depth: term_len_int };

            pub fn getLocusIndexForPrefix(self: *const CompletionTrie, noalias prefix: string_t) DEPQ_TYPE {
                const nodes: []CompletionTrieNode = self.node_list.items;
                const str_buffer = self.str_buffer;
                std.debug.assert(prefix.len > 0);
                var char_depth: term_len_int = 0;
                var cur_i = self.roots[prefix[0]];
                if (cur_i == NULL) return .{ .index = NULL, .char_depth = undefined };
                var term1 = prefix;
                if (SHOULD_PRINT) std.debug.print("term1: {s}\n", .{term1});

                var term2_start: str_buf_int = nodes[cur_i].term_start;
                if (SHOULD_PRINT) std.debug.print("term2: {s}\n", .{nodes[cur_i].term(self.str_buffer)});
                var term2_end: str_buf_int = term2_start + nodes[cur_i].term_len;

                while (true) {
                    while (true) {
                        term1 = term1[1..];
                        if (SHOULD_PRINT) std.debug.print("term1: {s}\n", .{term1});
                        if (0 == if (USE_NULL_TERMINATED_STRINGS) term1[0] else term1.len) return .{ .index = cur_i, .char_depth = char_depth };
                        term2_start += 1;
                        if (term2_start >= term2_end) break;
                        if (term1[0] != str_buffer[term2_start]) return .{ .index = NULL, .char_depth = undefined };
                    }

                    char_depth += nodes[cur_i].term_len;
                    cur_i = nodes[cur_i].down;

                    while (true) {
                        if (cur_i == NULL) return .{ .index = NULL, .char_depth = undefined };
                        term2_start = nodes[cur_i].term_start;
                        if (SHOULD_PRINT) std.debug.print("term2: {s}\n", .{nodes[cur_i].term(self.str_buffer)});
                        term2_end = term2_start + nodes[cur_i].term_len;
                        if (term2_end > term2_start and term1[0] == str_buffer[term2_start]) break;
                        cur_i = nodes[cur_i].next;
                    }
                }
            }

            // fn insert_cur_i(nodes: []const Node, scores: []const score_int, depq_len_: u8, str_buffer: string, parent_i: node_index_int, results: *[10][*:0]const u8, LCP: term_len_int, depq: *[4 + 1]node_index_int, depq_1_indexed: *[5 + 1]node_index_int, k: u8) u8 {

            //     // printDEPQ(self.nodes.items, self.scores.items, depq, depq_len_, str_buffer, results, k, "insert_cur_i");
            //     const cur_i = verticalSuccessor(nodes, LCP, parent_i);

            //     if (cur_i != NULL) { // we could check if cur_i > depq[0]
            //         if (SHOULD_PRINT) std.debug.print("{{ {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7} }}, cur_i: {:0>7} \n", .{ depq_1_indexed[0], depq_1_indexed[1], depq_1_indexed[2], depq_1_indexed[3], depq_1_indexed[4], depq_1_indexed[5], cur_i });
            //         if (SHOULD_PRINT) std.debug.print("score: {}\n", .{scores[cur_i]});
            //         var i: u8 = 0;
            //         const cur_i_score = scores[cur_i];
            //         while (true) {
            //             // { 3, 5, 6, 7, 9 } insert 6
            //             var j = i + 1;
            //             if (cur_i_score <= scores[depq_1_indexed[j]]) break;
            //             depq_1_indexed[i] = depq_1_indexed[j];
            //             i = j;
            //         }
            //         depq_1_indexed[i] = cur_i;
            //         if (SHOULD_PRINT) std.debug.print("{{ {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7} }} \n", .{ depq_1_indexed[0], depq_1_indexed[1], depq_1_indexed[2], depq_1_indexed[3], depq_1_indexed[4], depq_1_indexed[5] });
            //     }

            //     return insert_next_i(nodes, scores, depq_len_ - 1, str_buffer, results, LCP, depq, depq_1_indexed, k);
            // }

            // fn insert_next_i(nodes: []const Node, scores: []const score_int, depq_len: u8, str_buffer: string, results: *[10][*:0]const u8, LCP: term_len_int, depq: *[4 + 1]node_index_int, depq_1_indexed: *[5 + 1]node_index_int, k: u8) u8 {
            //     // printDEPQ(self.nodes.items, self.scores.items, depq, depq_len, str_buffer, results, k, "insert_next_i");

            //     var cur_i = depq[depq_len];

            //     // If the DEPQ is full but only because we already have so many completions. E.g. if we found
            //     // 8 completions already then we only need 2 more if topK=10. Because k has not been incremented
            //     // yet, when k=7, we would consider depq_len=2 to be full.
            //     // e.g. { 45, _ } -> 48, 49
            //     // std.debug.assert(depq_len <= 9 - k);
            //     if (SHOULD_PRINT) std.debug.print("pushing {} to results[{}]\n", .{ cur_i, k });

            //     results[if (K_DEC) 10 - k else k] = nodes[cur_i].term(str_buffer);
            //     var l = if (K_DEC) k - 1 else k + 1;
            //     if (l == if (K_DEC) 0 else 10) return 10;
            //     var next_i = horizontalSuccessor(nodes, cur_i);

            //     if (next_i != NULL) { // we could check if (next_i > depq[0]
            //         // std.debug.print("{{ {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7} }}, next_i: {:0>7} \n", .{ depq_1_indexed[0], depq_1_indexed[1], depq_1_indexed[2], depq_1_indexed[3], depq_1_indexed[4], depq_1_indexed[5], next_i });
            //         var i: u8 = 0;
            //         const next_i_score = scores[next_i];
            //         while (true) {
            //             // { 5, 6, 7, 8, 9 } insert 8
            //             var j = i + 1; // 2
            //             if (next_i_score <= scores[depq_1_indexed[j]]) break;
            //             depq_1_indexed[i] = depq_1_indexed[j];
            //             i = j; // 1
            //         }
            //         depq_1_indexed[i] = next_i;
            //         // std.debug.print("{{ {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7} }} \n", .{ depq_1_indexed[0], depq_1_indexed[1], depq_1_indexed[2], depq_1_indexed[3], depq_1_indexed[4], depq_1_indexed[5] });
            //         // if (SHOULD_PRINT) printFinalState(depq_len, depq, next_i, k);
            //     }

            //     return insert_cur_i(nodes, scores, depq_len, str_buffer, cur_i, results, LCP, depq, depq_1_indexed, l);
            // }

            pub fn topKCompletionsToPrefix(self: *const CompletionTrie, noalias prefix: string_t, noalias results: *[10][*:0]const u8) u8 {
                const locus_and_LCP = @call(.always_inline, CompletionTrie.getLocusIndexForPrefix, .{ self, prefix });
                const locus: node_index_int = locus_and_LCP.index;
                const char_depth = locus_and_LCP.char_depth;
                return @call(.always_inline, CompletionTrie.topKCompletionsToLocus, .{ self, locus, char_depth, results });
            }

            fn printDEPQ(self: *const CompletionTrie, nodes: []const CompletionTrieNode, depq: *[10]DEPQ_TYPE, depq_len: u8, results: anytype, k: u8) void {
                if (!SHOULD_PRINT) return;
                const chars = self.str_buffer;
                if (depq_len != 0) {
                    std.debug.print("depq: [{}]{{ (\"{s}\", \"{s}\", {})", .{ depq_len, nodes[depq[0].index].full_term(chars, depq[0].char_depth), nodes[depq[0].index].term(chars), nodes[depq[0].index].score });
                    var i: u8 = 0;
                    while (true) {
                        i += 1;
                        if (i == depq_len) break;
                        std.debug.print(", (\"{s}\", \"{s}\", {})", .{ nodes[depq[i].index].full_term(chars, depq[i].char_depth), nodes[depq[i].index].term(chars), nodes[depq[i].index].score });
                    }
                    std.debug.print(" }}\n", .{});
                } else {
                    std.debug.print("depq: [0]{{ }}\n", .{});
                }

                if (0 < if (K_DEC) 10 - k else k) {
                    std.debug.print("           results: [{}]{{ \"{s}\"", .{ if (K_DEC) 10 - k else k, results[0] });
                    var i: u8 = 0;
                    while (true) {
                        i += 1;
                        if (i == if (K_DEC) 10 - k else k) break;
                        std.debug.print(", \"{s}\"", .{results[i]});
                    }
                    std.debug.print(" }}\n\n", .{});
                } else {
                    std.debug.print("           results: [0]{{ }}\n", .{});
                }
            }

            // cur_i = self.getLocusIndexForPrefix(cur_i, LCP, prefix, nodes, str_buffer);

            /// Fills up a given array of strings with completions to a given prefix string, if present in the structure,
            /// and returns the number of completions that were written.
            /// The completions will be in descending sorted order by score, so the "most relevant" completions will
            /// come first. The algorithm is explained here: https://validark.github.io/DynSDT/#top-k_enumeration
            /// The data structure owns the memory within the individual strings.
            pub fn topKCompletionsToLocus(self: *const CompletionTrie, locus: node_index_int, locus_char_depth: term_len_int, noalias results: *[10][*:0]const u8) u8 {
                const nodes: []CompletionTrieNode = self.node_list.items;
                const str_buffer = self.str_buffer;
                var k: u8 = if (K_DEC) 10 else 0;

                std.debug.assert(nodes[0].score == std.math.minInt(score_int));
                std.debug.assert(nodes[1].score == std.math.maxInt(score_int));
                var depq_1_indexed: [10 + 1]DEPQ_TYPE = undefined;
                depq_1_indexed[0] = .{ .index = 0, .char_depth = 0 };
                var depq: *[10]DEPQ_TYPE = depq_1_indexed[1..];
                inline for (depq) |*p| p.* = .{ .index = 1, .char_depth = 0 };

                var next_i = NULL;
                var depq_len: u8 = 0;
                var cur_i = locus;
                // var term_start: str_buf_int = undefined;
                var char_depth: term_len_int = locus_char_depth;

                while (true) {
                    // term_start = nodes[cur_i].term_start - char_depth;
                    while (true) {
                        if (next_i != NULL) {
                            const next_i_score = nodes[next_i].score;
                            const has_empty_slots = depq_len != (if (K_DEC) k else 9 - k);
                            var i: u8 = 0;
                            if (has_empty_slots) {
                                i = depq_len;
                                while (true) {
                                    if (next_i_score >= nodes[depq_1_indexed[i].index].score) break;
                                    depq_1_indexed[i + 1] = depq_1_indexed[i];
                                    std.debug.assert(i != 0);
                                    i -= 1;
                                }
                            } else {
                                while (true) {
                                    var j = i + 1;
                                    if (next_i_score <= nodes[depq_1_indexed[j].index].score) break;
                                    depq_1_indexed[i] = depq_1_indexed[j];
                                    i = j;
                                }
                            }
                            depq_1_indexed[i + @intFromBool(has_empty_slots)] = .{ .index = next_i, .char_depth = char_depth };
                            depq_len += @intFromBool(has_empty_slots);
                            self.printDEPQ(nodes, depq, depq_len, results, if (K_DEC) 10 - k else k);
                        }
                        if (nodes[cur_i].down == NULL) break;
                        char_depth += nodes[cur_i].term_len;
                        cur_i = nodes[cur_i].down;
                        next_i = nodes[cur_i].next;
                    }

                    results[if (K_DEC) 10 - k else k] = str_buffer[nodes[cur_i].term_start - char_depth ..][0 .. char_depth + nodes[cur_i].term_len :0];
                    // results[if (K_DEC) 10-k else k] = str_buffer[term_start..][0 .. char_depth + nodes[cur_i].term_start + nodes[cur_i].term_len :0];
                    k = if (K_DEC) k - 1 else k + 1;
                    depq_len = std.math.sub(@TypeOf(depq_len), depq_len, 1) catch return if (K_DEC) 10 - k else k;
                    self.printDEPQ(nodes, depq, depq_len, results, if (K_DEC) 10 - k else k);
                    cur_i = depq[depq_len].index;
                    char_depth = depq[depq_len].char_depth;
                    next_i = nodes[cur_i].next;
                }
            }
        };

        fn makeCompletionTrieRecursive(
            self: *const SlicedDynSDT,
            allocator: Allocator,
            list: *std.ArrayListUnmanaged(CompletionTrie.CompletionTrieNode),
            parent_slot: *node_index_int,
            top_LCP: str_buf_int,
            // is_root: bool,
        ) !void {
            const root_i = parent_slot.*;
            if (root_i == NULL) return;
            const nodes = self.nodes;
            const chars = self.str_buffer;
            _ = chars;
            // if (!is_root) {
            //     const parent_node = @fieldParentPtr(CompletionTrie.CompletionTrieNode, "next", parent_slot);
            //     std.debug.print("key: \"{s}\", score: {}, next: {s}, LCP: {}\n", .{
            //         chars[parent_node.term_start..][0..parent_node.term_len],
            //         parent_node.score,
            //         self.nodes[parent_node.next].term(chars),
            //         top_LCP,
            //     });
            // }

            const root: Node = nodes[root_i];
            const score: score_int = self.scores[root_i];
            const root_term_start: str_buf_int = root.term_start;
            const list_start_index: usize = list.items.len;

            var prev_down: *node_index_int = parent_slot;
            var selected_LCP: std.meta.Int(.unsigned, @typeInfo(term_len_int).Int.bits * 2) = 0;
            var last_min_LCP: @TypeOf(selected_LCP) = undefined;
            var prev_selected_i = NULL;
            var selected_i = NULL;

            // {
            //     var cur_i = root.next;
            //     while (cur_i != NULL) : (cur_i = nodes[cur_i].down) {
            //         std.debug.print("{}, {s}\n", .{ nodes[cur_i].LCP, nodes[cur_i].term(chars) });
            //     }
            // }

            // Selection sort.... oof?
            while (true) : (prev_selected_i = selected_i) {
                selected_i = NULL;
                last_min_LCP = selected_LCP;
                selected_LCP = root.term_len;

                {
                    var cur_i = root.next;

                    while (cur_i != NULL) : (cur_i = nodes[cur_i].down) {
                        const LCP = nodes[cur_i].LCP;
                        if (last_min_LCP < LCP and LCP <= selected_LCP) {
                            selected_LCP = LCP;
                            selected_i = cur_i;
                        }
                    }
                }

                if (last_min_LCP == 0 and selected_LCP == top_LCP) continue;
                last_min_LCP = @max(top_LCP, last_min_LCP);

                prev_down.* = @as(node_index_int, @intCast(list.items.len));
                prev_down = blk: {
                    const slot: *CompletionTrie.CompletionTrieNode = try list.addOne(allocator);
                    slot.* = CompletionTrie.CompletionTrieNode{
                        .term_start = root_term_start + last_min_LCP,
                        .term_len = @as(term_len_int, @intCast(selected_LCP - last_min_LCP)),
                        .score = score,
                        .next = prev_selected_i, // This is from the old tree, we fix it up in the recursive call
                    };
                    // std.debug.print("key: {s}, next: {s}\n", .{ slot.term(chars), nodes[prev_selected_i].term(chars) });
                    break :blk &slot.down;
                };

                if (selected_i == NULL) break;
            }

            {
                const list_end_len = list.items.len;
                var i = list_start_index;

                while (i < list_end_len) : (i += 1) {
                    try makeCompletionTrieRecursive(self, allocator, list, &list.items[i].next, list.items[i].term_start - root.term_start);
                }
            }
        }

        pub fn makeCompletionTrie(self: *const SlicedDynSDT, allocator: Allocator) !CompletionTrie {
            var completion_trie = CompletionTrie{
                .roots = self.roots,
                .str_buffer = self.str_buffer,
                .node_list = blk: {
                    const new_memory = try allocator.alignedAlloc(CompletionTrie.CompletionTrieNode, null, self.nodes.len);
                    break :blk .{ .items = new_memory[0..0], .capacity = new_memory.len };
                },
            };
            errdefer completion_trie.node_list.deinit(allocator);

            (try completion_trie.node_list.addOne(allocator)).* = .{ .term_start = 0, .term_len = 0, .score = std.math.minInt(score_int) };
            (try completion_trie.node_list.addOne(allocator)).* = .{ .term_start = 0, .term_len = 0, .score = std.math.maxInt(score_int) };
            for (&completion_trie.roots) |*slot| try makeCompletionTrieRecursive(self, allocator, &completion_trie.node_list, slot, 0);
            return completion_trie;
        }

        fn makeArrayDynSDTRecursive(self: SlicedDynSDT, array_nodes: []ArrayDynSDT.ArrayNode, cur_array_node_ptr: *node_index_int, root: node_index_int) ArrayDynSDT.BranchPointPtr {
            const nodes = self.nodes;
            const scores = self.scores;

            var num_children: term_len_int = 0;
            var cur_i = nodes[root].next;
            while (cur_i != NULL) : (cur_i = nodes[cur_i].down) num_children += 1;

            cur_i = nodes[root].next;
            var bp: ArrayDynSDT.BranchPointPtr = undefined;
            bp.ptr = cur_array_node_ptr.*;
            cur_array_node_ptr.* += num_children;
            bp.end_ptr = cur_array_node_ptr.*;

            for (array_nodes[bp.ptr..][0..num_children]) |*node| {
                node.* = ArrayDynSDT.ArrayNode{
                    .score = scores[cur_i],
                    .LCP = nodes[cur_i].LCP,
                    .term_start = nodes[cur_i].term_start,
                    .branch_points = self.makeArrayDynSDTRecursive(array_nodes, cur_array_node_ptr, cur_i),
                };
                cur_i = nodes[cur_i].down;
            }

            return bp;
        }

        pub fn makeArrayDynSDT(self: SlicedDynSDT, allocator: Allocator) !ArrayDynSDT {
            const array_nodes = try allocator.alloc(ArrayDynSDT.ArrayNode, self.nodes.len);
            var cur_array_node_ptr: node_index_int = 0;
            var roots = std.mem.zeroes([256]ArrayDynSDT.ArrayNode);

            for (self.roots, 0..) |root, c| {
                if (root != NULL) {
                    roots[c] = ArrayDynSDT.ArrayNode{
                        .score = self.scores[root],
                        .LCP = 1,
                        .term_start = self.nodes[root].term_start,
                        .branch_points = self.makeArrayDynSDTRecursive(array_nodes, &cur_array_node_ptr, root),
                    };
                }
            }

            return ArrayDynSDT{ .roots = roots, .array_nodes = array_nodes, .str_buffer = self.str_buffer };
        }

        // inline fn getLocusIndexForPrefix(self: *const SlicedDynSDT, noalias prefix: string_t) if (BITWISE) struct { node_index_int, term_len_int } else node_index_int {
        //     return @call(.always_inline, getLocusIndexForPrefixGivenPrevious, .{ self, self.roots[prefix[0]], 1, prefix });
        // }

        fn getLocusIndexForPrefix(self: *const SlicedDynSDT, noalias prefix: string_t) if (BITWISE) struct { node_index_int, term_len_int } else node_index_int {
            const nodes = self.nodes;
            std.debug.assert(prefix.len > 0);

            var cur_i = self.roots[prefix[0]];
            if (cur_i == NULL) return if (BITWISE) .{ NULL, 0 } else NULL;
            var LCP: term_len_int = 1;
            var term1 = prefix[1..];
            if (0 == if (USE_NULL_TERMINATED_STRINGS) term1[0] else term1.len) return if (BITWISE) .{ cur_i, LCP } else cur_i;

            while (true) {
                outer: {
                    const first = if (STORE_4_TERM_BYTES_IN_NODE)
                        @as(u16, @intCast(bits_in_common2(std.mem.readIntLittle(u32, term1.ptr[0..4]), nodes[cur_i].next4chars) / if (BITWISE) 1 else 8));

                    if (STORE_4_TERM_BYTES_IN_NODE) {
                        LCP += first;
                        term1 = term1[first..];
                        if (0 == if (USE_NULL_TERMINATED_STRINGS) term1[0] else term1.len) return if (BITWISE) .{ cur_i, LCP } else cur_i;
                        if (first != (if (BITWISE) 32 else 4)) break :outer;
                    }

                    var term2 = nodes[cur_i].term(self.str_buffer) + if (BITWISE) LCP / 8 else LCP;
                    // LCP = longestCommonPrefixASM(LCP, term, term2);

                    // has_zero_byte
                    // index_of_first_set_byte
                    // std.debug.print("LCP: {}\n", .{LCP});
                    if (BITWISE) LCP &= ~@as(@TypeOf(LCP), 0b0111);
                    // std.debug.print("LCP: {}\n", .{LCP});

                    while (true) {
                        if (0 == if (USE_NULL_TERMINATED_STRINGS) term2[0] else term2.len) break;
                        if (BITWISE) {
                            const bit_chunk_size = 64;
                            const a = std.mem.readIntLittle(std.meta.Int(.unsigned, bit_chunk_size), term1.ptr[0..8]);
                            const b = std.mem.readIntLittle(std.meta.Int(.unsigned, bit_chunk_size), term2[0..8]);
                            const lcp = bits_in_common2(a, b);
                            LCP += @as(u16, @intCast(lcp));
                            term1 = term1[lcp / 8 ..];
                            if (0 == if (USE_NULL_TERMINATED_STRINGS) term1[0] else term1.len) return if (BITWISE) .{ cur_i, LCP } else cur_i;
                            if (bit_chunk_size != lcp) break;
                            term2 += lcp / 8;
                        } else {
                            if (term1[0] != term2[0]) break;
                            LCP += 1;
                            term1 = term1[1..];
                            if (0 == if (USE_NULL_TERMINATED_STRINGS) term1[0] else term1.len) return if (BITWISE) .{ cur_i, LCP } else cur_i;
                            term2 += 1;
                        }
                    }
                }

                // while (LCP < len and term1[LCP] == term2[LCP]) LCP += 1;
                // std.debug.assert(!(LCP < len and term1[LCP] == term2[LCP]));

                // LCP = longestCommonPrefix(LCP, prefix, nodes[cur_i].term(str_buffer));
                // }

                // if (0 == if (USE_NULL_TERMINATED_STRINGS) term1[0] else term1.len) return cur_i;
                // if (LCP == prefix.len) return cur_i;
                cur_i = nodes[cur_i].getNext();

                while (true) {
                    if (cur_i == NULL) return if (BITWISE) .{ NULL, 0 } else NULL;
                    const node = nodes[cur_i];
                    // std.debug.print("LCP: {} term: \"{s}\"\n", .{ node.LCP, node.term(str_buffer) });
                    if (node.getLCP() == LCP) break;
                    cur_i = node.getDown();
                }
            }
        }

        fn firstVerticalSuccessor(nodes: []const Node, LCP: term_len_int, _cur_i: node_index_int) node_index_int {
            var cur_i = nodes[_cur_i].getNext();
            while (true) : (cur_i = nodes[cur_i].getDown()) { // finds vertical successor
                // Having a separate check here allows the optimizer to extend the jump when we check cur_i == null after running this function
                if (cur_i == NULL) break;
                if (nodes[cur_i].getLCP() >= LCP) break; // might skip nodes when directly under the locus
            }
            return cur_i;
        }

        fn verticalSuccessor(nodes: []const Node, LCP: term_len_int, _cur_i: node_index_int) node_index_int {
            var cur_i = _cur_i;
            while (true) { // finds vertical successor
                cur_i = nodes[cur_i].getDown();
                // Having a separate check here allows the optimizer to extend the jump when we check cur_i == null after running this function
                if (cur_i == NULL) break;
                if (nodes[cur_i].getLCP() >= LCP) break; // might skip nodes when directly under the locus
            }
            return cur_i;
        }

        inline fn horizontalSuccessor(nodes: []const Node, cur_i: node_index_int) node_index_int {
            return nodes[cur_i].getNext();
        }

        const topK_int = if (builtin.mode == .Debug) u32 else u6;

        inline fn get_winner_i(a: node_index_int, b: node_index_int, scores: if (MAINTAIN_SORTED_ORDER_IN_MEMORY) []const score_int) node_index_int {
            return if (MAINTAIN_SORTED_ORDER_IN_MEMORY) // grab the winner
                @max(a, b)
            else if (scores[a] > scores[b]) a else b;
        }

        inline fn get_loser_i(a: node_index_int, b: node_index_int, winner_i: node_index_int) node_index_int {
            return if (MAINTAIN_SORTED_ORDER_IN_MEMORY)
                @min(a, b)
            else
                a ^ b ^ winner_i; // grab the loser
        }

        fn h(b: bool) string {
            return if (b) "vvvvvvv" else "^^^^^^^";
        }

        fn printState(depq_len: u32, depq: [4]u32, pred: [4]bool, shifted_depq: [4]u32, cur_i: u32) void {
            if (1 != 1) {
                std.debug.print("T depq: [{}]string{{ {:0>7}, {:0>7}, {:0>7}, {:0>7} }}, inserted: {}\n", .{ depq_len, if (depq_len > 0) depq[0] else 0, if (depq_len > 1) depq[1] else 0, if (depq_len > 2) depq[2] else 0, if (depq_len > 3) depq[3] else 0, cur_i });
                std.debug.print("+ depq: [{}]string{{ {s: >0}, {s: >0}, {s: >0}, {s: >0} }}\n", .{ depq_len, h(pred[0]), h(pred[1]), h(pred[2]), h(pred[3]) });
                std.debug.print("F depq: [{}]string{{ {:0>7}, {:0>7}, {:0>7}, {:0>7} }}, inserted: {}\n", .{ depq_len, if (depq_len >= 0) shifted_depq[0] else 0, if (depq_len >= 1) shifted_depq[1] else 0, if (depq_len >= 2) shifted_depq[2] else 0, if (depq_len >= 3) shifted_depq[3] else 0, cur_i });
            }
        }

        fn printFinalState(depq_len: u32, depq: [4]u32, cur_i: u32, k: u4) void {
            std.debug.print("_ depq: [{}]string{{ {:0>7}, {:0>7}, {:0>7}, {:0>7} }}, inserted: {}, k: {}\n\n", .{ depq_len, if (depq_len > 0) depq[0] else 0, if (depq_len > 1) depq[1] else 0, if (depq_len > 2) depq[2] else 0, if (depq_len > 3) depq[3] else 0, cur_i, k });
        }

        fn printDEPQ(nodes: []const Node, scores: []const score_int, depq: *[5]node_index_int, depq_len: u8, chars: string, results: anytype, k: u8, from: string) void {
            if (!SHOULD_PRINT) return;
            if (depq_len == 0) return;
            std.debug.print("({s}) depq: [{}]{{ (\"{s}\", {})", .{ from, depq_len, nodes[depq[0]].term(chars), scores[depq[0]] });
            var i: u8 = 0;
            while (true) {
                i += 1;
                if (i == depq_len) break;
                std.debug.print(", (\"{s}\", {})", .{ nodes[depq[i]].term(chars), scores[depq[i]] });
            }
            std.debug.print(" }}\n           results: [{}]{{ \"{s}\"", .{ if (K_DEC) 10 - k else k, results[0] });
            i = 0;
            while (true) {
                i += 1;
                if (i == if (K_DEC) 10 - k else k) break;
                std.debug.print(", \"{s}\"", .{results[i]});
            }
            std.debug.print(" }}\n\n", .{});
        }

        fn insert_cur_i(nodes: []const Node, scores: []const score_int, depq_len_: u8, str_buffer: string, parent_i: node_index_int, results: *[10][*:0]const u8, LCP: term_len_int, depq: *[4 + 1]node_index_int, depq_1_indexed: *[5 + 1]node_index_int, k: u8) u8 {

            // printDEPQ(self.nodes.items, self.scores.items, depq, depq_len_, str_buffer, results, k, "insert_cur_i");
            const cur_i = verticalSuccessor(nodes, LCP, parent_i);

            if (cur_i != NULL) { // we could check if cur_i > depq[0]
                if (SHOULD_PRINT) std.debug.print("{{ {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7} }}, cur_i: {:0>7} \n", .{ depq_1_indexed[0], depq_1_indexed[1], depq_1_indexed[2], depq_1_indexed[3], depq_1_indexed[4], depq_1_indexed[5], cur_i });
                if (SHOULD_PRINT) std.debug.print("score: {}\n", .{scores[cur_i]});
                var i: u8 = 0;
                const cur_i_score = scores[cur_i];
                while (true) {
                    // { 3, 5, 6, 7, 9 } insert 6
                    var j = i + 1;
                    if (cur_i_score <= scores[depq_1_indexed[j]]) break;
                    depq_1_indexed[i] = depq_1_indexed[j];
                    i = j;
                }
                depq_1_indexed[i] = cur_i;
                if (SHOULD_PRINT) std.debug.print("{{ {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7} }} \n", .{ depq_1_indexed[0], depq_1_indexed[1], depq_1_indexed[2], depq_1_indexed[3], depq_1_indexed[4], depq_1_indexed[5] });
            }

            return insert_next_i(nodes, scores, depq_len_ - 1, str_buffer, results, LCP, depq, depq_1_indexed, k);
        }

        fn insert_next_i(nodes: []const Node, scores: []const score_int, depq_len: u8, str_buffer: string, results: *[10][*:0]const u8, LCP: term_len_int, depq: *[4 + 1]node_index_int, depq_1_indexed: *[5 + 1]node_index_int, k: u8) u8 {
            // printDEPQ(self.nodes.items, self.scores.items, depq, depq_len, str_buffer, results, k, "insert_next_i");

            var cur_i = depq[depq_len];

            // If the DEPQ is full but only because we already have so many completions. E.g. if we found
            // 8 completions already then we only need 2 more if topK=10. Because k has not been incremented
            // yet, when k=7, we would consider depq_len=2 to be full.
            // e.g. { 45, _ } -> 48, 49
            // std.debug.assert(depq_len <= 9 - k);
            if (SHOULD_PRINT) std.debug.print("pushing {} to results[{}]\n", .{ cur_i, k });

            results[if (K_DEC) 10 - k else k] = nodes[cur_i].term(str_buffer);
            var l = if (K_DEC) k - 1 else k + 1;
            if (l == if (K_DEC) 0 else 10) return 10;
            var next_i = horizontalSuccessor(nodes, cur_i);

            if (next_i != NULL) { // we could check if (next_i > depq[0]
                // std.debug.print("{{ {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7} }}, next_i: {:0>7} \n", .{ depq_1_indexed[0], depq_1_indexed[1], depq_1_indexed[2], depq_1_indexed[3], depq_1_indexed[4], depq_1_indexed[5], next_i });
                var i: u8 = 0;
                const next_i_score = scores[next_i];
                while (true) {
                    // { 5, 6, 7, 8, 9 } insert 8
                    var j = i + 1; // 2
                    if (next_i_score <= scores[depq_1_indexed[j]]) break;
                    depq_1_indexed[i] = depq_1_indexed[j];
                    i = j; // 1
                }
                depq_1_indexed[i] = next_i;
                // std.debug.print("{{ {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7}, {:0>7} }} \n", .{ depq_1_indexed[0], depq_1_indexed[1], depq_1_indexed[2], depq_1_indexed[3], depq_1_indexed[4], depq_1_indexed[5] });
                // if (SHOULD_PRINT) printFinalState(depq_len, depq, next_i, k);
            }

            return insert_cur_i(nodes, scores, depq_len, str_buffer, cur_i, results, LCP, depq, depq_1_indexed, l);
        }

        pub fn topKCompletionsToPrefix(self: *const SlicedDynSDT, noalias prefix: string_t, noalias results: *[10][*:0]const u8) u8 {
            const locus_and_LCP = @call(.always_inline, getLocusIndexForPrefix, .{ self, prefix });
            const locus: node_index_int = if (BITWISE) locus_and_LCP[0] else locus_and_LCP;
            const LCP: term_len_int = if (BITWISE) locus_and_LCP[1] else @as(term_len_int, @intCast(prefix.len));
            return @call(.always_inline, topKCompletionsToLocus, .{ self, locus, LCP, results });
        }

        // cur_i = self.getLocusIndexForPrefix(cur_i, LCP, prefix, nodes, str_buffer);

        /// Fills up a given array of strings with completions to a given prefix string, if present in the structure,
        /// and returns the number of completions that were written.
        /// The completions will be in descending sorted order by score, so the "most relevant" completions will
        /// come first. The algorithm is explained here: https://validark.github.io/DynSDT/#top-k_enumeration
        /// The data structure owns the memory within the individual strings.
        pub fn topKCompletionsToLocus(self: *const SlicedDynSDT, locus: node_index_int, LCP: term_len_int, noalias results: *[10][*:0]const u8) u8 {
            const nodes = self.nodes;
            const scores = self.scores;
            const str_buffer = self.str_buffer;

            // We use the term "successor" to just mean "the next one". It is not akin to how the term is used for
            // vEB/x-fast/y-fast/z-fast trees.
            var cur_i = locus;

            // Push locus node to the results!
            results[0] = nodes[cur_i].term(str_buffer);

            // Find vertical successor, skipping over nodes as necessary with insufficient LCP's
            cur_i = firstVerticalSuccessor(nodes, LCP, cur_i);
            if (cur_i == NULL) return 1;

            // nodes[cur_i] is now the second completion
            results[1] = nodes[cur_i].term(str_buffer);

            var k: u8 = if (K_DEC) 10 - 2 else 2;
            const half_topK = 4;
            // const half_topK_bitmap_int = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = half_topK } });
            var depq_1_indexed: [half_topK + 1 + 1]node_index_int = undefined;
            depq_1_indexed[0] = 0;
            var depq: *[half_topK + 1]node_index_int = depq_1_indexed[1..];
            inline for (depq) |*p|
                p.* = if (MAINTAIN_SORTED_ORDER_IN_MEMORY) std.math.maxInt(node_index_int) else 1; // 1 is where our sentinel with a score of maxInt resides
            var depq_len: u8 = 0;

            std.debug.assert(scores[1] == std.math.maxInt(score_int));

            if (MOVE_FIRST_ITERATION_OF_TOPK_QUERY_OUT_OF_LOOP) {
                var next_i: node_index_int = horizontalSuccessor(nodes, cur_i);
                var old_i = verticalSuccessor(nodes, LCP, cur_i);
                cur_i = get_winner_i(old_i, next_i, scores);
                if (cur_i == NULL) return 2;
                results[2] = nodes[cur_i].term(str_buffer);
                k = if (K_DEC) 10 - 3 else 3;
                const loser_i = get_loser_i(next_i, old_i, cur_i);
                if (loser_i != NULL) depq[0] = loser_i;
                depq_len += @intFromBool(loser_i != NULL);
            }

            while (true) { // TODO: Maybe try inserting unconditionally? Insert both simultaneously?
                const next_i = horizontalSuccessor(nodes, cur_i);

                if (next_i != NULL) {
                    var i: u8 = depq_len;
                    const next_i_score = scores[next_i];
                    while (true) {
                        if (next_i_score >= scores[depq_1_indexed[i]]) break;
                        depq_1_indexed[i + 1] = depq_1_indexed[i];
                        std.debug.assert(i != 0);
                        i -= 1;
                    }
                    depq_1_indexed[i + 1] = next_i;
                    depq_len += 1;
                    printDEPQ(nodes, scores, depq, depq_len, str_buffer, results, k, "main2");
                    // std.debug.print("depq_len: {}, k: {}, i: {}\n", .{ depq_len, k, i });
                    if (depq_len == (if (K_DEC) k else 10 - k))
                        return insert_cur_i(nodes, scores, depq_len, str_buffer, cur_i, results, LCP, depq, &depq_1_indexed, k);
                }

                cur_i = verticalSuccessor(nodes, LCP, cur_i);

                if (cur_i != NULL) {
                    var i: u8 = depq_len;
                    const cur_i_score = scores[cur_i];
                    while (true) {
                        if (cur_i_score >= scores[depq_1_indexed[i]]) break;
                        depq_1_indexed[i + 1] = depq_1_indexed[i];
                        std.debug.assert(i != 0);
                        i -= 1;
                    }
                    depq_1_indexed[i + 1] = cur_i;

                    // When the DEPQ is full and we need to insert next_i, jump to the second while loop
                    // std.debug.assert(depq_len <= 10 - k);
                    printDEPQ(nodes, scores, depq, depq_len + 1, str_buffer, results, k, "main1");
                    if (depq_len + 1 == (if (K_DEC) k else 10 - k))
                        return insert_next_i(nodes, scores, depq_len, str_buffer, results, LCP, depq, &depq_1_indexed, k);
                } else {
                    depq_len = std.math.sub(@TypeOf(depq_len), depq_len, 1) catch return if (K_DEC) 10 - k else k;
                }

                cur_i = depq[depq_len];

                // If the DEPQ is full but only because we already have so many completions. E.g. if we found
                // 8 completions already then we only need 2 more if topK=10. Because k has not been incremented
                // yet, when k=7, we would consider depq_len=2 to be full.
                // e.g. { 45, _ } -> 48, 49
                // std.debug.assert(depq_len <= 9 - k);
                // std.debug.print("pushing {} to results[{}]\n", .{ cur_i, 10 - k });
                results[if (K_DEC) 10 - k else k] = nodes[cur_i].term(str_buffer);
                k = if (K_DEC) k - 1 else k + 1;
                printDEPQ(nodes, scores, depq, depq_len, str_buffer, results, k, "main3");
            }
        }
    };

    fn slice(self: DynSDT) SlicedDynSDT {
        const slices = self.data.multilist.slice();

        return .{
            .roots = self.roots,
            .nodes = slices.items(.node),
            .scores = slices.items(.score),
            .str_buffer = self.data.str_buffer_slice(),
        };
    }

    fn initWithNodes(nodes: []Node, chars: []u8) [256]node_index_int {
        var roots: [256]node_index_int = undefined;

        for (&roots) |*root| root.* = NULL;
        var i = @as(node_index_int, @intCast(nodes.len));

        NEXT_NODE: while (true) {
            i -= 1;
            if (i == 1) break;

            const node = &nodes[i];
            var term = node.term(chars);
            std.debug.assert(term[0] != 0);

            var LCP: term_len_int = if (BITWISE) 8 else 1;
            var cur_i: node_index_int = roots[term[0]];
            if (cur_i == NULL) {
                // node.@"next/LCP".LCP = 1;
                node.LCP = if (BITWISE) 8 else 1;
                if (STORE_4_TERM_BYTES_IN_NODE)
                    node.update_next4chars(chars);
                roots[term[0]] = i;
                continue;
            }

            term = term + 1;

            while (true) {
                if (0 != if (USE_NULL_TERMINATED_STRINGS) term[0] else term.len) outer: {
                    const first = if (STORE_4_TERM_BYTES_IN_NODE)
                        @as(u16, @intCast(bits_in_common2(std.mem.readIntLittle(u32, term[0..4]), nodes[cur_i].next4chars) / if (BITWISE) 1 else 8));

                    if (STORE_4_TERM_BYTES_IN_NODE) {
                        LCP += first;
                        term += first;
                        if (first != (if (BITWISE) 32 else 4) or 0 == if (USE_NULL_TERMINATED_STRINGS) term[0] else term.len) break :outer;
                    }

                    var term2 = nodes[cur_i].term(chars) + if (BITWISE) LCP / 8 else LCP;
                    if (BITWISE) LCP &= ~@as(@TypeOf(LCP), 0b0111);
                    // LCP = longestCommonPrefixASM(LCP, term, term2);
                    // term2 += if (BITWISE) LCP / 8 else LCP;

                    while (true) {
                        if (0 == if (USE_NULL_TERMINATED_STRINGS) term2[0] else term2.len) break;
                        if (BITWISE) {
                            const xor = term[0] ^ term2[0];
                            const tz = @ctz(xor);
                            LCP += tz;
                            if (xor != 0) break;
                            term += 1;
                            if (0 == if (USE_NULL_TERMINATED_STRINGS) term[0] else term.len) break;
                            term2 += 1;
                        } else {
                            if (term[0] != term2[0]) break;
                            LCP += 1;
                            term += 1;
                            if (0 == if (USE_NULL_TERMINATED_STRINGS) term[0] else term.len) break;
                            term2 += 1;
                        }
                    }
                }

                const next = nodes[cur_i].getNext();

                if (next == NULL) {
                    node.LCP = LCP;
                    if (STORE_4_TERM_BYTES_IN_NODE) node.update_next4chars(chars);
                    nodes[cur_i].next = i;
                    continue :NEXT_NODE;
                }

                cur_i = next;

                while (nodes[cur_i].getLCP() != LCP) : (cur_i = nodes[cur_i].getDown()) {
                    if (nodes[cur_i].getDown() == NULL) {
                        node.LCP = LCP;
                        if (STORE_4_TERM_BYTES_IN_NODE) node.update_next4chars(chars);
                        nodes[cur_i].down = i;
                        continue :NEXT_NODE;
                    }
                }
            }
        }

        return roots;
    }

    pub fn deinit(self: *DynSDT, allocator: Allocator) void {
        self.data.deinit(allocator);
        self.* = undefined;
    }

    fn readHelper1(file: *std.fs.File, file_buf: *[MAIN_BUF_LEN + 2]u8, file_buf_sentinel: []u8, file_buf_cursor: []u8, string_buffer_: []u8, node_list_cur_: []Node, scores_cur_: []score_int, string_buffer_start_ptr: usize, comptime matching: u8) (error{ Overflow, tooManyCharactersInBuffer, InvalidFile } || std.os.ReadError)!void {
        // file_buf_sentinel[0] = matching;

        var buf = file_buf_cursor;
        var sentinel = file_buf_sentinel;
        var node_list_cur = node_list_cur_;
        var scores_cur = scores_cur_;
        var string_buffer = string_buffer_;

        if (matching == '\t') {
            var current_term_len: u8 = 0;

            while (true) {
                const current_term_start_ptr = @intFromPtr(string_buffer.ptr);

                while (buf[0] != '\t') : (buf = buf[1..]) {
                    string_buffer[0] = buf[0];
                    string_buffer = string_buffer[1..];
                }

                current_term_len = try std.math.add(u8, current_term_len, std.math.cast(u8, @intFromPtr(string_buffer.ptr) - current_term_start_ptr) orelse return error.Overflow);

                if (@intFromPtr(buf.ptr) >= @intFromPtr(sentinel.ptr)) {
                    // if (@ptrToInt(sentinel.ptr) != @ptrToInt(&file_buf[MAIN_BUF_LEN])) {
                    // std.debug.print("[0] buf.len: {}, bytes_to_consume: {}\n", .{ buf.len, bytes_to_consume });
                    // std.debug.print("[0] bytes_to_consume: {}\nnode_list_i: {}\nbuf:{s}:\nptr1: {}\nptr2: {}\n", .{ bytes_to_consume, node_list_i, file_buf, @ptrToInt(buf.ptr), @ptrToInt(&file_buf[bytes_to_consume]) });
                    // return error.InvalidFile;e
                    // }
                    buf = file_buf;
                    var bytes_to_consume = try file.read(file_buf[0..MAIN_BUF_LEN]);
                    if (bytes_to_consume != MAIN_BUF_LEN) {
                        sentinel = file_buf[bytes_to_consume..];
                        sentinel[0] = '\t';
                        sentinel[1] = '\n';
                    }
                    continue;
                }

                const current_term_start = std.math.cast(str_buf_int, @intFromPtr(string_buffer.ptr) - string_buffer_start_ptr - current_term_len) orelse return error.tooManyCharactersInBuffer;
                string_buffer[0] = 0;
                string_buffer = string_buffer[1..];

                node_list_cur_[0] = Node.init(current_term_start, current_term_len);
                // std.debug.print("{s}\n", .{node_list_cur_[0].term(@intToPtr([*]u8, string_buffer_start_ptr)[0 .. current_term_start + current_term_len])});
                // if (std.mem.eql(u8, "w crawford", node_list_cur_[0].term(@intToPtr([*]u8, string_buffer_start_ptr)[0 .. current_term_start + current_term_len]))) {
                //     std.debug.print("Made it here!\n", .{});
                // }
                node_list_cur = node_list_cur_[1..];
                break;
            }
        } else if (matching == '\n') {
            var current_score: score_int = 0;

            while (true) {
                // if (buf.len <= 26323 + 30 and string_buffer.len <= 82696063 + 30) {
                //     std.debug.print("Hello!\n", .{});
                // }
                while (true) : (buf = buf[1..]) {
                    switch (buf[0]) {
                        '\n' => break,

                        // TODO: Do bounds checking LATER
                        '0'...'9' => |c| current_score = try std.math.add(score_int, try std.math.mul(score_int, current_score, 10), c - '0'),
                        else => unreachable,
                    }
                }

                if (@intFromPtr(buf.ptr) >= @intFromPtr(sentinel.ptr)) {
                    // if (@ptrToInt(sentinel.ptr) != @ptrToInt(&file_buf[MAIN_BUF_LEN])) {
                    // if (bytes_to_consume != MAIN_BUF_LEN) {
                    // std.debug.print("[0] buf.len: {}, bytes_to_consume: {}\n", .{ buf.len, bytes_to_consume });
                    // return;
                    // }
                    buf = file_buf;
                    var bytes_to_consume = try file.read(file_buf[0..MAIN_BUF_LEN]);
                    if (bytes_to_consume == 0) return;
                    sentinel = file_buf[bytes_to_consume..];
                    continue;
                }

                // if (scores_cur.len < 100) {
                // std.debug.print("Made it!\n", .{});
                // }

                scores_cur[0] = current_score;
                scores_cur = scores_cur[1..];
                if (scores_cur.len == 0) return;
                // if (@ptrToInt(scores_cur) == 0) {
                // std.debug.print("[1] buf.len: {}, bytes_to_consume: {}\n", .{ buf.len, bytes_to_consume });
                // break :OUTER;
                // std.debug.print("[1] bytes_to_consume: {}\nnode_list_i: {}\nbuf:{s}:\nptr1: {}\nptr2: {}\n", .{ bytes_to_consume, node_list_i, file_buf, @ptrToInt(buf.ptr), @ptrToInt(&file_buf[bytes_to_consume]) });
                // std.debug.print("str:{s}:\n", .{node_list.items[node_list_i].term(backing_string_buffer.items)});
                // }
                break;
            }
        } else unreachable;

        // @call(.{ .modifier = .always_tail }
        // @call()

        return @call(.always_tail, readHelper1, .{ file, file_buf, sentinel, buf[1..], string_buffer, node_list_cur, scores_cur, string_buffer_start_ptr, matching ^ 3 });
        // return readHelper1(file, file_buf, sentinel, buf[1..], string_buffer, node_list_cur, scores_cur, string_buffer_start_ptr, matching ^ 3);
    }

    const SCORE_LEN = std.fmt.count("{}", .{std.math.maxInt(score_int)});
    const SCORE_VEC_SIZE = @as(comptime_int, std.math.ceilPowerOfTwo(u16, SCORE_LEN) catch unreachable);

    fn parseScoreInt(score_slice: []u8) !score_int {
        if (score_slice.len == 0 or score_slice.len > SCORE_LEN) {
            return error.@"Number too long in file.";
        }

        // const buf: [std.fmt.count("{}", .{std.math.maxInt(u32)})]u8 = undefined;
        // for (buf) |*p| p.* = '0';

        // (slice.ptr - SCORE_VEC_SIZE)[0..SCORE_VEC_SIZE].* = @splat(SCORE_VEC_SIZE, @as(u8, '0'));
        // The size of our Vector is required to be known at compile time,
        // so let's compute our "multiplication mask" at compile time too!
        comptime var multi_mask: @Vector(SCORE_VEC_SIZE, u32) = undefined;

        // Our accumulator for our "multiplication mask" (radix pow 0, radix pow 1, radix pow 2, etc.)
        comptime var acc: score_int = 1;
        // Preload the vector with our powers of radix
        comptime for (0..SCORE_VEC_SIZE) |i| {
            multi_mask[SCORE_VEC_SIZE - i - 1] = acc;
            acc = std.math.mul(score_int, acc, 10) catch 0;
        };

        // Let's actually do the math now!
        var vec: @Vector(SCORE_VEC_SIZE, u8) = (score_slice.ptr - SCORE_VEC_SIZE + score_slice.len)[0..SCORE_VEC_SIZE].*;
        vec -%= @splat(SCORE_VEC_SIZE, @as(u8, '0'));

        return @reduce(.Add, vec * multi_mask);
    }

    const MEMCPY_STEP = 32;

    inline fn memcpy_chunk(noalias chars: anytype, noalias chunky: anytype, chars_i: *str_buf_int) void {
        // We copy bytes over in chunks of this size, that way our memcpy call can be compiled down to branchless code.
        var chunk = chunky;

        while (true) {
            @memcpy(chars[chars_i.*..][0..MEMCPY_STEP], chunk.ptr);
            chunk.len = std.math.sub(usize, chunk.len, MEMCPY_STEP) catch break;
            chars_i.* += MEMCPY_STEP;
            chunk.ptr += MEMCPY_STEP;
        }

        chars_i.* += @as(@TypeOf(chars_i.*), @intCast(chunk.len));
    }

    const MatchingState = enum(u1) {
        str = 0,
        int = 1,

        pub fn flip(self: *@This()) void {
            self.* = @as(@This(), @enumFromInt(@intFromEnum(self.*) ^ 1));
        }

        pub fn other(self: @This()) @This() {
            return @as(@This(), @enumFromInt(@intFromEnum(self) ^ 1));
        }
    };

    fn readHelper2(file_buf_main: []u8, file_buf_main_masks: []std.meta.Int(.unsigned, VEC_SIZE_FOR_POPCOUNT), int_start: *isize, term_start: *usize, nodes: *[]Node, scores: *[]score_int, chars: []u8, chars_i_: *usize, k_: isize, state_global: *MatchingState, state: MatchingState) error{ @"Number too long in file.", @"The number of characters exceeded what can be stored in str_buf_int", @"String length could not fit in term_len_int" }!void {
        // we need these to persist: term_start, nodes, scores, chars_i_
        var k = k_;
        var masks = file_buf_main_masks;
        const bitmask = blk: while (true) {
            if (masks.len == 0) {
                state_global.* = state;
                return;
            }
            const bitmask = masks[0];
            if (bitmask != 0) break :blk bitmask;
            k += 64;
            masks = masks[1..];
        };

        const int_end = k | @ctz(bitmask);
        masks[0] &= bitmask - 1;
        const prev_int_start = int_start.*;
        var file_slice: []u8 = undefined;

        // slice.ptr = file_buf_main.ptr + prev_int_start
        file_slice.ptr = if (prev_int_start < 0)
            file_buf_main.ptr - @as(usize, @intCast(-prev_int_start))
        else
            file_buf_main.ptr + @as(usize, @intCast(prev_int_start));

        file_slice.len = @as(usize, @intCast(int_end - prev_int_start));
        int_start.* = int_end + 1;

        switch (state) {
            .str => {
                _ = @as(term_len_int, @intCast((chars_i_.* + file_slice.len) - term_start.*));
                nodes.*[0] = Node.init(
                    std.math.cast(str_buf_int, term_start.*) orelse return error.@"The number of characters exceeded what can be stored in str_buf_int",
                    std.math.cast(term_len_int, (chars_i_.* + file_slice.len) - term_start.*) orelse return error.@"String length could not fit in term_len_int",
                );
                nodes.* = nodes.*[1..];
                memcpy_chunk(chars, file_slice, chars_i_);

                if (USE_NULL_TERMINATED_STRINGS) {
                    chars[chars_i_.*] = 0;
                    chars_i_.* += 1;
                }
                term_start.* = chars_i_.*;

                return @call(.always_tail, readHelper2, .{ file_buf_main, masks, int_start, term_start, nodes, scores, chars, chars_i_, k, state_global, state.other() });
            },
            .int => {
                // const set_amt = std.math.ceilPowerOfTwo(u16, std.fmt.count("{}", std.math.maxInt(score_int)));
                var score: std.meta.Int(.unsigned, @typeInfo(score_int).Int.bits * 2) = 0;

                @memset((file_slice.ptr - SCORE_VEC_SIZE)[0..SCORE_VEC_SIZE], '0');

                comptime var deviation = 0;
                comptime var acc = 1;
                // Preload the vector with our powers of radix
                inline for (1..SCORE_LEN + 1) |i| {
                    // std.debug.print("+ {c}*{}\n", .{ (slice.ptr + slice.len - i)[0], acc });
                    score +%= ((file_slice.ptr + file_slice.len - i)[0]) * @as(@TypeOf(score), acc);
                    deviation += '0' * acc;
                    acc = acc * 10;
                }

                const new_score = (score - deviation) +| scores.*[0];

                if (new_score > std.math.maxInt(score_int) or file_slice.len == 0 or file_slice.len > SCORE_LEN)
                    return error.@"Number too long in file.";

                scores.*[0] = @as(score_int, @intCast(new_score));
                scores.* = scores.*[1..];
                return @call(.always_tail, readHelper2, .{ file_buf_main, masks, int_start, term_start, nodes, scores, chars, chars_i_, k, state_global, state.other() });
            },
        }
    }

    const USE_SIMD_FOR_INIT = true;
    const SHOULD_ALIGN_BUFFER = false; // An experiment that proved fruitless

    // Used to store leftover data from iteration to iteration where we ended on a boundary.
    // Makes the hot loop simpler.
    // e.g. if file_buf_main ends with [...word1\t543] and then we refill it with [21\nword2\t520...]
    // we want to copy 543 to the beginning of the buffer, before the area where the data will be filled.
    // That way, we have the entire integer contiguously in the buffer which can be parsed all at once.
    const PRE_BUF_LEN = if (USE_SIMD_FOR_INIT)
        @max(@intFromBool(SHOULD_ALIGN_BUFFER) + @as(term_len_int, std.math.maxInt(term_len_int)), MEMCPY_STEP, SCORE_VEC_SIZE * 2)
    else
        0;
    const POST_BUF_LEN = if (USE_SIMD_FOR_INIT) VEC_SIZE_FOR_POPCOUNT else 2; // used to memset by `VEC_SIZE_FOR_POPCOUNT`-sized chunks

    pub fn initFromFile(allocator: Allocator, file_path: string) !DynSDT {
        std.debug.print("Instantiating Trie...\n", .{});
        const VEC_SIZE = VEC_SIZE_FOR_POPCOUNT;
        const start_time = std.time.milliTimestamp();
        var file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var file_buf align(if (SHOULD_ALIGN_BUFFER) VEC_SIZE else 1) = [_]u8{undefined} ** (PRE_BUF_LEN + MAIN_BUF_LEN + POST_BUF_LEN);
        const file_buf_main: []align(@alignOf(@TypeOf(file_buf))) u8 = file_buf[if (USE_SIMD_FOR_INIT) PRE_BUF_LEN else 0..][0..MAIN_BUF_LEN];

        // const over_allocated_terms = node_list.capacity - num_term_pairs;
        // const approximate_string_buffer_over_allocation = over_allocated_terms *| 8;

        const NUM_SENTINELS = 2;
        const buffer_requirements = try Buffer.calcNeededSize(file, file_buf_main, NUM_SENTINELS);
        const avg_string_len = 1 + buffer_requirements.strings_length / buffer_requirements.num_term_pairs;
        _ = avg_string_len;

        // We only need one allocation :D
        const new_bytes_len = buffer_requirements.total_size + @max(VEC_SIZE_TO_FIND_LCP, (MEMCPY_STEP - 1));
        const new_bytes = try allocator.alignedAlloc(u8, @alignOf(ScoredNode), new_bytes_len);
        errdefer allocator.free(new_bytes);

        const multilist: MultiArrayList(ScoredNode) = .{
            .bytes = new_bytes.ptr,
            .capacity = buffer_requirements.num_term_pairs,
            .len = buffer_requirements.num_term_pairs,
        };

        const multilist_slice = multilist.slice();
        const node_list: []Node = multilist_slice.items(.node);
        const score_list: []score_int = multilist_slice.items(.score);
        const chars = new_bytes[buffer_requirements.multilist_size..];

        var nodes: []Node = node_list;
        var scores: []score_int = score_list;

        // These are our NULL nodes, used as a sentinel sometimes to avoid bounds checks
        nodes[0..NUM_SENTINELS].* = [NUM_SENTINELS]Node{ Node.initSentinel(buffer_requirements.strings_length - 1), Node.initSentinel(buffer_requirements.strings_length - 1) };
        scores[0..NUM_SENTINELS].* = [NUM_SENTINELS]score_int{ std.math.minInt(score_int), std.math.maxInt(score_int) };

        // `nodes` and `scores` are now backwards fat pointers
        nodes.ptr += buffer_requirements.num_term_pairs;
        scores.ptr += buffer_requirements.num_term_pairs;
        nodes.len -= NUM_SENTINELS;
        scores.len -= NUM_SENTINELS;

        try file.seekTo(0);

        if (!USE_SIMD_FOR_INIT) {
            file_buf[MAIN_BUF_LEN] = '\t';
            file_buf[MAIN_BUF_LEN + 1] = '\n';
            var bytes_to_consume = try file.read(file_buf_main);
            try readHelper1(&file, &file_buf, file_buf[bytes_to_consume..], &file_buf, chars, nodes, scores, @intFromPtr(chars.ptr), '\t');
        }

        const ALLOW_ABSOLUTE_ORDER = false;
        var are_scores_in_absolute_order: if (ALLOW_ABSOLUTE_ORDER) bool else void = if (ALLOW_ABSOLUTE_ORDER) true;
        var are_scores_in_relative_order = true;
        var starting_char_mask: u256 = 0;
        var previous_score: score_int = std.math.maxInt(score_int);
        var previous_relative_score: score_int = std.math.maxInt(score_int);
        var prev_first_char: u8 = 0;

        if (USE_SIMD_FOR_INIT) {
            var file_buf_main_masks: [MAIN_BUF_LEN / VEC_SIZE]uint = undefined;
            var chars_i: str_buf_int = 0;
            var state: MatchingState = .str;
            var int_start: isize = 0;
            const MEMCPY_AS_WE_GO = true;

            // maxInt -> matching strings, 0 -> matching numbers
            var mask_state = if (!MEMCPY_AS_WE_GO) @as(uint, std.math.maxInt(uint));

            while (true) {
                var consumable_characters = try file.read(file_buf_main);
                const is_last_iteration = consumable_characters < MAIN_BUF_LEN;

                if (is_last_iteration) {
                    if (consumable_characters == 0) break;
                    const consumable_characters_aligned = std.mem.alignForward(@TypeOf(consumable_characters), consumable_characters, VEC_SIZE);
                    @memset(file_buf_main[consumable_characters..][0..VEC_SIZE], '\x00');
                    consumable_characters = consumable_characters_aligned;
                }

                const chunks = consumable_characters / VEC_SIZE;
                {
                    var buf = file_buf_main;

                    for (file_buf_main_masks[0..chunks]) |*p| {
                        const vec: @Vector(VEC_SIZE, u8) = buf[0..VEC_SIZE].*;
                        const tab_mask = @as(uint, @bitCast(vec == @splat(VEC_SIZE, @as(u8, '\t'))));
                        const newline_mask = @as(uint, @bitCast(vec == @splat(VEC_SIZE, @as(u8, '\n'))));
                        const newline_tab_mask = tab_mask | newline_mask;
                        p.* = newline_tab_mask;

                        if (!MEMCPY_AS_WE_GO) { // This code does NOT work. Needs reworking.
                            // a mask where all the term characters and newlines are set to 1
                            const term_newline_mask: uint = prefix_xor(newline_tab_mask) ^ mask_state;

                            // (',' is our stand-in for \n, ' ' is our stand-in for \t)
                            //                    LSB<-------------------------------------------------------->MSB
                            // vec:               wikipedia 1220297,world 30978,women 28285,william 27706,west 178
                            // tab_mask:          0000000001000000000000010000000000010000000000000100000000001000 (5)
                            // newline_mask:      0000000000000000010000000000010000000000010000000000000100000000 (4)
                            // term_newline_mask: 1111111110000000011111100000011111100000011111111000000111110000
                            // term_mask:         1111111110000000001111100000001111100000001111111000000011110000
                            //                    LSB<-------------------------------------------------------->MSB

                            const term_mask = term_newline_mask ^ newline_mask;
                            // Tell LLVM we are dealing with a strict subset.
                            std.debug.assert(term_mask == (term_newline_mask & ~newline_mask));

                            // TODO: Using VPCOMPRESSB, we could copy all strings directly into chars without needing
                            const packed_vector = @select(u8, @as(@Vector(VEC_SIZE, bool), @bitCast(term_mask)), vec, vec);
                            chars[chars_i..][0..VEC_SIZE].* = packed_vector;
                            chars_i += @popCount(term_mask);
                            // _mm512_mask_compress_epi8(vec, term_mask, chars.ptr + chars_i);
                            mask_state = signExtend(term_newline_mask);
                        }
                        // if the last character in the chunk was a newline or term character, we are matching that in the next iteration
                        buf = buf[VEC_SIZE..];
                    }
                }

                for (file_buf_main_masks[0..chunks], 0..) |b, k| {
                    var bitmask = b;
                    while (bitmask != 0) : ({
                        bitmask &= bitmask - 1;
                        state.flip();
                    }) {
                        const int_end = @as(isize, @intCast(k * VEC_SIZE | @ctz(bitmask)));
                        const prev_int_start = int_start;
                        int_start = int_end + 1;
                        var sliced: []u8 = undefined;

                        sliced.ptr = if (prev_int_start < 0)
                            file_buf_main.ptr - @as(usize, @intCast(-prev_int_start))
                        else
                            file_buf_main.ptr + @as(usize, @intCast(prev_int_start));

                        sliced.len = @as(usize, @intCast(int_end - prev_int_start));

                        switch (state) {
                            .str => {
                                const slice_len = std.math.cast(term_len_int, sliced.len) orelse
                                    return error.@"String length could not fit in term_len_int";

                                nodes.ptr -= 1;
                                nodes[0] = Node.init(chars_i, slice_len);
                                nodes.len -= 1;

                                var old_chars_i = chars_i;
                                memcpy_chunk(chars, sliced, &chars_i);
                                const first_char = chars[old_chars_i];

                                if (first_char != prev_first_char) {
                                    previous_relative_score = std.math.maxInt(score_int);
                                    are_scores_in_relative_order = are_scores_in_relative_order and ((starting_char_mask >> first_char) & 1) == 0;
                                    starting_char_mask |= (@as(u256, 1) << first_char);
                                    prev_first_char = first_char;
                                }

                                if (USE_NULL_TERMINATED_STRINGS) {
                                    chars[chars_i] = 0;
                                    chars_i += 1;
                                }
                            },

                            .int => {
                                sliced.len -= @intFromBool(sliced[sliced.len - 1] == '\r');
                                if (sliced.len == 0 or sliced.len > SCORE_LEN) return error.@"Number too long in file.";

                                var score: std.meta.Int(.unsigned, @typeInfo(score_int).Int.bits * 2) = 0;
                                // Prove at compile-time it is impossible to overflow
                                comptime std.debug.assert(PRE_BUF_LEN > SCORE_LEN + SCORE_VEC_SIZE);
                                @memset((sliced.ptr - SCORE_VEC_SIZE)[0..SCORE_VEC_SIZE], '0');

                                comptime var deviation = 0;
                                comptime var acc = 1;
                                comptime var upper_bound = 0;

                                inline for (1..SCORE_LEN + 1) |i| {
                                    score += ((sliced.ptr + sliced.len - i)[0]) * @as(@TypeOf(score), acc);
                                    upper_bound += std.math.maxInt(u8) * acc;
                                    deviation += '0' * acc;
                                    acc = acc * 10;
                                }

                                // Prove at compile-time that it is impossible to overflow out of `score`
                                comptime std.debug.assert(upper_bound <= std.math.maxInt(@TypeOf(score)));
                                const new_score = std.math.cast(score_int, score - deviation) orelse {
                                    std.debug.print("{}\n", .{score - deviation});
                                    return error.@"Number too long in file.";
                                };

                                if (ALLOW_ABSOLUTE_ORDER)
                                    are_scores_in_absolute_order = are_scores_in_absolute_order and previous_score >= new_score;
                                are_scores_in_relative_order = are_scores_in_relative_order and previous_relative_score >= new_score;
                                previous_score = new_score;
                                previous_relative_score = new_score;
                                scores.ptr -= 1;
                                scores[0] = new_score;
                                scores.len -= 1;
                            },
                        }
                    }
                }

                if (is_last_iteration) break;

                // If there is spare data, copy it to the front.
                // This is kinda a compromise that works fine for both the scores and nodes.
                // (Scores technically only need to copy a 16 byte chunk, and nodes could technically copy directly into chars)
                // However, this strategy makes the hot loops simpler and as a consequence a lil' faster too.
                var int_leftovers = file_buf_main[@as(usize, @intCast(int_start))..];
                if (int_leftovers.len > PRE_BUF_LEN) return error.@"The number of overflow characters could not fit in term_len_int";
                int_start = -@as(isize, @intCast(int_leftovers.len));

                // Should be rare to copy more than MEMCPY_STEP over.
                // This requires us to have `std.math.maxInt(term_len_int)` padding at the front of our buffer
                while (true) {
                    comptime std.debug.assert(POST_BUF_LEN >= MEMCPY_STEP - 1);
                    @memcpy((file_buf_main.ptr - int_leftovers.len)[0..MEMCPY_STEP], int_leftovers.ptr);
                    int_leftovers.len = std.math.sub(usize, int_leftovers.len, MEMCPY_STEP) catch break;
                    int_leftovers.ptr += MEMCPY_STEP;
                }
            }
        }

        // The sentinels point to this byte, and this guarantees that they will be at the very front of the `nodes` array
        // after we do a multilist sort. Note that this is guaranteed not to overwrite any real data because we overallocated
        chars[chars.len - 1] = 0;

        for (score_list[2..], 0..) |*score, i|
            score.* = @as(score_int, @intCast(i));

        std.debug.print("        Read terms in {} ms. (", .{std.time.milliTimestamp() - start_time});
        printCommifiedNumber(@as(usize, buffer_requirements.num_term_pairs) - NUM_SENTINELS); // don't count sentinels
        std.debug.print(" terms)\n", .{});

        if (!are_scores_in_relative_order and !(ALLOW_ABSOLUTE_ORDER and are_scores_in_absolute_order))
            sortNodes(chars, node_list, score_list, multilist, NUM_SENTINELS);

        const linked_time = std.time.milliTimestamp();

        var roots = DynSDT.initWithNodes(node_list, chars);
        const finish_time = std.time.milliTimestamp();
        const elapsed = finish_time - linked_time;
        // const bytes_used: usize = buffer_requirements.strings_length +
        //     @intCast(usize, buffer_requirements.multilist_size) * @sizeOf(Node) +
        //     @sizeOf(node_index_int) * 256 +
        //     @sizeOf(DynSDT) +
        //     @intCast(usize, buffer_requirements.multilist_size) * @sizeOf(score_int);
        const MB_used = new_bytes.len / 1000000;
        std.debug.print("        Linked structure in {} ms. ({}.{:0>2} MB)\n        The total time was {} ms.\n", .{
            elapsed,
            MB_used,
            new_bytes.len / 100000 - MB_used * 10 + @intFromBool(new_bytes.len % 100000 >= 50000),
            finish_time - start_time,
        });

        return DynSDT{
            .roots = roots,
            .data = Buffer{
                .multilist = multilist,
                .byte_buffer_len = new_bytes.len,
                .characters = .{
                    .len = buffer_requirements.strings_length,
                    .capacity = buffer_requirements.strings_length,
                },
            },
        };
    }

    fn sortNodes(chars: []u8, node_list: []Node, score_list: []score_int, multilist: MultiArrayList(ScoredNode), comptime NUM_SENTINELS: comptime_int) void {
        _ = NUM_SENTINELS;
        @setCold(true);
        const sort_start_time = std.time.milliTimestamp();

        // Sort by first character
        var char_counts = std.mem.zeroes([256]node_index_int);
        for (node_list) |node| char_counts[chars[node.term_start]] += 1;

        // Get prefix sums
        var prefix_sums: [256]node_index_int = undefined;
        var accumulator: node_index_int = 0;
        for (&prefix_sums, char_counts) |*p, char_count| {
            accumulator += char_count;
            p.* = accumulator;
        }

        const prefix_sums_saved = prefix_sums;

        for (&prefix_sums, &char_counts) |*prefix_sum, *char_count| {
            while (char_count.* > 0) {
                var i = prefix_sum.* - 1;

                var node = node_list[i];
                var score = score_list[i];

                while (true) {
                    const char = chars[node.term_start];
                    const slot = prefix_sums[char] - 1;
                    prefix_sums[char] = slot;
                    char_counts[char] -= 1;

                    var next_node = node_list[slot];
                    var next_score = score_list[slot];

                    node_list[slot] = node;
                    score_list[slot] = score;

                    if (i == slot) break;

                    node = next_node;
                    score = next_score;
                }
            }
        }

        var previous_upper: node_index_int = 0;
        for (prefix_sums_saved, 0..) |prefix_sum, c| {
            _ = c;
            if (previous_upper != prefix_sum) {
                // if (c == 'd') std.debug.print("Unsorted:\n", .{});
                var char = chars[node_list[previous_upper].term_start];
                for (node_list[previous_upper..prefix_sum], previous_upper..) |node, i| {
                    _ = i;
                    // if (c == 'd') std.debug.print("\t{s}: {}\n", .{ node.term(chars), score_list[i] });
                    const char2 = chars[node.term_start];
                    if (char != char2) {
                        @panic("We got a big problem!");
                    }
                }
                multilist.sortUnstableBounded(previous_upper, prefix_sum, struct {
                    score_list: []const score_int,
                    pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
                        return ctx.score_list[a_index] < ctx.score_list[b_index];
                    }
                }{ .score_list = score_list });

                // if (c == 'd') std.debug.print("Sorted:\n", .{});
                var previous_score: score_int = 0;
                for (node_list[previous_upper..prefix_sum], score_list[previous_upper..prefix_sum], 0..) |node, score, i| {
                    _ = i;
                    _ = node;
                    if (score < previous_score)
                        @panic("We has a big problem houstin!");
                    previous_score = score;
                    // if (c == 'd' and score < 3) std.debug.print("\ti: {}, {s}: {}\n", .{ i, node.term(chars), score });
                    //     const char2 = chars[node.term_start];
                    //     if (char != char2) {
                    //         @panic("We got a big problem!");
                    //     }
                }
                previous_upper = prefix_sum;
            }
        }

        const sort_end_time = std.time.milliTimestamp();
        std.debug.print("        Sorted nodes in {} ms.\n", .{sort_end_time - sort_start_time});
    }

    pub fn makeIndexOverQueries(self: *DynSDT, allocator: Allocator, queries: [][:0]const u8) !void {
        var map: std.StringHashMapUnmanaged(node_index_int) = .{};
        errdefer map.deinit(allocator);

        var count: usize = 0;
        for (queries) |query| count += @intFromBool(query.len <= PREFIX_SAVE);

        try map.ensureTotalCapacity(allocator, std.math.cast(u32, count *| 16) orelse return error.TooManyQueries);
        std.debug.print("count: {}\n", .{count});
        const slices = self.data.multilist.slice();
        const nodes: []const Node = slices.items(.node);
        const scores: []const score_int = slices.items(.score);
        _ = scores;
        const str_buffer: []const u8 = self.data.str_buffer_slice();

        for (queries) |query| {
            if (query.len <= PREFIX_SAVE) {
                const result = self.getLocusIndexForPrefix(self.roots[query[0]], if (BITWISE) 8 else 1, query, nodes, str_buffer);
                map.putAssumeCapacityNoClobber(query, result);
            }
        }
        self.map = map;
    }

    pub fn makeIndexOverQueries2(self: *DynSDT, allocator: Allocator, queries: [][:0]const u8) !void {
        _ = allocator;
        var roots2: struct {
            bitmap: u256 = 0,
            arr: ?[*]struct {
                bitmap: u256 = 0,
                arr: ?[*]struct {
                    bitmap: u256 = 0,
                    arr: ?[*]node_index_int = null,
                } = null,
            } = null,
        } = undefined;
        _ = roots2;

        //

        var count: usize = 0;
        for (queries) |query| count += @intFromBool(query.len <= PREFIX_SAVE);

        const slices = self.data.multilist.slice();
        const nodes: []const Node = slices.items(.node);
        const scores: []const score_int = slices.items(.score);
        _ = scores;
        const str_buffer: []const u8 = self.data.str_buffer_slice();

        for (self.roots) |cur_i_| {
            if (cur_i_ == NULL) continue;
            std.debug.print("{s}\n", .{nodes[cur_i_].term(str_buffer)});

            // cur_i.getNext();

            // while (nodes[cur_i].getLCP() != LCP) : (cur_i = nodes[cur_i].getDown()) {
            //     if (nodes[cur_i].getDown() == NULL) {
            //         node.LCP = LCP;
            //         if (STORE_4_TERM_BYTES_IN_NODE) node.update_next4chars(chars);
            //         nodes[cur_i].down = i;
            //         continue :NEXT_NODE;
            //     }
            // }

            // for (queries) |query| {
            //     if (query.len <= PREFIX_SAVE) {
            //         const result = self.getLocusIndexForPrefix(self.roots[query[0]], if (BITWISE) 8 else 1, query, nodes, str_buffer);
            //         map.putAssumeCapacityNoClobber(query, result);
            //     }
            // }
        }
    }

    pub fn binarySearchFirst(
        comptime T: type,
        items: []const T,
        context: anytype,
        comptime compareFn: fn (context: @TypeOf(context), mid_item: T) bool,
    ) ?usize {
        return if (items.len == 0 or compareFn(context, items[0]))
            null
        else
            binarySearchFirst(T, items, context, compareFn, @as(usize, 0), items.len - 1);
    }

    /// Finds the first value in a slice that matches a particular condition.
    /// Caller guarantees that if the answer runs off the bounds of the array, the bounds will not under/overflow.
    /// In other words, one of the following conditions must be true:
    ///   1. left-1 must not underflow AND right+1 must not overflow
    ///   2.
    pub fn binarySearchFirstBounded(
        comptime T: type,
        items: []const T,
        context: anytype,
        comptime compareFn: fn (context: @TypeOf(context), mid_item: T) bool,
        left: anytype,
        right: @TypeOf(left),
    ) @TypeOf(left) {
        while (left <= right) {
            // Avoid overflowing in the midpoint calculation
            const mid = left + (right - left) / 2;

            // Compare the key with the midpoint element
            if (compareFn(context, items[mid])) {
                right = mid - 1; // this can underflow if all elements return true
            } else {
                left = mid + 1; // this can overflow if all elements return false
            }
        }

        return left;
    }

    fn getNodeIndexForTerm(self: *const DynSDT, term: string) node_index_int {
        const nodes: []Node = self.nodes.items;
        const str_buffer = self.string_buffer.items;
        std.debug.assert(term.len > 0);
        var cur_i: node_index_int = self.roots[term[0]];
        if (cur_i == NULL) return NULL;
        var LCP: term_len_int = 1;
        while (true) {
            LCP = longestCommonPrefix(LCP, term, nodes[cur_i].term(str_buffer));
            if (LCP == term.len and LCP == nodes[cur_i].getTermLen()) return cur_i;
            cur_i = nodes[cur_i].getNext();

            while (true) : (cur_i = nodes[cur_i].getDown()) {
                if (cur_i == NULL) return NULL;
                if (nodes[cur_i].getLCP() == LCP) break;
            }
        }
    }

    pub fn getScore(self: *const DynSDT, term: string) !score_int {
        return switch (self.getNodeIndexForTerm(term)) {
            NULL => error.NodeNotFound,
            else => |i| self.scores.items[i],
        };
    }

    // Whether to decrement k or increment it
    const K_DEC = false;

    const ArrayDynSDT = struct {
        pub const BranchPointPtr = struct {
            ptr: node_index_int = 0,
            end_ptr: node_index_int = 0,

            pub fn slice(self: BranchPointPtr, array_nodes: []ArrayNode) []ArrayNode {
                return array_nodes[self.ptr..self.end_ptr];
            }
        };

        pub const DEPQBranchPointPtr = struct {
            bp: BranchPointPtr,
            score: score_int = 0,

            pub fn slice(self: BranchPointPtr, array_nodes: []ArrayNode) []ArrayNode {
                return array_nodes[self.ptr..self.end_ptr];
            }
        };

        const ArrayNode = struct { // 16 bytes
            score: score_int = 0,
            branch_points: BranchPointPtr = .{},
            LCP: term_len_int = 0,
            term_start: str_buf_int = 0,

            pub fn branch_points_slice(self: ArrayNode, array_nodes: []ArrayNode) []ArrayNode {
                return array_nodes[self.branch_points.ptr..][0..self.branch_points.len];
            }

            pub fn term(self: ArrayNode, buffer: string) [*:0]const u8 {
                return @as([*:0]const u8, @ptrCast(buffer[self.term_start..].ptr));
            }

            pub fn is_empty(self: *const ArrayNode) bool {
                return self.LCP == 0; // LCP has a minimum of 1, so 0 is non-sense
            }
        };

        str_buffer: []u8,
        roots: [256]ArrayNode,
        array_nodes: []ArrayNode,

        pub fn deinit(self: *ArrayDynSDT, allocator: Allocator) void {
            allocator.free(self.array_nodes);
            self.* = undefined;
        }

        pub fn getLocusNodeForPrefix(self: *const ArrayDynSDT, noalias prefix: string_t) if (BITWISE) struct { *const ArrayNode, term_len_int } else *const ArrayNode {
            var cur_node = &self.roots[prefix[0]];
            if (cur_node.is_empty()) return cur_node;
            var LCP: term_len_int = 1;
            var term1 = prefix[1..];
            if (0 == if (USE_NULL_TERMINATED_STRINGS) term1[0] else term1.len) return if (BITWISE) .{ cur_node, LCP } else cur_node;

            outer: while (true) {
                var term2 = cur_node.term(self.str_buffer) + LCP;

                while (true) {
                    if (0 == if (USE_NULL_TERMINATED_STRINGS) term2[0] else term2.len) break;
                    if (BITWISE) {
                        const bit_chunk_size = 64;
                        const a = std.mem.readIntLittle(std.meta.Int(.unsigned, bit_chunk_size), term1.ptr[0..8]);
                        const b = std.mem.readIntLittle(std.meta.Int(.unsigned, bit_chunk_size), term2[0..8]);
                        const lcp = bits_in_common2(a, b);
                        LCP += @as(u16, @intCast(lcp));
                        term1 = term1[lcp / 8 ..];
                        if (0 == if (USE_NULL_TERMINATED_STRINGS) term1[0] else term1.len) return if (BITWISE) .{ cur_node, LCP } else cur_node;
                        if (bit_chunk_size != lcp) break;
                        term2 += lcp / 8;
                    } else {
                        if (term1[0] != term2[0]) break;
                        LCP += 1;
                        term1 = term1[1..];
                        if (0 == if (USE_NULL_TERMINATED_STRINGS) term1[0] else term1.len) return if (BITWISE) .{ cur_node, LCP } else cur_node;
                        term2 += 1;
                    }
                }

                for (cur_node.branch_points.slice(self.array_nodes)) |*node| {
                    if (node.LCP == LCP) {
                        cur_node = node;
                        continue :outer;
                    }
                } else return if (BITWISE) .{ cur_node, 0 } else cur_node;
            }
        }

        pub fn topKCompletionsToPrefix(self: *const ArrayDynSDT, noalias prefix: string_t, noalias results: *[10][*:0]const u8) u8 {
            const locus_and_LCP = @call(.always_inline, getLocusNodeForPrefix, .{ self, prefix });
            const locus = if (BITWISE) locus_and_LCP[0] else locus_and_LCP;
            const LCP = if (BITWISE) locus_and_LCP[1] else @as(term_len_int, @intCast(prefix.len));
            return @call(.always_inline, topKCompletionsToLocus, .{ self, locus, LCP, results });
        }

        fn firstVerticalSuccessor(nodes: []const ArrayNode, LCP: term_len_int, _cur_i: node_index_int) node_index_int {
            var cur_i = nodes[_cur_i].getNext();
            while (true) : (cur_i = nodes[cur_i].getDown()) { // finds vertical successor
                // Having a separate check here allows the optimizer to extend the jump when we check cur_i == null after running this function
                if (cur_i == NULL) break;
                if (nodes[cur_i].getLCP() >= LCP) break; // might skip nodes when directly under the locus
            }
            return cur_i;
        }

        fn verticalSuccessor(nodes: []const Node, LCP: term_len_int, _cur_i: node_index_int) node_index_int {
            var cur_i = _cur_i;
            while (true) { // finds vertical successor
                cur_i = nodes[cur_i].getDown();
                // Having a separate check here allows the optimizer to extend the jump when we check cur_i == null after running this function
                if (cur_i == NULL) break;
                if (nodes[cur_i].getLCP() >= LCP) break; // might skip nodes when directly under the locus
            }
            return cur_i;
        }

        inline fn horizontalSuccessor(nodes: []const Node, cur_i: node_index_int) node_index_int {
            return nodes[cur_i].getNext();
        }

        /// Fills up a given array of strings with completions to a given prefix string, if present in the structure,
        /// and returns the number of completions that were written.
        /// The completions will be in descending sorted order by score, so the "most relevant" completions will
        /// come first. The algorithm is explained here: https://validark.github.io/DynSDT/#top-k_enumeration
        /// The data structure owns the memory within the individual strings.
        pub fn topKCompletionsToLocus(self: *const ArrayDynSDT, locus: *const ArrayNode, LCP: term_len_int, noalias results: *[10][*:0]const u8) u8 {
            const str_buffer: []const u8 = self.str_buffer;
            const nodes: []const ArrayNode = self.array_nodes;

            // Push locus node to the results!
            results[0] = locus.term(str_buffer);

            var cur = locus.branch_points;
            while (cur.ptr < cur.end_ptr) : (cur.ptr += 1) {
                // Find vertical successor, skipping over nodes as necessary with insufficient LCP's
                if (nodes[cur.ptr].LCP >= LCP) break;
            } else return 1;

            results[1] = nodes[cur.ptr].term(str_buffer);

            var k: u8 = if (K_DEC) 10 - 2 else 2;
            const half_topK = 4;
            // const half_topK_bitmap_int = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = half_topK } });
            var depq_1_indexed: [half_topK + 1 + 1]ArrayDynSDT.DEPQBranchPointPtr = undefined;
            depq_1_indexed[0] = .{ .bp = .{ .ptr = 0, .end_ptr = 0 }, .score = 0 };
            var depq: *[half_topK + 1]ArrayDynSDT.DEPQBranchPointPtr = depq_1_indexed[1..];
            inline for (depq) |*p| p.* = .{ .bp = .{ .ptr = 0, .end_ptr = 0 }, .score = std.math.maxInt(score_int) };
            var depq_len: u8 = 0;

            // if (MOVE_FIRST_ITERATION_OF_TOPK_QUERY_OUT_OF_LOOP) {
            //     var next_i: node_index_int = horizontalSuccessor(nodes, cur_i);
            //     var old_i = verticalSuccessor(nodes, LCP, cur_i);
            //     cur_i = get_winner_i(old_i, next_i, scores);
            //     if (cur_i == NULL) return 2;
            //     results[2] = nodes[cur_i].term(str_buffer);
            //     k = if (K_DEC) 10 - 3 else 3;
            //     const loser_i = get_loser_i(next_i, old_i, cur_i);
            //     if (loser_i != NULL) depq[0] = loser_i;
            //     depq_len += @boolToInt(loser_i != NULL);
            // }

            while (true) { // TODO: Maybe try inserting unconditionally? Insert both simultaneously?
                const next = nodes[cur.ptr].branch_points;

                if (next.ptr < next.end_ptr) {
                    var i: u8 = depq_len;
                    const next_score = nodes[next.ptr].score;
                    while (true) {
                        if (next_score >= depq_1_indexed[i].score) break;
                        depq_1_indexed[i + 1] = depq_1_indexed[i];
                        std.debug.assert(i != 0);
                        i -= 1;
                    }
                    depq_1_indexed[i + 1] = ArrayDynSDT.DEPQBranchPointPtr{ .bp = next, .score = next_score };
                    depq_len += 1;
                    // printDEPQ(nodes, scores, depq, depq_len + 1, str_buffer, results, k, "main2");
                    // std.debug.print("depq_len: {}, k: {}, i: {}\n", .{ depq_len, k, i });
                    if (depq_len == (if (K_DEC) k else 10 - k))
                        return insert_cur_i(nodes, depq_len, str_buffer, cur, results, LCP, depq, &depq_1_indexed, k);
                }

                while (true) { // finds vertical successor
                    cur.ptr += 1;
                    // Having a separate check here allows the optimizer to extend the jump when we check cur_i == null after running this function
                    if (cur.ptr >= cur.end_ptr) {
                        depq_len = std.math.sub(@TypeOf(depq_len), depq_len, 1) catch return if (K_DEC) 10 - k else k;
                        break;
                    } else if (nodes[cur.ptr].LCP >= LCP) { // might skip nodes when directly under the locus
                        var i: u8 = depq_len;
                        const cur_score = nodes[cur.ptr].score;

                        while (true) {
                            if (cur_score >= depq_1_indexed[i].score) break;
                            depq_1_indexed[i + 1] = depq_1_indexed[i];
                            std.debug.assert(i != 0);
                            i -= 1;
                        }

                        depq_1_indexed[i + 1] = ArrayDynSDT.DEPQBranchPointPtr{ .bp = cur, .score = cur_score };

                        // When the DEPQ is full and we need to insert next_i, jump to the second while loop
                        // std.debug.assert(depq_len <= 10 - k);
                        // printDEPQ(nodes, scores, depq, depq_len, str_buffer, results, k, "main1");
                        if (depq_len + 1 == (if (K_DEC) k else 10 - k))
                            return insert_next_i(nodes, depq_len, str_buffer, results, LCP, depq, &depq_1_indexed, k);

                        break;
                    }
                }

                cur = depq[depq_len].bp;

                // If the DEPQ is full but only because we already have so many completions. E.g. if we found
                // 8 completions already then we only need 2 more if topK=10. Because k has not been incremented
                // yet, when k=7, we would consider depq_len=2 to be full.
                // e.g. { 45, _ } -> 48, 49
                // std.debug.assert(depq_len <= 9 - k);
                results[if (K_DEC) 10 - k else k] = nodes[cur.ptr].term(str_buffer);
                k = if (K_DEC) k - 1 else k + 1;
                // printDEPQ(nodes, scores, depq, depq_len, str_buffer, results, k, "main3");
            }
        }

        fn insert_cur_i(nodes: []const ArrayNode, depq_len_: u8, str_buffer: string, parent: BranchPointPtr, results: *[10][*:0]const u8, LCP: term_len_int, depq: *[4 + 1]DEPQBranchPointPtr, depq_1_indexed: *[5 + 1]DEPQBranchPointPtr, k: u8) u8 {
            outer: {
                var cur = parent;
                while (true) {
                    cur.ptr += 1;
                    if (cur.ptr >= cur.end_ptr) break :outer;
                    if (nodes[cur.ptr].LCP >= LCP) break;
                }

                var i: u8 = 0;
                const cur_score = nodes[cur.ptr].score;
                while (true) {
                    // { 3, 5, 6, 7, 9 } insert 6
                    var j = i + 1;
                    if (cur_score <= depq_1_indexed[j].score) break;
                    depq_1_indexed[i] = depq_1_indexed[j];
                    i = j;
                }
                depq_1_indexed[i] = ArrayDynSDT.DEPQBranchPointPtr{ .bp = cur, .score = cur_score };
            }

            return insert_next_i(nodes, depq_len_ - 1, str_buffer, results, LCP, depq, depq_1_indexed, k);
        }

        fn insert_next_i(nodes: []const ArrayNode, depq_len: u8, str_buffer: string, results: *[10][*:0]const u8, LCP: term_len_int, depq: *[4 + 1]DEPQBranchPointPtr, depq_1_indexed: *[5 + 1]DEPQBranchPointPtr, k: u8) u8 {
            var cur = depq[depq_len].bp;

            // If the DEPQ is full but only because we already have so many completions. E.g. if we found
            // 8 completions already then we only need 2 more if topK=10. Because k has not been incremented
            // yet, when k=7, we would consider depq_len=2 to be full.
            // e.g. { 45, _ } -> 48, 49
            // std.debug.assert(depq_len <= 9 - k);
            results[if (K_DEC) 10 - k else k] = nodes[cur.ptr].term(str_buffer);
            var l = if (K_DEC) k - 1 else k + 1;
            if (l == if (K_DEC) 0 else 10) return 10;

            const next = nodes[cur.ptr].branch_points;
            if (next.ptr < next.end_ptr) {
                var i: u8 = 0;
                const next_score = nodes[next.ptr].score;
                while (true) {
                    // { 5, 6, 7, 8, 9 } insert 8
                    var j = i + 1; // 2
                    if (next_score <= depq_1_indexed[j].score) break;
                    depq_1_indexed[i] = depq_1_indexed[j];
                    i = j; // 1
                }
                depq_1_indexed[i] = ArrayDynSDT.DEPQBranchPointPtr{ .bp = next, .score = next_score };
            }

            return insert_cur_i(nodes, depq_len, str_buffer, cur, results, LCP, depq, depq_1_indexed, l);
        }
    };

    // pub fn increaseScore(term: string, n: score_int) void {
    //     const nodes: []Node = self.nodes.items;
    //     const scores: []Node = self.scores.items;
    //     const str_buffer = self.string_buffer.items;
    //     std.debug.assert(term.len > 0);
    //     var cur_i: node_index_int = self.roots[term[0]];
    //     if (cur_i == NULL) {
    //         // just insert into the list
    //         // self.roots[term[0]] =
    //         // find place to allocate it
    //     }
    //     var LCP: term_len_int = 1;
    //     while (true) {
    //         LCP = longestCommonPrefix(LCP, term, nodes[cur_i].term(str_buffer));
    //         if ((LCP == term.len) and (LCP == nodes[cur_i].getTermLen())) {
    //             // SET-ExactMatchFound
    //         }

    //         if (score > scores[cur_i]) {
    //             // Set-ScoreLocationFound
    //         }

    //         cur_i = nodes[cur_i].getNext();

    //         while (true) : (cur_i = nodes[cur_i].getDown()) {
    //             if (cur_i == NULL) return NULL; // just insert into the list
    //             if (nodes[cur_i].getLCP() == LCP) break;
    //         }
    //     }
    // }
};

/// Reads the entire file at file_path into a string buffer, rounded up to `alignment`. Caller owns memory.
fn readFileIntoAlignedBuffer(allocator: Allocator, file_path: string, comptime over_alloc: u32, comptime alignment: u32) ![]u8 {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const bytes_to_allocate = try file.getEndPos();
    const overaligned_size = try std.math.add(u64, bytes_to_allocate, @as(u64, over_alloc) + (alignment - 1));
    const buffer = try allocator.alloc(u8, std.mem.alignBackward(u64, overaligned_size, alignment));

    var cur = buffer[0..bytes_to_allocate];
    while (true) {
        cur = cur[try file.read(cur)..];
        if (cur.len == 0) return buffer;
    }
}

/// Counts the number of times `char` appears in a `buffer` which has been rounded up to a given `alignment`.
fn countCharInAlignedBuffer(buffer: string, comptime char: u8, comptime alignment: u32) usize {
    std.debug.assert(std.mem.isValidAlign(alignment));
    var count: usize = 0;
    var i: usize = 0;

    if (alignment == 1) {
        while (i < buffer.len) : (i += 1) count += @intFromBool(buffer[i] == char);
    } else while (i < buffer.len) : (i += alignment)
        count += @popCount(@as(std.meta.Int(.unsigned, alignment), @bitCast(@as(@Vector(alignment, u8), buffer[i..][0..alignment].*) == @splat(alignment, char))));

    return count;
}

/// Takes a `buffer` which has been rounded up to a given `alignment` and splits it by `char`. Caller owns memory.
/// TODO: Maybe could be sped up via SIMD:
/// https://millcomputing.com/topic/how-would-one-efficiently-iterate-over-set-bits-on-the-mill/
fn splitAlignedBufferByChar(allocator: Allocator, buffer: []u8, comptime char: u8, comptime alignment: u32) ![][:0]const u8 {
    const VEC_SIZE = alignment;
    const newlines_count = countCharInAlignedBuffer(buffer, char, alignment);

    const query_strings = try allocator.alloc([:0]const u8, newlines_count);
    var queries_count: usize = 0;
    var i: usize = 0;
    var string_start: usize = 0;

    if (alignment == 1) {
        while (i < buffer.len) : (i += 1) {
            if (buffer[i] != char) continue;
            buffer[i] = 0;
            query_strings[queries_count] = buffer[string_start..i :0];
            queries_count += 1;
            string_start = i + 1;
        }
    } else while (i < buffer.len) : (i += VEC_SIZE) {
        const vec: @Vector(VEC_SIZE, u8) = buffer[i..][0..VEC_SIZE].*;
        var delimiters = @as(std.meta.Int(.unsigned, VEC_SIZE), @bitCast(vec == @splat(VEC_SIZE, char)));

        // this iterates through each `char` in the vector by unsetting the lowest set bit after each iteration
        while (delimiters != 0) : (delimiters &= delimiters - 1) { // translates to the `blsr` instruction on x86
            const string_end = i + @ctz(delimiters);
            buffer[string_end] = 0;
            query_strings[queries_count] = buffer[string_start..string_end :0];
            queries_count += 1;
            string_start = string_end + 1;
        }
    }

    return query_strings;
}

fn has_zero_byte(v: anytype) @TypeOf(v) {
    const num_bits = switch (@typeInfo(@TypeOf(v))) {
        .Int => |i| i.bits + @intFromBool(i.bits == 0),
        else => 1,
    };
    if (num_bits % 8 != 0) @compileError("has_zero_byte must be called with an integer argument with a number of bits divisible by 8");

    const one_in_each_byte = comptime blk: {
        var ones = 0;

        for (0..num_bits / 8) |_| {
            ones |= ones << 8;
            ones |= 1;
        }
        break :blk ones;
    };

    const high_bit_in_each_byte = comptime 0x80 * one_in_each_byte;
    return (v -% one_in_each_byte) & ~v & high_bit_in_each_byte;
}

fn non_zero_mask(v: anytype) @TypeOf(v) {
    return v & (has_zero_byte(v) -% 1);
}

fn max_common_bits(x: anytype, y: @TypeOf(x)) @TypeOf(x) {
    return @ctz(has_zero_byte(x) | has_zero_byte(y)) & ~@as(@TypeOf(x), 0b0111);
}

fn bits_in_common(x: anytype, y: @TypeOf(x)) @TypeOf(x) {
    return @min(max_common_bits(x, y), @ctz(x ^ y));
}

fn bits_in_common2(x: anytype, y: @TypeOf(x)) @TypeOf(x) {
    return @ctz((x ^ y) | ((has_zero_byte(x) | has_zero_byte(y)) >> 7));
}

fn printArr(arr: [8]u8) void {
    for (@as([8]u8, @bitCast(@byteSwap(@as(u64, @bitCast(arr))))), 0..) |c, i| {
        if (i != 0) std.debug.print("_", .{});
        std.debug.print("{b:0>8}", .{c});
    }
    std.debug.print("\n", .{});
}

fn printInt(arr: u64) void {
    printArr(@as([8]u8, @bitCast(arr)));
}

inline fn speedTest(allocator: Allocator, trie: anytype, queries: anytype, comptime precompute_locus: bool) !void {
    // precompute the locus nodes of all queries
    const loci = blk: {
        if (precompute_locus) {
            const locus_t1 = std.time.nanoTimestamp();
            const loci = try allocator.alloc(struct { switch (@TypeOf(trie)) {
                *const DynSDT.ArrayDynSDT, *DynSDT.ArrayDynSDT, DynSDT.ArrayDynSDT => *const DynSDT.ArrayDynSDT.ArrayNode,
                else => node_index_int,
            }, term_len_int }, queries.len);
            for (queries, loci) |query, *locus| {
                switch (@TypeOf(trie)) {
                    *const DynSDT.ArrayDynSDT, *DynSDT.ArrayDynSDT, DynSDT.ArrayDynSDT => {
                        const ret = trie.getLocusNodeForPrefix(query);
                        locus.* = .{ ret, @as(term_len_int, @intCast(query.len)) };
                    },
                    *const DynSDT.SlicedDynSDT.CompletionTrie, *DynSDT.SlicedDynSDT.CompletionTrie, DynSDT.SlicedDynSDT.CompletionTrie => {
                        const ret = trie.getLocusIndexForPrefix(query);
                        locus.* = .{ ret.index, ret.char_depth };
                    },
                    else => {
                        const ret = trie.getLocusIndexForPrefix(query);
                        locus.* = .{ ret, @as(term_len_int, @intCast(query.len)) };
                    },
                }
            }
            // DynSDT.SlicedDynSDT.CompletionTrie
            const locus_t2 = std.time.nanoTimestamp();
            std.debug.print("Found the locus node for all queries in {}\n", .{std.fmt.fmtDurationSigned(@as(i64, @intCast(locus_t2 - locus_t1)))});

            break :blk loci;
        }
    };
    defer if (precompute_locus) allocator.free(loci);

    var results: [10][*:0]const u8 = undefined;

    {
        var i: u32 = 0;
        // var num_queries: u32 = 1;
        var mask: u32 = 1;
        for (0..0) |_|
            mask |= mask << 1;
        while (i < 24) : (i += 1) {
            const end_time = std.time.nanoTimestamp() + 1000000000;
            var iterations: u32 = 0;
            var k: u32 = 0;
            // while (true) {
            while (true) {
                // const t1 = std.time.nanoTimestamp();
                if (precompute_locus) {
                    _ = trie.topKCompletionsToLocus(loci[k][0], loci[k][1], &results);
                } else {
                    _ = trie.topKCompletionsToPrefix(queries[k], &results);
                }
                // const t2 = std.time.nanoTimestamp();
                // std.debug.print("Got answer in {}ns: ", .{t2 - t1});

                // std.debug.print("try std.testing.expect({} == trie.topKCompletionsToPrefix(\"{s}\", &results));\nfor ([{}]string{{ ", .{ num_results, queries[iterations], num_results });
                iterations += 1;
                k += 1;
                k &= mask;

                // if (num_results > 0) {
                //     std.debug.print("\"{s}\"", .{results[0]});
                //     for (results[1..num_results]) |result| {
                //         std.debug.print(", \"{s}\"", .{result});
                //     }
                //     std.debug.print(" }}) |str, i| try std.testing.expectEqualStrings(str, results[i]);\n", .{});
                // }
                // if (iterations == 200) break;
                if (std.time.nanoTimestamp() > end_time) break;
            }
            std.debug.print("{}: ", .{mask + 1});
            printCommifiedNumber(iterations);
            std.debug.print(" iterations in one second!\n", .{});
            mask |= mask << 1;
            // num_queries *= 10;
        }
    }

    {
        var NUM_QUERIES: u64 = 100000;

        while (NUM_QUERIES <= 1000000) : (NUM_QUERIES += 100000) {
            const start_time = std.time.milliTimestamp();
            var i: u32 = 0;
            while (i < NUM_QUERIES) : (i += 1) {
                if (precompute_locus) {
                    _ = trie.topKCompletionsToLocus(loci[i][0], loci[i][1], &results);
                } else {
                    _ = trie.topKCompletionsToPrefix(queries[i], &results);
                }
            }
            const total_time = std.time.milliTimestamp() - start_time;
            std.debug.print("Performed {} queries in {}ms\n", .{ NUM_QUERIES, total_time });
        }
    }
}

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{ .safety = true, .never_unmap = true, .retain_metadata = true }) = .{};
    const allocator = general_purpose_allocator.allocator();

    var trie = try DynSDT.initFromFile(allocator, "./terms_sorted2.txt"); // 95.6 MB in 224ms, that's ~427MB/s
    defer trie.deinit(allocator);

    const dynSDT = trie.slice();

    const completion_trie: DynSDT.SlicedDynSDT.CompletionTrie = blk: {
        const time_1 = std.time.nanoTimestamp();
        const completion_trie = try dynSDT.makeCompletionTrie(allocator);
        const time_2 = std.time.nanoTimestamp();
        std.debug.print("Made Completion Trie in {}\n", .{std.fmt.fmtDurationSigned(@as(i64, @intCast(time_2 - time_1)))});
        if (SHOULD_PRINT) {
            var results: [10][*:0]const u8 = undefined;
            std.debug.print("{}\n", .{completion_trie.topKCompletionsToPrefix("int", &results)});
        }
        break :blk completion_trie;
    };

    const arr_trie: DynSDT.ArrayDynSDT = blk: {
        const time_1 = std.time.nanoTimestamp();
        const arr_trie = try dynSDT.makeArrayDynSDT(allocator);
        const time_2 = std.time.nanoTimestamp();
        std.debug.print("Made array structure in {}\n", .{std.fmt.fmtDurationSigned(@as(i64, @intCast(time_2 - time_1)))});
        break :blk arr_trie;
    };

    /////////////////////////////////////////////////////////////////////////////

    const t1 = std.time.milliTimestamp();
    const queries_buffer = try readFileIntoAlignedBuffer(allocator, "./queries.txt", 0, VEC_SIZE_FOR_POPCOUNT);
    defer allocator.free(queries_buffer);

    const queries = try splitAlignedBufferByChar(allocator, queries_buffer, '\n', VEC_SIZE_FOR_POPCOUNT);
    defer allocator.free(queries);

    std.debug.print("Read in ", .{});
    printCommifiedNumber(queries.len);
    std.debug.print(" query strings in {}ms.\n", .{std.time.milliTimestamp() - t1});

    std.debug.print("prefix_xor: {b:0>64}\n", .{prefix_xor(@as(u64, 0b0010100000010000100000000100010000001000000100000010000001000000))});

    if (PREFIX_SAVE > 0) try trie.makeIndexOverQueries(allocator, queries);
    // try trie.makeIndexOverQueries2(allocator, queries);

    {
        var results: [10][*:0]const u8 = undefined;
        try std.testing.expect(10 == dynSDT.topKCompletionsToPrefix("dag ", &results));
        for (
            [_]struct { query: string_t, ans: [10]string }{
                .{ .query = "w", .ans = [10]string{ "wikipedia", "world", "women", "william", "west", "w", "white", "washington", "war", "wisconsin" } },
                .{ .query = "s", .ans = [10]string{ "station", "school", "season", "song", "state", "south", "st", "series", "states", "summer" } },
                .{ .query = "a", .ans = [10]string{ "and", "album", "at", "at the", "american", "a", "al", "airport", "athletics", "association" } },
                .{ .query = "m", .ans = [10]string{ "men", "michael", "m", "museum", "music", "martin", "mary", "my", "mount", "mark" } },
                .{ .query = "c", .ans = [10]string{ "county", "c", "championships", "cup", "church", "championship", "college", "charles", "city", "council" } },
                .{ .query = "b", .ans = [10]string{ "basketball", "band", "born", "by", "battle", "b", "battle of", "british", "bridge", "baseball" } },
                .{ .query = "p", .ans = [10]string{ "park", "politician", "paul", "peter", "party", "pennsylvania", "people", "p", "public", "power" } },
                .{ .query = "t", .ans = [10]string{ "the", "team", "thomas", "township", "tv", "to", "tv series", "texas", "tour", "the united" } },
                .{ .query = "d", .ans = [10]string{ "disambiguation", "de", "district", "david", "division", "d", "doubles", "daniel", "day", "del" } },
                .{ .query = "r", .ans = [10]string{ "river", "railway", "railway station", "robert", "richard", "road", "route", "rugby", "r", "red" } },
                .{ .query = "h", .ans = [10]string{ "house", "high", "high school", "henry", "historic", "hill", "hall", "hockey", "h", "history" } },
                .{ .query = "l", .ans = [10]string{ "list", "list of", "league", "la", "lake", "love", "language", "l", "lee", "louis" } },
                .{ .query = "g", .ans = [10]string{ "george", "games", "group", "game", "general", "grand", "green", "g", "great", "georgia" } },
                .{ .query = "k", .ans = [10]string{ "king", "k", "kentucky", "kingdom", "kansas", "khan", "kevin", "kim", "karl", "kong" } },
                .{ .query = "e", .ans = [10]string{ "election", "e", "european", "edward", "east", "el", "electoral", "elections", "earl", "episodes" } },
                .{ .query = "f", .ans = [10]string{ "film", "football", "footballer", "for", "f", "football team", "f c", "footballer born", "frank", "fc" } },
                .{ .query = "j", .ans = [10]string{ "john", "james", "j", "joseph", "jean", "jose", "jack", "jr", "jones", "joe" } },
                .{ .query = "n", .ans = [10]string{ "national", "new", "north", "new york", "no", "novel", "new zealand", "n", "number", "northern" } },
                .{ .query = "ma", .ans = [10]string{ "martin", "mary", "mark", "maria", "man", "magazine", "marie", "maryland", "management", "massachusetts" } },
                .{ .query = "o", .ans = [10]string{ "of", "of the", "open", "olympics", "on", "ohio", "one", "old", "o", "on the" } },
                .{ .query = "i", .ans = [10]string{ "in", "in the", "i", "international", "island", "ii", "institute", "ice", "illinois", "indiana" } },
                .{ .query = "v", .ans = [10]string{ "virginia", "voivodeship", "v", "van", "valley", "video", "von", "video game", "victoria", "village" } },
                .{ .query = "appl", .ans = [10]string{ "apple", "applied", "application", "applications", "appleton", "applied sciences", "appleby", "apples", "appliance", "applegate" } },
                .{ .query = "s ", .ans = [10]string{ "s route", "s tv", "s c", "s k", "s a", "s national", "s s", "s d", "s virgin", "s open" } },
            },
        ) |s| {
            try std.testing.expect(10 == dynSDT.topKCompletionsToPrefix(s.query, &results));
            for (s.ans, 0..) |str, i| try std.testing.expectEqualStrings(str, results[i][0..str.len]);
            try std.testing.expect(10 == arr_trie.topKCompletionsToPrefix(s.query, &results));
            for (s.ans, 0..) |str, i| try std.testing.expectEqualStrings(str, results[i][0..str.len]);
            try std.testing.expect(10 == completion_trie.topKCompletionsToPrefix(s.query, &results));
            for (s.ans, 0..) |str, i| try std.testing.expectEqualStrings(str, results[i][0..str.len]);
        }
    }

    std.debug.print("Tests passed!\n", .{});

    // for (queries) |query| {
    //     var expected_results: [10][*:0]const u8 = undefined;
    //     const expected_amt = dynSDT.topKCompletionsToPrefix(query, &expected_results);

    //     var results: [10][*:0]const u8 = undefined;
    //     try std.testing.expect(expected_amt == arr_trie.topKCompletionsToPrefix(query, &results));
    //     for (expected_results[0..expected_amt], results[0..expected_amt]) |str1, str2| {
    //         const len = std.mem.len(str1);
    //         try std.testing.expectEqualStrings(str1[0..len :0], str2[0..len :0]);
    //     }

    //     try std.testing.expect(expected_amt == completion_trie.topKCompletionsToPrefix(query, &results));
    //     for (expected_results[0..expected_amt], results[0..expected_amt]) |str1, str2| {
    //         const len = std.mem.len(str1);
    //         try std.testing.expectEqualStrings(str1[0..len :0], str2[0..len :0]);
    //     }
    // }

    // std.debug.print("All queries returned the same results!!\n", .{});

    try speedTest(allocator, &dynSDT, queries, true);
    try speedTest(allocator, &completion_trie, queries, true);
    try speedTest(allocator, &arr_trie, queries, true);
    // for (results) |result| std.debug.print("{s}\n", .{result});

    // std.debug.print("{} {}\n", .{ trie.locus_finding_time, trie.topk_search_time });

    // std.debug.print("{}\n", .{try trie.getScore("wikipedia")});
}
