//! The Windows `WebPageBackend`: a WebView2 controller per `WebPage`, hosted
//! in a child window of its own that the native-view host
//! (`Win32NativeHost`) places where its `WebView` is. The engine is the
//! Evergreen WebView2 runtime Windows 10 and 11 ship. `WebView2Loader.dll`
//! is used when it sits beside the executable; without it the runtime's own
//! `EmbeddedBrowserWebView.dll` is found through the registry (as the loader
//! does), so apps need no extra file.
//!
//! WebView2 is asynchronous: `create` returns at once with the page's
//! window, and the environment (one per process) and the page's controller
//! arrive later through the message loop SDL pumps. Until then the address,
//! bridges and origin the page is told are kept and applied when it is ready.
//!
//! Pages post to bridges as they do on macOS, through
//! `window.webkit.messageHandlers.<name>.postMessage(text)`: a script added
//! to every document forwards each to `chrome.webview.postMessage` as JSON
//! naming the bridge, so one page works on both. A message is heard only
//! from the trusted origin (`trust`) and only with a string body.
//! `SourceChanged`, `HistoryChanged` and `DocumentTitleChanged` report the
//! address, title and history; `NavigationCompleted` the failures (a
//! cancelled load is none). Windows only: every caller is behind
//! `os_tag == .windows`.

const std = @import("std");
const log = std.log.scoped(.ziggui_web_view2_backend);
const mod = @import("module.zig");
const views = @import("views");

extern "user32" fn GetClientRect(window: mod.HWND, rect: *mod.RECT) callconv(.winapi) i32;
extern "user32" fn SetWindowLongPtrW(window: mod.HWND, index: i32, value: isize) callconv(.winapi) isize;
extern "user32" fn GetWindowLongPtrW(window: mod.HWND, index: i32) callconv(.winapi) isize;
extern "kernel32" fn LoadLibraryW(name: [*:0]const u16) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetProcAddress(module: ?*anyopaque, name: [*:0]const u8) callconv(.winapi) ?*const anyopaque;
extern "kernel32" fn GetModuleFileNameW(module: ?*anyopaque, name: [*]u16, size: u32) callconv(.winapi) u32;
extern "kernel32" fn GetEnvironmentVariableW(name: [*:0]const u16, buffer: [*]u16, size: u32) callconv(.winapi) u32;
extern "advapi32" fn RegGetValueW(key: usize, sub_key: [*:0]const u16, value: [*:0]const u16, flags: u32, value_type: ?*u32, data: ?*anyopaque, size: ?*u32) callconv(.winapi) i32;

/// WebView2Loader's `CreateCoreWebView2EnvironmentWithOptions`.
const CreateEnvironment = *const fn (browser_folder: ?[*:0]const u16, user_data_folder: ?[*:0]const u16, options: ?*anyopaque, handler: *anyopaque) callconv(.winapi) mod.HRESULT;
/// The runtime's own entry the loader calls (`EmbeddedBrowserWebView.dll`).
const CreateEnvironmentInternal = *const fn (check_running_instance: bool, runtime_type: i32, user_data_folder: ?[*:0]const u16, options: ?*anyopaque, handler: *anyopaque) callconv(.winapi) mod.HRESULT;

/// `ICoreWebView2Environment`'s vtable slots.
const EnvironmentSlot = struct {
    const Self = @This();

    /// `CreateCoreWebView2Controller(HWND, handler)`.
    const create_controller = 3;
};

/// `ICoreWebView2Controller`'s vtable slots.
const ControllerSlot = struct {
    const Self = @This();

    /// `put_IsVisible(BOOL)`.
    const put_is_visible = 4;
    /// `put_Bounds(RECT)`.
    const put_bounds = 6;
    /// `MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON)`.
    const move_focus = 12;
    /// `add_GotFocus(handler, token)`.
    const add_got_focus = 15;
    /// `add_LostFocus(handler, token)`.
    const add_lost_focus = 17;
    /// `NotifyParentWindowPositionChanged()`.
    const notify_parent_window_position_changed = 23;
    /// `Close()`.
    const close = 24;
    /// `get_CoreWebView2(ICoreWebView2**)`.
    const get_core_web_view = 25;
};

/// `ICoreWebView2`'s vtable slots.
const WebViewSlot = struct {
    const Self = @This();

    /// `get_Settings(ICoreWebView2Settings**)`.
    const get_settings = 3;
    /// `get_Source(LPWSTR*)`.
    const get_source = 4;
    /// `Navigate(LPCWSTR)`.
    const navigate = 5;
    /// `add_NavigationStarting(handler, token)`.
    const add_navigation_starting = 7;
    /// `add_SourceChanged(handler, token)`.
    const add_source_changed = 11;
    /// `add_HistoryChanged(handler, token)`.
    const add_history_changed = 13;
    /// `add_NavigationCompleted(handler, token)`.
    const add_navigation_completed = 15;
    /// `AddScriptToExecuteOnDocumentCreated(LPCWSTR, handler)`.
    const add_script_to_execute_on_document_created = 27;
    /// `ExecuteScript(LPCWSTR, handler)`.
    const execute_script = 29;
    /// `Reload()`.
    const reload = 31;
    /// `add_WebMessageReceived(handler, token)`.
    const add_web_message_received = 34;
    /// `get_CanGoBack(BOOL*)`.
    const get_can_go_back = 38;
    /// `get_CanGoForward(BOOL*)`.
    const get_can_go_forward = 39;
    /// `GoBack()`.
    const go_back = 40;
    /// `GoForward()`.
    const go_forward = 41;
    /// `add_DocumentTitleChanged(handler, token)`.
    const add_document_title_changed = 46;
    /// `get_DocumentTitle(LPWSTR*)`.
    const get_document_title = 48;
};

/// `ICoreWebView2Settings`' vtable slots.
const SettingsSlot = struct {
    const Self = @This();

    /// `put_IsStatusBarEnabled(BOOL)`.
    const put_is_status_bar_enabled = 10;
    /// `put_AreHostObjectsAllowed(BOOL)`.
    const put_are_host_objects_allowed = 16;
};

