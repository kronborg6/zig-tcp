// Test client
const std = @import("std");
const posix = std.posix;

pub fn main() !void {
    const address = try std.net.Address.parseIp("127.0.0.1", 5882);

    const tpe: u32 = posix.SOCK.STREAM;
    const protocol = posix.IPPROTO.TCP;
    const socket = try posix.socket(address.any.family, tpe, protocol);
    defer posix.close(socket);

    try posix.connect(socket, &address.any, address.getOsSockLen());
    try writeMessage(socket, 1, "Hello World");
    try writeMessage(socket, 1, "Hello World");
    try writeMessage(socket, 10, "Hello World");
    // try writeMessage(socket, "It's OverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOver 9000!!");
    // try writeMessage(socket, "It's OverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOverOver 9000!!");
}

fn writeMessage(socket: posix.socket_t, verion: u16, msg: []const u8) !void {
    var buf: [4]u8 = undefined;
    var ver: [2]u8 = undefined;
    std.mem.writeInt(u32, &buf, @intCast(msg.len), .little);
    std.mem.writeInt(u16, &ver, @intCast(verion), .little);

    var vec = [3]posix.iovec_const{
        .{ .len = 4, .base = &buf },
        .{ .len = 2, .base = &ver },
        .{ .len = msg.len, .base = msg.ptr },
    };
    try writeAllVectored(socket, &vec);
}

fn writeAllVectored(socket: posix.socket_t, vec: []posix.iovec_const) !void {
    var i: usize = 0;
    while (true) {
        var n = try posix.writev(socket, vec[i..]);
        while (n >= vec[i].len) {
            n -= vec[i].len;
            i += 1;
            if (i >= vec.len) return;
        }
        vec[i].base += n;
        vec[i].len -= n;
    }
}
