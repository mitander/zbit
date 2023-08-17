const std = @import("std");
const bencode = @import("bencode.zig");

const File = struct {
    name: []const u8,
    length: usize,
};

const InfoMeta = struct {
    name: []const u8,
    pieces: []const u8,
    piece_length: usize,
    length: usize,
};

pub const TorrentMeta = struct {
    announce: []const u8,
    comment: []const u8,
    created_by: []const u8,
    creation_date: i64,
    info_hash: [20]u8,
    files: ?std.ArrayList(File),

    pub fn from_path(path: []const u8, ally: std.mem.Allocator) !TorrentMeta {
        var f = try std.fs.cwd().openFile(path, .{});
        defer f.close();
        const v = try bencode.parse_reader(f.reader(), ally);
        return serialize(v, ally);
    }

    pub fn from_buf(b: []const u8, ally: std.mem.Allocator) !TorrentMeta {
        var buf = std.io.fixedBufferStream(b);
        const v = try bencode.parse_reader(buf, ally);
        return serialize(v, ally);
    }

    fn serialize(v: bencode.Value, ally: std.mem.Allocator) !TorrentMeta {
        const info = v.get_dict("info").?;
        const hash = try hash_info(ally, info);
        return TorrentMeta{
            .announce = v.get_string("announce").?,
            .comment = v.get_string("comment").?,
            .created_by = v.get_string("created by").?,
            .creation_date = v.get_i64("creation date").?,
            .files = null, // TODO:
            .info_hash = hash,
        };
    }

    fn hash_info(ally: std.mem.Allocator, v: bencode.Value) ![20]u8 {
        var list = std.ArrayList(u8).init(ally);
        defer list.deinit();
        try v.encode(list.writer());
        var hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(list.items, hash[0..], std.crypto.hash.Sha1.Options{});
        return hash;
    }
};