/// The event arguments' vtable slots this backend reads.
const ArgumentsSlot = struct {
    const Self = @This();

    /// `ICoreWebView2WebMessageReceivedEventArgs::get_Source(LPWSTR*)`.
    const message_source = 3;
    /// `ICoreWebView2WebMessageReceivedEventArgs::TryGetWebMessageAsString(LPWSTR*)`.
    const message_string = 5;
    /// `ICoreWebView2NavigationStartingEventArgs::get_Uri(LPWSTR*)`.
    const navigation_uri = 3;
    /// `ICoreWebView2NavigationCompletedEventArgs::get_IsSuccess(BOOL*)`.
    const navigation_success = 3;
    /// `ICoreWebView2NavigationCompletedEventArgs::get_WebErrorStatus(COREWEBVIEW2_WEB_ERROR_STATUS*)`.
    const navigation_status = 4;
};

/// What a `Handler` answers: one WebView2 callback interface each.
const HandlerKind = enum(u32) {
    const Self = @This();

    /// The environment was made (`ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler`).
    environment,
    /// A page's controller was made (`ICoreWebView2CreateCoreWebView2ControllerCompletedHandler`).
    controller,
    /// A bridge message (`ICoreWebView2WebMessageReceivedEventHandler`).
    webMessage,
    /// The address changed (`ICoreWebView2SourceChangedEventHandler`).
    sourceChanged,
    /// The history changed (`ICoreWebView2HistoryChangedEventHandler`).
    historyChanged,
    /// The title changed (`ICoreWebView2DocumentTitleChangedEventHandler`).
    titleChanged,
    /// A load began (`ICoreWebView2NavigationStartingEventHandler`).
    navigationStarting,
    /// A load ended (`ICoreWebView2NavigationCompletedEventHandler`).
    navigationCompleted,
    /// The page took the keyboard (`ICoreWebView2FocusChangedEventHandler`).
    gotFocus,
    /// The page gave the keyboard up (`ICoreWebView2FocusChangedEventHandler`).
    lostFocus,

    /// The interface identifier this kind answers to `QueryInterface`.
    ///
    /// - `self`: the kind.
    /// - Returns: the identifier.
    fn interface(self: *const Self) std.os.windows.GUID {
        return switch (self.*) {
            .environment => std.os.windows.GUID.parse("{4e8a3389-c9d8-4bd2-b6b5-124fee6cc14d}"),
            .controller => std.os.windows.GUID.parse("{6c4819f3-c9b7-4260-8127-c9f5bde7f68c}"),
            .webMessage => std.os.windows.GUID.parse("{57213f19-00e6-49fa-8e07-898ea01ecbd2}"),
            .sourceChanged => std.os.windows.GUID.parse("{3c067f9f-5388-4772-8b48-79f7ef1ab37c}"),
            .historyChanged => std.os.windows.GUID.parse("{c79a420c-efd9-4058-9295-3e8b4bcab645}"),
            .titleChanged => std.os.windows.GUID.parse("{f5f2b923-953e-4042-9f95-f3a118e1afd4}"),
            .navigationStarting => std.os.windows.GUID.parse("{9adbe429-f36d-432b-9ddc-f8881fbd76e3}"),
            .navigationCompleted => std.os.windows.GUID.parse("{d33a35bf-1c49-4f98-93ab-006e0533fe1c}"),
            .gotFocus, .lostFocus => std.os.windows.GUID.parse("{05ea24bd-6452-4926-9014-4b82b498135d}"),
        };
    }
};

/// The vtable every `Handler` shares: `IUnknown` and `Invoke`.
const HandlerVtable = extern struct {
    const Self = @This();

    /// `QueryInterface`.
    query_interface: *const fn (*Handler, *const std.os.windows.GUID, *?*anyopaque) callconv(.winapi) mod.HRESULT,
    /// `AddRef`.
    add_ref: *const fn (*Handler) callconv(.winapi) u32,
    /// `Release`.
    release: *const fn (*Handler) callconv(.winapi) u32,
    /// `Invoke(first, second)`: (HRESULT, object) for a completion, (sender,
    /// arguments) for an event.
    invoke: *const fn (*Handler, usize, ?*anyopaque) callconv(.winapi) mod.HRESULT,
};

/// One WebView2 callback object, reference counted, that names its page by
/// id rather than pointer: WebView2 may release (or call) it after the page
/// is gone, when the lookup simply finds nothing.
const Handler = extern struct {
    const Self = @This();

    /// The COM vtable; first, as COM requires.
    vtable: *const HandlerVtable = &Self.table,
    /// The references held.
    references: u32 = 1,
    /// What it answers.
    kind: HandlerKind,
    /// The page it reports to (`NativePage.id`); 0 for the environment.
    page_id: u64,

    /// The shared vtable.
    const table = HandlerVtable{
        .query_interface = Self.queryInterface,
        .add_ref = Self.addRef,
        .release = Self.release,
        .invoke = Self.invoke,
    };

    /// Makes a handler with one reference, the caller's.
    ///
    /// - `kind`: what it answers.
    /// - `page_id`: the page it reports to.
    /// - Returns: the handler, or null when out of memory.
    fn make(kind: HandlerKind, page_id: u64) ?*Self {
        const handler = std.heap.c_allocator.create(Self) catch |err| {
            log.warn("WebView2 handler not made: {s}", .{@errorName(err)});
            return null;
        };
        handler.* = .{ .kind = kind, .page_id = page_id };
        return handler;
    }

    /// `IUnknown::QueryInterface`: itself for `IUnknown` and its own interface.
    ///
    /// - `self`: the handler.
    /// - `interface`: the interface asked for.
    /// - `object`: receives the interface.
    /// - Returns: `S_OK`, or `E_NOINTERFACE`.
    fn queryInterface(self: *Self, interface: *const std.os.windows.GUID, object: *?*anyopaque) callconv(.winapi) mod.HRESULT {
        const own = self.kind.interface();
        if (std.meta.eql(interface.*, mod.Com.iid_unknown) or std.meta.eql(interface.*, own)) {
            self.references += 1;
            object.* = self;
            return mod.Com.ok;
        }
        object.* = null;
        return mod.Com.no_interface;
    }

    /// `IUnknown::AddRef`.
    ///
    /// - `self`: the handler.
    /// - Returns: the references now held.
    fn addRef(self: *Self) callconv(.winapi) u32 {
        self.references += 1;
        return self.references;
    }

    /// `IUnknown::Release`: frees the handler with its last reference.
    ///
    /// - `self`: the handler.
    /// - Returns: the references left.
    fn release(self: *Self) callconv(.winapi) u32 {
        self.references -= 1;
        const left = self.references;
        if (left == 0) std.heap.c_allocator.destroy(self);
        return left;
    }

    /// `Invoke`: hands the callback to the backend.
    ///
    /// - `self`: the handler.
    /// - `first`: the completion's `HRESULT`, or the event's sender.
    /// - `second`: the object made, or the event's arguments.
    /// - Returns: `S_OK`.
    fn invoke(self: *Self, first: usize, second: ?*anyopaque) callconv(.winapi) mod.HRESULT {
        WebView2Backend.dispatch(self.kind, self.page_id, first, second);
        return mod.Com.ok;
    }
};

