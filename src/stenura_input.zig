//! This module provides the logic for communicating with steno machines using the Stenura protocol.
//! It was written with Plover's code as a basis, which can be found here:
//! https://github.com/openstenoproject/plover/blob/main/plover/machine/stentura.py
//! It was written and tested with a Elan Mira G2 steno machine.

const posix = @import("std").posix;
const Chord = @import("./chords.zig").Chord;
const ExtendedChord = @import("./chords.zig").ExtendedChord;
const std = @import("std");
const Allocator = std.mem.Allocator;
const ThreadSafeQueue = @import("./utils/thread_safe_queue.zig").ThreadSafeQueue;

const Actions = enum(u16) {
    /// Closes the current file.
    /// p1 is set to one, I don't know why.
    CLOSE = 0x02,

    /// Deletes the specified files. NOP on realtime file.
    /// p1 is set to the ASCII value corresponding to the drive letter, e.g. 'A'.
    /// The filename is specified in the data section.
    DELETE = 0x3,

    /// Unknown
    /// p1 is set to the ASCII value corresponding to the drive letter, e.g. 'A'.
    DISKSTATUS = 0x07,

    /// Opens a file for reading. This action is sticky and causes this file to be
    /// the current file for all following READC packets.
    /// p1 is set to the ASCII value corresponding to the drive letter, e.g. 'A'.
    /// The filename is specified in the data section.
    /// I'm told that if there is an error opening the realtime file then no
    /// strokes have been written yet.
    /// TODO: Check that and implement workaround.
    OPEN = 0x0A,

    /// Reads characters from the currently opened file.
    /// p1 is set to 1, I'm not sure why.
    /// p3 is set to the maximum number of bytes to read but should probably be
    /// 512.
    /// p4 is set to the block number.
    /// p5 is set to the starting byte offset within the block.
    /// It's possible that the machine will ignore the positional arguments to
    /// READC when reading from the realtime file and just return successive values
    /// for each call.
    /// The response will have the number of bytes read in p1 (but the same is
    /// deducible from the length). The data section will have the contents read
    /// from the file.
    READC = 0x0B,

    /// Unknown
    RESET = 0x14,

    /// Unknown
    TERM = 0x15,

    /// Returns the DOS filenames for the files in the requested drive.
    /// p1 is set to the ASCII value corresponding to the drive letter, e.g. 'A'.
    /// p2 is set to one to return the name of the realtime file (which is always
    /// 'REALTIME.000').
    /// p3 controls which page to return, with 20 filenames per page.
    /// The return packet contains a data section that is 512 bytes long. The first
    /// bytes seems to be one. The filename for the first file starts at offset 32.
    /// My guess would be that the other filenames would exist at a fixed offset of
    /// 24 bytes apart. So first filename is at 32, second is at 56, third at 80,
    /// etc. There seems to be some meta data stored after the filename but I don't
    /// know what it means.
    GETDOS = 0x18,

    /// Unknown
    DIAG = 0x19,
};

const RequestPacketHeader = packed struct {
    const Self = @This();
    const sizeof = @bitSizeOf(Self) / 8;

    var lastSeq: u8 = 0;

    /// Always set to ASCII SOH (0x1).
    SOH: u8 = 0x1,

    /// The sequence number of this packet.
    seq: u8,

    /// The total length of the packet, including the data
    /// section, in bytes
    len: u16,

    /// The action requested.
    action: u16,

    /// Parameter 1. The values for the parameters depend on the
    /// action.
    parameter1: u16 = 0,
    /// Parameter 2
    parameter2: u16 = 0,
    /// Parameter 3
    parameter3: u16 = 0,
    /// Parameter 4
    parameter4: u16 = 0,
    /// Parameter 5
    parameter5: u16 = 0,
    /// The CRC is computed over the packet from seq through p5
    checksum: u16 = 0,

    fn toLittle(self: *Self) void {
        const nativeToLittle = std.mem.nativeToLittle;
        self.action = nativeToLittle(u16, self.action);
        self.len = nativeToLittle(u16, self.len);
        self.parameter1 = nativeToLittle(u16, self.parameter1);
        self.parameter2 = nativeToLittle(u16, self.parameter2);
        self.parameter3 = nativeToLittle(u16, self.parameter3);
        self.parameter4 = nativeToLittle(u16, self.parameter4);
        self.parameter5 = nativeToLittle(u16, self.parameter5);
        self.checksum = nativeToLittle(u16, self.checksum);
    }

    pub fn writeToFd(self: Self, fd: posix.fd_t) !usize {
        var littleEndianSelf = self;
        littleEndianSelf.toLittle();
        return posix.write(fd, &@as([RequestPacketHeader.sizeof]u8, @bitCast(littleEndianSelf)));
    }
};

