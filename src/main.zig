const std = @import("std");
const log = std.log.scoped(.main);

const TorrentFile = @import("torrent_file.zig").TorrentFile;
const TrackerManager = @import("tracker.zig").TrackerManager;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var ally = gpa.allocator();
    defer _ = gpa.deinit();

    const data = try std.fs.cwd().readFileAlloc(ally, "./assets/example.torrent", 60_000);
    defer ally.free(data);

    var torrent = try TorrentFile.init(data, ally);
    defer torrent.deinit();
    log.debug("torrent '{s}' parsed with {d} file(s)", .{ torrent.files.items[0].path, torrent.files.items.len });

    const tracker_manager = try TrackerManager.init(torrent.announce_urls.items, torrent.info_hash, torrent.total_len, ally);
    defer tracker_manager.deinit();
}
