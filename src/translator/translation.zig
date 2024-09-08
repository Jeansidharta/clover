const std = @import("std");
const Allocator = std.mem.Allocator;
const SerialInput = @import("../serial_input.zig").SerialInput;
const Dictionary = @import("../dictionary.zig").Dictionary;
const DictionaryValue = @import("../dictionary.zig").DictionaryValue;
const Chord = @import("../chords.zig").Chord;
const DictionaryNode = @import("../dictionary.zig").DictionaryNode;
const XorgClient = @import("../x11.zig").XorgClient;
const Translator = @import("./init.zig").Translator;

const TranslationType = union(enum) {
    const Self = @This();
    empty,
    dictValue: *const DictionaryValue,
    rawChord: Chord,

    pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .empty => {},
            .dictValue => |dictValue| {
                try dictValue.format(fmt, options, writer);
            },
            .rawChord => |chord| {
                var chordOptions = options;
                chordOptions.width = 0;
                try chord.format(fmt, chordOptions, writer);
            },
        }
    }

    pub fn charactersLen(self: Self) usize {
        return switch (self) {
            .empty => 0,
            .dictValue => |dictValue| dictValue.charactersLen(),
            .rawChord => |chord| {
                var buf = [_:0]u8{0} ** 64;
                const len = (std.fmt.bufPrint(&buf, "{any:0}", .{chord}) catch {
                    return 0;
                }).len;
                return len;
            },
        };
    }
};

pub const Translation = struct {
    const Self = @This();
    const WriteValueArr = std.ArrayList(TranslationType);

    allocator: Allocator,
    shouldWrite: TranslationType = .{ .empty = void{} },
    shouldRevert: WriteValueArr,
    translator: *Translator,

    pub fn createInit(allocator: Allocator, translator: *Translator) !*Self {
        const translation = try allocator.create(Self);
        translation.* = .{
            .allocator = allocator,
            .shouldRevert = WriteValueArr.init(allocator),
            .translator = translator,
        };
        return translation;
    }

    pub fn destroy(self: *Self) void {
        self.shouldRevert.deinit();
        self.allocator.destroy(self);
    }

    pub fn writeTo(self: Translation, writerType: type, writer: writerType) !void {
        for (self.shouldRevert.items) |valueToRevert| {
            for (0..valueToRevert.charactersLen() + 1) |_| _ = try writer.writeByte(0x16);
        }

        switch (self.shouldWrite) {
            .empty => {},
            .dictValue => |dictValue| {
                switch (dictValue.*) {
                    .WriteWord => |word| {
                        _ = try writer.writeByte(' ');
                        _ = try writer.write(word.word);
                    },
                    .Undo => {
                        const firstUndo = self.translator.undoList.popOrNull() orelse return;
                        defer firstUndo.destroy();
                        try self.translator.undoState(firstUndo);

                        const secondUndo = self.translator.undoList.popOrNull() orelse return;
                        defer secondUndo.destroy();
                        try secondUndo.writeTo(writerType, writer);
                        try self.translator.undoState(secondUndo);
                    },
                }
            },
            .rawChord => |chord| {
                try chord.format("", .{ .width = 0 }, writer);
            },
        }
    }
};
