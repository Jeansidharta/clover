const std = @import("std");

pub const Chord = struct {
    hash: bool = false,
    left: struct {
        s: bool = false,
        t: bool = false,
        k: bool = false,
        p: bool = false,
        w: bool = false,
        h: bool = false,
        r: bool = false,
        a: bool = false,
        o: bool = false,
    } = .{},
    star: bool = false,
    right: struct {
        e: bool = false,
        u: bool = false,
        f: bool = false,
        r: bool = false,
        p: bool = false,
        b: bool = false,
        l: bool = false,
        g: bool = false,
        t: bool = false,
        s: bool = false,
        d: bool = false,
        z: bool = false,
    } = .{},

    fn keysTranslations(self: Chord) [24]([]const u8) {
        return [_]([]const u8){
            if (self.hash) "#" else "_",
            if (self.left.s) "S" else "_",
            if (self.left.t) "T" else "_",
            if (self.left.k) "K" else "_",
            if (self.left.p) "P" else "_",
            if (self.left.w) "W" else "_",
            if (self.left.h) "H" else "_",
            if (self.left.r) "R" else "_",
            if (self.left.a) "A" else "_",
            if (self.left.o) "O" else "_",
            if (self.star) "*" else "_",
            "-",
            if (self.right.e) "E" else "_",
            if (self.right.u) "U" else "_",
            if (self.right.f) "F" else "_",
            if (self.right.r) "R" else "_",
            if (self.right.p) "P" else "_",
            if (self.right.b) "B" else "_",
            if (self.right.l) "L" else "_",
            if (self.right.g) "G" else "_",
            if (self.right.t) "T" else "_",
            if (self.right.s) "S" else "_",
            if (self.right.d) "D" else "_",
            if (self.right.z) "Z" else "_",
        };
    }

    fn maxFmtSize() comptime_int {
        // Create a struct that'd have all keys set
        const allSetKeys: Chord = .{
            .hash = true,
            .left = .{
                .s = true,
                .t = true,
                .k = true,
                .p = true,
                .w = true,
                .h = true,
                .r = true,
                .a = true,
                .o = true,
            },
            .star = true,
            .right = .{
                .e = true,
                .u = true,
                .f = true,
                .r = true,
                .p = true,
                .b = true,
                .l = true,
                .g = true,
                .t = true,
                .s = true,
                .d = true,
                .z = true,
            },
        };
        const translations = allSetKeys.keysTranslations();
        var acc = 0;
        for (translations) |translation| {
            acc += translation.len;
        }
        return acc;
    }

    pub fn format(value: Chord, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        // Finds the largest size a string can have. This is to prevent an allocation for formating.
        const translations = value.keysTranslations();
        for (translations) |translation| {
            if (options.width == 0 and translation[0] == '_') {
                continue;
            }
            try writer.writeAll(translation);
        }
    }

    pub fn fromStenoString(keys: []const u8) !Chord {
        var stenoLayout: Chord = .{};
        const stenoOrder = "#STKPWHRAO*EUFRPBLGTSDZ";
        const rightSideIndex = comptime blk: {
            const splitIndex = std.mem.indexOf(u8, stenoOrder, "*").?;
            break :blk (splitIndex + 1);
        };
        const stenoOrderRef = [stenoOrder.len](*bool){
            &stenoLayout.hash,
            &stenoLayout.left.s,
            &stenoLayout.left.t,
            &stenoLayout.left.k,
            &stenoLayout.left.p,
            &stenoLayout.left.w,
            &stenoLayout.left.h,
            &stenoLayout.left.r,
            &stenoLayout.left.a,
            &stenoLayout.left.o,
            &stenoLayout.star,
            &stenoLayout.right.e,
            &stenoLayout.right.u,
            &stenoLayout.right.f,
            &stenoLayout.right.r,
            &stenoLayout.right.p,
            &stenoLayout.right.b,
            &stenoLayout.right.l,
            &stenoLayout.right.g,
            &stenoLayout.right.t,
            &stenoLayout.right.s,
            &stenoLayout.right.d,
            &stenoLayout.right.z,
        };

        var lastKey: usize = 0;
        for (keys) |rawKey| {
            const key = blk: { // Handles number notation
                const newKeyOpt: ?u8 = switch (rawKey) {
                    '1' => 'S',
                    '2' => 'T',
                    '3' => 'P',
                    '4' => 'H',
                    '5' => 'A',
                    '0' => 'O',
                    '6' => 'F',
                    '7' => 'P',
                    '8' => 'L',
                    '9' => 'T',
                    else => null,
                };
                if (newKeyOpt) |newKey| {
                    stenoLayout.hash = true;
                    break :blk newKey;
                }
                break :blk rawKey;
            };

            if (key == '-') {

                // This means a left-side character was found before the dash
                if (lastKey > rightSideIndex) return error.InvalidKey;

                lastKey = rightSideIndex;
                continue;
            }
            lastKey += (std.mem.indexOf(u8, stenoOrder[lastKey..], &[_]u8{std.ascii.toUpper(key)}) orelse {
                std.log.err("Error when parsing {s}\n", .{keys});

                return error.InvalidKey;
            });
            stenoOrderRef[lastKey].* = true;

            // Skips the key that was just used
            lastKey += 1;
        }
        return stenoLayout;
    }
};

