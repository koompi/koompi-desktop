#include <stdio.h>
#include <stdlib.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>

const char *  get_wndow_type(unsigned int win) {
    Atom prop_desktop, prop_type, prop, da;
    char *an = NULL;
    Display *dpy = NULL;
    int di;
    int status;
    unsigned char *prop_ret = NULL;
    unsigned long dl;
    /* const char * win_id = */ 
    Window child = win;
    dpy = XOpenDisplay(NULL);

    prop_type = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", True);
    prop_desktop = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DESKTOP", True);

    status = XGetWindowProperty(dpy, child, prop_type, 0L, sizeof (Atom), False,
                                XA_ATOM, &da, &di, &dl, &dl, &prop_ret);

    if (status == Success && prop_ret)
    {
        prop = ((Atom *)prop_ret)[0];

        /* Debug output, not really relevant: Re-resolve atom number to
         * printable name */
        an = XGetAtomName(dpy, prop);
        // fprintf(stderr, "Type found: %s\n", an);
        /* if (an) */
        /*     XFree(an); */

        /* Compare internal atom numbers */
        if (prop == prop_desktop)
            fprintf(stderr, "It's a desktop window!\n");
    }
    XFree(prop_ret);
    XCloseDisplay(dpy);
    return (const char * ) an;  
}