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
    info: InfoMeta,
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
        _ = ally;
        const info = v.get_dict("info").?;
        return TorrentMeta{
            .announce = v.get_string("announce").?,
            .comment = v.get_string("comment").?,
            .created_by = v.get_string("created by").?,
            .creation_date = v.get_i64("creation date").?,
            .files = null, // TODO:
            .info = InfoMeta{
                .length = info.get_u64("length").?,
                .name = info.get_string("name").?,
                .piece_length = info.get_u64("piece length").?,
                .pieces = info.get_string("pieces").?,
            },
        };
    }
};