/// One `WebPage`'s window and WebView2 objects (each owned), what it was
/// told before they arrived, and what it reports.
const NativePage = struct {
    const Self = @This();

    /// The handlers' name for it, never reused.
    id: u64,
    /// The page it reports to.
    page: *views.WebPage,
    /// The child window the controller draws in; the `NativeView` handle.
    container: mod.HWND,
    /// The `ICoreWebView2Controller`, once made.
    controller: ?*anyopaque = null,
    /// The `ICoreWebView2`, once made.
    web_view: ?*anyopaque = null,
    /// The controller is being made (or waits for the environment).
    creating: bool = true,
    /// The address asked for before the page was ready.
    pending_url: ?[:0]u8 = null,
    /// The origin the bridges hear, or null before it is told.
    trusted_url: ?[:0]u8 = null,
    /// The address the latest top-level load set out for, in the C allocator:
    /// an opaque-origin page (`data:`) posts as `about:blank`, before the web
    /// view reports its address.
    navigating_url: []u8 = &.{},
    /// The bridge names, to add when the page is ready.
    bridges: std.ArrayList([:0]u8) = .empty,
    /// Why the last load failed, until a load succeeds.
    failure: [512]u8 = undefined,
    /// How many bytes of `failure` are used.
    failure_length: usize = 0,

    /// Frees what the page holds (not the WebView2 objects, which `destroy`
    /// closes first).
    ///
    /// - `self`: the page.
    fn deinit(self: *Self) void {
        const allocator = std.heap.c_allocator;
        if (self.pending_url) |url| allocator.free(url);
        if (self.trusted_url) |url| allocator.free(url);
        if (self.navigating_url.len > 0) allocator.free(self.navigating_url);
        for (self.bridges.items) |name| allocator.free(name);
        self.bridges.deinit(allocator);
    }

    /// Keeps a failure to report, cut to fit on a character.
    ///
    /// - `self`: the page.
    /// - `text`: why the page failed; empty clears it.
    fn setFailure(self: *Self, text: []const u8) void {
        const length = views.DisplayText.fitLength(text, self.failure.len);
        @memcpy(self.failure[0..length], text[0..length]);
        self.failure_length = length;
    }

    /// Tells the page what it shows now: its address, title, history and failure.
    ///
    /// - `self`: the page.
    fn report(self: *Self) void {
        const allocator = std.heap.c_allocator;
        var url: []const u8 = "";
        var title: []const u8 = "";
        defer allocator.free(url);
        defer allocator.free(title);
        var can_go_back: i32 = 0;
        var can_go_forward: i32 = 0;
        if (self.web_view) |web_view| {
            url = WebView2Backend.stringProperty(web_view, WebViewSlot.get_source) catch |err| blk: {
                log.debug("page address not read: {s}", .{@errorName(err)});
                break :blk &.{};
            };
            title = WebView2Backend.stringProperty(web_view, WebViewSlot.get_document_title) catch |err| blk: {
                log.debug("page title not read: {s}", .{@errorName(err)});
                break :blk &.{};
            };
            _ = mod.Com.method(*const fn (*anyopaque, *i32) callconv(.winapi) mod.HRESULT, web_view, WebViewSlot.get_can_go_back)(web_view, &can_go_back);
            _ = mod.Com.method(*const fn (*anyopaque, *i32) callconv(.winapi) mod.HRESULT, web_view, WebViewSlot.get_can_go_forward)(web_view, &can_go_forward);
        }
        self.page.update(.{
            .url = url,
            .title = title,
            .failure = self.failure[0..self.failure_length],
            .can_go_back = can_go_back != 0,
            .can_go_forward = can_go_forward != 0,
        });
    }
};

/// Where the process's WebView2 environment stands.
const WebView2EnvironmentState = enum {
    const Self = @This();

    /// Not asked for yet.
    idle,
    /// Asked for; pages wait for it.
    creating,
    /// Made (`environment`).
    ready,
    /// Refused; `environment_failure` says why.
    failed,
};

