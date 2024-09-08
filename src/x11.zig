const std = @import("std");
const xlib = @cImport({
    @cInclude("X11/Xlib.h");
});
const xcb = @cImport({
    @cInclude("xcb/xproto.h");
});

pub const XorgClient = struct {
    rootWindow: xlib.Window,
    display: *xlib.Display,

    pub fn createInit() !XorgClient {
        // Open default display
        const display = xlib.XOpenDisplay(null) orelse return error.UnableToOpenDisplay;
        const root = xlib.DefaultRootWindow(display);
        return .{ .rootWindow = root, .display = display };
    }

    pub fn deinit(self: XorgClient) void {
        defer _ = xlib.XCloseDisplay(self.display);
    }

    pub fn getInputFocusWindow(self: XorgClient) xlib.Window {
        var window: xlib.Window = undefined;
        var returnState: c_int = undefined;
        _ = xlib.XGetInputFocus(self.display, &window, &returnState);
        return window;
    }

    fn createKeyEvent(self: XorgClient, win: xlib.Window, press: bool, keycode: u32, modifiers: u32) xlib.XKeyEvent {
        var event: xlib.XKeyEvent = undefined;

        event.display = self.display;
        event.window = win;
        event.root = self.rootWindow;
        event.subwindow = xlib.None;
        event.time = xlib.CurrentTime;
        event.x = 1;
        event.y = 1;
        event.x_root = 1;
        event.y_root = 1;
        event.same_screen = xlib.True;
        event.keycode = xlib.XKeysymToKeycode(self.display, keycode);
        event.state = modifiers;
        if (press) {
            event.type = xlib.KeyPress;
        } else event.type = xlib.KeyRelease;

        return event;
    }

    pub fn sendKeycodesToFocusedWindow(self: XorgClient, keycodes: []const u8) void {
        const window = self.getInputFocusWindow();
        var event = self.createKeyEvent(window, true, 0, 0);

        for (keycodes) |keycode| {
            event.keycode = keycode;
            event.type = xlib.KeyPress;
            _ = xlib.XSendEvent(self.display, window, xlib.True, xlib.KeyPressMask, @ptrCast(&event));
            event.type = xlib.KeyRelease;
            _ = xlib.XSendEvent(self.display, window, xlib.True, xlib.KeyReleaseMask, @ptrCast(&event));
        }
    }

    pub fn sendStringToFocusedWindow(self: XorgClient, string: []const u8) void {
        const window = self.getInputFocusWindow();
        var event = self.createKeyEvent(window, true, 0, 0);

        for (string) |char| {
            event.keycode = if (char == 0x16) char else xlib.XKeysymToKeycode(self.display, char);
            event.type = xlib.KeyPress;
            _ = xlib.XSendEvent(self.display, window, xlib.True, xlib.KeyPressMask, @ptrCast(&event));
            event.type = xlib.KeyRelease;
            _ = xlib.XSendEvent(self.display, window, xlib.True, xlib.KeyReleaseMask, @ptrCast(&event));
        }
    }

    pub fn flush(self: XorgClient) void {
        _ = xlib.XFlush(self.display);
    }

    pub fn getActiveWindow(self: XorgClient) xlib.Window {
        const property = xlib.XInternAtom(self.display, "_NET_ACTIVE_WINDOW", xlib.False);
        var type_return: c_ulong = undefined;
        var format_return: c_int = undefined;
        var nitems_return: c_ulong = undefined;
        var bytes_left: c_ulong = undefined;
        var data: [*c]u8 = undefined;
        _ = xlib.XGetWindowProperty(
            self.display,
            self.rootWindow,
            property,
            0,
            1,
            xlib.False,
            33, // XA_WINDOW
            &type_return,
            &format_return,
            &nitems_return,
            &bytes_left,
            &data,
        );
        defer _ = xlib.XFree(data);

        return data[0];
    }
};
