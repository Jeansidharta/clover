const std = @import("std");
const Allocator = std.mem.Allocator;
const Chord = @import("./chords.zig").Chord;

pub const DictionaryValue = union(enum) {
    const Self = @This();

    WriteWord: struct {
        word: []const u8,
        allocator: Allocator,
    },
    Undo,

    /// Does not take ownership of string
    pub fn fromString(allocator: Allocator, string: []const u8) !DictionaryValue {
        if (std.mem.eql(u8, string, "=undo")) {
            return .{ .Undo = void{} };
        } else {
            return .{
                .WriteWord = .{
                    .word = try allocator.dupe(u8, string),
                    .allocator = allocator,
                },
            };
        }
    }

    pub fn deinit(self: *DictionaryValue) void {
        switch (self) {
            .WriteWord => |writeWord| {
                writeWord.allocator.free(writeWord.word);
            },
            _ => {},
        }
    }

    pub fn toString(self: DictionaryValue) ?[]const u8 {
        switch (self) {
            .WriteWord => |writeWord| {
                return writeWord.word;
            },
            _ => {
                return null;
            },
        }
    }

    pub fn charactersLen(self: DictionaryValue) usize {
        switch (self) {
            .WriteWord => |writeWord| {
                return writeWord.word.len;
            },
            .Undo => {
                return 0;
            },
        }
    }

    pub fn format(value: DictionaryValue, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (value) {
            .WriteWord => |v| {
                return writer.writeAll(v.word);
            },
            .Undo => return writer.writeAll("UNDO"),
        }
    }
};

/// A dictionary is implemented as a tree of DictionaryNodes. Each node has a HashMap whose key
/// is a Chord and value is a DictionaryNode. Each DictionaryNode has an optional output.
pub const Dictionary = struct {
    const Self = @This();
    rootNodeDictionary: *DictionaryNode,
    allocator: Allocator,

    pub fn init(alloc: Allocator) !Dictionary {
        const rootNodeDictionary = try DictionaryNode.createInit(alloc, null);
        return Dictionary{
            .rootNodeDictionary = rootNodeDictionary,
            .allocator = alloc,
        };
    }

    pub fn loadFile(self: *Self, filePath: []const u8) !void {
        return parseJsonDictionary(self.allocator, self, filePath);
    }

    pub fn insertChordString(self: *Self, chordKey: []const u8, chordValue: []const u8) !void {
        var chordsSplit = std.mem.splitSequence(u8, chordKey, "/");
        var lastNodeDict = &self.rootNodeDictionary.children;
        var lastNode: *DictionaryNode = self.rootNodeDictionary;
        while (chordsSplit.next()) |chordString| {
            const chord = try Chord.fromStenoString(chordString);
            const newNode = if (lastNodeDict.get(chord)) |c| c else blk: {
                var node = try DictionaryNode.createInit(self.allocator, null);
                node.parent = lastNode;
                try lastNodeDict.put(chord, node);
                break :blk node;
            };

            lastNode = newNode;
            lastNodeDict = &newNode.children;
        }

        lastNode.value = try DictionaryValue.fromString(self.allocator, chordValue);
    }

    // TODO: This function has to clean ALL memory. This is mostly a placeholder for now
    pub fn deinit(self: *Dictionary) void {
        self.rootNodeDictionary.destroy();
    }

    fn printNode(node: *const DictionaryNode, key: *const Chord, depth: u32) !void {
        for (0..depth) |_| std.debug.print("    ", .{});
        if (node.value) |output| {
            std.debug.print("|-> {any:0} => \"{s}\"\n", .{ key, output });
        } else {
            std.debug.print("|-> {any:0} => NULL\n", .{key});
        }
        var iterator = node.children.iterator();
        while (iterator.next()) |entry| {
            try printNode(entry.value_ptr.*, entry.key_ptr, depth + 1);
        }
    }

    // Print the dictionary tree
    pub fn printTree(self: Dictionary) !void {
        std.debug.print("ROOT\n", .{});
        var iterator = self.rootNodeDictionary.children.iterator();
        while (iterator.next()) |entry| {
            try printNode(entry.value_ptr.*, entry.key_ptr, 0);
        }
    }
};

pub const DictionaryNode = struct {
    const Self = @This();
    pub const ChildrenHash = std.AutoHashMap(Chord, *Self);

    value: ?DictionaryValue,
    children: ChildrenHash,
    alloc: Allocator,
    parent: ?*Self,

    /// Caller takes ownership of returning pointer
    pub fn createInit(alloc: Allocator, dictValue: ?DictionaryValue) !*Self {
        const obj = try alloc.create(DictionaryNode);
        obj.* = .{
            .alloc = alloc,
            .value = dictValue,
            .children = ChildrenHash.init(alloc),
            .parent = null,
        };
        return obj;
    }

    pub fn destroy(self: *Self) void {
        self.children.deinit();
        // TODO - Figure out freeing for the outputs
        // if (self.output) |output| self.alloc.free(output);
        self.alloc.destroy(self);
    }

    pub fn processChord(self: Self, chord: Chord) ?*const Self {
        return self.children.get(chord);
    }

    pub fn travelUp(self: Self, distance: usize) *const Self {
        var node = &self;
        var dist = distance;
        while (dist > 0) {
            dist -= 1;
            std.debug.assert(node.parent != null);
            node = node.parent.?;
        }
        return node;
    }

    /// `depth` is the distance from the root node.
    pub fn depth(self: Self) u8 {
        var node = &self;
        var dist: u8 = 0;
        while (node.parent) |parent| {
            node = parent;
            dist += 1;
        }
        return dist;
    }

    pub fn findFirstNonEmptyParent(self: Self) ?*DictionaryNode {
        var node = self.parent orelse return null;
        while (node.value == null) {
            node = node.parent orelse return null;
        }
        return node;
    }

    pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        if (value.value) |innerValue| {
            return innerValue.format(fmt, options, writer);
        } else {
            return writer.writeAll("NULL");
        }
    }
};

pub fn parseJsonDictionary(alloc: Allocator, dictionary: *Dictionary, filePath: []const u8) !void {
    const file = try std.fs.cwd().openFile(filePath, .{});
    defer file.close();
    const fileReader = file.reader();

    var reader = std.json.reader(alloc, fileReader);
    defer reader.deinit();
    const json = try std.json.parseFromTokenSource(std.json.Value, alloc, &reader, .{});
    defer json.deinit();

    const rootObj = try switch (json.value) {
        .object => |obj| obj,
        else => error.invalidJson,
    };

    var iter = rootObj.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const word = switch (entry.value_ptr.*) {
            .string => |str| str,
            else => return error.invalidJson,
        };
        try dictionary.insertChordString(key, word);
    }
}
