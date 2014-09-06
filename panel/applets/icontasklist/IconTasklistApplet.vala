/*
 * IconTasklistApplet.vala
 * 
 * Copyright 2014 Ikey Doherty <ikey.doherty@gmail.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */


const string BUDGIE_STYLE_CLASS_BUTTON = "launcher";

/**
 * Attempt to match startup notification IDs
 */
public static bool startupid_match(string id1, string id2)
{
    /* Simple. If id1 == id2, or id1(WINID+1) == id2 */
    if (id1 == id2) {
        return true;
    }
    string[] spluts = id1.split("_");
    string[] splits = spluts[0].split("-");
    int winid = int.parse(splits[splits.length-1])+1;
    string id3 = "%s-%d_%s".printf(string.joinv("-", splits[0:splits.length-1]), winid, string.joinv("_", spluts[1:spluts.length]));

    return (id2 == id3);
}


/**
 * Trivial helper for IconTasklist - i.e. desktop lookups
 */
public class DesktopHelper : Object {

    Gee.HashMap<string?,string?> simpletons;
    bool init = false;

    public DesktopHelper()
    {
        /* Initialize simpletons. */
        simpletons = new Gee.HashMap<string?,string?>(null,null,null);
        simpletons["google-chrome-stable"] = "google-chrome";
    }

    /**
     * Obtain a DesktopAppInfo for a given window.
     * @param window X11 window to obtain DesktopAppInfo for
     *
     * @return a DesktopAppInfo if found, otherwise null.
     * 
     * @note This is immensely inefficient. We still need to cache some
     * lookups.
     */
    public DesktopAppInfo? get_app_info_for_window(Wnck.Window? window)
    {
        if (window == null) {
            return null;
        }
        if (window.get_class_group_name() == null) {
            return null;
        }
        var app_name = window.get_class_group_name();
        var c = app_name[0].tolower();
        var app_name_clean = "%c%s".printf(c,app_name[1:app_name.length]);

        var p1 = new DesktopAppInfo("%s.desktop".printf(app_name_clean));
        if (p1 == null) {
            if (app_name_clean in simpletons) {
                p1 = new DesktopAppInfo("%s.desktop".printf(simpletons[app_name_clean]));
            }
        }
        return p1;
    }
}

public class IconButton : Gtk.ToggleButton
{

    public new Gtk.Image image;
    public unowned Wnck.Window? window;
    protected Wnck.ActionMenu menu;
    public int icon_size;
    protected DesktopAppInfo? ainfo;

    public void update_from_window()
    {
        if (window == null) {
            return;
        }
        set_tooltip_text(window.get_name());

        // Things we can happily handle ourselves
        window.icon_changed.connect(update_icon);
        window.name_changed.connect(()=> {
            set_tooltip_text(window.get_name());
        });
        update_icon();
        set_active(window.is_active());

        // Actions menu
        menu = new Wnck.ActionMenu(window);
    }

    public IconButton(Wnck.Window? window, int size, DesktopAppInfo? ainfo)
    {
        image = new Gtk.Image();
        image.pixel_size = size;
        icon_size = size;
        add(image);

        this.window = window;
        relief = Gtk.ReliefStyle.NONE;
        this.ainfo = ainfo;

        // Replace styling with our own
        var st = get_style_context();
        st.remove_class(Gtk.STYLE_CLASS_BUTTON);
        st.add_class(BUDGIE_STYLE_CLASS_BUTTON);
        size_allocate.connect(on_size_allocate);

        update_from_window();

        // Handle clicking, etc.
        button_release_event.connect(on_button_release);
    }

    /**
     * This is for minimize animations, etc.
     */
    protected void on_size_allocate(Gtk.Allocation alloc)
    {
        if (window == null) {
            return;
        }
        int x, y;
        var toplevel = get_toplevel();
        translate_coordinates(toplevel, 0, 0, out x, out y);
        toplevel.get_window().get_root_coords(x, y, out x, out y);
        window.set_icon_geometry(x, y, alloc.width, alloc.height);
    }

    /**
     * Update the icon
     */
    public void update_icon()
    {
        if (window == null) {
            return;
        }

        if (window.get_icon_is_fallback()) {
            if (ainfo != null && ainfo.get_icon() != null) {
                image.set_from_gicon(ainfo.get_icon(), Gtk.IconSize.INVALID);
            } else {
                image.set_from_pixbuf(window.get_icon());
            }
        } else {
            image.set_from_pixbuf(window.get_icon());
        }
        image.pixel_size = icon_size;
    }

