const std = @import("std");
const log = std.log.scoped(.peer);

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
    socket: std.net.Stream,
    buffer: std.ArrayList(u8),
    tracker: Tracker,
    state: State,
    ally: std.mem.Allocator,

    const Self = @This();
    pub fn init(address: std.net.Address, allocator: std.mem.Allocator, tracker: Tracker) !Peer {
        return Peer{
            .address = address,
            .socket = try connect(address),
            .buffer = std.ArrayList(u8).init(allocator),
            .tracker = tracker,
            .state = State.Choking,
            .ally = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        if (self.socket) |socket| socket.close();
        self.buffer.deinit();
    }

    pub fn connect(address: std.net.Address) !std.net.Stream {
        log.info("connecting to peer '{any}'", .{address});
        var socket: std.net.Stream = undefined;
        for (0..20) |retry| {
            socket = std.net.tcpConnectToAddress(address) catch |err| {
                switch (err) {
                    error.ConnectionTimedOut, error.ConnectionRefused => {
                        std.log.err("connection failed to '{any}': '{}'", .{ address, err });
                        if (retry < 20) {
                            std.time.sleep(500 * std.time.ms_per_s);
                            log.warn("failed to connect: retry {d} of 20", .{retry});
                            continue;
                        }
                        return err;
                    },
                    else => return err,
                }
            };
            break;
        }
        log.info("connected to peer '{any}'", .{address});
        return socket;
    }
};
