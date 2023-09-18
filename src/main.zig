const std = @import("std");

const debug = std.log.debug;
const info = std.log.info;

const TorrentFile = @import("torrent_file.zig").TorrentFile;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    const data = try std.fs.cwd().readFileAlloc(ally, "./assets/example.torrent", 60_000);
    defer ally.free(data);

    var torrent = try TorrentFile.parse(data, ally);
    defer torrent.deinit();

    for (torrent.files.items) |f| {
        info("{any}", .{f});
    }
}
