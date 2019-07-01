/**
Text style properties and markup data structures.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.text.style;

import beamui.core.editable : TabSize;
import beamui.graphics.colors : Color;
import beamui.text.fonts : Font, FontFamily, FontStyle;

/// Specifies text alignment
enum TextAlign : ubyte
{
    start,
    center,
    end,
    justify
}

/** Specifies where to put text decoration lines, if any.

    Note that they can be combined with `|` to draw several lines.
*/
enum TextDecorLine
{
    none = 0,
    over = 1,
    under = 2,
    through = 4
}

/// Specifies the style of the text decoration line(s)
enum TextDecorStyle : ubyte
{
    solid,
    doubled,
    dotted,
    dashed,
    wavy
}

/// Decoration added to text (underline, etc.)
struct TextDecor
{
    TextDecorLine line;
    Color color;
    TextDecorStyle style;
}

/// Controls how text with `&` hotkey marks should be handled (used only in `ShortLabel`)
enum TextHotkey : ubyte
{
    /// Treat as usual text without a hotkey
    ignore,
    /// Only hide `&` marks
    hidden,
    /// Underline hotkey letter that goes after `&`
    underline,
    /// Underline hotkey letter that goes after `&` only when Alt pressed
    underlineOnAlt
}

/// Specifies how text that doesn't fit and is not displayed should behave
enum TextOverflow : ubyte
{
    clip,
    ellipsis,
    ellipsisMiddle
}

/// Controls capitalization of text
enum TextTransform : ubyte
{
    none,
    capitalize,
    uppercase,
    lowercase
}

/// Holds text properties - font style, colors, and so on
struct TextStyle
{
    /// Font that also contains size, style, weight properties
    Font font;
    /// Size of the tab character in number of spaces
    TabSize tabSize;
    TextAlign alignment;
    TextDecor decoration;
    TextOverflow overflow;
    TextTransform transform;
    /// Allows to underline a single character, usually mnemonic
    int underlinedCharIndex = -1;
    /// Text foreground color
    Color color;
    /// Text background color
    Color background;
}

/// Holds properties of the text, that influence only its layout
struct TextLayoutStyle
{
    Font font;
    TabSize tabSize;
    TextTransform transform;

    this(Font font)
    {
        this.font = font;
    }

    this(ref TextStyle superStyle)
    {
        font = superStyle.font;
        tabSize = superStyle.tabSize;
        transform = superStyle.transform;
    }
}

/// Opaque struct, that can hold one text style property
struct TextAttr
{
    package enum Type
    {
        foreground,
        background,
        fontFace,
        fontFamily,
        fontSize,
        fontStyle,
        fontWeight,
        tabSize,
        decoration,
        transform,
    }
    package union Data
    {
        Color foreground;
        Color background;
        string fontFace;
        FontFamily fontFamily;
        int fontSize;
        FontStyle fontStyle;
        ushort fontWeight;
        TabSize tabSize;
        TextDecor decoration;
        TextTransform transform;
    }
    package Type type;
    package Data data;

    this(Color color)
    {
        type = Type.foreground;
        data.foreground = color;
    }
    this(FontFamily fontFamily)
    {
        type = Type.fontFamily;
        data.fontFamily = fontFamily;
    }
    this(FontStyle fontStyle)
    {
        type = Type.fontStyle;
        data.fontStyle = fontStyle;
    }
    this(TabSize tabSize)
    {
        type = Type.tabSize;
        data.tabSize = tabSize;
    }
    this(TextDecor decoration)
    {
        type = Type.decoration;
        data.decoration = decoration;
    }
    this(TextTransform transform)
    {
        type = Type.transform;
        data.transform = transform;
    }

    static TextAttr bg(Color color)
    {
        TextAttr a;
        a.type = Type.background;
        a.data.background = color;
        return a;
    }
    static TextAttr fontFace(string face)
    {
        TextAttr a;
        a.type = Type.fontFace;
        a.data.fontFace = face;
        return a;
    }
    static TextAttr fontSize(int size)
    {
        TextAttr a;
        a.type = Type.fontSize;
        a.data.fontSize = size;
        return a;
    }
    static TextAttr fontWeight(ushort weight)
    {
        TextAttr a;
        a.type = Type.fontWeight;
        a.data.fontWeight = weight;
        return a;
    }
}

package struct MarkupUnit
{
    uint start; // absolute
    uint count;
    TextAttr attribute;
}

struct MarkupSpan
{
    private LineMarkup* markup;
    private uint _start; // absolute
    private uint _count;
    private uint currentIndex; // relative

    @disable this();

    private this(LineMarkup* mk, uint start, uint count)
    {
        markup = mk;
        _start = start;
        _count = count;
    }

    MarkupSpan set(TextAttr attribute)
    {
        assert(markup);
        markup.list ~= MarkupUnit(_start, _count, attribute);
        return this;
    }

    MarkupSpan span(uint start)
    {
        assert(start >= currentIndex);
        assert(start < _count);

        currentIndex = _count;
        return MarkupSpan(markup, _start + start, _count - start);
    }

    MarkupSpan span(uint start, uint count)
    {
        assert(start >= currentIndex);
        assert(count > 0);
        assert(start + count <= _count);

        currentIndex = start + count;
        return MarkupSpan(markup, _start + start, count);
    }
}

struct LineMarkup
{
    import std.container.array : Array;

    package Array!MarkupUnit list;
    package TextAlign alignment;
    private uint currentIndex; // absolute
    private bool alignmentSet;

    @property bool empty() const
    {
        return list.length == 0;
    }

    MarkupSpan span(uint start, uint count)
    {
        assert(start >= currentIndex);
        assert(count > 0);

        currentIndex = start + count;
        return MarkupSpan(&this, start, count);
    }

    LineMarkup* set(TextAlign alignment)
    {
        this.alignment = alignment;
        alignmentSet = true;
        return &this;
    }

    void clear()
    {
        list.length = 0;
        currentIndex = 0;
    }

    package void prepare()
    {
        import std.algorithm.sorting : sort;

        sort!`a.start < b.start`(list[]);
    }
}

// temporary thing

import beamui.core.collections : Buf;
import beamui.text.fonts : CustomCharProps;

void convertMarkupToCustomCharProps(uint len, CustomCharProps def,
    ref LineMarkup mk, ref Buf!CustomCharProps ps)
{
    ps.clear();
    if (mk.empty || len == 0)
        return;

    mk.prepare();
    auto list = mk.list[];
    foreach (i; 0 .. len)
    {
        if (list.length == 0)
            break;

        if (i >= list[0].start + list[0].count)
        {
            list = list[1 .. $];
            ps ~= def;
            continue;
        }

        CustomCharProps p = def;
        foreach (ref u; list)
        {
            if (u.start > i)
                break;

            assert(i < u.start + u.count);
            const a = &u.attribute;
            if (a.type == TextAttr.Type.foreground)
            {
                p.color = a.data.foreground;
            }
            else if (a.type == TextAttr.Type.decoration)
            {
                const dec = &a.data.decoration;
                if (dec.line == TextDecorLine.under)
                    p.textFlags = CustomCharProps(Color.none, true).textFlags;
            }
        }
        ps ~= p;
    }
    // fill the rest
    ps.resize(len, def);
}
