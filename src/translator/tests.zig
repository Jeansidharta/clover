const std = @import("std");
const Allocator = std.mem.Allocator;
const SerialInput = @import("../serial_input.zig").SerialInput;
const Dictionary = @import("../dictionary.zig").Dictionary;
const DictionaryValue = @import("../dictionary.zig").DictionaryValue;
const Chord = @import("../chords.zig").Chord;
const DictionaryNode = @import("../dictionary.zig").DictionaryNode;
const XorgClient = @import("../x11.zig").XorgClient;

const Translator = @import("./init.zig").Translator;
const Translation = @import("./translation.zig").Translation;
const Undo = @import("./undo.zig").Undo;

const WriteBuffer = struct {
    const errors = error{};
    const Self = @This();
    const Writer = std.io.GenericWriter(*Self, errors, Self.write);
    buffer: [2048:0]u8 = [_:0]u8{0} ** 2048,
    index: usize = 0,

    pub fn slice(self: *Self) []u8 {
        return self.buffer[0..self.index];
    }

    pub fn write(self: *Self, bytes: []const u8) errors!usize {
        var count: usize = 0;
        for (bytes) |byte| {
            count += 1;
            if (byte == 0x16) {
                if (self.index > 0) self.index -= 1;
                self.buffer[self.index] = 0;
            } else {
                self.buffer[self.index] = byte;
                self.index += 1;
            }
        }
        return count;
    }

    pub fn writer(self: *Self) Writer {
        return Writer{ .context = self };
    }

    pub fn compare(self: Self, target: []const u8) bool {
        for (target, 0..) |byte, index| {
            if (byte == self.buffer[index]) continue;
            std.debug.print("{s}\x1b[0;31m{s}\x1b[0m\n" ++ "{s}\x1b[0;32m{s}\x1b[0m\n", .{
                self.buffer[0..index],
                self.buffer[index..self.index],
                target[0..index],
                target[index..],
            });
            for (0..index) |_| std.debug.print(" ", .{});
            std.debug.print("^\n\n", .{});
            return false;
        }
        if (self.index > target.len) {
            std.debug.print("\n{s}\n{s}\n", .{ self.buffer[0..self.index], target });
            for (0..target.len) |_| std.debug.print(" ", .{});
            std.debug.print("^\n\n", .{});
            return false;
        }

        return true;
    }
};

test "Basic Undo" {
    // Initialization code
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var dict = try Dictionary.init(alloc);
    var translator = try Translator.init(alloc, dict.rootNodeDictionary);
    var writeBuffer = WriteBuffer{};

    // #STKPWHRAO*EUFRPBLGTSDZ
    try dict.insertChordString("S", "Batata");
    try dict.insertChordString("T", "Tomate");
    try dict.insertChordString("S/T/K", "Cebola");
    try dict.insertChordString("*", "=undo");

    _ = try (try translator.translate(try Chord.fromStenoString("S"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(" Batata"));
    std.log.err("{s}\n", .{writeBuffer.slice()});

    _ = try (try translator.translate(try Chord.fromStenoString("T"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(" Batata Tomate"));
    std.log.err("{s}\n", .{writeBuffer.slice()});

    _ = try (try translator.translate(try Chord.fromStenoString("K"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(" Cebola"));
    std.log.err("{s}\n", .{writeBuffer.slice()});

    _ = try (try translator.translate(try Chord.fromStenoString("*"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(" Batata Tomate"));
    std.log.err("{s}\n", .{writeBuffer.slice()});

    _ = try (try translator.translate(try Chord.fromStenoString("*"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(" Batata"));
    std.log.err("{s}\n", .{writeBuffer.slice()});

    _ = try (try translator.translate(try Chord.fromStenoString("*"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(""));
    std.log.err("{s}\n", .{writeBuffer.slice()});

    _ = try (try translator.translate(try Chord.fromStenoString("*"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(""));
    std.log.err("{s}\n", .{writeBuffer.slice()});
}

test "Missing Translations" {
    // Initialization code
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var dict = try Dictionary.init(alloc);
    var translator = try Translator.init(alloc, dict.rootNodeDictionary);
    var writeBuffer = WriteBuffer{};

    // #STKPWHRAO*EUFRPBLGTSDZ
    // try dict.insertChordString("H", "Cebola");
    // try dict.insertChordString("K", "Chocolate");
    // try dict.insertChordString("P", "Pimenta");
    try dict.insertChordString("*", "=undo");

    _ = try (try translator.translate(try Chord.fromStenoString("S"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare("S-"));

    _ = try (try translator.translate(try Chord.fromStenoString("*"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(""));
}

test "Real World" {
    // Initialization code
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var dict = try Dictionary.init(alloc);
    var translator = try Translator.init(alloc, dict.rootNodeDictionary);
    var writeBuffer = WriteBuffer{};

    // #STKPWHRAO*EUFRPBLGTSDZ
    try dict.insertChordString("H", "Cebola");
    try dict.insertChordString("K", "Chocolate");
    try dict.insertChordString("P", "Pimenta");
    try dict.insertChordString("*", "=undo");
    try dict.insertChordString("T/P/H", "Tomate");

    _ = try (try translator.translate(try Chord.fromStenoString("T"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(""));

    _ = try (try translator.translate(try Chord.fromStenoString("P"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(" Pimenta"));

    _ = try (try translator.translate(try Chord.fromStenoString("H"))).writeTo(WriteBuffer.Writer, writeBuffer.writer());
    try std.testing.expect(writeBuffer.compare(" Tomate"));
}
