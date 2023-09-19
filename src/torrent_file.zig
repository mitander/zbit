const std = @import("std");
const zencode = @import("zencode");
const log = std.log.scoped(.torrent_file);

const File = struct {
    path: []const u8,
    length: usize,
};

pub const TorrentFile = struct {
    announce_urls: std.ArrayList([]const u8),
    info_hash: [20]u8,
    pieces: []const u8,
    piece_hashes: [][20]u8,
    piece_len: usize,
    total_len: usize,
    files: std.ArrayList(File),
    ally: std.mem.Allocator,

    const Self = @This();

    pub fn init(bencode: []const u8, ally: std.mem.Allocator) !TorrentFile {
        const v = try zencode.parse(bencode, ally);
        defer v.deinit();
        zencode.MapLookupError = error.InvalidBencode;

        var announce_urls = std.ArrayList([]const u8).init(ally);
        errdefer announce_urls.deinit();

        errdefer for (announce_urls.items) |val| ally.free(val);
        if (zencode.mapLookupOptional(v.root.Map, "announce", .String)) |announce| {
            const owned_announce = try ally.dupe(u8, announce);
            try announce_urls.append(owned_announce);
        }
        if (zencode.mapLookupOptional(v.root.Map, "announce-list", .List)) |url_list| {
            for (url_list.items) |announce| {
                const owned_announce = try ally.dupe(u8, announce.String);
                try announce_urls.append(owned_announce);
            }
        }

        const info = try zencode.mapLookup(v.root.Map, "info", .Map);
        const name = try zencode.mapLookup(info, "name", .String);
        const pieces = try zencode.mapLookup(info, "pieces", .String);
        const piece_len: usize = @intCast(try zencode.mapLookup(info, "piece length", .Integer));
        var total_len: usize = @intCast(try zencode.mapLookup(info, "length", .Integer));

        var files = std.ArrayList(File).init(ally);
        errdefer files.deinit();
        const owned_name = try ally.dupe(u8, name);
        errdefer ally.free(owned_name);
        try files.append(.{ .path = owned_name, .length = total_len });

        if (zencode.mapLookupOptional(info, "files", .List)) |list| for (list.items) |file| {
            const length: usize = @intCast(try zencode.mapLookup(file.Map, "length", .Integer));
            const owned_path = try ally.dupe(u8, try zencode.mapLookup(file.Map, "path", .String));
            errdefer ally.free(owned_path);
            try files.append(.{ .path = owned_name, .length = length });
            total_len += length;
        };

        const hash_len = 20;
        const num_hashes = pieces.len / hash_len;
        if (pieces.len % hash_len != 0) return error.InvalidHash;
        var piece_hashes = try ally.alloc([20]u8, num_hashes);
        errdefer ally.free(piece_hashes);
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

        const owned_pieces = try ally.dupe(u8, pieces);
        errdefer ally.free(owned_pieces);

        return TorrentFile{
            .announce_urls = announce_urls,
            .info_hash = info_hash,
            .pieces = owned_pieces,
            .piece_hashes = piece_hashes,
            .piece_len = piece_len,
            .total_len = total_len,
            .files = files,
            .ally = ally,
        };
    }

    pub fn deinit(self: Self) void {
        self.ally.free(self.piece_hashes);
        self.ally.free(self.pieces);
        for (self.files.items) |file| self.ally.free(file.path);
        self.files.deinit();
        for (self.announce_urls.items) |url| self.ally.free(url);
        self.announce_urls.deinit();
    }
};

const testing = std.testing;

test "create torrent file" {
    const data = try std.fs.cwd().readFileAlloc(testing.allocator, "./assets/example.torrent", 100_000);
    defer testing.allocator.free(data);
    var torrent = try TorrentFile.init(data, testing.allocator);
    defer torrent.deinit();

    const hash_len = 20;
    const piece_len = torrent.pieces.len / hash_len;

    try testing.expectEqual(hash_len, torrent.info_hash.len);
    try testing.expectEqual(piece_len, torrent.piece_hashes.len);
    try testing.expectEqual(@as(usize, 262_144), torrent.piece_len);
    try testing.expectEqual(@as(usize, 50_000), torrent.pieces.len);
    try testing.expectEqual(@as(usize, 1), torrent.files.items.len);
    try testing.expectEqualStrings("debian-mac-12.1.0-amd64-netinst.iso", torrent.files.items[0].path);
    try testing.expectEqualStrings("http://bttracker.debian.org:6969/announce", torrent.announce_urls.items[0]);
}

test "create torrent with multiple files" {
    var torrent = try TorrentFile.init("d8:announce14:http://foo.com4:infod6:lengthi20e12:piece lengthi20e6:pieces20:0123456789012345678904:name11:example.iso5:filesld6:lengthi40e4:path8:test.txteeee", testing.allocator);
    defer torrent.deinit();
    try testing.expectEqual(@as(usize, 20), torrent.files.items[0].length);
    try testing.expectEqualStrings("example.iso", torrent.files.items[0].path);
    try testing.expectEqual(@as(usize, 40), torrent.files.items[1].length);
    try testing.expectEqualStrings("test.txt", torrent.files.items[1].path);
}
