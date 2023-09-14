const std = @import("std");

const debug = std.log.debug;
const info = std.log.info;

const TorrentMeta = @import("torrent_meta.zig").TorrentMeta;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    var torrent = try TorrentMeta.fromPath("./assets/example.torrent", ally);
    defer torrent.deinit(ally);

    info("{any}", .{torrent});
}