const PacketData = struct {
    const Self = @This();

    data: []const u8,
    checksum: u16 = 0,

    fn toLittle(self: *Self) void {
        self.checksum = std.mem.nativeToLittle(u16, self.checksum);
    }

    pub fn writeToFd(self: Self, fd: posix.fd_t) !usize {
        var littleEndianSelf = self;
        littleEndianSelf.toLittle();

        var written: usize = 0;
        written += try posix.write(fd, self.data);
        written += try posix.write(fd, &@as([2]u8, @bitCast(littleEndianSelf.checksum)));
        return written;
    }
};

const RequestPacket = struct {
    const Self = @This();
    const sizeof = @bitSizeOf(Self) / 8;

    header: RequestPacketHeader,
    data: ?PacketData = null,

    pub fn init(action: Actions, parameters: []const u16, data: ?[]const u8) Self {
        var params = [_]u16{0} ** 5;
        std.debug.assert(parameters.len <= 5);
        std.mem.copyForwards(u16, &params, parameters);

        var self: Self = .{
            .header = .{
                .seq = RequestPacketHeader.lastSeq,
                .action = @intFromEnum(action),
                .len = @intCast(RequestPacketHeader.sizeof),
                .parameter1 = params[0],
                .parameter2 = params[1],
                .parameter3 = params[2],
                .parameter4 = params[3],
                .parameter5 = params[4],
            },
        };
        RequestPacketHeader.lastSeq += 1;
        if (data) |d| {
            const packetData: PacketData = .{
                .data = d,
                .checksum = std.mem.nativeToLittle(u16, calculateCrc(d)),
            };
            self.header.len += @intCast(d.len + 2);
            self.data = packetData;
        }
        self.header.checksum = calculateCrc(@as([RequestPacketHeader.sizeof]u8, @bitCast(self.header))[1 .. RequestPacketHeader.sizeof - 2]);
        return self;
    }

    pub fn writeToFd(self: Self, fd: posix.fd_t) !usize {
        var written: usize = 0;
        written += try self.header.writeToFd(fd);
        if (self.data) |data| {
            written += try data.writeToFd(fd);
        }
        return written;
    }

    pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        const action: Actions = @enumFromInt(value.header.action);
        _ = try writer.print("[{}] {s} (", .{ value.header.seq, @tagName(action) });
        if (value.header.parameter1 != 0) _ = try writer.print(" {}", .{value.header.parameter1});
        if (value.header.parameter2 != 0) _ = try writer.print(" {}", .{value.header.parameter2});
        if (value.header.parameter3 != 0) _ = try writer.print(" {}", .{value.header.parameter3});
        if (value.header.parameter4 != 0) _ = try writer.print(" {}", .{value.header.parameter4});
        if (value.header.parameter5 != 0) _ = try writer.print(" {}", .{value.header.parameter5});
        _ = try writer.write(" )");
        if (value.data) |packetData| _ = try writer.print(" => {s}", .{packetData.data});
    }
};

const ResponsePacketHeader = packed struct {
    const Self = @This();
    const sizeof = @bitSizeOf(Self) / 8;

    /// Always set to ASCII SOH (0x1)
    SOH: u8 = 0x1,
    /// The sequence number of the request packet.
    seq: u8,
    /// The total length of the packet, including the data section, in bytes.
    len: u16,
    /// The action of the request packet.
    action: u16,
    /// The error code. Zero if no error.
    err: u16,
    /// Parameter 1. The values of the parameters depend on the action.
    parameter1: u16 = 0,
    /// Parameter 2
    parameter2: u16 = 0,
    /// The CRC is computed over the packet from seq through p2.
    checksum: u16,

    fn toNative(self: *Self) void {
        const littleToNative = std.mem.littleToNative;
        self.len = littleToNative(u16, self.len);
        self.action = littleToNative(u16, self.action);
        self.err = littleToNative(u16, self.err);
        self.parameter1 = littleToNative(u16, self.parameter1);
        self.parameter2 = littleToNative(u16, self.parameter2);
        self.checksum = littleToNative(u16, self.checksum);
    }

    pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        const action: Actions = @enumFromInt(value.action);
        _ = try writer.print("[{}] {s} (", .{ value.seq, @tagName(action) });
        if (value.parameter1 != 0) _ = try writer.print(" {}", .{value.parameter1});
        if (value.parameter2 != 0) _ = try writer.print(" {}", .{value.parameter2});
        _ = try writer.write(" )");
        if (value.err != 0) _ = try writer.print(" !ERROR {}! ", .{value.err});
    }
};

