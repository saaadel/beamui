/**
Widgets to show plain or formatted single- and multiline text.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.widgets.text;

import beamui.core.editable : TextChange, TextContent, TextPosition;
import beamui.text.line;
import beamui.text.simple;
import beamui.text.sizetest;
import beamui.text.style;
import beamui.widgets.widget;

/// Single-line text widget
class Label : Widget
{
    @property
    {
        /// Text to show
        override dstring text() const { return textobj.str; }
        /// ditto
        override void text(dstring s)
        {
            textobj.str = s;
            requestLayout();
        }
    }

    private
    {
        SimpleText textobj;
        TextSizeTester minSizeTester;
    }

    this(dstring txt = null)
    {
        textobj.str = txt;
        minSizeTester.str = "aaaaa";
        handleFontChange();
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case tabSize:
            textobj.style.tabSize = style.tabSize;
            break;
        case textAlign:
            textobj.style.alignment = style.textAlign;
            break;
        case textColor:
            textobj.style.color = style.textColor;
            break;
        case textDecorColor:
            textobj.style.decoration.color = style.textDecorColor;
            break;
        case textDecorLine:
            textobj.style.decoration.line = style.textDecorLine;
            break;
        case textDecorStyle:
            textobj.style.decoration.style = style.textDecorStyle;
            break;
        case textOverflow:
            textobj.style.overflow = style.textOverflow;
            break;
        case textTransform:
            textobj.style.transform = style.textTransform;
            minSizeTester.style.transform = style.textTransform;
            break;
        default:
            break;
        }
    }

    override protected void handleFontChange()
    {
        Font fnt = font.get;
        textobj.style.font = fnt;
        minSizeTester.style.font = fnt;
    }

    override void measure()
    {
        textobj.measure();

        Boundaries bs;
        const sz = textobj.size;
        const tmin = minSizeTester.getSize();
        bs.min.w = min(sz.w, tmin.w);
        bs.min.h = min(sz.h, tmin.h);
        bs.nat = sz;
        setBoundaries(bs);
    }

    override void draw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.draw(buf);
        Box b = innerBox;
        auto saver = ClipRectSaver(buf, b, style.alpha);

        // align vertically to center
        const sz = Size(b.w, textobj.size.h);
        b = alignBox(b, sz, Align.vcenter);
        textobj.draw(buf, b.x, b.y, b.w);
    }
}

/// Efficient single-line text widget. Can contain `&` character to underline a mnemonic
class ShortLabel : Widget
{
    @property
    {
        /// Text to show
        override dstring text() const { return original; }
        /// ditto
        override void text(dstring s)
        {
            if (style.textHotkey != TextHotkey.ignore)
            {
                auto r = extractMnemonic(s);
                textobj.str = r[0];
                hotkeyIndex = r[1];
            }
            else
            {
                textobj.str = s;
                hotkeyIndex = -1;
            }
            original = s;
            requestLayout();
        }

        /// Get the hotkey (mnemonic) character for the label (e.g. 'F' for `&File`).
        /// 0 if no hotkey or if disabled in styles
        dchar hotkey() const
        {
            import std.uni : toUpper;

            if (hotkeyIndex >= 0)
                return toUpper(textobj.str[hotkeyIndex]);
            else
                return 0;
        }
    }

    private
    {
        dstring original;
        int hotkeyIndex = -1;
        SimpleText textobj;
        TextSizeTester minSizeTester;
    }

    this(dstring txt = null)
    {
        text = txt;
        minSizeTester.str = "aaaaa";
        handleFontChange();
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case tabSize:
            textobj.style.tabSize = style.tabSize;
            break;
        case textHotkey:
            // recompute the mnemonic
            if (hotkeyIndex == -1 && style.textHotkey != TextHotkey.ignore)
            {
                auto r = extractMnemonic(original);
                textobj.str = r[0];
                hotkeyIndex = r[1];
            }
            else if (hotkeyIndex >= 0 && style.textHotkey == TextHotkey.ignore)
            {
                textobj.str = original;
                hotkeyIndex = -1;
            }
            break;
        case textAlign:
            textobj.style.alignment = style.textAlign;
            break;
        case textColor:
            textobj.style.color = style.textColor;
            break;
        case textDecorColor:
            textobj.style.decoration.color = style.textDecorColor;
            break;
        case textDecorLine:
            textobj.style.decoration.line = style.textDecorLine;
            break;
        case textDecorStyle:
            textobj.style.decoration.style = style.textDecorStyle;
            break;
        case textOverflow:
            textobj.style.overflow = style.textOverflow;
            break;
        case textTransform:
            textobj.style.transform = style.textTransform;
            minSizeTester.style.transform = style.textTransform;
            break;
        default:
            break;
        }
    }

    override protected void handleFontChange()
    {
        Font fnt = font.get;
        textobj.style.font = fnt;
        minSizeTester.style.font = fnt;
    }

    override void measure()
    {
        textobj.measure();

        Boundaries bs;
        const sz = textobj.size;
        const tmin = minSizeTester.getSize();
        bs.min.w = min(sz.w, tmin.w);
        bs.min.h = min(sz.h, tmin.h);
        bs.nat = sz;
        setBoundaries(bs);
    }

    override void draw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.draw(buf);
        Box b = innerBox;
        auto saver = ClipRectSaver(buf, b, style.alpha);

        textobj.style.underlinedCharIndex = textHotkey == TextHotkey.underline ? hotkeyIndex : -1;

        // align vertically to center
        Size sz = Size(b.w, textobj.size.h);
        b = alignBox(b, sz, Align.vcenter);
        textobj.draw(buf, b.x, b.y, b.w);
    }
}

/// Multiline text widget
class MultilineLabel : Widget
{
    @property
    {
        /// Text to show
        override dstring text() const { return textobj.str; }
        /// ditto
        override void text(dstring s)
        {
            textobj.str = s;
            requestLayout();
        }
    }

    private
    {
        SimpleText textobj;
        TextSizeTester minSizeTester;
        TextSizeTester natSizeTester;
    }

    this(dstring txt = null)
    {
        textobj.str = txt;
        minSizeTester.str = "aaaaa\na";
        natSizeTester.str =
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\na";
        dependentSize = DependentSize.height;
        handleFontChange();
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case tabSize:
            textobj.style.tabSize = style.tabSize;
            break;
        case textAlign:
            textobj.style.alignment = style.textAlign;
            break;
        case textColor:
            textobj.style.color = style.textColor;
            break;
        case textDecorColor:
            textobj.style.decoration.color = style.textDecorColor;
            break;
        case textDecorLine:
            textobj.style.decoration.line = style.textDecorLine;
            break;
        case textDecorStyle:
            textobj.style.decoration.style = style.textDecorStyle;
            break;
        case textOverflow:
            textobj.style.overflow = style.textOverflow;
            break;
        case textTransform:
            textobj.style.transform = style.textTransform;
            minSizeTester.style.transform = style.textTransform;
            natSizeTester.style.transform = style.textTransform;
            break;
        default:
            break;
        }
    }

    override protected void handleFontChange()
    {
        Font fnt = font.get;
        textobj.style.font = fnt;
        minSizeTester.style.font = fnt;
        natSizeTester.style.font = fnt;
    }

    override void measure()
    {
        textobj.measure();

        Boundaries bs;
        const sz = textobj.size;
        const tmin = minSizeTester.getSize();
        const tnat = natSizeTester.getSize();
        bs.min.w = min(sz.w, tmin.w);
        bs.min.h = min(sz.h, tmin.h);
        bs.nat.w = min(sz.w, tnat.w);
        bs.nat.h = min(sz.h, tnat.h);
        setBoundaries(bs);
    }

    override int heightForWidth(int width)
    {
        Size p = padding.size;
        int w = width - p.w;
        textobj.wrap(w);
        return textobj.sizeAfterWrap.h + p.h;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        // wrap again in case the parent widget had not called heightForWidth
        // must be cached when width is the same
        int w = geom.w - padding.width;
        textobj.wrap(w);
    }

    override void draw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.draw(buf);
        Box b = innerBox;
        auto saver = ClipRectSaver(buf, b, style.alpha);

        textobj.draw(buf, b.x, b.y, b.w);
    }
}

private Tup!(dstring, int) extractMnemonic(dstring s)
{
    if (s.length < 2)
        return tup(s, -1);

    const len = cast(int)s.length;
    bool found;
    foreach (i; 0 .. len - 1)
    {
        if (s[i] == '&')
        {
            found = true;
            break;
        }
    }
    if (found)
    {
        dchar[] result = new dchar[len];
        int pos = -1;
        found = false;
        int j;
        foreach (i; 0 .. len)
        {
            if (s[i] == '&' && !found)
                found = true;
            else
            {
                if (found && pos == -1 && s[i] != '&')
                    pos = j;
                result[j++] = s[i];
                found = false;
            }
        }
        return tup(cast(dstring)result[0 .. j], pos);
    }
    else
        return tup(s, -1);
}

unittest
{
    assert(extractMnemonic(""d) == tup(""d, -1));
    assert(extractMnemonic("a"d) == tup("a"d, -1));
    assert(extractMnemonic("&"d) == tup("&"d, -1));
    assert(extractMnemonic("abc123"d) == tup("abc123"d, -1));
    assert(extractMnemonic("&File"d) == tup("File"d, 0));
    assert(extractMnemonic("A && B"d) == tup("A & B"d, -1));
    assert(extractMnemonic("A &&& &B"d) == tup("A & B"d, 3));
    assert(extractMnemonic("&A&B&C&&D"d) == tup("ABC&D"d, 0));
    assert(extractMnemonic("a &"d) == tup("a &"d, -1));
}

/** Widget for multiline text with optional inner markup.
*/
class Paragraph : Widget
{
    @property
    {
        inout(TextContent) content() inout { return _content; }

        /// Get the whole text to show. May be costly in big multiline paragraphs
        override dstring text() const
        {
            return _content.getStr();
        }
        /// Replace the whole paragraph text. Does not preserve markup
        override void text(dstring s)
        {
            _content.replaceAll(s);
            resetAllMarkup();
        }
    }

