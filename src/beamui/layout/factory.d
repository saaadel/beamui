/**

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.layout.factory;

import beamui.layout.free;
import beamui.layout.linear;
import beamui.layout.table;
import beamui.widgets.widget;

alias LayoutInstantiator = ILayout function();

ILayout createLayout(string name)
{
    if (auto p = name in factory)
        return (*p)();
    else
        return null;
}

void addLayoutType(string name, LayoutInstantiator func)
{
    assert(name.length && func);
    factory[name] = func;
}

private LayoutInstantiator[string] factory;

static this()
{
    factory = [
        "free": &free,
        "row": &row,
        "column": &column,
        "table": &table,
    ];
}

private ILayout free()
{
    return new FreeLayout;
}

private ILayout row()
{
    return new LinearLayout(Orientation.horizontal);
}

private ILayout column()
{
    return new LinearLayout(Orientation.vertical);
}

private ILayout table()
{
    return new TableLayout;
}
