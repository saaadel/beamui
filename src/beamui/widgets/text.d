/**
Widgets to show plain or formatted single- and multiline text.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.widgets.text;

import beamui.core.editable : ListChange, TextContent, TextPosition;
import beamui.text.line;
import beamui.text.simple;
import beamui.text.sizetest;
import beamui.text.style;
import beamui.widgets.widget;

/** Efficient single- or multiline plain text widget.

    Can contain `&` character to underline a mnemonic key.
*/
class Label : Widget
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

            // needed because `style.textHotkey` may change
            updateStyles();

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
        TextSizeTester natSizeTester;
    }

    this(dstring txt = null)
    {
        original = txt;
        textobj.str = txt;
        minSizeTester.str = "aaaaa";
        // natSizeTester.str =
        //     "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\na";
        // dependentSize = DependentSize.height;
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case tabSize:
            const tsz = style.tabSize;
            textobj.style.tabSize = tsz;
            minSizeTester.style.tabSize = tsz;
            natSizeTester.style.tabSize = tsz;
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
        case textOverflow:
            textobj.style.overflow = style.textOverflow;
            break;
        case textTransform:
            const tr = style.textTransform;
            textobj.style.transform = tr;
            minSizeTester.style.transform = tr;
            natSizeTester.style.transform = tr;
            break;
        default:
            break;
        }
    }

    override protected void handleFontChange()
    {
        Font f = font.get;
        textobj.style.font = f;
        minSizeTester.style.font = f;
        natSizeTester.style.font = f;
    }

    override void measure()
    {
        updateStyles();

        textobj.measure();

        Boundaries bs;
        const sz = textobj.size;
        const tmin = minSizeTester.getSize();
        const tnat = natSizeTester.getSize();
        bs.min.w = min(sz.w, tmin.w);
        bs.min.h = min(sz.h, tmin.h);
        bs.nat.w = max(sz.w, tnat.w);
        bs.nat.h = max(sz.h, tnat.h);
        setBoundaries(bs);
    }

    override int heightForWidth(int width)
    {
        Size p = padding.size;
        textobj.wrap(width - p.w);
        return textobj.sizeAfterWrap.h + p.h;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        // wrap again in case the parent widget had not called heightForWidth
        // must be cached when width is the same
        // textobj.wrap(geom.w - padding.width);
    }

    override protected void drawContent(DrawBuf buf)
    {
        const b = innerBox;
        const sv = ClipRectSaver(buf, b);

        textobj.style.underlinedCharIndex = textHotkey == TextHotkey.underline ? hotkeyIndex : -1;

        // TODO: align vertically?
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
            _content.setStr(s);
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
        _content.afterChange ~= &handleChange;

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
        _content.afterChange -= &handleChange;
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
        const glyphs = line.glyphs;
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
                        x += glyphs[i].width;
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
                    x += glyphs[i].width;
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

        // find the line first
        VisibleLine vline = _visibleLines[$ - 1]; // default as if it is lower
        const VisibleLine first = _visibleLines[0];
        if (pt.y < first.y) // upper
        {
            vline = first;
        }
        else if (pt.y < vline.y + _lines[vline.index].height) // inside
        {
            foreach (ln; _visibleLines)
            {
                if (ln.y <= pt.y && pt.y < ln.y + _lines[ln.index].height)
                {
                    vline = ln;
                    break;
                }
            }
        }
        const TextLine* line = &_lines[vline.index];
        // then find the column
        const glyphs = line.glyphs;
        if (line.wrapped)
        {
            int y = vline.y;
            foreach (ref span; line.wrapSpans)
            {
                if (y <= pt.y && pt.y < y + span.height)
                {
                    int col = findClosestGlyphInRow(glyphs[span.start .. span.end], span.offset, pt.x);
                    if (col != -1)
                        col += span.start;
                    else
                        col = span.end;
                    return TextPosition(vline.index, col);
                }
                y += span.height;
            }
        }
        else
        {
            const col = findClosestGlyphInRow(glyphs, vline.x, pt.x);
            if (col != -1)
                return TextPosition(vline.index, col);
        }
        return TextPosition(vline.index, line.glyphCount);
    }

    private void handleChange(ListChange op, uint i, uint c)
    {
        import std.array : insertInPlace, replaceInPlace;

        if (op == ListChange.replaceAll)
        {
            _lines.length = c;
            foreach (j; 0 .. c)
            {
                _lines[j].str = _content[j];
                _lines[j].measured = false;
            }
        }
        else if (op == ListChange.append)
        {
            foreach (j; _content.lineCount - c - 1 .. _content.lineCount)
                _lines ~= TextLine(_content[j]);
        }
        else if (op == ListChange.insert)
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
        else if (op == ListChange.replace)
        {
            foreach (j; i .. i + c)
            {
                _lines[j].str = _content[j];
                _lines[j].measured = false;
            }
        }
        else if (op == ListChange.remove)
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
            const tsz = style.tabSize;
            _txtStyle.tabSize = tsz;
            minSizeTester.style.tabSize = tsz;
            natSizeTester.style.tabSize = tsz;
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
            const tr = style.textTransform;
            _txtStyle.transform = tr;
            minSizeTester.style.transform = tr;
            natSizeTester.style.transform = tr;
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

    override protected void drawContent(DrawBuf buf)
    {
        assert(_lines.length == _content.lineCount);

        _visibleLines.clear();
        if (_lines.length == 0)
            return;

        const b = innerBox;
        const sv = ClipRectSaver(buf, b);

        const clip = buf.clipRect;
        if (clip.empty)
            return; // clipped out

        // draw the paragraph at (b.x, b.y)
        int y;
        foreach (i, ref line; _lines)
        {
            const py = b.y + y;
            const h = line.height;
            if (py + h < clip.top)
            {
                y += h;
                continue; // line is fully above the clipping rectangle
            }
            if (clip.bottom <= py)
                break; // or below

            const x = line.draw(buf, b.x, py, _sizeAfterWrap.w, _txtStyle);
            _visibleLines ~= VisibleLine(cast(uint)i, x, y);
            y += h;
        }
    }
}