    private
    {
        TextContent _content;

        TextSizeTester minSizeTester;
        TextSizeTester natSizeTester;

        TextLine[] _lines;
        LineMarkup[] _markup;

        /// Text style to adjust default and related to the whole paragraph properties
        TextStyle _txtStyle;
        TextLayoutStyle _oldTLStyle;
        /// Text bounding box size
        Size _size;
        Size _sizeAfterWrap;

        static struct VisibleLine
        {
            uint index;
            int x;
            int y;
        }

        Buf!VisibleLine _visibleLines;
    }

    this(dstring txt)
    {
        this(new TextContent(txt));
    }

    this(TextContent content)
    {
        assert(content);
        _content = content;
        _content.onChange ~= &handleChange;

        minSizeTester.str = "aaaaa\na";
        natSizeTester.str =
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\na";
        dependentSize = DependentSize.height; // TODO: only when wrap is active

        _lines.length = _content.lineCount;
        foreach (i; 0 .. _content.lineCount)
            _lines[i].str = _content[i];

        _txtStyle.wrap = true;
    }

    ~this()
    {
        _content.onChange -= &handleChange;
    }

    /// Set or replace line markup by index. The index must be in range
    void setMarkup(uint lineIndex, ref LineMarkup markup)
    {
        assert(lineIndex < _lines.length);

        TextLine* line = &_lines[lineIndex];
        markup.prepare();
        if (line.markup)
        {
            *line.markup = markup;
        }
        else
        {
            _markup ~= markup;
            line.markup = &_markup[$ - 1];
        }
        // invalidate
        line.measured = false;
        needToMeasureText();
    }

