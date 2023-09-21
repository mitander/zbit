const std = @import("std");
const log = std.log.scoped(.torrent);

const TrackerManager = @import("tracker.zig").TrackerManager;
const MetaInfo = @import("metainfo.zig").MetaInfo;

pub const Torrent = struct {
    name: []const u8,
    peer_id: [20]u8,
    info_hash: [20]u8,
    piece_hashes: [][20]u8,
    tracker_manager: TrackerManager,
    metainfo: MetaInfo,
    arena: std.heap.ArenaAllocator,

    const Self = @This();

    pub fn init(metainfo: MetaInfo, allocator: std.mem.Allocator) !Torrent {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var ally = arena.allocator();
        errdefer arena.deinit();

        const peer_id = try generatePeerId(ally);
        const tracker_manager = try TrackerManager.init(metainfo, peer_id, ally);

        return Torrent{
            .name = metainfo.name,
            .peer_id = peer_id,
            .info_hash = metainfo.info_hash,
            .piece_hashes = metainfo.piece_hashes,
            .tracker_manager = tracker_manager,
            .metainfo = metainfo,
            .arena = arena,
        };
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }
};

fn generatePeerId(allocator: std.mem.Allocator) ![20]u8 {
    var peer_id: [20]u8 = undefined;
    var rand_buf: [12]u8 = undefined;
    std.crypto.random.bytes(&rand_buf);
    var id = try std.fmt.allocPrint(allocator, "-ZB0100-{s}", .{rand_buf});
    defer allocator.free(id);
    std.mem.copy(u8, &peer_id, id);
    return peer_id;
}
