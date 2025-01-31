/**

Synopsis:
---
dub run :opengl
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module app;

import beamui;

int main()
{
    GuiApp app;
    // you can explicitly set OpenGL context version
    app.conf.GLVersionMajor = 2;
    app.conf.GLVersionMinor = 1;
    if (!app.initialize())
        return -1;

    Window window = platform.createWindow("OpenGL example", null);

    //==========================================================================

    static if (USE_OPENGL)
        window.mainWidget = new MyOpenGLWidget;
    else
        window.mainWidget = new Label("Library is built without OpenGL support");

    //==========================================================================

    window.show();

    return platform.enterMessageLoop();
}

static if (USE_OPENGL):

class MyOpenGLWidget : Widget
{
}
