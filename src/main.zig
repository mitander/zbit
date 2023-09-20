const std = @import("std");
const log = std.log.scoped(.main);

const MetaInfo = @import("metainfo.zig").MetaInfo;
const TrackerManager = @import("tracker.zig").TrackerManager;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var ally = gpa.allocator();
    defer _ = gpa.deinit();

    const data = try std.fs.cwd().readFileAlloc(ally, "./assets/example.torrent", 60_000);
    defer ally.free(data);

    const info = try MetaInfo.init(data, ally);
    defer info.deinit();

    const tracker_manager = try TrackerManager.init(
        info.announce_urls.items,
        info.info_hash,
        info.total_len,
        ally,
    );
    defer tracker_manager.deinit();
}