const ResponsePacket = struct {
    const Self = @This();
    const sizeof = @bitSizeOf(Self) / 8;

    header: ResponsePacketHeader,
    data: ?PacketData,
    allocator: Allocator,

    fn readFromFd(fd: posix.fd_t, allocator: Allocator) !ResponsePacket {
        const header = blk: {
            var buffer: [ResponsePacketHeader.sizeof]u8 = undefined;
            var bytesRead: usize = 0;
            while (bytesRead < buffer.len) {
                bytesRead += try posix.read(fd, buffer[bytesRead..]);
            }
            var header: ResponsePacketHeader = @bitCast(buffer);
            header.toNative();
            break :blk header;
        };
        const data: ?PacketData = blk: {
            if (header.len < ResponsePacketHeader.sizeof) {
                std.log.warn("Stenura Response: Received packet with header len smaller than header size\n", .{});
                break :blk null;
            } else if (header.len == ResponsePacketHeader.sizeof) {
                break :blk null;
            } else if (header.len < ResponsePacketHeader.sizeof + 2) {
                std.log.warn("Stenura Response: Received header len with unsuficient size for data\n", .{});
                // Must have at least two bytes in length to accomoate the checksum
                break :blk null;
            }
            const dataLen: usize = @as(usize, header.len) - ResponsePacketHeader.sizeof - 2;
            var data: []u8 = try allocator.alloc(u8, dataLen);
            errdefer allocator.free(data);
            var bytesRead: usize = 0;
            while (bytesRead < dataLen) {
                bytesRead += try posix.read(fd, data[bytesRead..dataLen]);
            }
            var dataChecksum: [2]u8 = undefined;
            bytesRead = 0;
            while (bytesRead < 2) {
                bytesRead += try posix.read(fd, dataChecksum[bytesRead..2]);
            }
            const checksum: u16 = @bitCast(dataChecksum);
            const packetData: PacketData = .{ .data = data, .checksum = checksum };
            break :blk packetData;
        };
        return .{ .data = data, .header = header, .allocator = allocator };
    }

    pub fn deinit(self: Self) void {
        if (self.data) |packageData| {
            self.allocator.free(packageData.data);
        }
    }

    pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        _ = try writer.print("{}", .{value.header});
        if (value.data) |packetData| _ = try writer.print(" => {s}", .{packetData.data});
    }
};

// AA
//  10101010
/// 11^#STKP 11WHRAO* 11EUFRPB 11LGTSDZ
const StenuraStroke = packed struct {
    const Self = @This();

    pr: bool,
    k: bool,
    tr: bool,
    sr: bool,
    hash: bool,
    stenomark: bool,
    _bit1: bool = 1,
    _bit2: bool = 1,

    star: bool,
    o: bool,
    a: bool,
    rr: bool,
    h: bool,
    w: bool,
    _bit3: bool = 1,
    _bit4: bool = 1,

    b: bool,
    pl: bool,
    rl: bool,
    f: bool,
    u: bool,
    e: bool,
    _bit5: bool = 1,
    _bit6: bool = 1,

    z: bool,
    d: bool,
    sl: bool,
    tl: bool,
    g: bool,
    l: bool,
    _bit7: bool = 1,
    _bit8: bool = 1,

    pub fn toChord(self: Self) Chord {
        return .{
            .hash = self.hash,
            .left = .{
                .s = self.sr,
                .t = self.tr,
                .k = self.k,
                .p = self.pr,
                .w = self.w,
                .h = self.h,
                .r = self.rr,
                .a = self.a,
                .o = self.o,
            },
            .star = self.star,
            .right = .{
                .e = self.e,
                .u = self.u,
                .f = self.f,
                .r = self.rl,
                .p = self.pl,
                .b = self.b,
                .l = self.l,
                .g = self.g,
                .t = self.tl,
                .s = self.sl,
                .d = self.d,
                .z = self.z,
            },
        };
    }
};

