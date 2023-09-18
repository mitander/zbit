const std = @import("std");
const zencode = @import("zencode");

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

    pub fn parse(data: []const u8, ally: std.mem.Allocator) !TorrentFile {
        const v = try zencode.parse(data, ally);
        defer v.deinit();
        zencode.MapLookupError = error.InvalidBencode;

        var announce_urls = std.ArrayList([]const u8).init(ally);
        errdefer announce_urls.deinit();
        var announce = try zencode.mapLookup(v.root.Map, "announce", .String);
        if (validUrl(announce)) try announce_urls.append(try ally.dupe(u8, announce));
        if (zencode.mapLookupOptional(v.root.Map, "announce-list", .List)) |url_list| {
            for (url_list.items) |item| if (validUrl(item.String)) {
                try announce_urls.append(try ally.dupe(u8, item.String));
            };
        }

        const info = try zencode.mapLookup(v.root.Map, "info", .Map);
        const pieces = try zencode.mapLookup(info, "pieces", .String);
        const path = try zencode.mapLookup(info, "name", .String);
        const piece_len: usize = @intCast(try zencode.mapLookup(info, "piece length", .Integer));
        var total_len: usize = @intCast(try zencode.mapLookup(info, "length", .Integer));

        var files = std.ArrayList(File).init(ally);
        errdefer files.deinit();
        try files.append(.{ .path = try ally.dupe(u8, path), .length = total_len });
        if (zencode.mapLookupOptional(info, "files", .List)) |list| {
            for (list.items) |file| {
                const l: usize = @intCast(try zencode.mapLookup(file.Map, "length", .Integer));
                const p = try zencode.mapLookup(file.Map, "path", .String);
                total_len += l;
                try files.append(.{ .path = try ally.dupe(u8, p), .length = l });
            }
        }

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

        var list = std.ArrayList(u8).init(ally);
        defer list.deinit();
        const value_info = zencode.Value{ .Map = info };
        try value_info.encode(list.writer());
        var info_hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(list.items, info_hash[0..], std.crypto.hash.Sha1.Options{});

        return TorrentFile{
            .announce_urls = announce_urls,
            .info_hash = info_hash,
            .pieces = try ally.dupe(u8, pieces),
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

fn validUrl(url: []const u8) bool {
    if (url.len < 7) return false;
    return (std.mem.eql(u8, url[0..7], "http://") or std.mem.eql(u8, url[0..8], "https://"));
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

test "parse torrent file" {
    const data = try std.fs.cwd().readFileAlloc(testing.allocator, "./deps/zencode/assets/example.torrent", 100_000);
    defer testing.allocator.free(data);
    var torrent = try TorrentFile.parse(data, testing.allocator);
    defer torrent.deinit();

    const hash_len = 20;
    const piece_len = torrent.pieces.len / hash_len;

    try expectEqual(hash_len, torrent.info_hash.len);
    try expectEqual(piece_len, torrent.piece_hashes.len);
    try expectEqual(@as(usize, 262_144), torrent.piece_len);
    try expectEqual(@as(usize, 50_000), torrent.pieces.len);
    try expectEqual(@as(usize, 1), torrent.files.items.len);
    try expectEqualStrings("debian-mac-12.1.0-amd64-netinst.iso", torrent.files.items[0].path);
    try expectEqualStrings("http://bttracker.debian.org:6969/announce", torrent.announce_urls.items[0]);
}

test "parse torrent multiple files" {
    var torrent = try TorrentFile.parse("d8:announce14:http://foo.com4:infod6:lengthi20e12:piece lengthi20e6:pieces20:0123456789012345678904:name11:example.iso5:filesld6:lengthi40e4:path8:test.txteeee", testing.allocator);
    defer torrent.deinit();
    try expectEqual(@as(usize, 20), torrent.files.items[0].length);
    try expectEqualStrings("example.iso", torrent.files.items[0].path);
    try expectEqual(@as(usize, 40), torrent.files.items[1].length);
    try expectEqualStrings("test.txt", torrent.files.items[1].path);
}

test "parse url" {
    try testing.expect(validUrl("http://www.exampleurl.com") == true);
    try testing.expect(validUrl("https://www.exampleurl.com") == true);
    try testing.expect(validUrl("http//www.exampleurl.com") == false);
    try testing.expect(validUrl("htt://www.exampleurl.com") == false);
    try testing.expect(validUrl("www.exampleurl.com") == false);
}