pub const ExtendedChord = struct {
    function: bool = false,
    left: struct {
        s1: bool = false,
        s2: bool = false,
        t: bool = false,
        k: bool = false,
        p: bool = false,
        w: bool = false,
        h: bool = false,
        r: bool = false,
        a: bool = false,
        o: bool = false,
        n1: bool = false,
        n2: bool = false,
        n3: bool = false,
        n4: bool = false,
        n5: bool = false,
        n6: bool = false,
    } = .{},
    star1: bool = false,
    star2: bool = false,
    star3: bool = false,
    star4: bool = false,
    reset1: bool = false,
    reset2: bool = false,
    power: bool = false,
    right: struct {
        e: bool = false,
        u: bool = false,
        f: bool = false,
        r: bool = false,
        p: bool = false,
        b: bool = false,
        l: bool = false,
        g: bool = false,
        t: bool = false,
        s: bool = false,
        d: bool = false,
        z: bool = false,
        n7: bool = false,
        n8: bool = false,
        n9: bool = false,
        nA: bool = false,
        nB: bool = false,
        nC: bool = false,
    } = .{},

    fn keysTranslations(self: ExtendedChord) [43]([]const u8) {
        return [_]([]const u8){
            if (self.function) "Fn" else ".",
            if (self.left.n1) "#1" else ".",
            if (self.left.n2) "#2" else ".",
            if (self.left.n3) "#3" else ".",
            if (self.left.n4) "#4" else ".",
            if (self.left.n5) "#5" else ".",
            if (self.left.n6) "#6" else ".",
            if (self.left.s1) "S1" else ".",
            if (self.left.s2) "S2" else ".",
            if (self.left.t) "T" else ".",
            if (self.left.k) "K" else ".",
            if (self.left.p) "P" else ".",
            if (self.left.w) "W" else ".",
            if (self.left.h) "H" else ".",
            if (self.left.r) "R" else ".",
            if (self.left.a) "A" else ".",
            if (self.left.o) "O" else ".",
            if (self.star1) "*1" else ".",
            if (self.star2) "*2" else ".",
            if (self.reset1) "re1" else ".",
            if (self.reset2) "re2" else ".",
            "-",
            if (self.power) "pwr" else ".",
            if (self.star3) "*3" else ".",
            if (self.star4) "*4" else ".",
            if (self.right.e) "E" else ".",
            if (self.right.u) "U" else ".",
            if (self.right.f) "F" else ".",
            if (self.right.r) "R" else ".",
            if (self.right.p) "P" else ".",
            if (self.right.b) "B" else ".",
            if (self.right.l) "L" else ".",
            if (self.right.g) "G" else ".",
            if (self.right.t) "T" else ".",
            if (self.right.s) "S" else ".",
            if (self.right.d) "D" else ".",
            if (self.right.n7) "#7" else ".",
            if (self.right.n8) "#8" else ".",
            if (self.right.n9) "#9" else ".",
            if (self.right.nA) "#A" else ".",
            if (self.right.nB) "#B" else ".",
            if (self.right.nC) "#C" else ".",
            if (self.right.z) "Z" else ".",
        };
    }

    fn maxFmtSize() comptime_int {
        // Create a FullKeys struct that'd have all keys set
        const allSetKeys: ExtendedChord = .{
            .function = true,
            .left = .{
                .s1 = true,
                .s2 = true,
                .t = true,
                .k = true,
                .p = true,
                .w = true,
                .h = true,
                .r = true,
                .a = true,
                .o = true,
                .n1 = true,
                .n2 = true,
                .n3 = true,
                .n4 = true,
                .n5 = true,
                .n6 = true,
            },
            .star1 = true,
            .star2 = true,
            .star3 = true,
            .star4 = true,
            .reset1 = true,
            .reset2 = true,
            .power = true,
            .right = .{
                .e = true,
                .u = true,
                .f = true,
                .r = true,
                .p = true,
                .b = true,
                .l = true,
                .g = true,
                .t = true,
                .s = true,
                .d = true,
                .z = true,
                .n7 = true,
                .n8 = true,
                .n9 = true,
                .nA = true,
                .nB = true,
                .nC = true,
            },
        };
        const translations = allSetKeys.keysTranslations();
        var acc = 0;
        for (translations) |translation| {
            acc += translation.len;
        }
        return acc;
    }

    fn fmt(self: ExtendedChord) []const u8 {
        // Finds the largest size a string can have. This is to prevent an allocation for formating.
        const maxSize = maxFmtSize();
        const translations = self.keysTranslations();
        // Makes sure the buffer is in static memory
        var fmtString = struct {
            var buf: [maxSize:0]u8 = undefined;
        }.buf;
        var acc: usize = 0;
        for (translations) |translation| {
            @memcpy(fmtString[acc .. acc + translation.len], translation);
            acc += translation.len;
        }
        return fmtString[0..acc];
    }
};

