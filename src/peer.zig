const std = @import("std");
const zencode = @import("zencode");

const tracker_port = 6889;

pub const Peer = struct {
    address: std.net.Address,
    socket: ?std.fs.File,
    recv_buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(address: std.net.Address, ally: std.mem.Allocator) !Peer {
        var recv_buffer = std.ArrayList(u8).init(ally);
        return .{ .address = address, .socket = null, .recv_buffer = recv_buffer, .allocator = ally };
    }

    pub fn deinit(self: @This()) void {
        self.recv_buffer.deinit();
    }
};

pub const tracker_req_fmt =
    \\{s}?info_hash={s}&peer_id={s}&left={d}
    \\&port={d}&downloaded={d}&uploaded={d}&compact={d}
;

pub fn requestPeers(announce_urls: [][]const u8, info_hash: [20]u8, total_len: usize, ally: std.mem.Allocator) ![]Peer {
    var peers = std.ArrayList(Peer).init(ally);
    defer peers.deinit();
    const escaped_hash = std.Uri.escapeString(ally, info_hash[0..]) catch unreachable;
    defer ally.free(escaped_hash);
    const peer_id = try makePeerID(ally);
    defer ally.free(peer_id);
    const escaped_peer_id = std.Uri.escapeString(ally, peer_id[0..]) catch unreachable;
    defer ally.free(escaped_peer_id);

    const tracker_request = std.fmt.allocPrint(ally, tracker_req_fmt, .{
        announce_urls[0],
        escaped_hash[0..],
        escaped_peer_id[0..],
        total_len,
        tracker_port,
        0,
        0,
        0,
    }) catch unreachable;
    defer ally.free(tracker_request);
    const uri = try std.Uri.parse(tracker_request);
    var client = std.http.Client{ .allocator = ally };
    defer client.deinit();
    var headers = std.http.Headers{ .allocator = ally };
    defer headers.deinit();

    var request = try client.request(.GET, uri, headers, .{});
    defer request.deinit();
    try request.start();
    try request.wait();

    const body = try request.reader().readAllAlloc(ally, 8192);
    defer ally.free(body);
    std.debug.print("{s}", .{body});
    const tree = try zencode.parse(body, ally);
    defer tree.deinit();
    const map = tree.root.Map;

    if (zencode.mapLookupOptional(map, "failure reason", .String)) |failure_field| {
        std.log.warn("Tracker response failure {s}: {s}", .{ uri, failure_field });
        return error.TrackerFailure;
    }

    if (zencode.mapLookupOptional(map, "peers", .String)) |peer_values| {
        if (peer_values.len == 0 or peer_values.len % 6 != 0) return error.EmptyPeers;
        var i: usize = 0;
        while (i < peer_values.len) {
            const ip = [4]u8{ peer_values[i], peer_values[i + 1], peer_values[i + 2], peer_values[i + 3] };
            const peer_port = [2]u8{ peer_values[i + 4], peer_values[i + 5] };
            const port = std.mem.readIntBig(u16, &peer_port);
            const address = std.net.Address.initIp4(ip, port);
            const peer = try Peer.init(address, ally);
            for (peers.items) |p| {
                if (!p.address.eql(peer.address)) {
                    try peers.append(peer);
                }
            }
            i += 6;
        }
    } else {
        const peers_list = try zencode.mapLookup(map, "peers", .List);
        for (peers_list.items) |peer_values| {
            const ip = try zencode.mapLookup(peer_values.Map, "ip", .String);
            const port = try zencode.mapLookup(peer_values.Map, "port", .Integer);
            const casted_port: u16 = @intCast(port);
            const address = try std.net.Address.parseIp(ip, casted_port);
            const peer = try Peer.init(address, ally);
            for (peers.items) |p| {
                if (!p.address.eql(peer.address)) {
                    try peers.append(peer);
                }
            }
        }
    }

    return try peers.toOwnedSlice();
}

fn makePeerID(ally: std.mem.Allocator) ![]u8 {
    var rnd_buf: [12]u8 = undefined;
    std.crypto.random.bytes(&rnd_buf);
    return try std.fmt.allocPrint(ally, "-ZB0100-{s}", .{rnd_buf});
}
