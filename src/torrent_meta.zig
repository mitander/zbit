const std = @import("std");
const zencode = @import("zencode");

pub const Hash = struct {
    info: [20]u8,
    pieces: [][20]u8,
};

pub const Info = struct {
    name: []const u8,
    len: u64,
    pieces: []const u8,
    pieces_len: u64,
};

pub const TorrentMeta = struct {
    announce: []const u8,
    hash: Hash,
    info: Info,

    const Self = @This();

    // TODO: pass buffer instead of path
    pub fn parse(path: []const u8, ally: std.mem.Allocator) !TorrentMeta {
        var f = try std.fs.cwd().openFile(path, .{});
        defer f.close();
        const v = try zencode.parseReader(f.reader(), ally);
        defer v.deinit();

        const announce = try ally.dupe(u8, v.root.getString("announce").?);
        const info = v.root.getDict("info").?;
        const name = try ally.dupe(u8, info.getString("name").?);
        const len = try info.getU64("length");
        const pieces = try ally.dupe(u8, info.getString("pieces").?);
        const pieces_len = try info.getU64("piece length");

        const torrent_info = Info{
            .name = name,
            .len = len.?,
            .pieces = pieces,
            .pieces_len = pieces_len.?,
        };

        return TorrentMeta{
            .announce = announce,
            .hash = try hash(info, pieces, ally),
            .info = torrent_info,
        };
    }

    pub fn deinit(self: Self, ally: std.mem.Allocator) void {
        ally.free(self.announce);
        ally.free(self.info.pieces);
        ally.free(self.info.name);
        ally.free(self.hash.pieces);
    }

    fn hash(info: zencode.Value, pieces: []const u8, ally: std.mem.Allocator) !Hash {
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
        try info.encode(list.writer());
        var info_hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(list.items, info_hash[0..], std.crypto.hash.Sha1.Options{});
        return Hash{ .info = info_hash, .pieces = piece_hashes };
    }
};
