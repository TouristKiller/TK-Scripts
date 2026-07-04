#include <X11/Xlib.h>
#include <X11/Xatom.h>

#include <cstdio>
#include <cstring>
#include <string>

#include "tk_native_helper.h"

namespace
{
const long XDND_VERSION = 5;

std::string urlEncodePath(const char* path)
{
    static const char* hex = "0123456789ABCDEF";
    std::string out = "file://";
    for (const char* p = path; *p; ++p)
    {
        unsigned char c = static_cast<unsigned char>(*p);
        bool safe = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' ||
                    c == '~' || c == '/';
        if (safe)
        {
            out.push_back(static_cast<char>(c));
        }
        else
        {
            out.push_back('%');
            out.push_back(hex[(c >> 4) & 0xF]);
            out.push_back(hex[c & 0xF]);
        }
    }
    return out;
}

long getXdndAwareVersion(Display* dpy, Atom xdndAware, Window w)
{
    if (w == None) return 0;
    Atom actualType = None;
    int actualFormat = 0;
    unsigned long nItems = 0, bytesAfter = 0;
    unsigned char* data = nullptr;
    if (XGetWindowProperty(dpy, w, xdndAware, 0, 1, False, AnyPropertyType,
                           &actualType, &actualFormat, &nItems, &bytesAfter,
                           &data) != Success)
        return 0;
    long version = 0;
    if (data && actualType != None && nItems >= 1)
        version = static_cast<long>(*reinterpret_cast<Atom*>(data));
    if (data) XFree(data);
    return version;
}

Window findXdndTarget(Display* dpy, Atom xdndAware, Window root, int rootX, int rootY, long* outVersion)
{
    Window target = None;
    Window current = root;
    int x = rootX, y = rootY;
    for (int depth = 0; depth < 64; ++depth)
    {
        Window child = None;
        int cx = 0, cy = 0;
        if (!XTranslateCoordinates(dpy, root, current, rootX, rootY, &cx, &cy, &child))
            break;
        long version = getXdndAwareVersion(dpy, xdndAware, current);
        if (version > 0)
        {
            target = current;
            if (outVersion) *outVersion = version;
        }
        if (child == None) break;
        current = child;
        (void)x;
        (void)y;
    }
    return target;
}

void sendClientMessage(Display* dpy, Window target, Window source, Atom message,
                       long d0, long d1, long d2, long d3, long d4)
{
    XClientMessageEvent ev;
    std::memset(&ev, 0, sizeof(ev));
    ev.type = ClientMessage;
    ev.display = dpy;
    ev.window = target;
    ev.message_type = message;
    ev.format = 32;
    ev.data.l[0] = source;
    ev.data.l[1] = d1;
    ev.data.l[2] = d2;
    ev.data.l[3] = d3;
    ev.data.l[4] = d4;
    ev.data.l[0] = d0;
    XSendEvent(dpy, target, False, NoEventMask, reinterpret_cast<XEvent*>(&ev));
    XFlush(dpy);
}
}