    /**
     * Either show the actions menu, or activate our window
     */
    public virtual bool on_button_release(Gdk.EventButton event)
    {
        var timestamp = Gtk.get_current_event_time();

        // Right click, i.e. actions menu
        if (event.button == 3) {
            menu.popup(null, null, null, event.button, timestamp);
            return true;
        }

        // Normal left click, go handle the window
        if (window.is_minimized()) {
            window.unminimize(timestamp);
            window.activate(timestamp);
        } else {
            if (window.is_active()) {
                window.minimize();
            } else {
                window.activate(timestamp);
            }
        }

        return true;
    }
            
}

public class PinnedIconButton : IconButton
{
    protected DesktopAppInfo app_info;
    protected unowned Gdk.AppLaunchContext? context;
    public string? id = null;

    public PinnedIconButton(DesktopAppInfo info, int size, ref Gdk.AppLaunchContext context)
    {
        base(null, size, info);
        this.app_info = info;

        this.context = context;
        set_tooltip_text("Launch %s".printf(info.get_display_name()));
        image.set_from_gicon(info.get_icon(), Gtk.IconSize.INVALID);
    }

    protected override bool on_button_release(Gdk.EventButton event)
    {
        if (window == null)
        {
            if (event.button != 1) {
                return true;
            }
            /* Launch ourselves. */
            try {
                context.set_screen(get_screen());
                context.set_timestamp(event.time);
                var id = context.get_startup_notify_id(app_info, null);
                this.id = id;
                app_info.launch(null, this.context);
            } catch (Error e) {
                /* Animate a UFAILED image? */
                message(e.message);
            }
            return true;
        } else {
            return base.on_button_release(event);
        }
    }

    public void reset()
    {
        image.set_from_gicon(app_info.get_icon(), Gtk.IconSize.INVALID);
        set_tooltip_text("Launch %s".printf(app_info.get_display_name()));
        set_active(false);
        // Actions menu
        menu.destroy();
        menu = null;
        window = null;
        id = null;
    }
}

public class IconTasklistApplet : Budgie.Plugin, Peas.ExtensionBase
{
    public Budgie.Applet get_panel_widget()
    {
        return new IconTasklistAppletImpl();
    }
}

public class IconTasklistAppletImpl : Budgie.Applet
{

    protected Gtk.Box widget;
    protected Gtk.Box main_layout;
    protected Gtk.Box pinned;

    protected Wnck.Screen screen;
    protected Gee.HashMap<Wnck.Window,IconButton> buttons;
    protected Gee.HashMap<string?,PinnedIconButton?> pin_buttons;
    protected int icon_size = 32;
    private Settings settings;

    protected Gdk.AppLaunchContext context;
    protected DesktopHelper helper;

    protected void window_opened(Wnck.Window window)
    {
        // doesn't go on our list
        if (window.is_skip_tasklist()) {
            return;
        }
        string? launch_id = null;
        IconButton? button = null;
        if (window.get_application() != null) {
            launch_id = window.get_application().get_startup_id();
        }
        var pinfo = helper.get_app_info_for_window(window);

        // Check whether its launched with startup notification, if so
        // attempt to use a pin button where appropriate.
        if (launch_id != null) {
            PinnedIconButton? btn = null;
            foreach (var pbtn in pin_buttons.values) {
                if (pbtn.id != null && startupid_match(pbtn.id, launch_id)) {
                    btn = pbtn;
                    break;
                }
            }
            if (btn != null) {
                btn.window = window;
                btn.update_from_window();
                button = btn;
            }
        }
        // Alternatively.. find a "free slot"
        if (pinfo != null) {
            var pinfo2 = pin_buttons[pinfo.get_id()];
            if (pinfo2 != null && pinfo2.window == null) {
                /* Check its "group leader" ... */
                if (window.get_group_leader() == window.get_xid()) {
                    pinfo2.window = window;
                    pinfo2.update_from_window();
                    button = pinfo2;
                }
            }
        }

        // Fallback to new button.
        if (button == null) {
            var btn = new IconButton(window, icon_size, pinfo);
            button = btn;
            widget.pack_start(btn, false, false, 0);
        }
        buttons[window] = button;
        button.show_all();
    }