    /// Remove line markup by index. The index must be in range
    void resetMarkup(uint lineIndex)
    {
        assert(lineIndex < _lines.length);

        TextLine* line = &_lines[lineIndex];
        if (auto m = line.markup)
            m.clear();

        line.measured = false;
        needToMeasureText();
    }

    /// Remove markup for all lines
    void resetAllMarkup()
    {
        if (_markup.length == 0)
            return;

        _markup.length = 0;
        foreach (ref line; _lines)
        {
            if (line.markup)
            {
                line.measured = false;
                line.markup = null;
            }
        }
        needToMeasureText();
    }

    /** Convert logical text position into local 2D coordinates.

        Available after the drawing.
    */
    Point textualToLocal(TextPosition pos) const
    {
        if (_visibleLines.length == 0)
            return Point(0, 0);

        const VisibleLine first = _visibleLines[0];
        if (pos.line < first.index)
            return Point(first.x, first.y);

        const VisibleLine last = _visibleLines[$ - 1];
        if (pos.line > last.index)
            return Point(last.x, last.y);

        const VisibleLine ln = _visibleLines[pos.line - first.index];
        const TextLine* line = &_lines[ln.index];
        int x = ln.x;
        int y = ln.y;
        if (line.wrapped)
        {
            foreach (ref span; line.wrapSpans)
            {
                if (pos.pos <= span.end)
                {
                    x = span.offset;
                    foreach (i; span.start .. pos.pos)
                        x += line.glyphs[i].width;
                    break;
                }
                y += span.height;
            }
        }
        else
        {
            if (pos.pos < line.glyphCount)
            {
                foreach (i; 0 .. pos.pos)
                    x += line.glyphs[i].width;
            }
            else
                x += line.size.w;

        }
        return Point(x, y);
    }