/// The WebView2 web view behind every `WebPage` on Windows.
pub const WebView2Backend = struct {
    const Self = @This();

    /// The backend `WebPage`s are made with.
    pub const backend: views.WebPageBackend = .{
        .create = Self.create,
        .destroy = Self.destroy,
        .view = Self.view,
        .trust = Self.trust,
        .load = Self.load,
        .go_back = Self.goBack,
        .go_forward = Self.goForward,
        .reload = Self.reload,
        .add_bridge = Self.addBridge,
    };

    /// `HKEY_LOCAL_MACHINE`.
    const hkey_local_machine: usize = 0x80000002;
    /// `HKEY_CURRENT_USER`.
    const hkey_current_user: usize = 0x80000001;
    /// `RRF_RT_REG_SZ`.
    const rrf_rt_reg_sz: u32 = 0x2;
    /// `GWLP_USERDATA`.
    const gwlp_userdata: i32 = -21;
    /// `COLOR_WINDOW + 1`: the system window color, as a class brush.
    const color_window_brush: usize = 6;
    /// `WS_CHILD`.
    const ws_child: u32 = 0x40000000;
    /// `WS_CLIPCHILDREN`.
    const ws_clip_children: u32 = 0x02000000;
    /// `WM_SIZE`.
    const wm_size: u32 = 0x0005;
    /// `WM_MOVE`.
    const wm_move: u32 = 0x0003;
    /// `WM_SETFOCUS`.
    const wm_set_focus: u32 = 0x0007;
    /// `COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC`.
    const move_focus_programmatic: i32 = 0;
    /// `COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED`.
    const status_cancelled: i32 = 14;
    /// The runtime's client id under `EdgeUpdate` (the Evergreen WebView2 runtime).
    const runtime_client = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";
    /// The page window's class.
    const container_class = std.unicode.utf8ToUtf16LeStringLiteral("ZigguiWebView2Host");

    /// The live pages.
    var pages: std.ArrayList(*NativePage) = .empty;
    /// The next page id.
    var next_id: u64 = 1;
    /// The process's `ICoreWebView2Environment`, once made.
    var environment: ?*anyopaque = null;
    /// Where the environment stands.
    var environment_state: WebView2EnvironmentState = .idle;
    /// Why the environment was refused.
    var environment_failure: []const u8 = "";
    /// The page window's class is registered.
    var class_registered: bool = false;

    /// Makes a page window and asks for its controller, which arrives later.
    ///
    /// - `page`: the page it reports to.
    /// - Returns: the page, or null when COM or Windows refused.
    fn create(page: *views.WebPage) ?*anyopaque {
        if (!mod.Com.enterApartment()) return null;
        const instance = mod.Win32.GetModuleHandleW(null);
        if (!class_registered) {
            _ = mod.Win32.RegisterClassExW(&.{
                .lpfnWndProc = Self.containerProcedure,
                .hInstance = instance,
                .lpszClassName = Self.container_class,
                .hbrBackground = @ptrFromInt(Self.color_window_brush),
            });
            class_registered = true;
        }
        const parking = mod.Win32NativeHost.parkingWindow() orelse return null;
        const container = mod.Win32.CreateWindowExW(0, Self.container_class, null, Self.ws_child | Self.ws_clip_children, 0, 0, 640, 480, parking, null, instance, null) orelse return null;
        const native = std.heap.c_allocator.create(NativePage) catch |err| {
            log.warn("page not made: {s}", .{@errorName(err)});
            _ = mod.Win32.DestroyWindow(container);
            return null;
        };
        native.* = .{ .id = next_id, .page = page, .container = container };
        next_id += 1;
        pages.append(std.heap.c_allocator, native) catch |err| {
            log.warn("page not made: {s}", .{@errorName(err)});
            std.heap.c_allocator.destroy(native);
            _ = mod.Win32.DestroyWindow(container);
            return null;
        };
        _ = SetWindowLongPtrW(container, Self.gwlp_userdata, @bitCast(@intFromPtr(native)));
        switch (environment_state) {
            .idle => Self.startEnvironment(),
            .creating => {},
            .ready => Self.startController(native),
            .failed => {},
        }
        if (environment_state == .failed) {
            native.creating = false;
            native.setFailure(environment_failure);
        }
        return native;
    }

    /// Closes the page's WebView2 objects, destroys its window and frees it.
    ///
    /// - `handle`: the page.
    fn destroy(handle: *anyopaque) void {
        const native = Self.nativeOf(handle);
        for (pages.items, 0..) |live, index| {
            if (live == native) {
                _ = pages.swapRemove(index);
                break;
            }
        }
        if (native.controller) |controller| {
            _ = mod.Com.method(*const fn (*anyopaque) callconv(.winapi) mod.HRESULT, controller, ControllerSlot.close)(controller);
        }
        mod.Com.release(native.web_view);
        mod.Com.release(native.controller);
        _ = SetWindowLongPtrW(native.container, Self.gwlp_userdata, 0);
        _ = mod.Win32.DestroyWindow(native.container);
        native.deinit();
        std.heap.c_allocator.destroy(native);
    }

    /// The page's window, for the native-view host to place.
    ///
    /// - `handle`: the page.
    /// - Returns: its `HWND`.
    fn view(handle: *anyopaque) ?*anyopaque {
        return Self.nativeOf(handle).container;
    }

    /// Sets the origin the bridges hear: that of `url`, or `url` itself
    /// when it has no host (a `data:` page).
    ///
    /// - `handle`: the page.
    /// - `url`: the trusted address.
    fn trust(handle: *anyopaque, url: [:0]const u8) void {
        const native = Self.nativeOf(handle);
        const copy = std.heap.c_allocator.dupeSentinel(u8, url, 0) catch |err| {
            log.warn("origin not trusted: {s}", .{@errorName(err)});
            return;
        };
        if (native.trusted_url) |old| std.heap.c_allocator.free(old);
        native.trusted_url = copy;
    }

    /// Loads `url`, now or once the page is ready.
    ///
    /// - `handle`: the page.
    /// - `url`: the address.
    /// - Returns: false when it names no scheme, or WebView2 refuses it.
    fn load(handle: *anyopaque, url: [:0]const u8) bool {
        if (!Self.hasScheme(url)) return false;
        const native = Self.nativeOf(handle);
        native.setFailure("");
        const web_view = native.web_view orelse {
            const copy = std.heap.c_allocator.dupeSentinel(u8, url, 0) catch |err| {
                log.warn("address not kept: {s}", .{@errorName(err)});
                return false;
            };
            if (native.pending_url) |old| std.heap.c_allocator.free(old);
            native.pending_url = copy;
            return true;
        };
        return Self.navigate(web_view, url);
    }

    /// Goes back one page in the history, if it can.
    ///
    /// - `handle`: the page.
    fn goBack(handle: *anyopaque) void {
        Self.call(handle, WebViewSlot.go_back);
    }

    /// Goes forward one page in the history, if it can.
    ///
    /// - `handle`: the page.
    fn goForward(handle: *anyopaque) void {
        Self.call(handle, WebViewSlot.go_forward);
    }

    /// Loads the page showing again.
    ///
    /// - `handle`: the page.
    fn reload(handle: *anyopaque) void {
        Self.call(handle, WebViewSlot.reload);
    }

    /// Lets the page post messages under `name`, now or once it is ready.
    ///
    /// - `handle`: the page.
    /// - `name`: the bridge's name.
    fn addBridge(handle: *anyopaque, name: [:0]const u8) void {
        const native = Self.nativeOf(handle);
        var known = false;
        for (native.bridges.items) |existing| {
            if (std.mem.eql(u8, existing, name)) known = true;
        }
        // A name already added has its script on every document already:
        // WebView2 keeps each script added, so injecting again only piles up
        // copies that run on every page.
        if (known) return;
        const copy = std.heap.c_allocator.dupeSentinel(u8, name, 0) catch |err| {
            log.warn("bridge {s} not added: {s}", .{ name, @errorName(err) });
            return;
        };
        native.bridges.append(std.heap.c_allocator, copy) catch |err| {
            std.heap.c_allocator.free(copy);
            log.warn("bridge {s} not added: {s}", .{ name, @errorName(err) });
            return;
        };
        if (native.web_view) |web_view| Self.injectBridge(web_view, name);
    }

    /// Runs a callback a `Handler` received, on the UI thread.
    ///
    /// - `kind`: what it answers.
    /// - `page_id`: the page it names.
    /// - `first`: the completion's `HRESULT`, or the event's sender.
    /// - `second`: the object made, or the event's arguments.
    fn dispatch(kind: HandlerKind, page_id: u64, first: usize, second: ?*anyopaque) void {
        if (kind == .environment) return Self.environmentMade(@bitCast(@as(u32, @truncate(first))), second);
        const native = Self.pageWithId(page_id) orelse {
            // The page went while its controller was made: close it again.
            if (kind == .controller) if (second) |controller| {
                _ = mod.Com.method(*const fn (*anyopaque) callconv(.winapi) mod.HRESULT, controller, ControllerSlot.close)(controller);
            };
            return;
        };
        switch (kind) {
            .environment => unreachable,
            .controller => Self.controllerMade(native, @bitCast(@as(u32, @truncate(first))), second),
            .sourceChanged, .historyChanged, .titleChanged => native.report(),
            .navigationStarting => Self.navigationStarting(native, second),
            .navigationCompleted => Self.navigationCompleted(native, second),
            .webMessage => Self.messageReceived(native, second),
            .gotFocus => {
                _ = mod.Win32.SetPropW(native.container, mod.Win32NativeHost.focus_property, @ptrFromInt(1));
            },
            .lostFocus => {
                _ = mod.Win32.RemovePropW(native.container, mod.Win32NativeHost.focus_property);
            },
        }
    }

    /// Asks for the process's environment, with the user data under
    /// `%LOCALAPPDATA%\<executable>\WebView2`.
    fn startEnvironment() void {
        environment_state = .creating;
        const handler = Handler.make(.environment, 0) orelse return Self.environmentRefused("Out of memory.");
        defer _ = Handler.release(handler);
        var folder_buffer: [1024]u16 = undefined;
        const folder = Self.userDataFolder(&folder_buffer);
        if (LoadLibraryW(std.unicode.utf8ToUtf16LeStringLiteral("WebView2Loader.dll"))) |loader| {
            if (GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions")) |address| {
                const function: CreateEnvironment = @ptrCast(address);
                const result = function(null, folder, null, handler);
                if (result < 0) Self.environmentRefused("WebView2 could not start.");
                return;
            }
        }
        var path_buffer: [1024]u16 = undefined;
        const path = Self.runtimeLibrary(&path_buffer) orelse return Self.environmentRefused("Web pages need the Microsoft Edge WebView2 Runtime, which is not installed.");
        const runtime = LoadLibraryW(path) orelse return Self.environmentRefused("The WebView2 runtime could not be loaded.");
        const address = GetProcAddress(runtime, "CreateWebViewEnvironmentWithOptionsInternal") orelse return Self.environmentRefused("The WebView2 runtime is too old.");
        const function: CreateEnvironmentInternal = @ptrCast(address);
        const result = function(true, 0, folder, null, handler);
        if (result < 0) Self.environmentRefused("WebView2 could not start.");
    }

    /// Fails every waiting page: the environment was refused.
    ///
    /// - `text`: why.
    fn environmentRefused(text: []const u8) void {
        log.warn("WebView2 environment refused: {s}", .{text});
        environment_state = .failed;
        environment_failure = text;
        for (pages.items) |native| {
            if (!native.creating) continue;
            native.creating = false;
            native.setFailure(text);
            native.report();
        }
    }

    /// Takes the environment and asks for each waiting page's controller.
    ///
    /// - `result`: the creation's `HRESULT`.
    /// - `made`: the environment, borrowed.
    fn environmentMade(result: mod.HRESULT, made: ?*anyopaque) void {
        const made_environment = made orelse return Self.environmentRefused("WebView2 could not start.");
        if (result < 0) return Self.environmentRefused("WebView2 could not start.");
        mod.Com.addRef(made_environment);
        environment = made_environment;
        environment_state = .ready;
        for (pages.items) |native| {
            if (native.creating and native.controller == null) Self.startController(native);
        }
    }

    /// Asks the environment for a page's controller in its window.
    ///
    /// - `native`: the page.
    fn startController(native: *NativePage) void {
        const made_environment = environment orelse return;
        const handler = Handler.make(.controller, native.id) orelse return;
        defer _ = Handler.release(handler);
        const result = mod.Com.method(*const fn (*anyopaque, mod.HWND, *anyopaque) callconv(.winapi) mod.HRESULT, made_environment, EnvironmentSlot.create_controller)(made_environment, native.container, handler);
        if (result < 0) {
            native.creating = false;
            native.setFailure("WebView2 could not make the page.");
            native.report();
        }
    }

    /// Takes a page's controller: sizes it to the window, listens to it,
    /// adds the bridges and loads what was asked for.
    ///
    /// - `native`: the page.
    /// - `result`: the creation's `HRESULT`.
    /// - `made`: the controller, borrowed.
    fn controllerMade(native: *NativePage, result: mod.HRESULT, made: ?*anyopaque) void {
        native.creating = false;
        const controller = made orelse {
            native.setFailure("WebView2 could not make the page.");
            return native.report();
        };
        if (result < 0) {
            native.setFailure("WebView2 could not make the page.");
            return native.report();
        }
        mod.Com.addRef(controller);
        native.controller = controller;
        var web_view: ?*anyopaque = null;
        _ = mod.Com.method(*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) mod.HRESULT, controller, ControllerSlot.get_core_web_view)(controller, &web_view);
        const live = web_view orelse return;
        native.web_view = live;

        var settings: ?*anyopaque = null;
        _ = mod.Com.method(*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) mod.HRESULT, live, WebViewSlot.get_settings)(live, &settings);
        if (settings) |held| {
            defer mod.Com.release(held);
            _ = mod.Com.method(*const fn (*anyopaque, i32) callconv(.winapi) mod.HRESULT, held, SettingsSlot.put_is_status_bar_enabled)(held, 0);
            _ = mod.Com.method(*const fn (*anyopaque, i32) callconv(.winapi) mod.HRESULT, held, SettingsSlot.put_are_host_objects_allowed)(held, 0);
        }
        Self.listen(live, WebViewSlot.add_source_changed, .sourceChanged, native.id);
        Self.listen(live, WebViewSlot.add_history_changed, .historyChanged, native.id);
        Self.listen(live, WebViewSlot.add_document_title_changed, .titleChanged, native.id);
        Self.listen(live, WebViewSlot.add_navigation_starting, .navigationStarting, native.id);
        Self.listen(live, WebViewSlot.add_navigation_completed, .navigationCompleted, native.id);
        Self.listen(live, WebViewSlot.add_web_message_received, .webMessage, native.id);
        Self.listen(controller, ControllerSlot.add_got_focus, .gotFocus, native.id);
        Self.listen(controller, ControllerSlot.add_lost_focus, .lostFocus, native.id);

        Self.fitController(native);
        _ = mod.Com.method(*const fn (*anyopaque, i32) callconv(.winapi) mod.HRESULT, controller, ControllerSlot.put_is_visible)(controller, 1);
        for (native.bridges.items) |name| Self.injectBridge(live, name);
        if (native.pending_url) |url| {
            defer {
                std.heap.c_allocator.free(url);
                native.pending_url = null;
            }
            if (!Self.navigate(live, url)) native.setFailure("The address is not valid.");
        }
        native.report();
    }

    /// Registers a handler for one of a WebView2 object's events; the object
    /// keeps the only reference.
    ///
    /// - `object`: the controller or web view.
    /// - `slot`: the `add_` method's slot.
    /// - `kind`: what the handler answers.
    /// - `page_id`: the page it reports to.
    fn listen(object: *anyopaque, comptime slot: usize, kind: HandlerKind, page_id: u64) void {
        const handler = Handler.make(kind, page_id) orelse return;
        defer _ = Handler.release(handler);
        var token: i64 = 0;
        const result = mod.Com.method(*const fn (*anyopaque, *anyopaque, *i64) callconv(.winapi) mod.HRESULT, object, slot)(object, handler, &token);
        if (result < 0) log.warn("WebView2 event {t} not registered [0x{x}]", .{ kind, @as(u32, @bitCast(result)) });
    }

    /// Keeps the address a top-level load sets out for.
    ///
    /// - `native`: the page.
    /// - `arguments`: the `ICoreWebView2NavigationStartingEventArgs`.
    fn navigationStarting(native: *NativePage, arguments: ?*anyopaque) void {
        const held = arguments orelse return;
        const uri = Self.stringProperty(held, ArgumentsSlot.navigation_uri) catch |err| {
            log.warn("navigation address not read: {s}", .{@errorName(err)});
            return;
        };
        if (native.navigating_url.len > 0) std.heap.c_allocator.free(native.navigating_url);
        native.navigating_url = uri;
    }

    /// Records why a load failed (a cancelled one is no failure) and reports.
    ///
    /// - `native`: the page.
    /// - `arguments`: the `ICoreWebView2NavigationCompletedEventArgs`.
    fn navigationCompleted(native: *NativePage, arguments: ?*anyopaque) void {
        const held = arguments orelse return native.report();
        var success: i32 = 1;
        var status: i32 = 0;
        _ = mod.Com.method(*const fn (*anyopaque, *i32) callconv(.winapi) mod.HRESULT, held, ArgumentsSlot.navigation_success)(held, &success);
        _ = mod.Com.method(*const fn (*anyopaque, *i32) callconv(.winapi) mod.HRESULT, held, ArgumentsSlot.navigation_status)(held, &status);
        if (success != 0) {
            native.setFailure("");
        } else if (status != Self.status_cancelled) {
            native.setFailure(Self.describeStatus(status));
        }
        native.report();
    }

    /// Hands the page a bridge message posted from its trusted origin with a
    /// string body; any other is dropped, with a warning.
    ///
    /// - `native`: the page.
    /// - `arguments`: the `ICoreWebView2WebMessageReceivedEventArgs`.
    fn messageReceived(native: *NativePage, arguments: ?*anyopaque) void {
        const held = arguments orelse return;
        const allocator = std.heap.c_allocator;
        // An opaque-origin document (a `data:` page) posts as `about:blank`;
        // only the top-level document reaches this event, so it is the page
        // the latest load set out for.
        var source = Self.stringProperty(held, ArgumentsSlot.message_source) catch |err| {
            log.warn("bridge message dropped: its source not read: {s}", .{@errorName(err)});
            return;
        };
        defer allocator.free(source);
        if (std.mem.eql(u8, source, "about:blank") and native.navigating_url.len > 0) {
            const copy = allocator.dupe(u8, native.navigating_url) catch |err| {
                log.warn("bridge message dropped: {s}", .{@errorName(err)});
                return;
            };
            allocator.free(source);
            source = copy;
        }
        const trusted = native.trusted_url orelse {
            log.warn("bridge message before any trusted origin", .{});
            return;
        };
        if (!mod.WebOrigin.same(trusted, source)) {
            log.warn("bridge message from an untrusted origin dropped", .{});
            return;
        }
        const text = Self.stringProperty(held, ArgumentsSlot.message_string) catch {
            log.warn("bridge received a non-string message", .{});
            return;
        };
        defer allocator.free(text);
        const Envelope = struct {
            const Self = @This();

            /// The bridge the page posted under.
            bridge: []const u8,
            /// The posted text; null when the page posted something else.
            body: ?[]const u8 = null,
        };
        const parsed = std.json.parseFromSlice(Envelope, allocator, text, .{ .ignore_unknown_fields = true }) catch {
            log.warn("bridge received a message it cannot read", .{});
            return;
        };
        defer parsed.deinit();
        const body = parsed.value.body orelse {
            log.warn("bridge received a non-string body", .{});
            return;
        };
        for (native.bridges.items) |name| {
            if (std.mem.eql(u8, name, parsed.value.bridge)) {
                return native.page.receive(.{ .bridge = name, .body = body });
            }
        }
        log.warn("message to an unregistered bridge dropped", .{});
    }

    /// Adds the script that makes `window.webkit.messageHandlers.<name>`
    /// post through `chrome.webview`, to every document from now on and to
    /// the one showing.
    ///
    /// - `web_view`: the `ICoreWebView2`.
    /// - `name`: the bridge's name.
    fn injectBridge(web_view: *anyopaque, name: []const u8) void {
        const allocator = std.heap.c_allocator;
        const quoted = std.json.Stringify.valueAlloc(allocator, name, .{}) catch |err| {
            log.warn("bridge script not added: {s}", .{@errorName(err)});
            return;
        };
        defer allocator.free(quoted);
        const script = allocator.print(
            "(function(){{var w=window.chrome&&window.chrome.webview;if(!w)return;" ++
                "window.webkit=window.webkit||{{}};" ++
                "var h=window.webkit.messageHandlers=window.webkit.messageHandlers||{{}};" ++
                "h[{s}]={{postMessage:function(b){{w.postMessage(JSON.stringify({{bridge:{s},body:typeof b==='string'?b:null}}));}}}};}})();",
            .{ quoted, quoted },
        ) catch |err| {
            log.warn("bridge script not added: {s}", .{@errorName(err)});
            return;
        };
        defer allocator.free(script);
        const wide_script = mod.Com.wide(allocator, script) catch |err| {
            log.warn("bridge script not added: {s}", .{@errorName(err)});
            return;
        };
        defer allocator.free(wide_script);
        _ = mod.Com.method(*const fn (*anyopaque, [*:0]const u16, ?*anyopaque) callconv(.winapi) mod.HRESULT, web_view, WebViewSlot.add_script_to_execute_on_document_created)(web_view, wide_script, null);
        _ = mod.Com.method(*const fn (*anyopaque, [*:0]const u16, ?*anyopaque) callconv(.winapi) mod.HRESULT, web_view, WebViewSlot.execute_script)(web_view, wide_script, null);
    }

    /// Asks the web view to load an address.
    ///
    /// - `web_view`: the `ICoreWebView2`.
    /// - `url`: the address.
    /// - Returns: false when WebView2 refused it.
    fn navigate(web_view: *anyopaque, url: []const u8) bool {
        const wide_url = mod.Com.wide(std.heap.c_allocator, url) catch |err| {
            log.warn("address not loaded: {s}", .{@errorName(err)});
            return false;
        };
        defer std.heap.c_allocator.free(wide_url);
        return mod.Com.method(*const fn (*anyopaque, [*:0]const u16) callconv(.winapi) mod.HRESULT, web_view, WebViewSlot.navigate)(web_view, wide_url) >= 0;
    }

    /// Calls a no-argument `ICoreWebView2` method on a ready page.
    ///
    /// - `handle`: the page.
    /// - `slot`: the method's slot.
    fn call(handle: *anyopaque, comptime slot: usize) void {
        const web_view = Self.nativeOf(handle).web_view orelse return;
        _ = mod.Com.method(*const fn (*anyopaque) callconv(.winapi) mod.HRESULT, web_view, slot)(web_view);
    }

    /// Sizes a page's controller to its window's client area.
    ///
    /// - `native`: the page.
    fn fitController(native: *NativePage) void {
        const controller = native.controller orelse return;
        var bounds = mod.RECT{};
        _ = GetClientRect(native.container, &bounds);
        _ = mod.Com.method(*const fn (*anyopaque, mod.RECT) callconv(.winapi) mod.HRESULT, controller, ControllerSlot.put_bounds)(controller, bounds);
    }

    /// The page window's procedure: keeps the controller sized to the window,
    /// tells it when the window moves, and hands it the keyboard focus.
    ///
    /// - `window`: the page window.
    /// - `message`: the message.
    /// - `wparam`: its word parameter.
    /// - `lparam`: its long parameter.
    /// - Returns: the message's result.
    fn containerProcedure(window: mod.HWND, message: u32, wparam: mod.WPARAM, lparam: mod.LPARAM) callconv(.winapi) mod.LRESULT {
        const address: usize = @bitCast(GetWindowLongPtrW(window, Self.gwlp_userdata));
        if (address != 0) {
            const native: *NativePage = @ptrFromInt(address);
            switch (message) {
                Self.wm_size => Self.fitController(native),
                Self.wm_move => if (native.controller) |controller| {
                    _ = mod.Com.method(*const fn (*anyopaque) callconv(.winapi) mod.HRESULT, controller, ControllerSlot.notify_parent_window_position_changed)(controller);
                },
                Self.wm_set_focus => if (native.controller) |controller| {
                    _ = mod.Com.method(*const fn (*anyopaque, i32) callconv(.winapi) mod.HRESULT, controller, ControllerSlot.move_focus)(controller, Self.move_focus_programmatic);
                },
                else => {},
            }
        }
        return mod.Win32.DefWindowProcW(window, message, wparam, lparam);
    }

    /// Reads a string a WebView2 object hands over (`LPWSTR*`, freed here).
    ///
    /// - `object`: the object.
    /// - `slot`: the getter's slot.
    /// - Returns: the UTF-8 copy in the C allocator; an error when the object refused.
    fn stringProperty(object: *anyopaque, comptime slot: usize) error{ OutOfMemory, Refused }![]u8 {
        var value: ?[*:0]u16 = null;
        const result = mod.Com.method(*const fn (*anyopaque, *?[*:0]u16) callconv(.winapi) mod.HRESULT, object, slot)(object, &value);
        if (result < 0) return error.Refused;
        defer mod.Com.freeTask(value);
        return mod.Com.narrow(std.heap.c_allocator, value);
    }

    /// The text a failed load reports, for a `COREWEBVIEW2_WEB_ERROR_STATUS`
    /// (its values as `WebView2.h` numbers them; 14, a cancelled load, is no
    /// failure and never reaches here).
    ///
    /// - `status`: the status.
    /// - Returns: the text.
    fn describeStatus(status: i32) []const u8 {
        return switch (status) {
            // CERTIFICATE_COMMON_NAME_IS_INCORRECT … CERTIFICATE_IS_INVALID.
            1...5 => "The server's certificate is not valid.",
            // SERVER_UNREACHABLE.
            6 => "The server could not be reached.",
            // TIMEOUT.
            7 => "The request timed out.",
            // ERROR_HTTP_INVALID_SERVER_RESPONSE.
            8 => "The server sent a response that is not valid.",
            // CONNECTION_ABORTED, CONNECTION_RESET, DISCONNECTED.
            9, 10, 11 => "The network connection was lost.",
            // CANNOT_CONNECT.
            12 => "Could not connect to the server.",
            // HOST_NAME_NOT_RESOLVED.
            13 => "A server with the specified hostname could not be found.",
            // REDIRECT_FAILED.
            15 => "The page could not be redirected.",
            // VALID_AUTHENTICATION_CREDENTIALS_REQUIRED, VALID_PROXY_AUTHENTICATION_REQUIRED.
            17, 18 => "The page needs a sign-in.",
            // UNKNOWN, UNEXPECTED_ERROR.
            else => "The page could not be loaded.",
        };
    }

    /// Reports whether an address names a scheme (`https:`, `data:`, `file:`).
    ///
    /// - `url`: the address.
    /// - Returns: true when it starts with letters, digits, `+`, `-` or `.`
    ///   (a letter first) and a colon.
    fn hasScheme(url: []const u8) bool {
        const colon = std.mem.findScalar(u8, url, ':') orelse return false;
        if (colon == 0 or !std.ascii.isAlphabetic(url[0])) return false;
        for (url[0..colon]) |character| {
            if (!std.ascii.isAlphanumeric(character) and character != '+' and character != '-' and character != '.') return false;
        }
        return true;
    }

    /// The live page with an id.
    ///
    /// - `id`: the id.
    /// - Returns: the page, or null when it is gone.
    fn pageWithId(id: u64) ?*NativePage {
        for (pages.items) |native| {
            if (native.id == id) return native;
        }
        return null;
    }

    /// The page behind a handle.
    ///
    /// - `handle`: the handle `create` returned.
    /// - Returns: the page.
    fn nativeOf(handle: *anyopaque) *NativePage {
        return @ptrCast(@alignCast(handle));
    }

    /// Writes `%LOCALAPPDATA%\<executable name>\WebView2`.
    ///
    /// - `buffer`: where.
    /// - Returns: the folder, or null to let WebView2 pick one beside the executable.
    fn userDataFolder(buffer: *[1024]u16) ?[*:0]const u16 {
        const local = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("LOCALAPPDATA"), buffer, 900);
        if (local == 0 or local >= 900) return null;
        var module: [512]u16 = undefined;
        const module_length = GetModuleFileNameW(null, &module, module.len);
        if (module_length == 0 or module_length >= module.len) return null;
        const path = module[0..module_length];
        const name_start = if (std.mem.findScalarLast(u16, path, '\\')) |slash| slash + 1 else 0;
        var name = path[name_start..];
        if (name.len > 4 and name[name.len - 4] == '.') name = name[0 .. name.len - 4];
        const suffix = std.unicode.utf8ToUtf16LeStringLiteral("\\WebView2");
        if (local + 1 + name.len + suffix.len + 1 > buffer.len) return null;
        var length: usize = local;
        buffer[length] = '\\';
        length += 1;
        @memcpy(buffer[length..][0..name.len], name);
        length += name.len;
        @memcpy(buffer[length..][0..suffix.len], suffix);
        length += suffix.len;
        buffer[length] = 0;
        return buffer[0..length :0].ptr;
    }

    /// Finds the installed runtime's `EmbeddedBrowserWebView.dll` through
    /// `EdgeUpdate\ClientState\<runtime>\EBWebView`, machine-wide then per user.
    ///
    /// - `buffer`: where the path is written.
    /// - Returns: the path, or null when no runtime is installed.
    fn runtimeLibrary(buffer: *[1024]u16) ?[*:0]const u16 {
        const keys = [_]struct { root: usize, path: [:0]const u16 }{
            .{ .root = Self.hkey_local_machine, .path = std.unicode.utf8ToUtf16LeStringLiteral("SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\ClientState\\" ++ Self.runtime_client) },
            .{ .root = Self.hkey_local_machine, .path = std.unicode.utf8ToUtf16LeStringLiteral("SOFTWARE\\Microsoft\\EdgeUpdate\\ClientState\\" ++ Self.runtime_client) },
            .{ .root = Self.hkey_current_user, .path = std.unicode.utf8ToUtf16LeStringLiteral("SOFTWARE\\Microsoft\\EdgeUpdate\\ClientState\\" ++ Self.runtime_client) },
        };
        const architecture = if (mod.cpu_arch == .aarch64) "arm64" else if (mod.cpu_arch == .x86) "x86" else "x64";
        const library = std.unicode.utf8ToUtf16LeStringLiteral("\\EBWebView\\" ++ architecture ++ "\\EmbeddedBrowserWebView.dll");
        for (keys) |key| {
            var size: u32 = @intCast((buffer.len - library.len - 1) * 2);
            const status = RegGetValueW(key.root, key.path, std.unicode.utf8ToUtf16LeStringLiteral("EBWebView"), Self.rrf_rt_reg_sz, null, buffer, &size);
            if (status != 0 or size < 4) continue;
            const length = size / 2 - 1; // the size counts the NUL
            @memcpy(buffer[length..][0..library.len], library);
            buffer[length + library.len] = 0;
            return buffer[0 .. length + library.len :0].ptr;
        }
        return null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "web view2: only an address naming a scheme is loaded" {
    try std.testing.expect(WebView2Backend.hasScheme("https://ziglang.org"));
    try std.testing.expect(WebView2Backend.hasScheme("data:text/html;base64,AA=="));
    try std.testing.expect(!WebView2Backend.hasScheme("ziglang.org"));
    try std.testing.expect(!WebView2Backend.hasScheme(":nothing"));
}

test "web view2: load failures follow WebView2's status numbering" {
    try std.testing.expectEqual(@as(i32, 14), WebView2Backend.status_cancelled);
    try std.testing.expectEqualStrings("A server with the specified hostname could not be found.", WebView2Backend.describeStatus(13));
    try std.testing.expectEqualStrings("The page could not be redirected.", WebView2Backend.describeStatus(15));
    try std.testing.expectEqualStrings("The page could not be loaded.", WebView2Backend.describeStatus(16));
    try std.testing.expectEqualStrings("The page needs a sign-in.", WebView2Backend.describeStatus(17));
    try std.testing.expectEqualStrings("The page needs a sign-in.", WebView2Backend.describeStatus(18));
}