test "parse_simple_keys Example" {
    try std.testing.expectEqual(
        try Chord.fromStenoString("#SR*R"),
        @as(Chord, .{
            .hash = true,
            .left = .{ .s = true, .r = true },
            .star = true,
            .right = .{ .r = true },
        }),
    );
}
test "parse_simple_keys Numbers" {
    try std.testing.expectEqual(
        try Chord.fromStenoString("1234506789"),
        @as(Chord, .{
            .hash = true,
            .left = .{ .s = true, .t = true, .p = true, .h = true, .a = true, .o = true },
            .right = .{ .f = true, .p = true, .l = true, .t = true },
        }),
    );
}
test "parse_simple_keys Double Rs with dashes" {
    try std.testing.expectEqual(
        try Chord.fromStenoString("-R"),
        @as(Chord, .{
            .right = .{ .r = true },
        }),
    );
    try std.testing.expectEqual(
        try Chord.fromStenoString("R-R"),
        @as(Chord, .{
            .left = .{ .r = true },
            .right = .{ .r = true },
        }),
    );
    try std.testing.expectEqual(
        try Chord.fromStenoString("R"),
        @as(Chord, .{
            .left = .{ .r = true },
        }),
    );
    try std.testing.expectEqual(
        try Chord.fromStenoString("RR"),
        @as(Chord, .{
            .left = .{ .r = true },
            .right = .{ .r = true },
        }),
    );
}
test "parse_simple_keys Invalid Keys" {
    try std.testing.expectError(
        error.InvalidKey,
        Chord.fromStenoString("X"),
    );
    try std.testing.expectError(
        error.InvalidKey,
        Chord.fromStenoString("-W"),
    );
    try std.testing.expectError(
        error.InvalidKey,
        Chord.fromStenoString("U-"),
    );
    try std.testing.expectError(
        error.InvalidKey,
        Chord.fromStenoString("KK"),
    );
}
