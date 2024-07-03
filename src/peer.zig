const std = @import("std");
const log = std.log.scoped(.peer);

const MetaInfo = @import("metainfo.zig").MetaInfo;
const Tracker = @import("tracker.zig").Tracker;

const HANDSHAKE_FMT = "19" ++ "BitTorrent protocol" ++ ("\x00" ** 8) ++ "{:20}{:20}";
const KEEP_ALIVE_FMT = ("\x00" ** 4);
const UNCHOKE_FMT = "{:4}\x01";
const INTERESTED_FMT = "{:4}\x02";
const REQUEST_FMT = "{:4}\x06{:4}{:4}{:4}";

pub const State = enum {
    Choking,
    Interested,
};

pub const MessageType = union(enum) {
    Request: struct { index: u32, begin: u32, length: u32 },
    Piece: struct { index: u32, begin: u32, data: []const u8 },
    Cancel: struct { index: u32, begin: u32, length: u32 },
};

pub const Message = union(enum) {
    Choke: [4]u8,
    Unchoke: [4]u8,
    Interested: [4]u8,
    NotInterested: [4]u8,
    Have: [5]u8,
    Bitfield: []const u8,
    Request: MessageType,

    pub fn id(self: @This()) u8 {
        return @intFromEnum(self);
    }
};

pub const Peer = struct {
    address: std.net.Address,
    socket: std.posix.socket_t,
    buffer: std.ArrayList(u8),
    tracker: Tracker,
    state: State,
    connected: bool,
    ally: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, address: std.net.Address, tracker: Tracker) !Peer {
        const sock_flags = std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC;
        const socket = try std.posix.socket(address.any.family, sock_flags, std.posix.IPPROTO.TCP);
        errdefer std.os.closeSocket(socket);
        return Peer{
            .address = address,
            .socket = socket,
            .buffer = std.ArrayList(u8).init(allocator),
            .tracker = tracker,
            .state = State.Choking,
            .connected = false,
            .ally = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        if (self.socket) |socket| socket.close();
        self.buffer.deinit();
    }

    pub fn download(self: Self, metainfo: MetaInfo, peer_id: [20]u8) !void {
        try self.connect();
        try self.sendHandshake(metainfo, peer_id);
        try self.sendInterested();
        try self.sendChoke();
    }

    fn connect(self: Self) !void {
        log.debug("connecting to peer '{any}", .{self.address});
        for (0..2) |retry| {
            std.posix.connect(self.socket, &self.address.any, self.address.getOsSockLen()) catch |err| {
                switch (err) {
                    error.ConnectionTimedOut, error.ConnectionRefused => {
                        log.warn("connection failed to '{any}', retry {d} of 2", .{
                            self.address,
                            retry + 1,
                        });
                        std.time.sleep(200 * std.time.ms_per_s);
                        continue;
                    },
                    else => return err,
                }
            };
            log.debug("connected to peer '{any}", .{self.address});
            break;
        }
    }

    fn sendHandshake(self: Self, metainfo: MetaInfo, peer_id: [20]u8) !void {
        const handshake_payload = "\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00";
        _ = try std.posix.sendto(self.socket, handshake_payload, 0, @ptrCast(&self.address.any), self.address.any.len);
        _ = try std.posix.sendto(self.socket, metainfo.info_hash[0..], 0, @ptrCast(&self.address.any), self.address.any.len);
        _ = try std.posix.sendto(self.socket, peer_id[0..], 0, @ptrCast(&self.address.any), self.address.any.len);

        while (true) {
            var buf: [68]u8 = undefined;
            const len = try std.posix.read(self.socket, &buf);
            if (len == 68) {
                break;
            }
            log.warn("invalid handshake read: '{d}'", .{len});
        }
        log.debug("handshaked '{any}'", .{self.address});
    }

    fn sendInterested(self: Self) !void {
        var msg: [5]u8 = undefined;
        std.mem.writeInt(u32, msg[0..4], 1, .big);
        std.mem.writeInt(u8, &msg[4], 3, .big);
        _ = try std.posix.sendto(self.socket, &msg, 0, @ptrCast(&self.address.any), self.address.any.len);
        log.debug("interested: '{any}'", .{self.address});
    }

    fn sendChoke(self: Self) !void {
        var msg: [5]u8 = undefined;
        std.mem.writeInt(u32, msg[0..4], 1, .big);
        std.mem.writeInt(u8, &msg[4], 1, .big);
        _ = try std.posix.sendto(self.socket, &msg, 0, @ptrCast(&self.address.any), self.address.any.len);
        log.debug("choke: '{any}'", .{self.address});
    }
};
