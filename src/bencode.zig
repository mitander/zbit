const std = @import("std");

const MAX_NUM_LEN = 25;

pub fn parse_bytes(raw_ben: []const u8, ally: std.mem.Allocator) !Value {
    var b = std.io.fixedBufferStream(raw_ben);
    return parse_reader(b.reader(), ally);
}

pub fn parse_reader(r: anytype, ally: std.mem.Allocator) !Value {
    var pr: PeekableReader(@TypeOf(r)) = .{ .child_reader = r };
    return pr.parse_inner(ally);
}

pub const Value = union(enum) {
    String: []const u8,
    Integer: i64,
    List: []const Value,
    Dictionary: std.StringArrayHashMapUnmanaged(Value),

    const Self = @This();

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        _ = fmt;
        _ = options;

        switch (self) {
            .String => |v| {
                try writer.writeByte('"');
                try std.fmt.format(writer, "{}", .{std.zig.fmtEscapes(v)});
                try writer.writeByte('"');
            },
            .Integer => |v| {
                try std.fmt.format(writer, "{d}", .{v});
            },
            .List => |v| {
                try writer.writeByte('[');
                for (v) |item| {
                    try writer.print("{}", .{item});
                    try writer.writeByte(',');
                }
                try writer.writeByte(']');
            },
            .Dictionary => |v| {
                try writer.writeByte('{');
                for (v.keys(), v.values()) |key, val| {
                    try writer.print("\"{s}\": {},", .{ key, val });
                }
                try writer.writeByte('}');
            },
        }
    }

    pub fn encode(self: Self, writer: anytype) !void {
        switch (self) {
            .String => |v| {
                try writer.print("{d}", .{v.len});
                try writer.writeByte(':');
                try writer.writeAll(v);
            },
            .Integer => |v| {
                try writer.writeByte('i');
                try writer.print("{d}", .{v});
                try writer.writeByte('e');
            },
            .List => |v| {
                try writer.writeByte('l');
                for (v) |item| {
                    try item.encode(writer);
                }
                try writer.writeByte('e');
            },
            .Dictionary => |v| {
                try writer.writeByte('d');
                for (v.keys(), v.values()) |key, val| {
                    try (Value{ .String = key }).encode(writer);
                    try val.encode(writer);
                }
                try writer.writeByte('e');
            },
        }
    }

    pub fn get_dict(self: Self, key: []const u8) ?Value {
        std.debug.assert(self == .Dictionary);
        const ret = self.Dictionary.get(key) orelse return null;
        return if (ret == .Dictionary) ret else null;
    }

    pub fn get_list(self: Self, key: []const u8) ?[]const Value {
        return self.get_tag(key, .List);
    }

    pub fn get_string(self: Self, key: []const u8) ?[]const u8 {
        return self.get_tag(key, .String);
    }

    pub fn get_i64(self: Self, key: []const u8) ?i64 {
        return self.get_tag(key, .Integer);
    }

    pub fn get_u64(self: Self, key: []const u8) ?u64 {
        return @intCast(self.get_i64(key) orelse return null);
    }

    fn get_tag(self: Self, key: []const u8, comptime tag: std.meta.FieldEnum(Value)) ?std.meta.FieldType(Value, tag) {
        std.debug.assert(self == .Dictionary);
        const ret = self.Dictionary.get(key) orelse return null;
        return if (ret == tag) @field(ret, @tagName(tag)) else null;
    }
};

fn PeekableReader(comptime ReaderType: type) type {
    return struct {
        child_reader: ReaderType,
        buf: ?u8 = null,

        pub const Error = ReaderType.Error;
        pub const Reader = std.io.Reader(*Self, Error, read);

        const Self = @This();

        fn read(self: *Self, dst: []u8) Error!usize {
            if (self.buf) |c| {
                dst[0] = c;
                self.buf = null;
                return 1;
            }
            return self.child_reader.read(dst);
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        pub fn peek(self: *Self) !?u8 {
            if (self.buf == null) {
                self.buf = self.child_reader.readByte() catch |err| switch (err) {
                    error.EndOfStream => return null,
                    else => |e| return e,
                };
            }
            return self.buf;
        }

        fn parse_string(self: *Self, ally: std.mem.Allocator) ![]const u8 {
            const str = try self.reader().readUntilDelimiterAlloc(ally, ':', MAX_NUM_LEN);
            const len = try std.fmt.parseInt(usize, str, 10);
            var buf = try ally.alloc(u8, len);
            const l = try self.reader().readAll(buf);
            return buf[0..l];
        }

        fn parse_integer(self: *Self, ally: std.mem.Allocator) !i64 {
            const str = try self.reader().readUntilDelimiterAlloc(ally, 'e', MAX_NUM_LEN);
            return try std.fmt.parseInt(i64, str, 10);
        }

        fn parse_list(self: *Self, ally: std.mem.Allocator) ![]Value {
            var list = std.ArrayList(Value).init(ally);
            while (try self.peek()) |c| {
                if (c == 'e') {
                    self.buf = null;
                    return list.toOwnedSlice();
                }
                const v = try self.parse_inner(ally);
                try list.append(v);
            }
            return error.EndOfStream;
        }

        fn parse_dict(self: *Self, ally: std.mem.Allocator) !std.StringArrayHashMapUnmanaged(Value) {
            var map = std.StringArrayHashMapUnmanaged(Value){};
            while (try self.peek()) |c| {
                if (c == 'e') {
                    self.buf = null;
                    return map;
                }
                const k = try self.parse_string(ally);
                const v = try self.parse_inner(ally);
                try map.put(ally, k, v);
            }
            return error.EndOfStream;
        }

        fn parse_inner(self: *Self, ally: std.mem.Allocator) anyerror!Value {
            const char = try self.peek() orelse return error.EndOfStream;

            if (char >= '0' and char <= '9') {
                return Value{
                    .String = try self.parse_string(ally),
                };
            }

            switch (try self.reader().readByte()) {
                'i' => {
                    return .{
                        .Integer = try self.parse_integer(ally),
                    };
                },
                'l' => {
                    return .{
                        .List = try self.parse_list(ally),
                    };
                },
                'd' => {
                    return .{
                        .Dictionary = try self.parse_dict(ally),
                    };
                },
                else => return error.BencodeBadDelimiter,
            }
        }
    };
}
