const std = @import("std");
const log = std.log.scoped(.torrent);

const TrackerManager = @import("tracker.zig").TrackerManager;
const MetaInfo = @import("metainfo.zig").MetaInfo;

pub const State = enum {
    Choking,
    Interested,
};

pub const Client = struct {
    name: []const u8,
    peer_id: [20]u8,
    info_hash: [20]u8,
    piece_hashes: [][20]u8,
    tracker_manager: TrackerManager,
    metainfo: MetaInfo,
    state: State,
    arena: std.heap.ArenaAllocator,

    const Self = @This();

    pub fn init(metainfo: MetaInfo, allocator: std.mem.Allocator) !Client {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const ally = arena.allocator();
        errdefer arena.deinit();

        const peer_id = try new_peer_id(ally);
        const tracker_manager = try TrackerManager.init(metainfo, peer_id, ally);

        return Client{
            .name = metainfo.name,
            .peer_id = peer_id,
            .info_hash = metainfo.info_hash,
            .piece_hashes = metainfo.piece_hashes,
            .tracker_manager = tracker_manager,
            .metainfo = metainfo,
            .state = State.Choking,
            .arena = arena,
        };
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }
};

fn new_peer_id(allocator: std.mem.Allocator) ![20]u8 {
    var peer_id: [20]u8 = undefined;
    var rand_buf: [12]u8 = undefined;
    std.crypto.random.bytes(&rand_buf);
    const id = try std.fmt.allocPrint(allocator, "-ZB0100-{s}", .{rand_buf});
    defer allocator.free(id);
    std.mem.copyForwards(u8, &peer_id, id);
    return peer_id;
}
