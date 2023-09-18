const std = @import("std");

const debug = std.log.debug;
const info = std.log.info;

const TorrentMeta = @import("torrent_meta.zig").TorrentMeta;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    const data = try std.fs.cwd().readFileAlloc(ally, "./assets/example.torrent", 60_000);
    defer ally.free(data);

    var torrent = try TorrentMeta.parse(data, ally);
    defer torrent.deinit(ally);

    info("{s}", .{torrent.info.name});
}
