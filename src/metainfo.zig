const std = @import("std");
const zencode = @import("zencode");
const log = std.log.scoped(.metainfo);

const File = struct {
    path: []const u8,
    length: usize,
};

pub const MetaInfo = struct {
    name: []const u8,
    announce_urls: std.ArrayList([]const u8),
    info_hash: [20]u8,
    pieces: []const u8,
    piece_hashes: [][20]u8,
    piece_len: usize,
    total_len: usize,
    files: std.ArrayList(File),
    arena: std.heap.ArenaAllocator,

    const Self = @This();

    pub fn init(bencode: []const u8, allocator: std.mem.Allocator) !MetaInfo {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var ally = arena.allocator();
        errdefer arena.deinit();

        const tree = try zencode.parse(bencode, ally);
        defer tree.deinit();
        zencode.MapLookupError = error.InvalidBencode;

        var announce_urls = std.ArrayList([]const u8).init(ally);
        if (zencode.mapLookupOptional(tree.root.Map, "announce-list", .List)) |announce_list| {
            for (announce_list.items) |announce| {
                for (announce.List.items) |item| {
                    try announce_urls.append(item.String);
                }
            }
        } else {
            const announce = try zencode.mapLookup(tree.root.Map, "announce", .String);
            try announce_urls.append(announce);
        }

        const info = try zencode.mapLookup(tree.root.Map, "info", .Map);
        const name = try zencode.mapLookup(info, "name", .String);
        const pieces = try zencode.mapLookup(info, "pieces", .String);
        const piece_len: usize = @intCast(try zencode.mapLookup(info, "piece length", .Integer));

        var total_len: usize = 0;
        var files = std.ArrayList(File).init(ally);
        try files.append(.{ .path = name, .length = total_len }); // root folder

        if (zencode.mapLookupOptional(info, "files", .List)) |list| {
            for (list.items) |file| {
                const length: usize = @intCast(try zencode.mapLookup(file.Map, "length", .Integer));
                const path_list = try zencode.mapLookup(file.Map, "path", .List);
                for (path_list.items) |path| {
                    try files.append(.{ .path = path.String, .length = length });
                    total_len += length;
                }
            }
        } else {
            const length: usize = @intCast(try zencode.mapLookup(info, "length", .Integer));
            total_len += length;
        }

        const hash_len = 20;
        const num_hashes = pieces.len / hash_len;
        if (pieces.len % hash_len != 0) return error.InvalidHash;

        var piece_hashes = try ally.alloc([20]u8, num_hashes);
        for (0..num_hashes) |i| {
            const begin = i * hash_len;
            const end = (i + 1) * hash_len;
            std.mem.copy(u8, &piece_hashes[i], pieces[begin..end]);
        }

        var info_bencoded = std.ArrayList(u8).init(ally);
        defer info_bencoded.deinit();
        const value_info = zencode.Value{ .Map = info };
        try value_info.encode(info_bencoded.writer());
        var info_hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(info_bencoded.items, info_hash[0..], std.crypto.hash.Sha1.Options{});

        return MetaInfo{
            .name = name,
            .announce_urls = announce_urls,
            .info_hash = info_hash,
            .pieces = pieces,
            .piece_hashes = piece_hashes,
            .piece_len = piece_len,
            .total_len = total_len,
            .files = files,
            .arena = arena,
        };
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }
};

const testing = std.testing;

test "create metainfo" {
    const data = try std.fs.cwd().readFileAlloc(testing.allocator, "./assets/example.torrent", 100_000);
    defer testing.allocator.free(data);
    var info = try MetaInfo.init(data, testing.allocator);
    defer info.deinit();

    const hash_len = 20;
    const piece_len = info.pieces.len / hash_len;

    try testing.expectEqual(hash_len, info.info_hash.len);
    try testing.expectEqual(piece_len, info.piece_hashes.len);
    try testing.expectEqual(@as(usize, 262_144), info.piece_len);
    try testing.expectEqual(@as(usize, 50_000), info.pieces.len);
    try testing.expectEqual(@as(usize, 1), info.files.items.len);
    try testing.expectEqualStrings("debian-mac-12.1.0-amd64-netinst.iso", info.files.items[0].path);
    try testing.expectEqualStrings("http://bttracker.debian.org:6969/announce", info.announce_urls.items[0]);
}

test "create metainfo with multiple files" {
    var info = try MetaInfo.init("d8:announce14:http://foo.com4:infod12:piece lengthi20e6:pieces20:0123456789012345678904:name11:example.iso5:filesld6:lengthi40e4:pathl8:test.txteeeee", testing.allocator);
    defer info.deinit();

    try testing.expectEqual(@as(usize, 0), info.files.items[0].length); // root folder
    try testing.expectEqualStrings("example.iso", info.files.items[0].path);
    try testing.expectEqual(@as(usize, 40), info.files.items[1].length);
    try testing.expectEqualStrings("test.txt", info.files.items[1].path);
}
