const std = @import("std");

const debug = std.log.debug;
const info = std.log.info;

const TorrentMeta = @import("torrent_meta.zig").TorrentMeta;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();

    const torrent = try TorrentMeta.from_path("./assets/example.torrent", ally);
    info("hash: {b}", .{torrent.info_hash});
}
