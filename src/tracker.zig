const std = @import("std");
const log = std.log.scoped(.tracker);
const zencode = @import("zencode");

const MetaInfo = @import("metainfo.zig").MetaInfo;

pub const Peer = struct {
    address: std.net.Address,
    recv_buffer: std.ArrayList(u8),

    pub fn init(address: std.net.Address, allocator: std.mem.Allocator) Peer {
        var recv_buffer = std.ArrayList(u8).init(allocator);
        return Peer{ .address = address, .recv_buffer = recv_buffer };
    }
};

pub const Tracker = struct {
    uri: std.Uri,
    last_update: std.atomic.Atomic(i64),
    ally: std.mem.Allocator,

    const Self = @This();

    pub fn init(uri: std.Uri, allocator: std.mem.Allocator) Tracker {
        return Tracker{
            .uri = uri,
            .last_update = std.atomic.Atomic(i64).init(0),
            .ally = allocator,
        };
    }

    pub fn requestPeers(self: Self) ![]Peer {
        var arena = std.heap.ArenaAllocator.init(self.ally);
        var ally = arena.allocator();
        errdefer arena.deinit();

        const bencode = try self.sendRequest(ally);
        const tree = try zencode.parse(bencode, ally);
        defer tree.deinit();

        if (zencode.mapLookupOptional(tree.root.Map, "failure reason", .String)) |failure_field| {
            std.log.warn("tracker response failure {s}: {s}", .{ self.uri, failure_field });
            return error.TrackerFailure;
        }

        var peers = std.ArrayList(Peer).init(ally);
        if (zencode.mapLookupOptional(tree.root.Map, "peers", .String)) |peer_values| {
            // compacted peer list, every peer is 6 bytes total:
            // 4 bytes ip, 2 bytes port
            if (peer_values.len == 0 or peer_values.len % 6 != 0) {
                return error.EmptyPeers;
            }
            var i: usize = 0;
            while (i < peer_values.len) : (i += 6) {
                const ip = [4]u8{
                    peer_values[i],
                    peer_values[i + 1],
                    peer_values[i + 2],
                    peer_values[i + 3],
                };
                const peer_port = [2]u8{ peer_values[i + 4], peer_values[i + 5] };
                const port = std.mem.readIntBig(u16, &peer_port);
                const address = std.net.Address.initIp4(ip, port);
                const peer = Peer.init(address, ally);
                try addUniquePeer(&peers, peer);
            }
        } else {
            const peers_list = try zencode.mapLookup(tree.root.Map, "peers", .List);
            for (peers_list.items) |peer_values| {
                const ip = try zencode.mapLookup(peer_values.Map, "ip", .String);
                const port = try zencode.mapLookup(peer_values.Map, "port", .Integer);
                const casted_port: u16 = @intCast(port);
                const address = try std.net.Address.parseIp(ip, casted_port);
                const peer = Peer.init(address, ally);
                try addUniquePeer(&peers, peer);
            }
        }
        return try peers.toOwnedSlice();
    }

    fn addUniquePeer(peers: *std.ArrayList(Peer), peer: Peer) !void {
        for (peers.items) |p| {
            if (p.address.eql(peer.address)) {
                return;
            }
        }
        log.debug("added peer: {any}", .{peer.address});
        try peers.append(peer);
    }

    fn sendRequest(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var ally = arena.allocator();
        errdefer arena.deinit();

        var client = std.http.Client{ .allocator = ally };
        var headers = std.http.Headers{ .allocator = ally };
        var request = try client.request(.GET, self.uri, headers, .{});
        try request.start();
        try request.wait();

        return try request.reader().readAllAlloc(allocator, 8192);
    }
};

pub const TrackerManager = struct {
    trackers: std.ArrayList(Tracker),
    peers: std.ArrayList(Peer),
    arena: std.heap.ArenaAllocator,

    const Self = @This();

    pub fn init(metainfo: MetaInfo, peer_id: [20]u8, allocator: std.mem.Allocator) !TrackerManager {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var ally = arena.allocator();
        errdefer arena.deinit();

        var trackers = std.ArrayList(Tracker).init(ally);
        var tracker_peers = std.ArrayList(Peer).init(ally);
        for (metainfo.announce_urls.items) |url| {
            const uri = parseUri(url, peer_id, metainfo.info_hash, metainfo.total_len, ally) catch {
                log.warn("skipping tracker '{s}': missing 'http' or 'https' schema", .{url});
                continue;
            };
            const tracker = Tracker.init(uri, ally);
            try trackers.append(tracker);
            const peers = try tracker.requestPeers();
            try tracker_peers.appendSlice(peers);
        }

        log.info("manager created: {d} tracker(s) and {d} peer(s)", .{ trackers.items.len, tracker_peers.items.len });
        return TrackerManager{
            .trackers = trackers,
            .peers = tracker_peers,
            .arena = arena,
        };
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }
};

fn parseUri(url: []const u8, peer_id: [20]u8, info_hash: [20]u8, total_len: usize, allocator: std.mem.Allocator) !std.Uri {
    const escaped_hash = std.Uri.escapeString(allocator, &info_hash) catch unreachable;
    const request_fmt = "{s}?info_hash={s}&peer_id={s}&left={d}&port={d}&downloaded=0&uploaded=0&compact=0";
    const tracker_port = 6889;

    const req = std.fmt.allocPrint(allocator, request_fmt, .{
        url,
        escaped_hash,
        peer_id,
        total_len,
        tracker_port,
    }) catch unreachable;
    return try std.Uri.parse(req);
}
