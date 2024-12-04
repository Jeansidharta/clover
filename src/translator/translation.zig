const std = @import("std");
const Allocator = std.mem.Allocator;
const SerialInput = @import("../serial_input.zig").SerialInput;
const Dictionary = @import("../dictionary.zig").Dictionary;
const DictionaryValue = @import("../dictionary.zig").DictionaryValue;
const Chord = @import("../chords.zig").Chord;
const DictionaryNode = @import("../dictionary.zig").DictionaryNode;
const SeenValueType = @import("../dictionary.zig").SeenValueType;
const XorgClient = @import("../x11.zig").XorgClient;
const Translator = @import("./init.zig").Translator;

const TranslationType = union(enum) {
    const Self = @This();
    /// Should write nothing
    empty,
    /// Should write what is in the dictionary node
    dictValue: *const DictionaryValue,
    /// Should write the chord the user typed
    rawChord: Chord,

    fn seenTypes(self: Self) SeenValueType {
        return switch (self) {
            .empty | .rawChord => SeenValueType{},
            .dictValue => |value| value.seenTypes(),
        };
    }

    pub fn writeTo(self: Self, previous: Self, writer: anytype) !void {
        switch (self) {
            .empty => {},
            .dictValue => |dictValue| {
                const previousValues = previous.seenTypes();
                // if (previousValues.
            },
            .rawChord => |chord| {
                const chordOptions: std.fmt.FormatOptions = .{ .width = 0 };
                // Forces the chord to be written in its short form
                try chord.format("{}", chordOptions, writer);
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

/// A Translation is what should be returned when calling `Translator.translate`.
/// It should have all the information necessary to write what should be written.
pub const Translation = struct {
    const Self = @This();
    const WriteValueArr = std.ArrayList(TranslationType);

    allocator: Allocator,
    shouldWrite: TranslationType = .{ .empty = void{} },
    shouldRevert: WriteValueArr,
    previousTranslation: ?*const Self = null,
    /// The last chord that created this translation
    chord: Chord,
    translator: *Translator,

    pub fn createInit(allocator: Allocator, chord: Chord, translator: *Translator) !*Self {
        const translation = try allocator.create(Self);
        translation.* = .{
            .allocator = allocator,
            .shouldRevert = WriteValueArr.init(allocator),
            .translator = translator,
            .chord = chord,
        };
        return translation;
    }

    pub fn destroy(self: *Self) void {
        self.shouldRevert.deinit();
        self.allocator.destroy(self);
    }

    pub fn writeTo(self: Self, previous: Self, writerType: type, writer: writerType) !void {
        for (self.shouldRevert.items) |valueToRevert| {
            for (0..valueToRevert.charactersLen() + 1) |_| _ = try writer.writeByte(0x16);
        }

        switch (self.shouldWrite) {
            .empty => {},
            .dictValue => |dictValue| {
                if (dictValue.types.items.len == 1 and dictValue.types.items[0] == .Undo) {
                    const firstUndo = self.translator.undoList.popOrNull() orelse return;
                    defer firstUndo.destroy();
                    try self.translator.undoState(firstUndo);

                    const secondUndo = self.translator.undoList.popOrNull() orelse return;
                    defer secondUndo.destroy();
                    try secondUndo.writeTo(writerType, writer);
                    try self.translator.undoState(secondUndo);
                } else try dictValue.writeTo(writerType, writer);
            },
            .rawChord => |chord| {
                try chord.format("", .{ .width = 0 }, writer);
            },
        }
    }
};
