const std = @import("std");
const net = std.net;
const posix = std.posix;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.tcp_demo);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try Server.init(allocator, 4096);
    defer server.deinit();

    const address = try std.net.Address.parseIp("127.0.0.1", 5882);
    try server.run(address);
}

const Server = struct {
    // creates our polls and clients slices and is passed to Client.init
    // for it to create our read buffer.
    allocator: Allocator,

    // The number of clients we currently have connected
    connected: usize,

    // polls[0] is always our listening socket
    polls: []posix.pollfd,

    // list of clients, only client[0..connected] are valid
    clients: []Client,

    // This is always polls[1..] and it's used to so that we can manipulate
    // clients and client_polls together. Necessary because polls[0] is the
    // listening socket, and we don't ever touch that.
    client_polls: []posix.pollfd,

    fn init(allocator: Allocator, max: usize) !Server {
        // + 1 for the listening socket
        const polls = try allocator.alloc(posix.pollfd, max + 1);
        errdefer allocator.free(polls);

        const clients = try allocator.alloc(Client, max);
        errdefer allocator.free(clients);

        return .{
            .polls = polls,
            .clients = clients,
            .client_polls = polls[1..],
            .connected = 0,
            .allocator = allocator,
        };
    }

    fn deinit(self: *Server) void {
        // TODO: Close connected sockets? We'll talk about shutdowns in
        // a future part.
        self.allocator.free(self.polls);
        self.allocator.free(self.clients);
    }

    fn run(self: *Server, address: std.net.Address) !void {
        const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.any.family, tpe, protocol);
        defer posix.close(listener);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, 128);

        // One of the polling slots (the first one) is reserved for our listening
        // socket.
        self.polls[0] = .{
            .fd = listener,
            .revents = 0,
            .events = posix.POLL.IN,
        };

        while (true) {
            // Oops, still have a +1 here, since we want to poll all our connected
            // clients, plus our listening socket
            _ = try posix.poll(self.polls[0 .. self.connected + 1], -1);

            if (self.polls[0].revents != 0) {
                // listening socket is ready
                self.accept(listener) catch |err| log.err("failed to accept: {}", .{err});
            }

            var i: usize = 0;
            while (i < self.connected) {
                const revents = self.client_polls[i].revents;
                if (revents == 0) {
                    // this socket isn't ready, move on to the next one
                    i += 1;
                    continue;
                }

                var client = &self.clients[i];
                if (revents & posix.POLL.IN == posix.POLL.IN) {
                    // this socket is ready to be read
                    while (true) {
                        const msg = client.readMessage() catch {
                            // we don't increment `i` when we remove the client
                            // because removeClient does a swap and puts the last
                            // client at position i
                            self.removeClient(i);
                            std.debug.print("failed \n", .{});
                            break;
                        } orelse {
                            std.debug.print("failed to read message\n", .{});
                            // no more messages, but this client is still connected
                            i += 1;
                            break;
                        };

                        std.debug.print("[{any}]: {s}\n", .{ client.address, msg });
                    }
                }
            }
        }
    }

    fn accept(self: *Server, listener: posix.socket_t) !void {
        while (true) {
            var address: net.Address = undefined;
            var address_len: posix.socklen_t = @sizeOf(net.Address);
            const socket = posix.accept(listener, &address.any, &address_len, posix.SOCK.NONBLOCK) catch |err| switch (err) {
                error.WouldBlock => return,
                else => return err,
            };

            const client = Client.init(self.allocator, socket, address) catch |err| {
                posix.close(socket);
                log.err("failed to initialize client: {}", .{err});
                std.debug.print("failed to initialize client: {}", .{err});
                return;
            };
            std.debug.print("connected: {any}\n", .{client.address});

            const connected = self.connected;
            self.clients[connected] = client;
            self.client_polls[connected] = .{
                .fd = socket,
                .revents = 0,
                .events = posix.POLL.IN,
            };
            self.connected = connected + 1;
        }
    }

    fn removeClient(self: *Server, at: usize) void {
        var client = self.clients[at];

        posix.close(client.socket);
        client.deinit(self.allocator);

        // Swap the client we're removing with the last one
        // So that when we set connected -= 1, it'll effectively "remove"
        // the client from our slices.
        const last_index = self.connected - 1;
        self.clients[at] = self.clients[last_index];
        self.client_polls[at] = self.client_polls[last_index];

        self.connected = last_index;
    }
};

const Client = struct {
    reader: Reader,
    socket: posix.socket_t,
    address: std.net.Address,

    fn init(allocator: Allocator, socket: posix.socket_t, address: std.net.Address) !Client {
        const reader = try Reader.init(allocator, 4096);
        errdefer reader.deinit(allocator);

        return .{
            .reader = reader,
            .socket = socket,
            .address = address,
        };
    }

    fn deinit(self: *const Client, allocator: Allocator) void {
        self.reader.deinit(allocator);
    }

    fn readMessage(self: *Client) !?[]const u8 {
        return self.reader.readMessage(self.socket) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => return err,
        };
    }
};

const Reader = struct {
    buf: []u8,
    pos: usize = 0,
    start: usize = 0,

    fn init(allocator: Allocator, size: usize) !Reader {
        const buf = try allocator.alloc(u8, size);
        return .{
            .pos = 0,
            .start = 0,
            .buf = buf,
        };
    }

    fn deinit(self: *const Reader, allocator: Allocator) void {
        allocator.free(self.buf);
    }

    fn readMessage(self: *Reader, socket: posix.socket_t) ![]u8 {
        var buf = self.buf;

        while (true) {
            if (try self.bufferedMessage()) |msg| {
                return msg;
            }
            const pos = self.pos;
            const n = try posix.read(socket, buf[pos..]);
            if (n == 0) {
                return error.Closed;
            }
            self.pos = pos + n;
        }
    }

    fn bufferedMessage(self: *Reader) !?[]u8 {
        const buf = self.buf;
        const pos = self.pos;
        const start = self.start;
        var header: Header = undefined;
        std.debug.assert(pos >= start);
        const unprocessed = buf[start..pos];
        if (unprocessed.len < 8) {
            self.ensureSpace(8 - unprocessed.len) catch unreachable;
            return null;
        }

        header.length = std.mem.readInt(u32, unprocessed[0..4], .little);
        header.version = std.mem.readInt(u16, unprocessed[4..6], .little);
        header.msg_type = std.mem.readInt(u16, unprocessed[6..8], .little);
        // _ = std.mem.readInt(u16, unprocessed[4..6], .little);
        std.debug.print("len: {}\n", .{header.length});

        // the length of our message + the length of our prefix
        const total_len = header.length + 8;

        if (unprocessed.len < total_len) {
            try self.ensureSpace(total_len);
            std.debug.print("g\n", .{});
            return null;
        }

        self.start += total_len;
        return unprocessed[8..total_len];
    }

    fn ensureSpace(self: *Reader, space: usize) error{BufferTooSmall}!void {
        const buf = self.buf;
        if (buf.len < space) {
            return error.BufferTooSmall;
        }

        const start = self.start;
        const spare = buf.len - start;
        if (spare >= space) {
            return;
        }

        const unprocessed = buf[start..self.pos];
        std.mem.copyForwards(u8, buf[0..unprocessed.len], unprocessed);
        self.start = 0;
        self.pos = unprocessed.len;
    }
};

const Header = extern struct {
    length: u32, // 4 bytes
    version: u16, // 2 bytes
    msg_type: u16, // 4 bytes
};
