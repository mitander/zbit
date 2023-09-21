const std = @import("std");
const log = std.log.scoped(.main);

const MetaInfo = @import("metainfo.zig").MetaInfo;
const Torrent = @import("torrent.zig").Torrent;

const example_file = "./assets/example.torrent";
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var ally = gpa.allocator();
    defer _ = gpa.deinit();

    const data = try std.fs.cwd().readFileAlloc(ally, example_file, 60_000);
    defer ally.free(data);

    const info = try MetaInfo.init(data, ally);
    defer info.deinit();

    const torrent = try Torrent.init(info, ally);
    defer torrent.deinit();
}
