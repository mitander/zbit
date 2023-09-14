const std = @import("std");
const zencode = @import("zencode");

const File = struct {
    name: []const u8,
    length: usize,
};

pub const Info = struct {
    name: []const u8,
    len: u64,
    pieces: []const u8,
    pieces_len: u64,
};

pub const TorrentMeta = struct {
    announce: []const u8,
    info_hash: [20]u8,
    info: Info,

    const Self = @This();
    pub fn fromPath(path: []const u8, ally: std.mem.Allocator) !TorrentMeta {
        var f = try std.fs.cwd().openFile(path, .{});
        defer f.close();
        const v = try zencode.parseReader(f.reader(), ally);
        defer v.deinit();
        return serialize(v, ally);
    }

    pub fn fromBuf(b: []const u8, ally: std.mem.Allocator) !TorrentMeta {
        var buf = std.io.fixedBufferStream(b);
        const v = try zencode.parseReader(buf, ally);
        defer v.deinit();
        return serialize(v, ally);
    }

    pub fn deinit(self: Self, ally: std.mem.Allocator) void {
        ally.free(self.announce);
        ally.free(self.info.pieces);
        ally.free(self.info.name);
    }

    fn serialize(v: zencode.ValueTree, ally: std.mem.Allocator) !TorrentMeta {
        const info = v.root.getDict("info").?;
        const len = try info.getU64("length");
        const pieces_len = try info.getU64("piece length");
        return TorrentMeta{
            .announce = try ally.dupe(u8, v.root.getString("announce").?),
            .info_hash = try v.hashInfo(ally),
            .info = Info{
                .name = try ally.dupe(u8, info.getString("name").?),
                .len = len.?,
                .pieces = try ally.dupe(u8, info.getString("pieces").?),
                .pieces_len = pieces_len.?,
            },
        };
    }
};