    /** Find the closest char position by a point in local 2D coordinates.

        Available after the drawing.
    */
    TextPosition localToTextual(Point pt) const
    {
        if (_visibleLines.length == 0)
            return TextPosition(0, 0);

        const VisibleLine first = _visibleLines[0];
        if (pt.y < first.y)
            return TextPosition(first.index, 0);

        const VisibleLine last = _visibleLines[$ - 1];
        if (pt.y >= last.y + _lines[last.index].height)
            return TextPosition(last.index, _lines[last.index].glyphCount);

        foreach (ln; _visibleLines)
        {
            const TextLine* line = &_lines[ln.index];
            if (ln.y <= pt.y && pt.y < ln.y + line.height)
            {
                if (line.wrapped)
                {
                    int y = ln.y;
                    foreach (ref span; line.wrapSpans)
                    {
                        if (y <= pt.y && pt.y < y + span.height)
                        {
                            int col = findInRow(line.glyphs[span.start .. span.end], pt.x, span.offset);
                            if (col != -1)
                                col += span.start;
                            else
                                col = span.end;
                            return TextPosition(ln.index, col);
                        }
                        y += span.height;
                    }
                }
                else
                {
                    const col = findInRow(line.glyphs, pt.x, ln.x);
                    if (col != -1)
                        return TextPosition(ln.index, col);
                }
                return TextPosition(ln.index, line.glyphCount);
            }
        }
        return TextPosition(last.index, _lines[last.index].glyphCount);
    }

    private int findInRow(T)(T row, int x, int x0) const
    {
        int x1 = x0;
        foreach (i; 0 .. row.length)
        {
            x1 += row[i].width;
            const int mx = (x0 + x1) / 2;
            if (x <= mx)
                return cast(int)i;
            x0 = x1;
        }
        return -1;
    }