bool startFileDragLinux(const char* utf8_path)
{
    if (!utf8_path || !*utf8_path)
    {
        tknh_log("[TKNativeHelper] leeg pad\n");
        return false;
    }

    Display* dpy = XOpenDisplay(nullptr);
    if (!dpy)
    {
        tknh_log("[TKNativeHelper] XOpenDisplay faalde\n");
        return false;
    }

    int screen = DefaultScreen(dpy);
    Window root = RootWindow(dpy, screen);

    Atom XdndAware = XInternAtom(dpy, "XdndAware", False);
    Atom XdndSelection = XInternAtom(dpy, "XdndSelection", False);
    Atom XdndEnter = XInternAtom(dpy, "XdndEnter", False);
    Atom XdndLeave = XInternAtom(dpy, "XdndLeave", False);
    Atom XdndPosition = XInternAtom(dpy, "XdndPosition", False);
    Atom XdndStatus = XInternAtom(dpy, "XdndStatus", False);
    Atom XdndDrop = XInternAtom(dpy, "XdndDrop", False);
    Atom XdndFinished = XInternAtom(dpy, "XdndFinished", False);
    Atom XdndActionCopy = XInternAtom(dpy, "XdndActionCopy", False);
    Atom uriListType = XInternAtom(dpy, "text/uri-list", False);

    Window source = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
    XSetSelectionOwner(dpy, XdndSelection, source, CurrentTime);
    if (XGetSelectionOwner(dpy, XdndSelection) != source)
    {
        tknh_log("[TKNativeHelper] kon XdndSelection niet claimen\n");
        XDestroyWindow(dpy, source);
        XCloseDisplay(dpy);
        return false;
    }

    XChangeProperty(dpy, source, XInternAtom(dpy, "XdndTypeList", False), XA_ATOM, 32,
                    PropModeReplace, reinterpret_cast<unsigned char*>(&uriListType), 1);

    std::string uriList = urlEncodePath(utf8_path);
    uriList += "\r\n";

    if (XGrabPointer(dpy, root, True,
                     PointerMotionMask | ButtonReleaseMask,
                     GrabModeAsync, GrabModeAsync, None, None, CurrentTime) != GrabSuccess)
    {
        tknh_log("[TKNativeHelper] XGrabPointer faalde\n");
        XDestroyWindow(dpy, source);
        XCloseDisplay(dpy);
        return false;
    }

    Window currentTarget = None;
    long currentVersion = 0;
    bool willAccept = false;
    bool dropped = false;
    bool running = true;

    XEvent ev;
    while (running)
    {
        XNextEvent(dpy, &ev);
        switch (ev.type)
        {
        case MotionNotify:
        {
            int rx = ev.xmotion.x_root;
            int ry = ev.xmotion.y_root;
            long version = 0;
            Window target = findXdndTarget(dpy, XdndAware, root, rx, ry, &version);
            if (target != currentTarget)
            {
                if (currentTarget != None)
                    sendClientMessage(dpy, currentTarget, source, XdndLeave, source, 0, 0, 0, 0);
                currentTarget = target;
                currentVersion = version;
                willAccept = false;
                if (currentTarget != None)
                {
                    long useVersion = currentVersion < XDND_VERSION ? currentVersion : XDND_VERSION;
                    sendClientMessage(dpy, currentTarget, source, XdndEnter,
                                      source, (useVersion << 24), uriListType, 0, 0);
                }
            }
            if (currentTarget != None)
            {
                sendClientMessage(dpy, currentTarget, source, XdndPosition,
                                  source, 0, ((rx << 16) | (ry & 0xFFFF)),
                                  CurrentTime, XdndActionCopy);
            }
            break;
        }
        case ClientMessage:
        {
            if (ev.xclient.message_type == XdndStatus)
            {
                willAccept = (ev.xclient.data.l[1] & 1) != 0;
            }
            else if (ev.xclient.message_type == XdndFinished)
            {
                running = false;
            }
            break;
        }
        case SelectionRequest:
        {
            XSelectionRequestEvent* req = &ev.xselectionrequest;
            XSelectionEvent notify;
            std::memset(&notify, 0, sizeof(notify));
            notify.type = SelectionNotify;
            notify.display = req->display;
            notify.requestor = req->requestor;
            notify.selection = req->selection;
            notify.target = req->target;
            notify.time = req->time;
            notify.property = req->property;
            if (req->target == uriListType && req->property != None)
            {
                XChangeProperty(dpy, req->requestor, req->property, req->target, 8,
                                PropModeReplace,
                                reinterpret_cast<const unsigned char*>(uriList.c_str()),
                                static_cast<int>(uriList.size()));
            }
            else
            {
                notify.property = None;
            }
            XSendEvent(dpy, req->requestor, False, NoEventMask,
                       reinterpret_cast<XEvent*>(&notify));
            XFlush(dpy);
            break;
        }
        case ButtonRelease:
        {
            if (currentTarget != None && willAccept)
            {
                sendClientMessage(dpy, currentTarget, source, XdndDrop,
                                  source, 0, CurrentTime, 0, 0);
                dropped = true;
            }
            else
            {
                if (currentTarget != None)
                    sendClientMessage(dpy, currentTarget, source, XdndLeave, source, 0, 0, 0, 0);
                running = false;
            }
            break;
        }
        default:
            break;
        }
    }

    XUngrabPointer(dpy, CurrentTime);
    XSetSelectionOwner(dpy, XdndSelection, None, CurrentTime);
    XDestroyWindow(dpy, source);
    XCloseDisplay(dpy);

    if (!dropped)
        tknh_log("[TKNativeHelper] XDND drop niet geaccepteerd\n");
    return dropped;
}
