const std = @import("std");
const Allocator = std.mem.Allocator;
const Chord = @import("./chords.zig").Chord;

pub const SeenValueType = struct {
    Raw: bool = false,
    AttachPrefix: bool = false,
    AttachInfix: bool = false,
    AttachSuffix: bool = false,
    Glue: bool = false,
    CapitalizeNext: bool = false,
    CapitalizePrev: bool = false,
    UncapitalizeNext: bool = false,
    UncapitalizePrev: bool = false,
    CarryCapitalization: bool = false,
    CapsLockMode: bool = false,
    UppercaseNextWord: bool = false,
    UppercasePrevWord: bool = false,
    DoNothing: bool = false,
    Currency: bool = false,
    Conditional: bool = false,
    RepeatLastStroke: bool = false,
    ToggleAsterisk: bool = false,
    InsertSpaceBetweenLastStokes: bool = false,
    RemoveSpaceBetweenLastStokes: bool = false,
    Command: bool = false,
};

const ValueType = union(enum) {
    const Self = @This();

    const Range = struct {
        start: usize,
        len: usize,
        pub fn init(start: usize, len: usize) Range {
            return .{ .start = start, .len = len };
        }
    };

    Raw: Range,
    AttachPrefix: Range,
    AttachInfix: Range,
    AttachSuffix: Range,

    Glue: Range,
    CapitalizeNext,
    CapitalizePrev,
    UncapitalizeNext,
    UncapitalizePrev,
    CarryCapitalization: Range,
    CapsLockMode,
    UppercaseNextWord,
    UppercasePrevWord,
    DoNothing,
    Currency: struct { prefix: Range, suffix: Range },
    Conditional: struct { regex: Range, ifTrue: Range, ifFalse: Range },

    // Macros
    RepeatLastStroke,
    ToggleAsterisk,
    InsertSpaceBetweenLastStokes,
    RemoveSpaceBetweenLastStokes,
    Undo,

    // TODO implement properly commnads, as specified here:
    // https://plover.wiki/index.php/Dictionary_format#Keyboard_Shortcuts
    Command,

    // pub fn charLength(self: Self) usize {
    //     switch (self) {
    //         .Glue => |range| range.len,
    //         .CapitalizeNext => 0,
    //         .CapitalizePrev => 0,
    //         .UncapitalizeNext => 0,
    //         .UncapitalizePrev => 0,
    //         .CarryCapitalization => |range| range.len,
    //         .CapsLockMode => 0,
    //         .UppercaseNextWord => 0,
    //         .UppercasePrevWord => 0,
    //         .DoNothing => 0,
    //         .Currency => |currencyStruct| {},
    //         .Conditional => |conditionalStruct| {},
    //         .RepeatLastStroke => 0,
    //         .ToggleAsterisk => 0,
    //         .InsertSpaceBetweenLastStokes => 0,
    //         .RemoveSpaceBetweenLastStokes => 0,
    //         .Command => 0,
    //     }
    // }
};

