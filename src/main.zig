const std = @import("std");
const peer = @import("peer.zig");
const TorrentFile = @import("torrent_file.zig").TorrentFile;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var ally = gpa.allocator();
    defer _ = gpa.deinit();

    const data = try std.fs.cwd().readFileAlloc(ally, "./assets/example.torrent", 60_000);
    defer ally.free(data);

    var torrent = try TorrentFile.init(data, ally);
    std.log.debug("{any}", .{torrent});
    defer torrent.deinit();

    const peers = try peer.requestPeers(torrent.announce_urls.items, torrent.info_hash, torrent.total_len, ally);
    for (peers) |p| {
        p.deinit();
    }
}
