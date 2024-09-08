const std = @import("std");
const Allocator = std.mem.Allocator;
// const SerialInput = @import("./serial_input.zig").SerialInput;
const StenuraInput = @import("./stenura_input.zig").StenuraInput;
const Dictionary = @import("./dictionary.zig").Dictionary;
const DictionaryNode = @import("./dictionary.zig").DictionaryNode;
const Chord = @import("./chords.zig").Chord;
const XorgClient = @import("./x11.zig").XorgClient;
const Translator = @import("./translator/init.zig").Translator;

const errors = error{};

fn xorgWriterFn(xorgClient: XorgClient, bytes: []const u8) errors!usize {
    xorgClient.sendStringToFocusedWindow(bytes);
    return bytes.len;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // const input = try StenuraInput.open("/dev/ttyUSB0");
    const device = "/tmp/link";
    const input = StenuraInput.init(alloc, device) catch |e| {
        switch (e) {
            error.FileNotFound => {
                std.log.err("Input device not found at {s}\n", .{device});
            },
            else => return e,
        }
        return;
    };
    defer input.close();

    var rootDictionary = try Dictionary.init(alloc);
    defer rootDictionary.deinit();

    try rootDictionary.loadFile("main.json");
    try rootDictionary.printTree();

    const xorgClient = try XorgClient.createInit();
    defer xorgClient.deinit();

    var translator = try Translator.init(alloc, rootDictionary.rootNodeDictionary);

    std.debug.print("Reading bytes...\n", .{});
    const xorgWriterType = std.io.GenericWriter(XorgClient, errors, xorgWriterFn);
    const xorgWriter = xorgWriterType{ .context = xorgClient };
    while (true) {
        const chord = input.read();
        std.debug.print("\n{}\n", .{chord});
        const translation = try translator.translate(chord);
        try translation.writeTo(xorgWriterType, xorgWriter);
        xorgClient.flush();
    }
    std.debug.print("All done!", .{});
}

test {
    std.testing.refAllDecls(@This());
}
