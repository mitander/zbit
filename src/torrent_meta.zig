const std = @import("std");
const zencode = @import("zencode");

const File = struct {
    path: []const u8,
    length: i64,
};

pub const Hash = struct {
    info: [20]u8,
    pieces: [][20]u8,
};

pub const Info = struct {
    name: []const u8,
    pieces: []const u8,
    piece_len: i64,
    files: std.ArrayList(File),
};

pub const TorrentMeta = struct {
    announce: []const u8,
    hash: Hash,
    info: Info,

    const Self = @This();

    pub fn parse(data: []const u8, ally: std.mem.Allocator) !TorrentMeta {
        const v = try zencode.parse(data, ally);
        defer v.deinit();
        zencode.MapLookupError = error.InvalidBencode;

        var torrent: TorrentMeta = undefined;
        errdefer torrent.deinit(ally);

        const announce = try zencode.mapLookup(v.root.Map, "announce", .String);
        const info = try zencode.mapLookup(v.root.Map, "info", .Map);
        const name = try zencode.mapLookup(info, "name", .String);
        const pieces = try zencode.mapLookup(info, "pieces", .String);
        const piece_len = try zencode.mapLookup(info, "piece length", .Integer);

        var files = std.ArrayList(File).init(ally);
        if (zencode.mapLookupOptional(v.root.Map, "files", .List)) |list| {
            for (list) |file| {
                const length = try zencode.mapLookup(file.Map, "length", .Integer);
                const path = try zencode.mapLookup(file.Map, "path", .String);
                try torrent.info.files.append(.{ .path = path, .length = length });
            }
        } else {
            const len = try zencode.mapLookup(info, "length", .Integer);
            const path = try ally.dupe(u8, name);
            try files.append(.{ .path = path, .length = len });
        }

        return .{
            .announce = try ally.dupe(u8, announce),
            .hash = try hash(info, pieces, ally),
            .info = .{
                .name = try ally.dupe(u8, name),
                .pieces = try ally.dupe(u8, pieces),
                .piece_len = piece_len,
                .files = files,
            },
        };
    }

    pub fn deinit(self: Self, ally: std.mem.Allocator) void {
        ally.free(self.announce);
        ally.free(self.info.pieces);
        ally.free(self.info.name);
        ally.free(self.hash.pieces);
        for (self.info.files.items) |file| {
            ally.free(file.path);
        }
        self.info.files.deinit();
    }

    fn hash(info: std.StringArrayHashMapUnmanaged(zencode.Value), pieces: []const u8, ally: std.mem.Allocator) !Hash {
        const hash_len = 20;
        const num_hashes = pieces.len / hash_len;
        var piece_hashes = try ally.alloc([20]u8, num_hashes);
        if (pieces.len % hash_len != 0) {
            return error.InvalidHash;
        }

        for (0..num_hashes) |i| {
            const begin = i * hash_len;
            const end = (i + 1) * hash_len;
            std.mem.copy(u8, &piece_hashes[i], pieces[begin..end]);
        }

        var list = std.ArrayList(u8).init(ally);
        defer list.deinit();
        const value_info = zencode.Value{ .Map = info };
        try value_info.encode(list.writer());
        var info_hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(list.items, info_hash[0..], std.crypto.hash.Sha1.Options{});
        return Hash{ .info = info_hash, .pieces = piece_hashes };
    }
};

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

test "parse torrent file" {
    const data = try std.fs.cwd().readFileAlloc(testing.allocator, "./deps/zencode/assets/example.torrent", 100_000);
    defer std.testing.allocator.free(data);

    var torrent = try TorrentMeta.parse(data, testing.allocator);
    defer torrent.deinit(testing.allocator);
    const hash_len = 20;
    const piece_len = torrent.info.pieces.len / hash_len;

    try expectEqualStrings("http://bttracker.debian.org:6969/announce", torrent.announce);
    try expectEqual(hash_len, torrent.hash.info.len);
    try expectEqual(piece_len, torrent.hash.pieces.len);
    try expectEqual(@as(i64, 262_144), torrent.info.piece_len);
    try expectEqual(@as(usize, 50_000), torrent.info.pieces.len);
    try expectEqualStrings("debian-mac-12.1.0-amd64-netinst.iso", torrent.info.name);
    try expectEqual(@as(usize, 1), torrent.info.files.items.len);
    try expectEqualStrings(torrent.info.name, torrent.info.files.items[0].path);
}
