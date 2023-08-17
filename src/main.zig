const std = @import("std");
const bencode = @import("bencode.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();

    var buf = std.io.fixedBufferStream(@embedFile("example.torrent"));
    const r = buf.reader();
    const bc = try bencode.parse_reader(r, ally);

    std.log.info("{s}", .{bc.get_dict("info").?.get_string("name").?});
    std.log.info("{s}", .{bc.get_dict("info").?});
}