fn makeOpenRequest() RequestPacket {
    return RequestPacket.init(
        Actions.OPEN,
        &[_]u16{'A'},
        "REALTIME.000",
    );
}

fn makeReadcRequest(startOffset: u16) RequestPacket {
    const param1: u16 = 1;
    const param2: u16 = 1;
    const maxBytesToRead: u16 = 512;
    const blockNumber: u16 = 0;
    return RequestPacket.init(
        Actions.READC,
        &[_]u16{
            param1,
            param2,
            maxBytesToRead,
            blockNumber,
            startOffset,
        },
        null,
    );
}

/// Compute the Crc algorithm used by the stentura protocol.
///
/// This algorithm is described by the Rocksoft^TM Model CRC Algorithm as
/// follows:
/// Name   : "CRC-16"
/// Width  : 16
/// Poly   : 8005
/// Init   : 0000
/// RefIn  : True
/// RefOut : True
/// XorOut : 0000
/// Check  : BB3D
const _CRC_TABLE = [_]u16{ 0x0000, 0xc0c1, 0xc181, 0x0140, 0xc301, 0x03c0, 0x0280, 0xc241, 0xc601, 0x06c0, 0x0780, 0xc741, 0x0500, 0xc5c1, 0xc481, 0x0440, 0xcc01, 0x0cc0, 0x0d80, 0xcd41, 0x0f00, 0xcfc1, 0xce81, 0x0e40, 0x0a00, 0xcac1, 0xcb81, 0x0b40, 0xc901, 0x09c0, 0x0880, 0xc841, 0xd801, 0x18c0, 0x1980, 0xd941, 0x1b00, 0xdbc1, 0xda81, 0x1a40, 0x1e00, 0xdec1, 0xdf81, 0x1f40, 0xdd01, 0x1dc0, 0x1c80, 0xdc41, 0x1400, 0xd4c1, 0xd581, 0x1540, 0xd701, 0x17c0, 0x1680, 0xd641, 0xd201, 0x12c0, 0x1380, 0xd341, 0x1100, 0xd1c1, 0xd081, 0x1040, 0xf001, 0x30c0, 0x3180, 0xf141, 0x3300, 0xf3c1, 0xf281, 0x3240, 0x3600, 0xf6c1, 0xf781, 0x3740, 0xf501, 0x35c0, 0x3480, 0xf441, 0x3c00, 0xfcc1, 0xfd81, 0x3d40, 0xff01, 0x3fc0, 0x3e80, 0xfe41, 0xfa01, 0x3ac0, 0x3b80, 0xfb41, 0x3900, 0xf9c1, 0xf881, 0x3840, 0x2800, 0xe8c1, 0xe981, 0x2940, 0xeb01, 0x2bc0, 0x2a80, 0xea41, 0xee01, 0x2ec0, 0x2f80, 0xef41, 0x2d00, 0xedc1, 0xec81, 0x2c40, 0xe401, 0x24c0, 0x2580, 0xe541, 0x2700, 0xe7c1, 0xe681, 0x2640, 0x2200, 0xe2c1, 0xe381, 0x2340, 0xe101, 0x21c0, 0x2080, 0xe041, 0xa001, 0x60c0, 0x6180, 0xa141, 0x6300, 0xa3c1, 0xa281, 0x6240, 0x6600, 0xa6c1, 0xa781, 0x6740, 0xa501, 0x65c0, 0x6480, 0xa441, 0x6c00, 0xacc1, 0xad81, 0x6d40, 0xaf01, 0x6fc0, 0x6e80, 0xae41, 0xaa01, 0x6ac0, 0x6b80, 0xab41, 0x6900, 0xa9c1, 0xa881, 0x6840, 0x7800, 0xb8c1, 0xb981, 0x7940, 0xbb01, 0x7bc0, 0x7a80, 0xba41, 0xbe01, 0x7ec0, 0x7f80, 0xbf41, 0x7d00, 0xbdc1, 0xbc81, 0x7c40, 0xb401, 0x74c0, 0x7580, 0xb541, 0x7700, 0xb7c1, 0xb681, 0x7640, 0x7200, 0xb2c1, 0xb381, 0x7340, 0xb101, 0x71c0, 0x7080, 0xb041, 0x5000, 0x90c1, 0x9181, 0x5140, 0x9301, 0x53c0, 0x5280, 0x9241, 0x9601, 0x56c0, 0x5780, 0x9741, 0x5500, 0x95c1, 0x9481, 0x5440, 0x9c01, 0x5cc0, 0x5d80, 0x9d41, 0x5f00, 0x9fc1, 0x9e81, 0x5e40, 0x5a00, 0x9ac1, 0x9b81, 0x5b40, 0x9901, 0x59c0, 0x5880, 0x9841, 0x8801, 0x48c0, 0x4980, 0x8941, 0x4b00, 0x8bc1, 0x8a81, 0x4a40, 0x4e00, 0x8ec1, 0x8f81, 0x4f40, 0x8d01, 0x4dc0, 0x4c80, 0x8c41, 0x4400, 0x84c1, 0x8581, 0x4540, 0x8701, 0x47c0, 0x4680, 0x8641, 0x8201, 0x42c0, 0x4380, 0x8341, 0x4100, 0x81c1, 0x8081, 0x4040 };
fn calculateCrc(data: []const u8) u16 {
    var checksum: u16 = 0;
    for (data) |byte| {
        checksum = (_CRC_TABLE[(checksum ^ byte) & 0xff] ^
            ((checksum >> 8) & 0xff));
    }
    return checksum;
}