    protected void window_closed(Wnck.Window window)
    {
        IconButton? btn = null;
        if (!buttons.has_key(window)) {
            return;
        }
        btn = buttons[window];
        // We'll destroy a PinnedIconButton if it got unpinned
        if (btn is PinnedIconButton && btn.get_parent() != widget) {
            var pbtn = btn as PinnedIconButton;
            pbtn.reset();
        } else {
            btn.destroy();
        }
        buttons.unset(window);
    }

    /**
     * Just update the active state on the buttons
     */
    protected void active_window_changed(Wnck.Window? previous_window)
    {
        IconButton? btn;
        Wnck.Window? new_active;
        if (previous_window != null)
        {
            // Update old active button
            if (buttons.has_key(previous_window)) {
                btn = buttons[previous_window];
                btn.set_active(false);
            } 
        }
        new_active = screen.get_active_window();
        if (new_active == null) {
            return;
        }
        if (!buttons.has_key(new_active)) {
            return;
        }
        btn = buttons[new_active];
        btn.set_active(true);
    }

    public IconTasklistAppletImpl()
    {
        // Init wnck
        screen = Wnck.Screen.get_default();
        screen.window_opened.connect(window_opened);
        screen.window_closed.connect(window_closed);
        screen.active_window_changed.connect(active_window_changed);
        this.context = Gdk.Screen.get_default().get_display().get_app_launch_context();

        helper = new DesktopHelper();

        // Easy mapping :)
        buttons = new Gee.HashMap<Wnck.Window,IconButton>(null,null,null);
        pin_buttons = new Gee.HashMap<string?,PinnedIconButton?>(null,null,null);
        icon_size_changed.connect((i,s)=> {
            icon_size = (int)i;
            Wnck.set_default_icon_size(icon_size);
            foreach (var btn in buttons.values) {
                Idle.add(()=>{
                    btn.icon_size = icon_size;
                    btn.update_icon();
                    return false;
                });
            }
        });

        main_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        pinned = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        main_layout.pack_start(pinned, false, false, 0);
        pinned.set_property("margin-right", 10);

        widget = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        main_layout.pack_start(widget, false, false, 0);

        // Update orientation when parent panel does
        orientation_changed.connect((o)=> {
            main_layout.set_orientation(o);
            widget.set_orientation(o);
            pinned.set_orientation(o);
        });

        settings = new Settings("com.evolve-os.budgie.panel");
        settings.changed.connect(on_settings_change);

        on_settings_change("pinned-launchers");
        add(main_layout);
        show_all();
    }

    protected void on_settings_change(string key)
    {
        /* Don't care if its not launchers. */
        if (key != "pinned-launchers") {
            return;
        }
        string[] files = settings.get_strv(key);
        /* We don't actually remove anything >_> */
        foreach (string desktopfile in settings.get_strv(key)) {
            /* Ensure we don't have this fella already. */
            if (pin_buttons.has_key(desktopfile)) {
                continue;
            }
            var info = new DesktopAppInfo(desktopfile);
            if (info == null) {
                message("Invalid application! %s", desktopfile);
                continue;
            }
            var button = new PinnedIconButton(info, icon_size, ref this.context);
            pin_buttons[desktopfile] = button;
            pinned.pack_start(button, false, false, 0);
            button.show_all();
        }
        string[] removals = {};
        /* Conversely, remove ones which have been unset. */
        foreach (string key_name in pin_buttons.keys) {
            if (key_name in files) {
                continue;
            }
            /* We have a removal. */
            PinnedIconButton? btn = pin_buttons[key_name];
            if (btn.window == null) {
                btn.destroy();
            } else {
                /* We need to move this fella.. */
                pinned.remove(btn);
                widget.pack_start(btn, false, false, 0);
            }
            removals += key_name;
        }
        foreach (string key_name in removals) {
            pin_buttons.unset(key_name);
        }

        for (int i=0; i<files.length; i++) {
            pinned.reorder_child(pin_buttons[files[i]], i);
        }
    }
} // End class

[ModuleInit]
public void peas_register_types(TypeModule module) 
{
    // boilerplate - all modules need this
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(IconTasklistApplet));
}
