const std = @import("std");
const Allocator = std.mem.Allocator;
const SerialInput = @import("../serial_input.zig").SerialInput;
const Dictionary = @import("../dictionary.zig").Dictionary;
const DictionaryValue = @import("../dictionary.zig").DictionaryValue;
const Chord = @import("../chords.zig").Chord;
const DictionaryNode = @import("../dictionary.zig").DictionaryNode;
const XorgClient = @import("../x11.zig").XorgClient;

pub const Translation = @import("./translation.zig").Translation;
pub const Undo = @import("./undo.zig").Undo;

pub const Translator = struct {
    const ArrayList = std.ArrayList(*const DictionaryNode);
    const UndoArrayList = std.ArrayList(*Undo);

    /// Given that the dictionary is implemented as a tree of chords, a "possible branch" is a
    /// branch of the dictionary tree that could still have a word in the next call to the
    /// `translate` method. This `possibleBranches` array is a list of these branches in order of
    /// longest to shortest branch. Another property of this array is that the last branch in the
    /// array will contain the last word that was written.
    possibleBranches: ArrayList,

    /// The root of the dictionary tree
    rootDictionary: *const DictionaryNode,

    undoList: UndoArrayList,

    allocator: Allocator,

    pub fn init(allocator: Allocator, rootDictionary: *const DictionaryNode) !Translator {
        return .{
            .possibleBranches = Translator.ArrayList.init(allocator),
            .rootDictionary = rootDictionary,
            .undoList = UndoArrayList.init(allocator),
            .allocator = allocator,
        };
    }

    /// Note that this function is not pure. It modifies the internal state of the translator.
    /// That means consecutive two calls with the same chord will probably have a different output.
    pub fn translate(self: *Translator, chord: Chord) !*Translation {
        // The object that will eventually be returned. Starts as an empty translation.
        var translation = try Translation.createInit(self.allocator, self);
        errdefer translation.destroy();

        // Object responsible for holding necessary information for an undo
        var undo = try Undo.createInit(self.allocator, translation);
        errdefer undo.destroy();

        var dictValueToOutputOpt: ?*const DictionaryValue = null;
        var index: isize = 0;
        // Looks for the first branch with a non-null output
        // Use an index because the array will be mutated in the loop
        while (index < self.possibleBranches.items.len) : (index += 1) {
            const branch = self.possibleBranches.items[@intCast(index)];
            if (branch.processChord(chord)) |child| {
                // Replace the branch with its child.
                //
                // This @constCast should be okay because we are simply changing the pointer
                // inside the array, and not the array structure or length in any way.
                @constCast(self.possibleBranches.items)[@intCast(index)] = child;
                if (child.value) |*dictValue| {
                    dictValueToOutputOpt = dictValue;
                    // Prevents processing the rest of the array. This is necessary if we want to
                    // be able to revert any previously written branch.
                    break;
                }
            } else {
                // Since we haven't yet found a child with an output, this current
                // branch is just a hipotetical branch that was never actually written.
                // Therefore, we can just remove it from the array.
                const branchTrimmed = self.possibleBranches.orderedRemove(@intCast(index));
                try undo.translatorStateChange.branchesTrimmed.append(.{ branchTrimmed, @intCast(index) });
                // Adjust the index to reflect the recently removed item
                index -= 1;
            }
        }
        if (dictValueToOutputOpt) |dictValueToOutput| {
            translation.shouldWrite = .{ .dictValue = dictValueToOutput };
            // Since we do have a child with an output, we have to revert any previously written
            // outputs. Any branch after the one we found in the array is one that was previously
            // written, and therefore must be reverted. The idea is to remove the remaining
            // branches of the array, reverting each of their respective outputs.

            try translation.shouldRevert.append(.{ .dictValue = &self.possibleBranches.getLast().value.? });
            while (self.possibleBranches.items.len - 1 > index) {
                // By popping the array, we guarantee the property that the last branch in the array
                // has the word that was last written.
                const prev = self.possibleBranches.pop();
                const curr = self.possibleBranches.getLast();
                const n = curr.travelUp(curr.depth() - prev.depth());
                if (n.value) |*value| {
                    try translation.shouldRevert.append(.{ .dictValue = value });
                }

                try undo.translatorStateChange.branchesReplaced.append(prev);
            }
        } else if (self.rootDictionary.processChord(chord)) |newBranch| {
            // Since we have no branch with a word, start a new branch off of the root dictionary.
            //
            // Merge the new node as a possible branch. Note that by always appending the new nodes,
            // we maintain the property that the `possibleBranches` array is sorted from longest to
            // shortest branch.
            try self.possibleBranches.append(newBranch);
            if (newBranch.value) |*dictValueOutput| {
                translation.shouldWrite = .{ .dictValue = dictValueOutput };
            }
        } else {
            translation.shouldWrite = .{ .rawChord = chord };
        }

        try self.undoList.append(undo);
        return translation;
    }

    pub fn undoState(self: *Translator, undo: *const Undo) !void {
        for (self.possibleBranches.items) |*branch| {
            // We are essentially just replacing the branch in the array with it's parent
            //
            // @constCast is allowed here because the array's length or shape does not change. We
            // are simply updating the content of the item in the array.
            //
            // .? is allowed here because these branches should always have a parent.
            branch.* = branch.*.parent.?;
        }

        // Reverse the branches that were trimmed.
        var index = undo.translatorStateChange.branchesTrimmed.items.len;
        while (index > 0) {
            index -= 1;
            const trimmedBranch = undo.translatorStateChange.branchesTrimmed.items[index];
            const branch = trimmedBranch[0];
            const trimIndex = trimmedBranch[1];
            try self.possibleBranches.insert(trimIndex, branch);
        }

        // If a new branch was added in the last chord, it would be a direct child of the root node.
        // Since at the start of this function we replaced every branch with it's parent, this new node
        // would show up here as the root note (identified by not having a parent). Therefore,
        // this undo operation would have to remove that element from the list.
        if (self.possibleBranches.items.len == 0) return;
        if (self.possibleBranches.getLast().parent == null) {
            _ = self.possibleBranches.pop();
        }
    }
};