pub const Message = struct {
    const Self = @This();
    /// CALLBACK DOES NOT OWN MEMORY
    const ResponseCallback = *const fn (res: *Self, response: ResponsePacket) void;
    const TimeoutCallback = *const fn (res: *Self) void;

    requestPacket: RequestPacket,
    sentInstant: std.time.Instant,
    tries: u8,
    responseCallback: ResponseCallback = emptyResponseCallback,
    timeoutCallback: TimeoutCallback = emptyTimeoutCallback,
    inputInstance: *StenuraInput,

    fn emptyResponseCallback(_: *const Self, res: ResponsePacket) void {
        res.deinit();
    }
    fn emptyTimeoutCallback(_: *const Self) void {}
};

fn readWorker(input: *StenuraInput, allocator: Allocator, fd: std.posix.fd_t) !void {
    while (true) {
        const response = try ResponsePacket.readFromFd(fd, allocator);
        var message = blk: {
            input.messagePollMutex.lock();
            defer input.messagePollMutex.unlock();
            for (input.messagesPool.items, 0..) |message, index| {
                if (message.requestPacket.header.seq == response.header.seq) {
                    const mes = input.messagesPool.orderedRemove(index);
                    break :blk mes;
                }
            }
            std.log.warn("Stenura Serial Input: Received response packet with unmatching seq {}\n", .{response.header.seq});
            response.deinit();
            continue;
        };
        message.responseCallback(&message, response);
    }
}

fn retrierWorker(input: *StenuraInput, fd: std.posix.fd_t) !void {
    const maxTries: u8 = 3;
    const milisecond = 1e6;
    const retryTime: u64 = 4 * 500 * milisecond; // This number was copied from Plover
    while (true) {
        const now = try std.time.Instant.now();
        var smallestRetryTime = retryTime;
        {
            input.messagePollMutex.lock();
            defer input.messagePollMutex.unlock();
            for (input.messagesPool.items) |*message| {
                const since = if (now.order(message.sentInstant) == .gt) now.since(message.sentInstant) else 0;
                const timeTillNextRetry =
                    if (since > message.tries * retryTime)
                blk: {
                    if (message.tries >= maxTries) {
                        message.timeoutCallback(message);
                        break :blk retryTime;
                    }
                    std.log.info("Retrying message {} for the {}th time", .{ message.requestPacket.header.seq, message.tries });
                    _ = try message.requestPacket.writeToFd(fd);
                    message.tries += 1;
                    break :blk retryTime;
                } else message.tries * retryTime - since;
                if (timeTillNextRetry < smallestRetryTime) smallestRetryTime = timeTillNextRetry;
            }
        }
        std.time.sleep(smallestRetryTime);
    }
}

fn pollingWorker(input: *StenuraInput, fd: std.posix.fd_t, startOffset: u16) !void {
    const pollInterval = 100 * 1e6; // 100 ms
    var offset: u16 = startOffset;
    while (true) {
        const readcRequest = makeReadcRequest(offset);
        // std.log.info("Polling {}", .{readcRequest});
        const response = try input.sendRequestSync(fd, readcRequest);
        if (response.header.err != 0) {
            std.log.err("Received error message: {}", .{response.header.err});
            continue;
        }
        offset += response.header.parameter1;
        if (response.data) |packetData| {
            // std.log.info("Response {} => ({}) {x}", .{ response.header, packetData.data.len, packetData.data });

            const data = packetData.data;
            if (data.len % 4 != 0) {
                std.log.warn("Chord data length is not a multiple of 4", .{});
            }
            for (0..data.len / 4) |i| {
                const chordBits = data[i .. i + 4][0..4];
                const stenuraStroke: StenuraStroke = @bitCast(chordBits.*);
                input.chordQueue.push(stenuraStroke.toChord());
            }
        }
        std.time.sleep(pollInterval);
    }
    return;
}