    private void handleChange(TextChange op, uint i, uint c)
    {
        import std.array : insertInPlace, replaceInPlace;

        if (op == TextChange.replaceAll)
        {
            _lines.length = c;
            foreach (j; 0 .. c)
            {
                _lines[j].str = _content[j];
                _lines[j].measured = false;
            }
        }
        else if (op == TextChange.append)
        {
            foreach (j; _content.lineCount - c - 1 .. _content.lineCount)
                _lines ~= TextLine(_content[j]);
        }
        else if (op == TextChange.insert)
        {
            if (c > 1)
            {
                import std.algorithm : map;

                auto ls = map!(s => TextLine(s))(_content.lines[i .. i + c]);
                insertInPlace(_lines, i, ls);
            }
            else if (c == 1)
            {
                insertInPlace(_lines, i, TextLine(_content[i]));
            }
        }
        else if (op == TextChange.replace)
        {
            foreach (j; i .. i + c)
            {
                _lines[j].str = _content[j];
                _lines[j].measured = false;
            }
        }
        else if (op == TextChange.remove)
        {
            // TODO: delete markup
            TextLine[] dummy;
            replaceInPlace(_lines, i, i + c, dummy);
        }
        needToMeasureText();
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case tabSize:
            _txtStyle.tabSize = style.tabSize;
            break;
        case textAlign:
            _txtStyle.alignment = style.textAlign;
            break;
        case textColor:
            _txtStyle.color = style.textColor;
            break;
        case textDecorColor:
            _txtStyle.decoration.color = style.textDecorColor;
            break;
        case textDecorLine:
            _txtStyle.decoration.line = style.textDecorLine;
            break;
        case textDecorStyle:
            _txtStyle.decoration.style = style.textDecorStyle;
            break;
        case textOverflow:
            _txtStyle.overflow = style.textOverflow;
            break;
        case textTransform:
            _txtStyle.transform = style.textTransform;
            minSizeTester.style.transform = style.textTransform;
            natSizeTester.style.transform = style.textTransform;
            break;
        default:
            break;
        }
    }

    override protected void handleFontChange()
    {
        Font f = font.get;
        _txtStyle.font = f;
        minSizeTester.style.font = f;
        natSizeTester.style.font = f;
    }

    private void needToMeasureText()
    {
        _oldTLStyle.font = null;
        requestLayout();
    }

    override void measure()
    {
        assert(_lines.length == _content.lineCount);

        updateStyles();

        Size tsz;
        auto tlstyle = TextLayoutStyle(_txtStyle);
        if (_oldTLStyle !is tlstyle)
        {
            _oldTLStyle = tlstyle;

            foreach (ref line; _lines)
            {
                line.measure(tlstyle);
                tsz.w = max(tsz.w, line.size.w);
                tsz.h += line.size.h;
            }
            _size = tsz;
            _sizeAfterWrap = tsz;
        }
        else
            tsz = _size;

        Boundaries bs;
        const tmin = minSizeTester.getSize();
        const tnat = natSizeTester.getSize();
        bs.min.w = min(tsz.w, tmin.w);
        bs.min.h = min(tsz.h, tmin.h);
        bs.nat.w = max(tsz.w, tnat.w);
        bs.nat.h = max(tsz.h, tnat.h);
        setBoundaries(bs);
    }

    override int heightForWidth(int width)
    {
        Size p = padding.size;
        wrap(width - p.w);
        return _sizeAfterWrap.h + p.h;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        setBox(geom);
        // wrap again in case the parent widget had not called heightForWidth
        // must be cached when width is the same
        wrap(geom.w - padding.width);
    }

    /// Wrap lines within a width
    private void wrap(int boxWidth)
    {
        if (boxWidth == _sizeAfterWrap.w)
            return;

        if (_txtStyle.wrap)
        {
            int h;
            foreach (ref line; _lines)
                h += line.wrap(boxWidth);
            _sizeAfterWrap.h = h;
        }
        _sizeAfterWrap.w = boxWidth;
    }

    override void draw(DrawBuf buf)
    {
        assert(_lines.length == _content.lineCount);

        _visibleLines.clear();
        if (_lines.length == 0 || visibility != Visibility.visible)
            return;

        super.draw(buf);
        const b = innerBox;
        const saver = ClipRectSaver(buf, b, style.alpha);

        const clip = buf.clipRect;
        if (clip.empty)
            return; // clipped out

        // draw the paragraph at (b.x, b.y)
        int y;
        foreach (i, ref line; _lines)
        {
            const p = Point(b.x, b.y + y);
            const h = line.height;
            if (p.y + h < clip.top)
            {
                y += h;
                continue; // line is fully above the clipping rectangle
            }
            if (clip.bottom <= p.y)
                break; // or below

            const x = line.draw(buf, p, _sizeAfterWrap.w, _txtStyle);
            _visibleLines ~= VisibleLine(cast(uint)i, x, y);
            y += h;
        }
    }
}
