const std = @import("std");
const Allocator = std.mem.Allocator;
const SerialInput = @import("../serial_input.zig").SerialInput;
const Dictionary = @import("../dictionary.zig").Dictionary;
const DictionaryValue = @import("../dictionary.zig").DictionaryValue;
const Chord = @import("../chords.zig").Chord;
const DictionaryNode = @import("../dictionary.zig").DictionaryNode;
const XorgClient = @import("../x11.zig").XorgClient;

const Translation = @import("./init.zig").Translation;

// TODO: Worry about what happens when an undo action is replaced.
// Imagine this dictionary: { "KAT": "cat", "KAT/*/RAOPB": "KATRINA", "*": "=undo" }
// What happens when user hits KAT -> * -> RAOPB?
// It should write "cat", then undo it, and then write "KATRINA"
// Most importantly, it should keep the undo history in a way that if the user hit the * key again
// it should go back to when the user hit KAT -> *
pub const Undo = struct {
    const Self = @This();
    const NodeArrayList = std.ArrayList(*const DictionaryNode);
    const NodeIndexArrayList = std.ArrayList(std.meta.Tuple(&[_]type{ *const DictionaryNode, usize }));

    allocator: Allocator,
    translatorStateChange: struct {
        branchesTrimmed: NodeIndexArrayList,
        branchesReplaced: NodeArrayList,
    },
    /// This is the translation that will be undone if this undo applied
    translation: *const Translation,

    pub fn createInit(allocator: Allocator, translation: *const Translation) !*Self {
        const undo = try allocator.create(Self);
        undo.* = .{
            .allocator = allocator,
            .translatorStateChange = .{
                .branchesTrimmed = NodeIndexArrayList.init(allocator),
                .branchesReplaced = NodeArrayList.init(allocator),
            },
            .translation = translation,
        };
        return undo;
    }

    pub fn destroy(self: *Undo) void {
        self.translatorStateChange.branchesTrimmed.deinit();
        self.translatorStateChange.branchesReplaced.deinit();
        self.allocator.destroy(self);
    }

    pub fn writeTo(self: Self, writerType: type, writer: writerType) !void {
        const toDelete = self.translation.shouldWrite.charactersLen();
        for (0..toDelete + 1) |_| _ = try writer.writeByte(0x16);

        var index = self.translation.shouldRevert.items.len;
        while (index > 0) {
            index -= 1;
            const revert = self.translation.shouldRevert.items[index];
            try writer.writeByte(' ');
            try revert.format("", .{}, writer);
        }
    }
};