/// Once initted, this structure should be pinned on memory. Cannot be moved.
pub const StenuraInput = struct {
    const Self = @This();
    const MessagesPool = std.ArrayList(Message);
    const ChordQueue = ThreadSafeQueue(Chord, 1024);

    messagesPool: MessagesPool,
    messagePollMutex: std.Thread.Mutex = .{},
    syncEvent: std.Thread.ResetEvent = .{},
    syncEventData: ?ResponsePacket = null,
    chordQueue: ChordQueue = ChordQueue.init(),
    fd: posix.fd_t,

    fn sendRequest(self: *Self, fd: posix.fd_t, request: RequestPacket, responseCallback: ?Message.ResponseCallback, timeoutCallback: ?Message.TimeoutCallback) !void {
        {
            self.messagePollMutex.lock();
            defer self.messagePollMutex.unlock();
            try self.messagesPool.append(Message{
                .responseCallback = responseCallback orelse Message.emptyResponseCallback,
                .timeoutCallback = timeoutCallback orelse Message.emptyTimeoutCallback,
                .sentInstant = try std.time.Instant.now(),
                .tries = 1,
                .requestPacket = request,
                .inputInstance = self,
            });
        }
        _ = try request.writeToFd(fd);
    }

    fn setSyncEventSuccess(message: *Message, response: ResponsePacket) void {
        if (message.inputInstance.syncEventData) |data| data.deinit();
        message.inputInstance.syncEventData = response;
        message.inputInstance.syncEvent.set();
    }
    fn setSyncEventTimeout(response: *Message) void {
        response.inputInstance.syncEvent.set();
    }

    fn sendRequestSync(self: *Self, fd: posix.fd_t, request: RequestPacket) !ResponsePacket {
        self.syncEvent.reset();
        if (self.syncEventData) |data| data.deinit();
        self.syncEventData = null;
        try self.sendRequest(fd, request, setSyncEventSuccess, setSyncEventTimeout);
        self.syncEvent.wait();
        return self.syncEventData orelse error.Timeout;
    }

    pub fn read(self: *Self) Chord {
        return self.chordQueue.pop();
    }

    pub fn init(allocator: Allocator, path: []const u8) !*Self {
        const fd = try posix.open(path, .{
            .ACCMODE = .RDWR,
            .NOCTTY = true,
            .SYNC = true,
            .DSYNC = true,
            // .NONBLOCK = true,
        }, 0);

        var attrs = try posix.tcgetattr(fd);

        // Default baud rate
        attrs.ispeed = .B9600;
        attrs.ospeed = .B9600;

        // Makes the terminal file descriptor not buffer until a newline character
        attrs.lflag.ICANON = false;
        // Disables XON/XOFF control flow. Required to receive some packets
        attrs.iflag.IXON = false;

        const self: *Self = try allocator.create(Self);
        self.* = StenuraInput{
            .fd = fd,
            .messagesPool = MessagesPool.init(allocator),
            .messagePollMutex = .{},
            .syncEvent = .{},
            .syncEventData = null,
        };

        try posix.tcsetattr(fd, .NOW, attrs);

        _ = try std.Thread.spawn(.{ .allocator = allocator }, retrierWorker, .{ self, fd });
        _ = try std.Thread.spawn(.{ .allocator = allocator }, readWorker, .{ self, allocator, fd });

        const openRequest = makeOpenRequest();
        _ = try self.sendRequestSync(fd, openRequest);

        var offset: u16 = 0;
        var wasEmpty = false;
        while (!wasEmpty) {
            const readcRequest = makeReadcRequest(offset);
            const response = try self.sendRequestSync(fd, readcRequest);
            offset += response.header.parameter1;
            wasEmpty = response.data == null;
        }

        _ = try std.Thread.spawn(.{ .allocator = allocator }, pollingWorker, .{ self, fd, offset });
        return self;
    }

    pub fn close(self: Self) void {
        posix.close(self.fd);
    }
};
