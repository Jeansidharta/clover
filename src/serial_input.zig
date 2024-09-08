const posix = @import("std").posix;
const Chord = @import("./chords.zig").Chord;
const ExtendedChord = @import("./chords.zig").ExtendedChord;

pub const GeminiKeys = packed struct {
    n6: bool = false,
    n5: bool = false,
    n4: bool = false,
    n3: bool = false,
    n2: bool = false,
    n1: bool = false,
    fun: bool = false,
    _one: bool = true,

    hl: bool = false,
    wl: bool = false,
    pl: bool = false,
    kl: bool = false,
    tl: bool = false,
    s2: bool = false,
    s1: bool = false,
    _zero1: bool = false,

    res2: bool = false,
    res1: bool = false,
    star2: bool = false,
    star1: bool = false,
    ol: bool = false,
    al: bool = false,
    rl: bool = false,
    _zero2: bool = false,

    rr: bool = false,
    fr: bool = false,
    ur: bool = false,
    er: bool = false,
    star4: bool = false,
    star3: bool = false,
    pwr: bool = false,
    _zero3: bool = false,

    dr: bool = false,
    sr: bool = false,
    tr: bool = false,
    gr: bool = false,
    lr: bool = false,
    br: bool = false,
    pr: bool = false,
    _zero4: bool = false,

    zr: bool = false,
    nC: bool = false,
    nB: bool = false,
    nA: bool = false,
    n9: bool = false,
    n8: bool = false,
    n7: bool = false,
    _zero5: bool = false,

    pub fn fmt(self: GeminiKeys) [53]u8 {
        const packet: u48 = @bitCast(self);
        var string: [53]u8 = undefined;
        inline for (0..6) |byte_index| {
            inline for (0..8) |bit_index| {
                const packet_index = (5 - byte_index) * 8 + bit_index;
                const string_index = byte_index * 9 + bit_index;
                string[string_index] = if ((packet & (0x80_00_00_00_00_00 >> packet_index)) == 0) '0' else '1';
            }
            if (byte_index < 5) string[byte_index * 9 + 8] = ' ';
        }
        return string;
    }

    pub fn new(value: u48) GeminiKeys {
        return @bitCast(@byteSwap(value));
    }

    /// Returns a valid GeminiKey instance with all keys pressed
    pub fn new_set() GeminiKeys {
        return GeminiKeys.new(0xFF_7F_7F_7F_7F_7F);
    }

    pub fn toSimpleKey(self: GeminiKeys) Chord {
        return .{
            .hash = self.n1 or self.n2 or self.n3 or self.n4 or self.n5 or self.n6 or self.n7 or self.n8 or self.n9 or self.nA or self.nB or self.nC,
            .left = .{
                .s = self.s1 or self.s2,
                .t = self.tl,
                .k = self.kl,
                .p = self.pl,
                .w = self.wl,
                .h = self.hl,
                .r = self.rl,
                .a = self.al,
                .o = self.ol,
            },
            .star = self.star1 or self.star2 or self.star3 or self.star4,
            .right = .{
                .e = self.er,
                .u = self.ur,
                .f = self.fr,
                .r = self.rr,
                .p = self.pr,
                .b = self.br,
                .l = self.lr,
                .g = self.gr,
                .t = self.tr,
                .s = self.sr,
                .d = self.dr,
                .z = self.zr,
            },
        };
    }

    pub fn toFullKey(self: GeminiKeys) ExtendedChord {
        return .{
            .function = self.fun,
            .left = .{
                .s1 = self.s1,
                .s2 = self.s2,
                .t = self.tl,
                .k = self.kl,
                .p = self.pl,
                .w = self.wl,
                .h = self.hl,
                .r = self.rl,
                .a = self.al,
                .o = self.ol,
                .n1 = self.n1,
                .n2 = self.n2,
                .n3 = self.n3,
                .n4 = self.n4,
                .n5 = self.n5,
                .n6 = self.n6,
            },
            .star1 = self.star1,
            .star2 = self.star2,
            .star3 = self.star3,
            .star4 = self.star4,
            .reset1 = self.res1,
            .reset2 = self.res2,
            .power = self.pwr,
            .right = .{
                .e = self.er,
                .u = self.ur,
                .f = self.fr,
                .r = self.rr,
                .p = self.pr,
                .b = self.br,
                .l = self.lr,
                .g = self.gr,
                .t = self.tr,
                .s = self.sr,
                .d = self.dr,
                .z = self.zr,
                .n7 = self.n7,
                .n8 = self.n8,
                .n9 = self.n9,
                .nA = self.nA,
                .nB = self.nB,
                .nC = self.nC,
            },
        };
    }
};

pub const SerialInput = struct {
    fd: posix.fd_t,

    pub fn open(path: []const u8) !SerialInput {
        const fd = try posix.open(path, .{ .ACCMODE = .RDONLY, .NOCTTY = true, .SYNC = true, .DSYNC = true }, 0);

        var attrs = try posix.tcgetattr(fd);

        // Default gemini baud rate
        attrs.ispeed = .B9600;
        attrs.ospeed = .B9600;

        // Makes the terminal file descriptor not buffer until a newline character
        attrs.lflag.ICANON = false;
        // Disables XON/XOFF control flow. Required to receive some packets
        attrs.iflag.IXON = false;

        // std.debug.print("iflag: {any}\n\noflag: {any}\n\ncflag: {any}\n\nlflag: {any}\n\n", .{ attrs.iflag, attrs.oflag, attrs.cflag, attrs.lflag });
        try posix.tcsetattr(fd, .NOW, attrs);
        return .{ .fd = fd };
    }

    pub fn close(self: SerialInput) void {
        posix.close(self.fd);
    }

    pub fn read(self: SerialInput) !GeminiKeys {
        var buf: [128]u8 = undefined;
        const bytes = try posix.read(self.fd, &buf);
        if (bytes != 6) return error.IncorrectBytes;
        const gemini_keys: GeminiKeys = @bitCast(buf[0..6].*);
        if (!gemini_keys._one or
            gemini_keys._zero1 or
            gemini_keys._zero2 or
            gemini_keys._zero3 or
            gemini_keys._zero4 or
            gemini_keys._zero5)
        {
            return error.InvalidPacket;
        }
        return gemini_keys;
    }
};