pub const DictionaryValue = struct {
    const Self = @This();
    const ValueTypeList = std.ArrayList(ValueType);

    allocator: Allocator,
    rawString: []const u8,
    types: ValueTypeList,

    fn seenTypes(self: Self) SeenValueType {
        var seenValueType: SeenValueType = .{};
        blk: for (self.types.items) |item| {
            inline for (@typeInfo(ValueType).@"enum".fields) |field| {
                if (item == field) {
                    @field(seenValueType, field.name) = true;
                    continue :blk;
                }
            }
        }
        return null;
    }

    pub fn writeTo(self: Self, writerType: type, writer: writerType) !void {
        switch (self) {
            .WriteWord => |word| {
                _ = try writer.writeByte(' ');
                _ = try writer.write(word.word);
            },
        }
    }

    // TODO: implement friendly command names:
    // https://plover.wiki/index.php/Dictionary_format#Escaping_Special_Characters
    // TODO: implement modes
    // https://plover.wiki/index.php/Dictionary_format#Output_Modes
    fn parseTypeString(string: []const u8, offset: usize) !ValueType {
        const startsWith = std.mem.startsWith;
        const endsWith = std.mem.endsWith;
        const eql = std.mem.eql;

        if (string.len == 0) return .{ .DoNothing = {} };
        if (startsWith(u8, string, "~|")) {
            return .{ .CarryCapitalization = .init(offset + 2, string.len) };
        }
        if (startsWith(u8, string, "^~|") and endsWith(u8, string, "^")) {
            return .{ .CarryCapitalization = .init(offset + 3, string.len - 1) };
        }
        if (startsWith(u8, string, "^") and endsWith(u8, string, "^")) {
            return .{ .AttachInfix = .init(offset + 1, string.len - 1) };
        }
        if (startsWith(u8, string, "^")) {
            return .{ .AttachPrefix = .init(offset + 1, string.len) };
        }
        if (endsWith(u8, string, "^")) {
            return .{ .AttachSuffix = .init(offset, string.len - 1) };
        }
        if (endsWith(u8, string, "&")) {
            return .{ .Glue = .init(offset + 1, string.len) };
        }
        if (eql(u8, string, "-|")) {
            return .{ .CapitalizeNext = {} };
        }
        if (eql(u8, string, "*-|")) {
            return .{ .CapitalizePrev = {} };
        }
        if (eql(u8, string, ">")) {
            return .{ .CapitalizeNext = {} };
        }
        if (eql(u8, string, "*>")) {
            return .{ .CapitalizePrev = {} };
        }
        if (eql(u8, string, "*>")) {
            return .{ .CapitalizePrev = {} };
        }
        if (eql(u8, string, "#Caps_Lock") or eql(u8, string, "#caps_lock")) {
            return .{ .CapsLockMode = {} };
        }
        if (eql(u8, string, "<")) {
            return .{ .UppercaseNextWord = {} };
        }
        if (eql(u8, string, "*<")) {
            return .{ .UppercasePrevWord = {} };
        }
        if (startsWith(u8, string, "*(") and endsWith(u8, string, ")")) {
            const currencySpec = string[2 .. string.len - 1];
            const currencyLetterPos = std.mem.indexOf(u8, currencySpec, "c") orelse return error.CurrencyMissingC;
            return .{ .Currency = .{
                .prefix = .init(offset + 2, currencyLetterPos),
                .suffix = .init(offset + 3 + currencyLetterPos, currencySpec.len - 1 - currencyLetterPos),
            } };
        }
        if (startsWith(u8, string, "=")) {
            var splitIter = std.mem.splitScalar(u8, string, '/');
            const regex = splitIter.next() orelse return error.ConditionalMissingRegex;
            const ifTrue = splitIter.next() orelse return error.ConditionalMissingIfTrue;
            const ifFalse = splitIter.next() orelse return error.ConditionalMissingIfFalse;
            return .{ .Conditional = .{
                .regex = .init(offset + 1, regex.len + 1),
                .ifTrue = .init(offset + 2 + regex.len, ifTrue.len),
                .ifFalse = .init(offset + 3 + regex.len + ifTrue.len, ifFalse.len),
            } };
        }
        return error.unknown;
    }

    // TODO: Implement escaping, as specified here:
    // https://plover.wiki/index.php/Dictionary_format#Escaping_Special_Characters
    fn parseTypes(allocator: Allocator, rawString: []const u8) !ValueTypeList {
        var types = ValueTypeList.init(allocator);
        errdefer types.deinit();

        var firstCharInBraces: ?usize = null;
        var firstCharOutsideBraces: usize = 0;
        for (rawString, 0..) |char, index| {
            switch (char) {
                '{' => {
                    if (firstCharOutsideBraces != index)
                        try types.append(.{ .Raw = .{
                            .start = firstCharOutsideBraces,
                            .len = index - firstCharOutsideBraces,
                        } });
                    if (firstCharInBraces) |_| return error.cannotNestType;
                    firstCharInBraces = index + 1;
                },
                '}' => if (firstCharInBraces) |f| {
                    try types.append(try parseTypeString(rawString[f..index], f));
                    firstCharInBraces = null;
                    firstCharOutsideBraces = index + 1;
                } else return error.MissingOpenBracket,
                else => {},
            }
        }
        if (firstCharInBraces) |_| return error.MissingCloseBracket;
        if (firstCharOutsideBraces != rawString.len - 1) {
            try types.append(.{
                .Raw = .{
                    .start = firstCharOutsideBraces,
                    .len = rawString.len - firstCharOutsideBraces - 1,
                },
            });
        }
        return types;
    }

    /// Does not take ownership of string
    pub fn fromString(allocator: Allocator, string: []const u8) !DictionaryValue {
        const types =
            if (std.mem.eql(u8, string, "=undo"))
        blk: {
            var list = ValueTypeList.init(allocator);
            try list.append(.Undo);
            break :blk list;
        } else try parseTypes(allocator, string);

        return .{
            .allocator = allocator,
            .rawString = try allocator.dupe(u8, string),
            .types = types,
        };
    }

    // TODO: proper deinit
    pub fn deinit(_: *DictionaryValue) void {}

    // pub fn charactersLen(self: DictionaryValue) usize {
    //     switch (self.types) {
    //         .Raw => return self.rawString.len,
    //         .Undo => 0,
    //         .ValueTypeList => |list| {
    //             var sum: usize = 0;
    //             for (list.items) |valueType| {
    //                 sum += valueType.charLength();
    //             }
    //             return sum;
    //         },
    //     }
    // }

    // pub fn format(self: Self, prevTranslation: ?Self, prevStroke: ?Self, writer: anytype) !void {
    //     switch (self.types) {
    //         .Raw => {
    //             return writer.writeAll(self.rawString);
    //         },
    //         .UNDO => return writer.writeAll("UNDO"),
    //         .ValueTypeList => |list| {
    //             for (list.items) |valueType| {
    //                 switch (valueType) {
    //                     .Raw => |range| {
    //                         writer.writeAll(self.rawString[range.start..range.end]);
    //                     },
    //                     .AttachInfix => |range| {},
    //                     .AttachSuffix => |range| {},
    //                     .Glue => |range| {},
    //                     .CapitalizeNext => {},
    //                     .CapitalizePrev => {},
    //                     .UncapitalizeNext => {},
    //                     .UncapitalizePrev => {},
    //                     .CarryCapitalization => {},
    //                     .UppercaseNextWord => {},
    //                     .UppercasePrevWord => {},
    //                     .SuppressNextSpace => {},
    //                     .InsertSpace => {},
    //                     .DoNothing => {},
    //                     .Currency => |specs| {},
    //                     .Conditional => |specs| {},
    //                     .Macro => {},
    //                 }
    //             }
    //         },
    //     }
    // }
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
