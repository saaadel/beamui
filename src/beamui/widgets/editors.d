/**
Single-line and multiline simple text editors.

Copyright: Vadim Lopatin 2014-2017, James Johnson 2017, dayllenger 2019
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.editors;

public import beamui.core.editable;
import beamui.core.collections;
import beamui.core.linestream;
import beamui.core.parseutils : isWordChar;
import beamui.core.signals;
import beamui.core.stdaction;
import beamui.core.streams;
import beamui.graphics.colors;
import beamui.text.line;
import beamui.text.simple;
import beamui.text.sizetest;
import beamui.text.style;
import beamui.widgets.controls;
import beamui.widgets.menu;
import beamui.widgets.popup;
import beamui.widgets.scroll;
import beamui.widgets.scrollbar;
import beamui.widgets.widget;
import beamui.platforms.common.platform;

/// Editor state to display in status line
struct EditorStateInfo
{
    /// Editor mode: true if replace mode, false if insert mode
    bool replaceMode;
    /// Cursor position column (1-based)
    int col;
    /// Cursor position line (1-based)
    int line;
    /// Character under cursor
    dchar character;
    /// Returns true if editor is in active state
    @property bool active() const
    {
        return col > 0 && line > 0;
    }
}

/// Flags used for search / replace / text highlight
enum TextSearchOptions
{
    none = 0,
    caseSensitive = 1,
    wholeWords = 2,
    selectionOnly = 4,
}

/// Delete word before cursor (ctrl + backspace)
Action ACTION_ED_DEL_PREV_WORD;
/// Delete char after cursor (ctrl + del key)
Action ACTION_ED_DEL_NEXT_WORD;

/// Indent text block or single line (e.g., Tab key to insert tab character)
Action ACTION_ED_INDENT;
/// Unindent text or remove whitespace before cursor (usually Shift+Tab)
Action ACTION_ED_UNINDENT;

/// Insert new line before current position (Ctrl+Shift+Enter)
Action ACTION_ED_PREPEND_NEW_LINE;
/// Insert new line after current position (Ctrl+Enter)
Action ACTION_ED_APPEND_NEW_LINE;
/// Delete current line
Action ACTION_ED_DELETE_LINE;
/// Turn On/Off replace mode
Action ACTION_ED_TOGGLE_REPLACE_MODE;

/// Toggle line comment
Action ACTION_ED_TOGGLE_LINE_COMMENT;
/// Toggle block comment
Action ACTION_ED_TOGGLE_BLOCK_COMMENT;
/// Toggle bookmark in current line
Action ACTION_ED_TOGGLE_BOOKMARK;
/// Move cursor to next bookmark
Action ACTION_ED_GOTO_NEXT_BOOKMARK;
/// Move cursor to previous bookmark
Action ACTION_ED_GOTO_PREVIOUS_BOOKMARK;

/// Find text
Action ACTION_ED_FIND;
/// Find next occurence - continue search forward
Action ACTION_ED_FIND_NEXT;
/// Find previous occurence - continue search backward
Action ACTION_ED_FIND_PREV;
/// Replace text
Action ACTION_ED_REPLACE;

void initStandardEditorActions()
{
    ACTION_ED_DEL_PREV_WORD = new Action(null, Key.backspace, KeyMods.control);
    ACTION_ED_DEL_NEXT_WORD = new Action(null, Key.del, KeyMods.control);

    ACTION_ED_INDENT = new Action(null, Key.tab);
    ACTION_ED_UNINDENT = new Action(null, Key.tab, KeyMods.shift);

    ACTION_ED_PREPEND_NEW_LINE = new Action(tr("Prepend new line"), Key.enter, KeyMods.control | KeyMods.shift);
    ACTION_ED_APPEND_NEW_LINE = new Action(tr("Append new line"), Key.enter, KeyMods.control);
    ACTION_ED_DELETE_LINE = new Action(tr("Delete line"), Key.D, KeyMods.control).addShortcut(Key.L, KeyMods.control);
    ACTION_ED_TOGGLE_REPLACE_MODE = new Action(tr("Replace mode"), Key.ins);
    ACTION_ED_TOGGLE_LINE_COMMENT = new Action(tr("Toggle line comment"), Key.divide, KeyMods.control);
    ACTION_ED_TOGGLE_BLOCK_COMMENT = new Action(tr("Toggle block comment"), Key.divide, KeyMods.control | KeyMods.shift);

    ACTION_ED_TOGGLE_BOOKMARK = new Action(tr("Toggle bookmark"), Key.B, KeyMods.control | KeyMods.shift);
    ACTION_ED_GOTO_NEXT_BOOKMARK = new Action(tr("Go to next bookmark"), Key.down, KeyMods.control | KeyMods.shift | KeyMods.alt);
    ACTION_ED_GOTO_PREVIOUS_BOOKMARK = new Action(tr("Go to previous bookmark"), Key.up, KeyMods.control | KeyMods.shift | KeyMods.alt);

    ACTION_ED_FIND = new Action(tr("Find..."), Key.F, KeyMods.control);
    ACTION_ED_FIND_NEXT = new Action(tr("Find next"), Key.F3);
    ACTION_ED_FIND_PREV = new Action(tr("Find previous"), Key.F3, KeyMods.shift);
    ACTION_ED_REPLACE = new Action(tr("Replace..."), Key.H, KeyMods.control);

    bunch(
        ACTION_ED_DEL_PREV_WORD,
        ACTION_ED_DEL_NEXT_WORD,
        ACTION_ED_INDENT,
        ACTION_ED_UNINDENT,
    ).context(ActionContext.widget);
    bunch(
        ACTION_ED_PREPEND_NEW_LINE,
        ACTION_ED_APPEND_NEW_LINE,
        ACTION_ED_DELETE_LINE,
        ACTION_ED_TOGGLE_REPLACE_MODE,
        ACTION_ED_TOGGLE_LINE_COMMENT,
        ACTION_ED_TOGGLE_BLOCK_COMMENT,
        ACTION_ED_TOGGLE_BOOKMARK,
        ACTION_ED_GOTO_NEXT_BOOKMARK,
        ACTION_ED_GOTO_PREVIOUS_BOOKMARK,
        ACTION_ED_FIND,
        ACTION_ED_FIND_NEXT,
        ACTION_ED_FIND_PREV,
        ACTION_ED_REPLACE
    ).context(ActionContext.widgetTree);
}

/// Base for all editor widgets
class EditWidgetBase : ScrollAreaBase, ActionOperator
{
    @property
    {
        /// Editor content object
        inout(EditableContent) content() inout { return _content; }
        /// ditto
        void content(EditableContent content)
        {
            if (_content is content)
                return; // not changed
            if (_content !is null)
            {
                // disconnect old content
                _content.onContentChange.disconnect(&handleContentChange);
                if (_ownContent)
                {
                    destroy(_content);
                }
            }
            _content = content;
            _ownContent = false;
            _content.onContentChange.connect(&handleContentChange);
            if (_content.readOnly)
                enabled = false;
        }

        /// Readonly flag (when true, user cannot change content of editor)
        bool readOnly() const
        {
            return !enabled || _content.readOnly;
        }
        /// ditto
        void readOnly(bool readOnly)
        {
            enabled = !readOnly;
            invalidate();
        }

        /// Replace mode flag (when true, entered character replaces character under cursor)
        bool replaceMode() const { return _replaceMode; }
        /// ditto
        void replaceMode(bool replaceMode)
        {
            _replaceMode = replaceMode;
            handleEditorStateChange();
            invalidate();
        }

        /// When true, spaces will be inserted instead of tabs on Tab key
        bool useSpacesForTabs() const
        {
            return _content.useSpacesForTabs;
        }
        /// ditto
        void useSpacesForTabs(bool useSpacesForTabs)
        {
            _content.useSpacesForTabs = useSpacesForTabs;
        }

        /// Tab size (in number of spaces)
        int tabSize() const
        {
            return _content.tabSize;
        }
        /// ditto
        void tabSize(int value)
        {
            const ts = TabSize(value);
            if (ts != _content.tabSize)
            {
                _content.tabSize = ts;
                _txtStyle.tabSize = ts;
                requestLayout();
            }
        }

        /// True if smart indents are supported
        bool supportsSmartIndents() const
        {
            return _content.supportsSmartIndents;
        }
        /// True if smart indents are enabled
        bool smartIndents() const
        {
            return _content.smartIndents;
        }
        /// ditto
        void smartIndents(bool enabled)
        {
            _content.smartIndents = enabled;
        }

        /// True if smart indents are enabled
        bool smartIndentsAfterPaste() const
        {
            return _content.smartIndentsAfterPaste;
        }
        /// ditto
        void smartIndentsAfterPaste(bool enabled)
        {
            _content.smartIndentsAfterPaste = enabled;
        }

        /// When true shows mark on tab positions in beginning of line
        bool showTabPositionMarks() const { return _showTabPositionMarks; }
        /// ditto
        void showTabPositionMarks(bool flag)
        {
            if (flag != _showTabPositionMarks)
            {
                _showTabPositionMarks = flag;
                invalidate();
            }
        }

        /// To hold _scrollpos.x toggling between normal and word wrap mode
        private int previousXScrollPos;
        private ScrollBarMode previousHScrollbarMode;
        /// True if word wrap mode is set
        bool wordWrap() const { return _wordWrap; }
        /// ditto
        void wordWrap(bool v)
        {
            _wordWrap = v;
            _txtStyle.wrap = v;
            // horizontal scrollbar should not be visible in word wrap mode
            if (v)
            {
                previousHScrollbarMode = hscrollbarMode;
                previousXScrollPos = scrollPos.x;
                hscrollbarMode = ScrollBarMode.hidden;
                scrollPos.x = 0;
            }
            else
            {
                hscrollbarMode = previousHScrollbarMode;
                scrollPos.x = previousXScrollPos;
            }
            invalidate();
        }

        /// Text in the editor
        override dstring text() const
        {
            return _content.text;
        }
        /// ditto
        override void text(dstring s)
        {
            _content.text = s;
            requestLayout();
        }

        dstring minSizeTester() const
        {
            return _minSizeTester.str;
        }
        /// ditto
        void minSizeTester(dstring txt)
        {
            _minSizeTester.str = txt;
            requestLayout();
        }

        /// Placeholder is a short peace of text that describe expected value in an input field
        dstring placeholder() const
        {
            return _placeholder ? _placeholder.str : null;
        }
        /// ditto
        void placeholder(dstring txt)
        {
            if (!_placeholder)
            {
                if (txt.length > 0)
                {
                    _placeholder = new SimpleText(txt);
                    _placeholder.style.font = font;
                    _placeholder.style.color = NamedColor.gray;
                }
            }
            else
                _placeholder.str = txt;
        }

        /// Font line height, always > 0
        protected int lineHeight() const { return _lineHeight; }
    }

    /// When true, Tab / Shift+Tab presses are processed internally in widget (e.g. insert tab character) instead of focus change navigation.
    bool wantTabs = true;
    /// When true, allows copy / cut whole current line if there is no selection
    bool copyCurrentLineWhenNoSelection = true;

    /// Modified state change listener (e.g. content has been saved, or first time modified after save)
    Signal!(void delegate(bool modified)) onModifiedStateChange;

    /// Signal to emit when editor content is changed
    Signal!(void delegate(EditableContent)) onContentChange;

    /// Signal to emit when editor cursor position or Insert/Replace mode is changed.
    Signal!(void delegate(ref EditorStateInfo editorState)) onStateChange;

    // left pane - can be used to show line numbers, collapse controls, bookmarks, breakpoints, custom icons
    protected int _leftPaneWidth;

    private
    {
        EditableContent _content;
        /// When `_ownContent` is false, `_content` should not be destroyed in editor destructor
        bool _ownContent = true;

        int _lineHeight = 1;
        int _spaceWidth;

        bool _selectAllWhenFocusedWithTab;
        bool _deselectAllWhenUnfocused;

        bool _replaceMode;

        Color _selectionColorFocused = Color(0x60A0FF, 0x50);
        Color _selectionColorNormal = Color(0x60A0FF, 0x30);
        Color _searchHighlightColorCurrent = Color(0x8080FF, 0x80);
        Color _searchHighlightColorOther = Color(0x8080FF, 0x40);

        Color _caretColor = Color(0x0);
        Color _caretColorReplace = Color(0x8080FF, 0x80);
        Color _matchingBracketHighlightColor = Color(0xFFE0B0, 0xA0);

        /// When true, call `measureVisibleText` on next layout
        bool _contentChanged = true;

        bool _showTabPositionMarks;

        bool _wordWrap;

        TextStyle _txtStyle;
        SimpleText* _placeholder;
        TextSizeTester _minSizeTester;
    }

    this(ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        super(hscrollbarMode, vscrollbarMode);
        allowsFocus = true;
        bindActions();
        handleFontChange();
    }

    ~this()
    {
        unbindActions();
        if (_ownContent)
        {
            destroy(_content);
            _content = null;
        }
    }

    //===============================================================
    // Focus

    override @property bool canFocus() const
    {
        // allow to focus even if not enabled
        return allowsFocus && visible;
    }

    override Widget setFocus(FocusReason reason = FocusReason.unspecified)
    {
        Widget res = super.setFocus(reason);
        if (focused)
            handleEditorStateChange();
        return res;
    }

    override protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
    {
        if (focused)
        {
            updateActions();
            startCaretBlinking();
        }
        else
        {
            stopCaretBlinking();
            cancelHoverTimer();

            if (_deselectAllWhenUnfocused)
                clearSelectionInternal();
        }
        if (focused && _selectAllWhenFocusedWithTab && receivedFocusFromKeyboard)
            selectAll();
        super.handleFocusChange(focused);
    }

    //===============================================================

    override void handleThemeChange()
    {
        super.handleThemeChange();
        _caretColor = currentTheme.getColor("edit_caret", Color(0x0));
        _caretColorReplace = currentTheme.getColor("edit_caret_replace", Color(0x8080FF, 0x80));
        _selectionColorFocused = currentTheme.getColor("editor_selection_focused", Color(0x60A0FF, 0x50));
        _selectionColorNormal = currentTheme.getColor("editor_selection_normal", Color(0x60A0FF, 0x30));
        _searchHighlightColorCurrent = currentTheme.getColor("editor_search_highlight_current", Color(0x8080FF, 0x80));
        _searchHighlightColorOther = currentTheme.getColor("editor_search_highlight_other", Color(0x8080FF, 0x40));
        _matchingBracketHighlightColor = currentTheme.getColor("editor_matching_bracket_highlight", Color(0xFFE0B0, 0xA0));
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        if (auto ph = _placeholder)
        {
            switch (ptype) with (StyleProperty)
            {
            case textAlign:
                ph.style.alignment = style.textAlign;
                break;
            case textDecorLine:
                ph.style.decoration.line = style.textDecorLine;
                break;
            case textDecorStyle:
                ph.style.decoration.style = style.textDecorStyle;
                break;
            case textOverflow:
                ph.style.overflow = style.textOverflow;
                break;
            case textTransform:
                ph.style.transform = style.textTransform;
                break;
            default:
                break;
            }
        }

        switch (ptype) with (StyleProperty)
        {
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
            _minSizeTester.style.transform = style.textTransform;
            break;
        default:
            break;
        }
    }

    override protected void handleFontChange()
    {
        Font font = font();
        _spaceWidth = font.spaceWidth;
        _lineHeight = max(font.height, 1);
        _txtStyle.font = font;
        _minSizeTester.style.font = font;
        if (auto ph = _placeholder)
            ph.style.font = font;
    }

    /// Updates `onStateChange` with recent position
    protected void handleEditorStateChange()
    {
        if (!onStateChange.assigned)
            return;
        EditorStateInfo info;
        if (visible)
        {
            info.replaceMode = _replaceMode;
            info.line = _caretPos.line + 1;
            info.col = _caretPos.pos + 1;
            if (0 <= _caretPos.line && _caretPos.line < _content.lineCount)
            {
                dstring line = _content.line(_caretPos.line);
                if (_caretPos.pos >= 0 && _caretPos.pos < line.length)
                    info.character = line[_caretPos.pos];
                else
                    info.character = '\n';
            }
        }
        onStateChange(info);
    }

    override protected void adjustClientBox(ref Box clb)
    {
        updateLeftPaneWidth();
        clb.x += _leftPaneWidth;
        clb.w -= _leftPaneWidth;
    }

    /// Override to add custom items on left panel
    protected void updateLeftPaneWidth()
    {
    }

    override bool canShowPopupMenu(int x, int y)
    {
        if (popupMenu is null)
            return false;
        if (popupMenu.openingSubmenu.assigned)
            if (!popupMenu.openingSubmenu(popupMenu))
                return false;
        return true;
    }

    override CursorType getCursorType(int x, int y) const
    {
        return x < box.x + _leftPaneWidth ? CursorType.arrow : CursorType.ibeam;
    }

    //===============================================================

    protected void processSmartIndent(EditOperation operation)
    {
        if (!supportsSmartIndents)
            return;
        if (!smartIndents && !smartIndentsAfterPaste)
            return;
        _content.syntaxSupport.applySmartIndent(operation, this);
    }

    protected void handleContentChange(EditOperation operation,
            ref TextRange rangeBefore, ref TextRange rangeAfter, Object source)
    {
        debug (editors)
            Log.d("handleContentChange rangeBefore: ", rangeBefore, ", rangeAfter: ", rangeAfter,
                    ", text: ", operation.content);
        _contentChanged = true;
        if (source is this)
        {
            if (operation.action == EditAction.replaceContent)
            {
                // fully replaced, e.g., loaded from file or text property is assigned
                _caretPos = rangeAfter.end;
                clearSelectionInternal();
                measureVisibleText();
                ensureCaretVisible();
                correctCaretPos();
                requestLayout();
                updateActions();
            }
            else if (operation.action == EditAction.saveContent)
            {
                // saved
            }
            else
            {
                // modified
                _caretPos = rangeAfter.end;
                clearSelectionInternal();
                measureVisibleText();
                ensureCaretVisible();
                updateActions();
                processSmartIndent(operation);
            }
        }
        else
        {
            measureVisibleText();
            correctCaretPos();
            requestLayout();
            updateActions();
        }
        invalidate();
        if (onModifiedStateChange.assigned)
        {
            if (_lastReportedModifiedState != _content.modified)
            {
                _lastReportedModifiedState = _content.modified;
                onModifiedStateChange(_content.modified);
                updateActions();
            }
        }
        onContentChange(_content);
        handleEditorStateChange();
        return;
    }

    private bool _lastReportedModifiedState;

    abstract protected Size measureVisibleText();

    //===============================================================
    // Coordinate mapping, caret, and selection

    abstract protected Box textPosToClient(TextPosition p) const;

    abstract protected TextPosition clientToTextPos(Point pt) const;

    abstract protected void ensureCaretVisible(bool center = false);

    private
    {
        TextPosition _caretPos;
        TextRange _selectionRange;

        int _caretBlinkingInterval = 800;
        ulong _caretTimerID;
        bool _caretBlinkingPhase;
        long _lastBlinkStartTs;
        bool _caretBlinks = true;
    }

    @property
    {
        /// Returns caret position
        TextPosition caretPos() const { return _caretPos; }

        /// Current selection range
        TextRange selectionRange() const { return _selectionRange; }
        /// ditto
        void selectionRange(TextRange range)
        {
            if (range.empty)
                return;
            _selectionRange = range;
            _caretPos = range.end;
            handleEditorStateChange();
        }

        /// When true, enables caret blinking, otherwise it's always visible
        bool showCaretBlinking() const { return _caretBlinks; }
        /// ditto
        void showCaretBlinking(bool blinks)
        {
            _caretBlinks = blinks;
        }
    }

    /// Change caret position, fixing it to valid bounds
    void setCaretPos(int line, int column, bool select = false)
    {
        auto pos = TextPosition(line, column);
        _content.correctPosition(pos);
        if (_caretPos != pos)
        {
            const old = _caretPos;
            _caretPos = pos;
            updateSelectionAfterCursorMovement(old, select);
        }
    }
    /// Change caret position, fixing it to valid bounds, and ensure it is visible
    void jumpTo(int line, int column, bool select = false, bool center = false)
    {
        auto pos = TextPosition(line, column);
        _content.correctPosition(pos);
        if (_caretPos != pos)
        {
            const old = _caretPos;
            _caretPos = pos;
            updateSelectionAfterCursorMovement(old, select);
            ensureCaretVisible(center);
        }
    }

    protected void startCaretBlinking()
    {
        if (auto win = window)
        {
            static if (BACKEND_CONSOLE)
            {
                win.caretRect = caretRect;
                win.caretReplace = _replaceMode;
            }
            else
            {
                const long ts = currentTimeMillis;
                if (_caretTimerID)
                {
                    if (_lastBlinkStartTs + _caretBlinkingInterval / 4 > ts)
                        return; // don't update timer too frequently
                    cancelTimer(_caretTimerID);
                }
                _caretTimerID = setTimer(_caretBlinkingInterval / 2, {
                    _caretBlinkingPhase = !_caretBlinkingPhase;
                    if (!_caretBlinkingPhase)
                        _lastBlinkStartTs = currentTimeMillis;
                    invalidate();
                    const bool repeat = focused;
                    if (!repeat)
                        _caretTimerID = 0;
                    return repeat;
                });
                _lastBlinkStartTs = ts;
                _caretBlinkingPhase = false;
                invalidate();
            }
        }
    }

    protected void stopCaretBlinking()
    {
        if (auto win = window)
        {
            static if (BACKEND_CONSOLE)
            {
                win.caretRect = Rect.init;
            }
            else
            {
                if (_caretTimerID)
                {
                    cancelTimer(_caretTimerID);
                    _caretTimerID = 0;
                }
            }
        }
    }

    /// In word wrap mode, set by caretRect so ensureCaretVisible will know when to scroll
    private int caretHeightOffset;

    /// Returns cursor rectangle
    protected Rect caretRect() const
    {
        Box caret = textPosToClient(_caretPos);
        if (_replaceMode)
        {
            caret.w = _spaceWidth;
            if (_caretPos.pos < _content.lineLength(_caretPos.line))
            {
                const nextPos = TextPosition(_caretPos.line, _caretPos.pos + 1);
                const nextBox = textPosToClient(nextPos);
                // if it is not a line break
                if (caret.x < nextBox.x)
                    caret.w = nextBox.x - caret.x;
            }
        }
        caret.x += clientBox.x;
        caret.y += clientBox.y;
        return Rect(caret);
    }

    /// Draw caret
    protected void drawCaret(DrawBuf buf)
    {
        if (focused)
        {
            if (_caretBlinkingPhase && _caretBlinks)
                return;

            const Rect r = caretRect();
            if (r.intersects(Rect(clientBox)))
            {
                if (_replaceMode && BACKEND_GUI)
                    buf.fillRect(r, _caretColorReplace);
                else
                    buf.fillRect(Rect(r.left, r.top, r.left + 1, r.bottom), _caretColor);
            }
        }
    }

    /// When cursor position or selection is out of content bounds, fix it to nearest valid position
    protected void correctCaretPos()
    {
        const oldCaretPos = _caretPos;
        _content.correctPosition(_caretPos);
        _content.correctPosition(_selectionRange.start);
        _content.correctPosition(_selectionRange.end);
        if (_selectionRange.empty)
            clearSelectionInternal();
        if (oldCaretPos != _caretPos)
            handleEditorStateChange();
    }

    protected void updateSelectionAfterCursorMovement(TextPosition oldCaretPos, bool selecting)
    {
        if (selecting)
        {
            if (oldCaretPos == _selectionRange.start)
            {
                if (_caretPos >= _selectionRange.end)
                {
                    _selectionRange.start = _selectionRange.end;
                    _selectionRange.end = _caretPos;
                }
                else
                {
                    _selectionRange.start = _caretPos;
                }
            }
            else if (oldCaretPos == _selectionRange.end)
            {
                if (_caretPos < _selectionRange.start)
                {
                    _selectionRange.end = _selectionRange.start;
                    _selectionRange.start = _caretPos;
                }
                else
                {
                    _selectionRange.end = _caretPos;
                }
            }
            else
            {
                if (oldCaretPos < _caretPos)
                {
                    // start selection forward
                    _selectionRange.start = oldCaretPos;
                    _selectionRange.end = _caretPos;
                }
                else
                {
                    // start selection backward
                    _selectionRange.start = _caretPos;
                    _selectionRange.end = oldCaretPos;
                }
            }
        }
        else
            clearSelectionInternal();
        invalidate();
        updateActions();
        handleEditorStateChange();
    }

    private dstring _textToHighlight;
    private TextSearchOptions _textToHighlightOptions;

    /// Text pattern to highlight - e.g. for search
    @property dstring textToHighlight() const { return _textToHighlight; }
    /// Set text to highlight -- e.g. for search
    void setTextToHighlight(dstring pattern, TextSearchOptions textToHighlightOptions)
    {
        _textToHighlight = pattern;
        _textToHighlightOptions = textToHighlightOptions;
        invalidate();
    }

    protected void selectWordByMouse(int x, int y)
    {
        const TextPosition oldCaretPos = _caretPos;
        const TextPosition newPos = clientToTextPos(Point(x, y));
        const TextRange r = _content.wordBounds(newPos);
        if (r.start < r.end)
        {
            _selectionRange = r;
            _caretPos = r.end;
            invalidate();
            updateActions();
        }
        else
        {
            _caretPos = newPos;
            updateSelectionAfterCursorMovement(oldCaretPos, false);
        }
        handleEditorStateChange();
    }

    protected void selectLineByMouse(int x, int y)
    {
        const TextPosition oldCaretPos = _caretPos;
        const TextPosition newPos = clientToTextPos(Point(x, y));
        const TextRange r = _content.lineRange(newPos.line);
        if (r.start < r.end)
        {
            _selectionRange = r;
            _caretPos = r.end;
            invalidate();
            updateActions();
        }
        else
        {
            _caretPos = newPos;
            updateSelectionAfterCursorMovement(oldCaretPos, false);
        }
        handleEditorStateChange();
    }

    protected void updateCaretPositionByMouse(int x, int y, bool selecting)
    {
        const TextPosition pos = clientToTextPos(Point(x, y));
        setCaretPos(pos.line, pos.pos, selecting);
    }

    /// Generate string of spaces, to reach next tab position
    protected dstring spacesForTab(int currentPos)
    {
        const int newPos = (currentPos + tabSize + 1) / tabSize * tabSize;
        return "                "d[0 .. (newPos - currentPos)];
    }

    /// Returns true if one or more lines selected fully
    final protected bool multipleLinesSelected() const
    {
        return _selectionRange.end.line > _selectionRange.start.line;
    }

    private bool _camelCasePartsAsWords = true;

    void replaceSelectionText(dstring newText)
    {
        auto op = new EditOperation(EditAction.replace, _selectionRange, [newText]);
        _content.performOperation(op, this);
    }

    protected bool removeSelectionTextIfSelected()
    {
        if (_selectionRange.empty)
            return false;
        // clear selection
        auto op = new EditOperation(EditAction.replace, _selectionRange, [""d]);
        _content.performOperation(op, this);
        return true;
    }

    /// Returns current selection text (joined with LF when span over multiple lines)
    dstring getSelectedText() const
    {
        return getRangeText(_selectionRange);
    }

    /// Returns text for specified range (joined with LF when span over multiple lines)
    dstring getRangeText(TextRange range) const
    {
        return concatDStrings(_content.rangeText(range));
    }

    /// Returns range for line with cursor
    @property TextRange currentLineRange() const
    {
        return _content.lineRange(_caretPos.line);
    }

    /// Clear selection (doesn't change text, just deselects)
    void clearSelection()
    {
        _selectionRange = TextRange(_caretPos, _caretPos);
        invalidate();
    }

    private void clearSelectionInternal()
    {
        _selectionRange = TextRange(_caretPos, _caretPos);
    }

    protected bool removeRangeText(TextRange range)
    {
        if (range.empty)
            return false;
        _selectionRange = range;
        _caretPos = _selectionRange.start;
        auto op = new EditOperation(EditAction.replace, range, [""d]);
        _content.performOperation(op, this);
        return true;
    }

    //===============================================================
    // Actions

    protected void bindActions()
    {
        debug (editors)
            Log.d("Editor `", id, "`: bind actions");

        ACTION_LINE_BEGIN.bind(this, { jumpToLineBegin(false); });
        ACTION_LINE_END.bind(this, { jumpToLineEnd(false); });
        ACTION_DOCUMENT_BEGIN.bind(this, { jumpToDocumentBegin(false); });
        ACTION_DOCUMENT_END.bind(this, { jumpToDocumentEnd(false); });
        ACTION_SELECT_LINE_BEGIN.bind(this, { jumpToLineBegin(true); });
        ACTION_SELECT_LINE_END.bind(this, { jumpToLineEnd(true); });
        ACTION_SELECT_DOCUMENT_BEGIN.bind(this, { jumpToDocumentBegin(true); });
        ACTION_SELECT_DOCUMENT_END.bind(this, { jumpToDocumentEnd(true); });

        ACTION_BACKSPACE.bind(this, &DelPrevChar);
        ACTION_DELETE.bind(this, &DelNextChar);
        ACTION_ED_DEL_PREV_WORD.bind(this, &DelPrevWord);
        ACTION_ED_DEL_NEXT_WORD.bind(this, &DelNextWord);

        ACTION_ED_INDENT.bind(this, &Tab);
        ACTION_ED_UNINDENT.bind(this, &BackTab);

        ACTION_SELECT_ALL.bind(this, &selectAll);

        ACTION_UNDO.bind(this, { _content.undo(this); });
        ACTION_REDO.bind(this, { _content.redo(this); });

        ACTION_CUT.bind(this, &cut);
        ACTION_COPY.bind(this, &copy);
        ACTION_PASTE.bind(this, &paste);

        ACTION_ED_TOGGLE_REPLACE_MODE.bind(this, {
            replaceMode = !replaceMode;
            invalidate();
        });
    }

    protected void unbindActions()
    {
        bunch(
            ACTION_LINE_BEGIN,
            ACTION_LINE_END,
            ACTION_DOCUMENT_BEGIN,
            ACTION_DOCUMENT_END,
            ACTION_SELECT_LINE_BEGIN,
            ACTION_SELECT_LINE_END,
            ACTION_SELECT_DOCUMENT_BEGIN,
            ACTION_SELECT_DOCUMENT_END,
            ACTION_BACKSPACE,
            ACTION_DELETE,
            ACTION_ED_DEL_PREV_WORD,
            ACTION_ED_DEL_NEXT_WORD,
            ACTION_ED_INDENT,
            ACTION_ED_UNINDENT,
            ACTION_SELECT_ALL,
            ACTION_UNDO,
            ACTION_REDO,
            ACTION_CUT,
            ACTION_COPY,
            ACTION_PASTE,
            ACTION_ED_TOGGLE_REPLACE_MODE
        ).unbind(this);
    }

    protected void updateActions()
    {
        debug (editors)
            Log.d("Editor `", id, "`: update actions");

        ACTION_ED_INDENT.enabled = enabled && wantTabs;
        ACTION_ED_UNINDENT.enabled = enabled && wantTabs;

        ACTION_UNDO.enabled = enabled && _content.hasUndo;
        ACTION_REDO.enabled = enabled && _content.hasRedo;

        ACTION_CUT.enabled = enabled && (copyCurrentLineWhenNoSelection || !_selectionRange.empty);
        ACTION_COPY.enabled = copyCurrentLineWhenNoSelection || !_selectionRange.empty;
        ACTION_PASTE.enabled = enabled && platform.hasClipboardText();
    }

    void jumpToLineBegin(bool select)
    {
        const space = _content.getLineWhiteSpace(_caretPos.line);
        int pos = _caretPos.pos;
        if (pos > 0)
        {
            if (pos > space.firstNonSpaceIndex && space.firstNonSpaceIndex > 0)
                pos = space.firstNonSpaceIndex;
            else
                pos = 0;
        }
        else // caret is on the left border
        {
            if (space.firstNonSpaceIndex > 0)
                pos = space.firstNonSpaceIndex;
        }
        jumpTo(_caretPos.line, pos, select);
    }

    void jumpToLineEnd(bool select)
    {
        const currentLineLen = _content.lineLength(_caretPos.line);
        const pos = max(_caretPos.pos, currentLineLen);
        jumpTo(_caretPos.line, pos, select);
    }

    void jumpToDocumentBegin(bool select)
    {
        jumpTo(0, 0, select);
    }

    void jumpToDocumentEnd(bool select)
    {
        const end = _content.end;
        jumpTo(end.line, end.pos, select);
    }

    protected void DelPrevChar()
    {
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionTextIfSelected()) // clear selection
            return;
        if (_caretPos.pos > 0)
        {
            // delete prev char in current line
            auto range = TextRange(_caretPos, _caretPos);
            range.start.pos--;
            removeRangeText(range);
        }
        else if (_caretPos.line > 0)
        {
            // merge with previous line
            auto range = TextRange(_caretPos, _caretPos);
            range.start = _content.lineEnd(range.start.line - 1);
            removeRangeText(range);
        }
    }
    protected void DelNextChar()
    {
        const currentLineLength = _content[_caretPos.line].length;
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionTextIfSelected()) // clear selection
            return;
        if (_caretPos.pos < currentLineLength)
        {
            // delete char in current line
            auto range = TextRange(_caretPos, _caretPos);
            range.end.pos++;
            removeRangeText(range);
        }
        else if (_caretPos.line < _content.lineCount - 1)
        {
            // merge with next line
            auto range = TextRange(_caretPos, _caretPos);
            range.end.line++;
            range.end.pos = 0;
            removeRangeText(range);
        }
    }
    protected void DelPrevWord()
    {
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionTextIfSelected()) // clear selection
            return;
        const TextPosition newpos = _content.moveByWord(_caretPos, -1, _camelCasePartsAsWords);
        if (newpos < _caretPos)
            removeRangeText(TextRange(newpos, _caretPos));
    }
    protected void DelNextWord()
    {
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionTextIfSelected()) // clear selection
            return;
        const TextPosition newpos = _content.moveByWord(_caretPos, 1, _camelCasePartsAsWords);
        if (newpos > _caretPos)
            removeRangeText(TextRange(_caretPos, newpos));
    }

    protected void Tab()
    {
        if (readOnly)
            return;
        if (_selectionRange.empty)
        {
            const emptyRange = TextRange(_caretPos, _caretPos);
            if (useSpacesForTabs)
            {
                // insert one or more spaces to
                dstring spaces = spacesForTab(_caretPos.pos);
                auto op = new EditOperation(EditAction.replace, emptyRange, [spaces]);
                _content.performOperation(op, this);
            }
            else
            {
                // just insert tab character
                auto op = new EditOperation(EditAction.replace, emptyRange, ["\t"d]);
                _content.performOperation(op, this);
            }
        }
        else
        {
            if (multipleLinesSelected)
            {
                indentRange(false);
            }
            else
            {
                // insert tab
                if (useSpacesForTabs)
                {
                    // insert one or more spaces to
                    dstring spaces = spacesForTab(_selectionRange.start.pos);
                    auto op = new EditOperation(EditAction.replace, _selectionRange, [spaces]);
                    _content.performOperation(op, this);
                }
                else
                {
                    // just insert tab character
                    auto op = new EditOperation(EditAction.replace, _selectionRange, ["\t"d]);
                    _content.performOperation(op, this);
                }
            }

        }
    }
    protected void BackTab()
    {
        if (readOnly)
            return;
        if (_selectionRange.empty)
        {
            // remove spaces before caret
            const TextRange r = spaceBefore(_caretPos);
            if (!r.empty)
            {
                auto op = new EditOperation(EditAction.replace, r, [""d]);
                _content.performOperation(op, this);
            }
        }
        else
        {
            if (multipleLinesSelected())
            {
                indentRange(true);
            }
            else
            {
                // remove space before selection
                const TextRange r = spaceBefore(_selectionRange.start);
                if (!r.empty)
                {
                    const int nchars = r.end.pos - r.start.pos;
                    TextRange saveRange = _selectionRange;
                    TextPosition saveCursor = _caretPos;
                    auto op = new EditOperation(EditAction.replace, r, [""d]);
                    _content.performOperation(op, this);
                    if (saveCursor.line == saveRange.start.line)
                        saveCursor.pos -= nchars;
                    if (saveRange.end.line == saveRange.start.line)
                        saveRange.end.pos -= nchars;
                    saveRange.start.pos -= nchars;
                    _selectionRange = saveRange;
                    _caretPos = saveCursor;
                    ensureCaretVisible();
                }
            }
        }
    }

    /// Cut currently selected text into clipboard
    void cut()
    {
        if (readOnly)
            return;
        TextRange range = _selectionRange;
        if (range.empty && copyCurrentLineWhenNoSelection)
        {
            range = currentLineRange;
        }
        if (!range.empty)
        {
            dstring selectionText = getRangeText(range);
            platform.setClipboardText(selectionText);
            auto op = new EditOperation(EditAction.replace, range, [""d]);
            _content.performOperation(op, this);
        }
    }

    /// Copy currently selected text into clipboard
    void copy()
    {
        TextRange range = _selectionRange;
        if (range.empty && copyCurrentLineWhenNoSelection)
        {
            range = currentLineRange;
        }
        if (!range.empty)
        {
            dstring selectionText = getRangeText(range);
            platform.setClipboardText(selectionText);
        }
    }

    /// Replace currently selected text with clipboard content
    void paste()
    {
        if (readOnly)
            return;
        dstring selectionText = platform.getClipboardText();
        dstring[] lines;
        if (_content.multiline)
        {
            lines = splitDString(selectionText);
        }
        else
        {
            lines = [replaceEOLsWithSpaces(selectionText)];
        }
        auto op = new EditOperation(EditAction.replace, _selectionRange, lines);
        _content.performOperation(op, this);
    }

    /// Select whole text
    void selectAll()
    {
        _selectionRange.start.line = 0;
        _selectionRange.start.pos = 0;
        _selectionRange.end = _content.lineEnd(_content.lineCount - 1);
        _caretPos = _selectionRange.end;
        ensureCaretVisible();
        invalidate();
        updateActions();
    }

    protected TextRange spaceBefore(TextPosition pos) const
    {
        auto result = TextRange(pos, pos);
        dstring s = _content[pos.line];
        int x = 0;
        int start = -1;
        for (int i = 0; i < pos.pos; i++)
        {
            const ch = s[i];
            if (ch == ' ')
            {
                if (start == -1 || (x % tabSize) == 0)
                    start = i;
                x++;
            }
            else if (ch == '\t')
            {
                if (start == -1 || (x % tabSize) == 0)
                    start = i;
                x = (x + tabSize + 1) / tabSize * tabSize;
            }
            else
            {
                x++;
                start = -1;
            }
        }
        if (start != -1)
        {
            result.start.pos = start;
        }
        return result;
    }

    /// Change line indent
    protected dstring indentLine(dstring src, bool back, TextPosition* cursorPos)
    {
        int firstNonSpace = -1;
        int x = 0;
        int unindentPos = -1;
        int cursor = cursorPos ? cursorPos.pos : 0;
        for (int i = 0; i < src.length; i++)
        {
            const ch = src[i];
            if (ch == ' ')
            {
                x++;
            }
            else if (ch == '\t')
            {
                x = (x + tabSize + 1) / tabSize * tabSize;
            }
            else
            {
                firstNonSpace = i;
                break;
            }
            if (x <= tabSize)
                unindentPos = i + 1;
        }
        if (firstNonSpace == -1) // only spaces or empty line -- do not change it
            return src;
        if (back)
        {
            // unindent
            if (unindentPos == -1)
                return src; // no change
            if (unindentPos == src.length)
            {
                if (cursorPos)
                    cursorPos.pos = 0;
                return ""d;
            }
            if (cursor >= unindentPos)
                cursorPos.pos -= unindentPos;
            return src[unindentPos .. $].dup;
        }
        else
        {
            // indent
            if (useSpacesForTabs)
            {
                if (cursor > 0)
                    cursorPos.pos += tabSize;
                return spacesForTab(0) ~ src;
            }
            else
            {
                if (cursor > 0)
                    cursorPos.pos++;
                return "\t"d ~ src;
            }
        }
    }

    /// Indent / unindent range
    protected void indentRange(bool back)
    {
        TextRange r = _selectionRange;
        r.start.pos = 0;
        if (r.end.pos > 0)
            r.end = _content.lineBegin(r.end.line + 1);
        if (r.end.line <= r.start.line)
            r = TextRange(_content.lineBegin(_caretPos.line), _content.lineBegin(_caretPos.line + 1));
        int lineCount = r.end.line - r.start.line;
        if (r.end.pos > 0)
            lineCount++;
        dstring[] newContent = new dstring[lineCount + 1];
        bool changed;
        for (int i = 0; i < lineCount; i++)
        {
            dstring srcline = _content.line(r.start.line + i);
            dstring dstline = indentLine(srcline, back, r.start.line + i == _caretPos.line ? &_caretPos : null);
            newContent[i] = dstline;
            if (dstline.length != srcline.length)
                changed = true;
        }
        if (changed)
        {
            const TextRange saveRange = r;
            const TextPosition saveCursor = _caretPos;
            auto op = new EditOperation(EditAction.replace, r, newContent);
            _content.performOperation(op, this);
            _selectionRange = saveRange;
            _caretPos = saveCursor;
            ensureCaretVisible();
        }
    }

    //===============================================================
    // Events

    override bool handleKeyEvent(KeyEvent event)
    {
        import std.ascii : isAlpha;

        debug (keys)
            Log.d("handleKeyEvent ", event.action, " ", event.key, ", mods ", event.allModifiers);
        if (focused)
            startCaretBlinking();
        cancelHoverTimer();

        const bool noOtherModifiers = !event.alteredBy(KeyMods.alt | KeyMods.meta);
        if (event.action == KeyAction.keyDown && noOtherModifiers)
        {
            const bool shiftPressed = event.alteredBy(KeyMods.shift);
            const bool controlPressed = event.alteredBy(KeyMods.control);
            if (event.key == Key.left)
            {
                correctCaretPos();
                TextPosition pos = _caretPos;
                if (!controlPressed)
                {
                    // move cursor one char left
                    if (pos.pos > 0)
                    {
                        pos.pos--;
                    }
                    else if (pos.line > 0)
                    {
                        pos.line--;
                        pos.pos = int.max;
                    }
                }
                else
                {
                    // move cursor one word left
                    pos = _content.moveByWord(pos, -1, _camelCasePartsAsWords);
                }
                // with selection when Shift is pressed
                jumpTo(pos.line, pos.pos, shiftPressed);
                return true;
            }
            if (event.key == Key.right)
            {
                correctCaretPos();
                TextPosition pos = _caretPos;
                if (!controlPressed)
                {
                    // move cursor one char right
                    const currentLineLength = _content[pos.line].length;
                    if (pos.pos < currentLineLength)
                    {
                        pos.pos++;
                    }
                    else if (pos.line < _content.lineCount - 1 && _content.multiline)
                    {
                        pos.pos = 0;
                        pos.line++;
                    }
                }
                else
                {
                    // move cursor one word right
                    pos = _content.moveByWord(pos, 1, _camelCasePartsAsWords);
                }
                // with selection when Shift is pressed
                jumpTo(pos.line, pos.pos, shiftPressed);
                return true;
            }
        }

        const bool noCtrlPressed = !event.alteredBy(KeyMods.control);
        if (event.action == KeyAction.text && event.text.length && noCtrlPressed)
        {
            debug (editors)
                Log.d("text entered: ", event.text);
            if (readOnly)
                return true;
            if (!(event.alteredBy(KeyMods.alt) && event.text.length == 1 && isAlpha(event.text[0])))
            { // filter out Alt+A..Z
                if (replaceMode && _selectionRange.empty &&
                        _content[_caretPos.line].length >= _caretPos.pos + event.text.length)
                {
                    // replace next char(s)
                    TextRange range = _selectionRange;
                    range.end.pos += cast(int)event.text.length;
                    auto op = new EditOperation(EditAction.replace, range, [event.text]);
                    _content.performOperation(op, this);
                }
                else
                {
                    auto op = new EditOperation(EditAction.replace, _selectionRange, [event.text]);
                    _content.performOperation(op, this);
                }
                return true;
            }
        }
        return super.handleKeyEvent(event);
    }

    private TextPosition _hoverTextPosition;
    private Point _hoverMousePosition;
    private ulong _hoverTimer;
    private long _hoverTimeoutMillis = 800;

    /// Override to handle mouse hover timeout in text
    protected void handleHoverTimeout(Point pt, TextPosition pos)
    {
        // override to do something useful on hover timeout
    }

    protected void handleHover(Point pos)
    {
        if (_hoverMousePosition == pos)
            return;
        debug (mouse)
            Log.d("handleHover ", pos);
        cancelHoverTimer();
        const p = pos - clientBox.pos;
        _hoverMousePosition = pos;
        _hoverTextPosition = clientToTextPos(p);
        const Box reversePos = textPosToClient(_hoverTextPosition);
        if (p.x < reversePos.x + 10)
        {
            _hoverTimer = setTimer(_hoverTimeoutMillis, delegate() {
                handleHoverTimeout(_hoverMousePosition, _hoverTextPosition);
                _hoverTimer = 0;
                return false;
            });
        }
    }

    protected void cancelHoverTimer()
    {
        if (_hoverTimer)
        {
            cancelTimer(_hoverTimer);
            _hoverTimer = 0;
        }
    }

    override bool handleMouseEvent(MouseEvent event)
    {
        debug (mouse)
            Log.d("mouse event: ", id, " ", event.action, "  (", event.x, ",", event.y, ")");
        // support onClick
        const bool insideLeftPane = event.x < clientBox.x && event.x >= clientBox.x - _leftPaneWidth;
        if (event.action == MouseAction.buttonDown && insideLeftPane)
        {
            setFocus();
            cancelHoverTimer();
            if (handleLeftPaneMouseClick(event))
                return true;
        }
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            setFocus();
            cancelHoverTimer();
            if (event.tripleClick)
            {
                selectLineByMouse(event.x - clientBox.x, event.y - clientBox.y);
            }
            else if (event.doubleClick)
            {
                selectWordByMouse(event.x - clientBox.x, event.y - clientBox.y);
            }
            else
            {
                const bool doSelect = event.alteredBy(KeyMods.shift);
                updateCaretPositionByMouse(event.x - clientBox.x, event.y - clientBox.y, doSelect);

                if (event.keyMods == KeyMods.control)
                    handleControlClick();
            }
            startCaretBlinking();
            invalidate();
            return true;
        }
        if (event.action == MouseAction.move && event.alteredByButton(MouseButton.left))
        {
            updateCaretPositionByMouse(event.x - clientBox.x, event.y - clientBox.y, true);
            return true;
        }
        if (event.action == MouseAction.move && event.noMouseMods)
        {
            // hover
            if (focused && !insideLeftPane)
            {
                handleHover(event.pos);
            }
            else
            {
                cancelHoverTimer();
            }
            return true;
        }
        if (event.action == MouseAction.buttonUp && event.button == MouseButton.left)
        {
            cancelHoverTimer();
            return true;
        }
        if (event.action == MouseAction.focusOut || event.action == MouseAction.cancel)
        {
            cancelHoverTimer();
            return true;
        }
        if (event.action == MouseAction.focusIn)
        {
            cancelHoverTimer();
            return true;
        }
        cancelHoverTimer();
        return super.handleMouseEvent(event);
    }

    protected bool handleLeftPaneMouseClick(MouseEvent event)
    {
        return false;
    }

    /// Handle Ctrl + Left mouse click on text
    protected void handleControlClick()
    {
        // override to do something useful on Ctrl + Left mouse click in text
    }

    protected void drawLeftPane(DrawBuf buf, Rect rc, int line)
    {
        // override for custom drawn left pane
    }
}

/// Single line editor
class EditLine : EditWidgetBase
{
    @property
    {
        /// Password character - 0 for normal editor, some character
        /// e.g. '*' to hide text by replacing all characters with this char
        dchar passwordChar() const { return _passwordChar; }
        /// ditto
        void passwordChar(dchar ch)
        {
            if (_passwordChar != ch)
            {
                _passwordChar = ch;
                requestLayout();
            }
        }

        override Size fullContentSize() const
        {
            Size sz = _txtline.size;
            sz.w += clientBox.w / 16;
            return sz;
        }
    }

    /// Handle Enter key press inside line editor
    Signal!(bool delegate()) onEnterKeyPress; // FIXME: better name

    private
    {
        dchar _passwordChar = 0;

        TextLine _txtline;
    }

    this(dstring initialContent = null)
    {
        super(ScrollBarMode.hidden, ScrollBarMode.hidden);
        _content = new EditableContent(false);
        _content.onContentChange ~= &handleContentChange;
        _selectAllWhenFocusedWithTab = true;
        _deselectAllWhenUnfocused = true;
        wantTabs = false;
        text = initialContent;
        _minSizeTester.str = "aaaaa"d;
        handleThemeChange();
    }

    /// Set default popup menu with copy/paste/cut/undo/redo
    EditLine setDefaultPopupMenu()
    {
        popupMenu = new Menu;
        popupMenu.add(ACTION_UNDO, ACTION_REDO, ACTION_CUT, ACTION_COPY, ACTION_PASTE);
        return this;
    }

    override protected Box textPosToClient(TextPosition p) const
    {
        Box b;
        if (p.pos <= 0)
            b.x = 0;
        else if (p.pos >= _txtline.glyphCount)
            b.x = _txtline.size.w;
        else
        {
            foreach (ref fg; _txtline.glyphs[0 .. p.pos])
                b.x += fg.width;
        }
        b.x -= scrollPos.x;
        b.w = 1;
        b.h = clientBox.h;
        return b;
    }

    override protected TextPosition clientToTextPos(Point pt) const
    {
        pt.x += scrollPos.x;
        const col = findClosestGlyphInRow(_txtline.glyphs, 0, pt.x);
        return TextPosition(0, col != -1 ? col : _txtline.glyphCount);
    }

    override protected void ensureCaretVisible(bool center = false)
    {
        const Box b = textPosToClient(_caretPos);
        const oldpos = scrollPos.x;
        if (b.x < 0)
        {
            // scroll left
            scrollPos.x = max(scrollPos.x + b.x - clientBox.w / 10, 0);
        }
        else if (b.x >= clientBox.w - 10)
        {
            // scroll right
            scrollPos.x += (b.x - clientBox.w) + _spaceWidth * 4;
        }
        if (oldpos != scrollPos.x)
            invalidate();
        updateScrollBars();
        handleEditorStateChange();
    }

    protected dstring applyPasswordChar(dstring s)
    {
        if (!_passwordChar || s.length == 0)
            return s;
        dchar[] ss = s.dup;
        foreach (ref ch; ss)
            ch = _passwordChar;
        return cast(dstring)ss;
    }

    override bool handleKeyEvent(KeyEvent event)
    {
        if (onEnterKeyPress.assigned)
        {
            if (event.key == Key.enter && event.noModifiers)
            {
                if (event.action == KeyAction.keyDown)
                {
                    if (onEnterKeyPress())
                        return true;
                }
            }
        }
        return super.handleKeyEvent(event);
    }

    override protected void adjustBoundaries(ref Boundaries bs)
    {
        measureVisibleText();
        _minSizeTester.style.tabSize = _content.tabSize;
        const sz = _minSizeTester.getSize() + Size(_leftPaneWidth, 0);
        bs.min += sz;
        bs.nat += sz;
    }

    override protected Size measureVisibleText()
    {
        _txtline.str = applyPasswordChar(text);
        _txtline.measured = false;
        auto tlstyle = TextLayoutStyle(_txtStyle);
        tlstyle.wrap = false;
        _txtline.measure(tlstyle);
        return _txtline.size;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        clientBox = innerBox;

        if (_contentChanged)
        {
            measureVisibleText();
            _contentChanged = false;
        }
    }

    /// Override to custom highlight of line background
    protected void drawLineBackground(DrawBuf buf, Box lineBox, Box visibleBox)
    {
        if (!_selectionRange.empty)
        {
            // line inside selection
            const int start = textPosToClient(_selectionRange.start).x;
            const int end = textPosToClient(_selectionRange.end).x;
            Rect rc = lineBox;
            rc.left = start + clientBox.x;
            rc.right = end + clientBox.x;
            if (!rc.empty)
            {
                // draw selection rect for line
                buf.fillRect(rc, focused ? _selectionColorFocused : _selectionColorNormal);
            }
            if (_leftPaneWidth > 0)
            {
                Rect leftPaneRect = visibleBox;
                leftPaneRect.right = leftPaneRect.left;
                leftPaneRect.left -= _leftPaneWidth;
                drawLeftPane(buf, leftPaneRect, 0);
            }
        }
    }

    override protected void drawClient(DrawBuf buf)
    {
        // already clipped by the client box
        const b = clientBox;
        drawLineBackground(buf, b, b);

        if (_txtline.glyphCount == 0)
        {
            // draw the placeholder when no text
            if (auto ph = _placeholder)
                ph.draw(buf, b.x - scrollPos.x, b.y, b.w);
        }
        else
            _txtline.draw(buf, b.x - scrollPos.x, b.y, b.w, _txtStyle);

        drawCaret(buf);
    }
}

/// Multiline editor
class EditBox : EditWidgetBase
{
    @property
    {
        int minFontSize() const { return _minFontSize; }
        /// ditto
        void minFontSize(int size)
        {
            _minFontSize = size;
        }

        int maxFontSize() const { return _maxFontSize; }
        /// ditto
        void maxFontSize(int size)
        {
            _maxFontSize = size;
        }

        /// When true, show marks for tabs and spaces at beginning and end of line, and tabs inside line
        bool showWhiteSpaceMarks() const { return _showWhiteSpaceMarks; }
        /// ditto
        void showWhiteSpaceMarks(bool show)
        {
            if (_showWhiteSpaceMarks != show)
            {
                _showWhiteSpaceMarks = show;
                invalidate();
            }
        }

        protected int firstVisibleLine() const { return _firstVisibleLine; }

        final protected int linesOnScreen() const
        {
            return (clientBox.h + _lineHeight - 1) / _lineHeight;
        }

        override Size fullContentSize() const
        {
            return Size(_maxLineWidth + (_extendRightScrollBound ? clientBox.w / 16 : 0),
                        _lineHeight * _content.lineCount);
        }
    }

    protected bool _extendRightScrollBound = true;

    private
    {
        int _minFontSize = -1; // disable zooming
        int _maxFontSize = -1; // disable zooming
        bool _showWhiteSpaceMarks;

        int _firstVisibleLine;
        int _maxLineWidth; // computed in `measureVisibleText`
        int _lastMeasureLineCount;

        /// Lines, visible in the client area
        TextLine[] _visibleLines;
        /// Local positions of the lines
        Point[] _visibleLinePositions;
        // a stupid pool for markup
        LineMarkup[] _markup;
        uint _markupEngaged;
    }

    this(dstring initialContent = null,
         ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        super(hscrollbarMode, vscrollbarMode);
        _content = new EditableContent(true); // multiline
        _content.onContentChange ~= &handleContentChange;
        text = initialContent;
        _minSizeTester.str = "aaaaa\naaaaa"d;
        setScrollSteps(0, 3);
        handleThemeChange();
    }

    ~this()
    {
        eliminate(_findPanel);
    }

    override protected void updateVScrollBar(ScrollData data)
    {
        data.setRange(_content.lineCount, max(linesOnScreen - 1, 1));
        data.position = _firstVisibleLine;
    }

    override protected void handleHScroll(ScrollEvent event)
    {
        if (scrollPos.x != event.position)
        {
            scrollPos.x = event.position;
            invalidate();
        }
    }

    override protected void handleVScroll(ScrollEvent event)
    {
        if (_firstVisibleLine != event.position)
        {
            _firstVisibleLine = event.position;
            event.discard();
            measureVisibleText();
            updateScrollBars();
            invalidate();
        }
    }

    override bool handleKeyEvent(KeyEvent event)
    {
        const bool noOtherModifiers = !event.alteredBy(KeyMods.alt | KeyMods.meta);
        if (event.action == KeyAction.keyDown && noOtherModifiers)
        {
            const bool shiftPressed = event.alteredBy(KeyMods.shift);
            const bool controlPressed = event.alteredBy(KeyMods.control);
            if (event.key == Key.up)
            {
                if (!controlPressed)
                    // move cursor one line up (with selection when Shift pressed)
                    moveCursorByLine(true, shiftPressed);
                else
                    scrollUp();
                return true;
            }
            if (event.key == Key.down)
            {
                if (!controlPressed)
                    // move cursor one line down (with selection when Shift pressed)
                    moveCursorByLine(false, shiftPressed);
                else
                    scrollDown();
                return true;
            }
        }
        return super.handleKeyEvent(event);
    }

    protected void moveCursorByLine(bool up, bool select)
    {
        int line = _caretPos.line;
        if (up)
            line--;
        else
            line++;
        jumpTo(line, _caretPos.pos, select);
    }

    override bool handleWheelEvent(WheelEvent event)
    {
        cancelHoverTimer();

        const mods = event.keyMods;
        if (event.deltaY > 0)
        {
            if (mods == KeyMods.shift)
                scrollRight();
            else if (mods == KeyMods.control)
                zoom(false);
            else
                scrollDown();
            return true;
        }
        if (event.deltaY < 0)
        {
            if (mods == KeyMods.shift)
                scrollLeft();
            else if (mods == KeyMods.control)
                zoom(true);
            else
                scrollUp();
            return true;
        }

        if (event.deltaX < 0)
        {
            scrollLeft();
            return true;
        }
        if (event.deltaX > 0)
        {
            scrollRight();
            return true;
        }
        if (event.deltaZ < 0)
        {
            zoom(false);
            return true;
        }
        if (event.deltaZ > 0)
        {
            zoom(true);
            return true;
        }

        return super.handleWheelEvent(event);
    }

    private bool _enableScrollAfterText = true;
    override protected void ensureCaretVisible(bool center = false)
    {
        _caretPos.line = clamp(_caretPos.line, 0, _content.lineCount - 1);

        // fully visible lines
        const int visibleLines = max(linesOnScreen - 1, 1);
        int maxFirstVisibleLine = _content.lineCount - 1;
        if (!_enableScrollAfterText)
            maxFirstVisibleLine = max(_content.lineCount - visibleLines, 0);

        int line = _firstVisibleLine;

        if (_caretPos.line < _firstVisibleLine)
        {
            line = _caretPos.line;
            if (center)
                line -= visibleLines / 2;
        }
        else if (_wordWrap && _firstVisibleLine <= maxFirstVisibleLine)
        {
            // for wordwrap mode, move down sooner
            const int offsetLines = -caretHeightOffset / _lineHeight;
            debug (editors)
                Log.d("offsetLines: ", offsetLines);
            if (_caretPos.line >= _firstVisibleLine + visibleLines - offsetLines)
            {
                line = _caretPos.line - visibleLines + 1 + offsetLines;
                if (center)
                    line += visibleLines / 2;
            }
        }
        else if (_caretPos.line >= _firstVisibleLine + visibleLines)
        {
            line = _caretPos.line - visibleLines + 1;
            if (center)
                line += visibleLines / 2;
        }

        line = clamp(line, 0, maxFirstVisibleLine);
        if (_firstVisibleLine != line)
        {
            _firstVisibleLine = line;
            measureVisibleText();
            invalidate();
        }

        const Box b = textPosToClient(_caretPos);
        const oldpos = scrollPos.x;
        if (b.x < 0)
        {
            // scroll left
            scrollPos.x = max(scrollPos.x + b.x - clientBox.w / 4, 0);
        }
        else if (b.x >= clientBox.w - 10)
        {
            // scroll right
            if (!_wordWrap)
                scrollPos.x += (b.x - clientBox.w) + clientBox.w / 4;
            else
                scrollPos.x = 0;
        }
        if (oldpos != scrollPos.x)
            invalidate();
        updateScrollBars();
        handleEditorStateChange();
    }

    override protected Box textPosToClient(TextPosition pos) const
    {   // similar to the method in Paragraph
        const first = _firstVisibleLine;
        const lines = _visibleLines;
        const positions = _visibleLinePositions;

        if (lines.length == 0 || pos.line < first || first + cast(int)lines.length <= pos.line)
            return Box.init;

        Box b;
        b.w = 1;
        b.h = _lineHeight;
        b.pos = positions[pos.line - first];

        const TextLine* line = &lines[pos.line - first];
        const glyphs = line.glyphs;
        if (line.wrapped)
        {
            foreach (ref span; line.wrapSpans)
            {
                if (pos.pos <= span.end)
                {
                    b.x = span.offset;
                    foreach (i; span.start .. pos.pos)
                        b.x += glyphs[i].width;
                    break;
                }
                b.y += span.height;
            }
        }
        else
        {
            if (pos.pos < line.glyphCount)
            {
                foreach (i; 0 .. pos.pos)
                    b.x += glyphs[i].width;
            }
            else
                b.x += line.size.w;
        }
        b.x -= scrollPos.x;
        return b;
    }

    override protected TextPosition clientToTextPos(Point pt) const
    {   // similar to the method in Paragraph
        const first = _firstVisibleLine;
        const lines = _visibleLines;
        const positions = _visibleLinePositions;

        if (lines.length == 0)
            return TextPosition(0, 0);

        // find the line first
        const(TextLine)* line = &lines[$ - 1]; // default as if it is lower
        int index = first + cast(int)lines.length - 1;
        if (pt.y < positions[0].y) // upper
        {
            line = &lines[0];
            index = first;
        }
        else if (pt.y < positions[$ - 1].y + line.height) // inside
        {
            foreach (i, ref ln; lines)
            {
                const p = positions[i];
                if (p.y <= pt.y && pt.y < p.y + ln.height)
                {
                    line = &ln;
                    index = first + cast(int)i;
                    break;
                }
            }
        }
        // then find the column
        pt.x += scrollPos.x;
        const p = positions[index - first];
        const glyphs = line.glyphs;
        if (line.wrapped)
        {
            int y = p.y;
            foreach (ref span; line.wrapSpans)
            {
                if (y <= pt.y && pt.y < y + span.height)
                {
                    int col = findClosestGlyphInRow(glyphs[span.start .. span.end], span.offset, pt.x);
                    if (col != -1)
                        col += span.start;
                    else
                        col = span.end;
                    return TextPosition(index, col);
                }
                y += span.height;
            }
        }
        else
        {
            const col = findClosestGlyphInRow(glyphs, p.x, pt.x);
            if (col != -1)
                return TextPosition(index, col);
        }
        return TextPosition(index, line.glyphCount);
    }

    //===============================================================
    // Actions

    override protected void bindActions()
    {
        super.bindActions();

        ACTION_PAGE_UP.bind(this, { jumpByPageUp(false); });
        ACTION_PAGE_DOWN.bind(this, { jumpByPageDown(false); });
        ACTION_PAGE_BEGIN.bind(this, { jumpToPageBegin(false); });
        ACTION_PAGE_END.bind(this, { jumpToPageEnd(false); });
        ACTION_SELECT_PAGE_UP.bind(this, { jumpByPageUp(true); });
        ACTION_SELECT_PAGE_DOWN.bind(this, { jumpByPageDown(true); });
        ACTION_SELECT_PAGE_BEGIN.bind(this, { jumpToPageBegin(true); });
        ACTION_SELECT_PAGE_END.bind(this, { jumpToPageEnd(true); });

        ACTION_ZOOM_IN.bind(this, { zoom(true); });
        ACTION_ZOOM_OUT.bind(this, { zoom(false); });

        ACTION_ENTER.bind(this, &InsertNewLine);
        ACTION_ED_PREPEND_NEW_LINE.bind(this, &PrependNewLine);
        ACTION_ED_APPEND_NEW_LINE.bind(this, &AppendNewLine);
        ACTION_ED_DELETE_LINE.bind(this, &DeleteLine);

        ACTION_ED_TOGGLE_BOOKMARK.bind(this, {
            _content.lineIcons.toggleBookmark(_caretPos.line);
        });
        ACTION_ED_GOTO_NEXT_BOOKMARK.bind(this, {
            LineIcon mark = _content.lineIcons.findNext(LineIconType.bookmark,
                    _selectionRange.end.line, 1);
            if (mark)
                jumpTo(mark.line, 0);
        });
        ACTION_ED_GOTO_PREVIOUS_BOOKMARK.bind(this, {
            LineIcon mark = _content.lineIcons.findNext(LineIconType.bookmark,
                    _selectionRange.end.line, -1);
            if (mark)
                jumpTo(mark.line, 0);
        });

        ACTION_ED_TOGGLE_LINE_COMMENT.bind(this, &toggleLineComment);
        ACTION_ED_TOGGLE_BLOCK_COMMENT.bind(this, &toggleBlockComment);

        ACTION_ED_FIND.bind(this, &openFindPanel);
        ACTION_ED_FIND_NEXT.bind(this, { findNext(false); });
        ACTION_ED_FIND_PREV.bind(this, { findNext(true); });
        ACTION_ED_REPLACE.bind(this, &openReplacePanel);
    }

    override protected void unbindActions()
    {
        super.unbindActions();

        bunch(
            ACTION_PAGE_UP,
            ACTION_PAGE_DOWN,
            ACTION_PAGE_BEGIN,
            ACTION_PAGE_END,
            ACTION_SELECT_PAGE_UP,
            ACTION_SELECT_PAGE_DOWN,
            ACTION_SELECT_PAGE_BEGIN,
            ACTION_SELECT_PAGE_END,
            ACTION_ZOOM_IN,
            ACTION_ZOOM_OUT,
            ACTION_ENTER,
            ACTION_ED_TOGGLE_BOOKMARK,
            ACTION_ED_GOTO_NEXT_BOOKMARK,
            ACTION_ED_GOTO_PREVIOUS_BOOKMARK,
            ACTION_ED_TOGGLE_LINE_COMMENT,
            ACTION_ED_TOGGLE_BLOCK_COMMENT,
            ACTION_ED_PREPEND_NEW_LINE,
            ACTION_ED_APPEND_NEW_LINE,
            ACTION_ED_DELETE_LINE,
            ACTION_ED_FIND,
            ACTION_ED_FIND_NEXT,
            ACTION_ED_FIND_PREV,
            ACTION_ED_REPLACE
        ).unbind(this);
    }

    override protected void updateActions()
    {
        super.updateActions();

        ACTION_ED_GOTO_NEXT_BOOKMARK.enabled = _content.lineIcons.hasBookmarks;
        ACTION_ED_GOTO_PREVIOUS_BOOKMARK.enabled = _content.lineIcons.hasBookmarks;

        SyntaxSupport syn = _content.syntaxSupport;
        {
            Action a = ACTION_ED_TOGGLE_LINE_COMMENT;
            a.visible = syn && syn.supportsToggleLineComment;
            if (a.visible)
                a.enabled = enabled && syn.canToggleLineComment(_selectionRange);
        }
        {
            Action a = ACTION_ED_TOGGLE_BLOCK_COMMENT;
            a.visible = syn && syn.supportsToggleBlockComment;
            if (a.visible)
                a.enabled = enabled && syn.canToggleBlockComment(_selectionRange);
        }

        ACTION_ED_REPLACE.enabled = !readOnly;
    }

    /// Zoom in when `zoomIn` is true and out vice versa
    void zoom(bool zoomIn)
    {
        const int dir = zoomIn ? 1 : -1;
        if (_minFontSize < _maxFontSize && _minFontSize > 0 && _maxFontSize > 0)
        {
            const int currentFontSize = style.fontSize;
            const int increment = currentFontSize >= 30 ? 2 : 1;
            int fs = currentFontSize + increment * dir;
            if (fs > 30)
                fs &= 0xFFFE;
            if (currentFontSize != fs && _minFontSize <= fs && fs <= _maxFontSize)
            {
                debug (editors)
                    Log.i("Font size in editor ", id, " zoomed to ", fs);
                style.fontSize = cast(ushort)fs;
                measureVisibleText();
                updateScrollBars();
            }
        }
    }

    void jumpToPageBegin(bool select)
    {
        jumpTo(_firstVisibleLine, _caretPos.pos, select);
    }

    void jumpToPageEnd(bool select)
    {
        const line = min(_firstVisibleLine + linesOnScreen - 2, _content.lineCount - 1);
        jumpTo(line, _caretPos.pos, select);
    }

    void jumpByPageUp(bool select)
    {
        const TextPosition oldCaretPos = _caretPos;
        ensureCaretVisible();
        const int newpos = _firstVisibleLine - linesOnScreen;
        if (newpos < 0)
        {
            _firstVisibleLine = 0;
            _caretPos.line = 0;
        }
        else
        {
            const int delta = _firstVisibleLine - newpos;
            _firstVisibleLine = newpos;
            _caretPos.line -= delta;
        }
        correctCaretPos();
        measureVisibleText();
        updateScrollBars();
        updateSelectionAfterCursorMovement(oldCaretPos, select);
    }

    void jumpByPageDown(bool select)
    {
        TextPosition oldCaretPos = _caretPos;
        ensureCaretVisible();
        const int newpos = _firstVisibleLine + linesOnScreen;
        if (newpos >= _content.lineCount)
        {
            _caretPos.line = _content.lineCount - 1;
        }
        else
        {
            const int delta = newpos - _firstVisibleLine;
            _firstVisibleLine = newpos;
            _caretPos.line += delta;
        }
        correctCaretPos();
        measureVisibleText();
        updateScrollBars();
        updateSelectionAfterCursorMovement(oldCaretPos, select);
    }

    void toggleLineComment()
    {
        SyntaxSupport syn = _content.syntaxSupport;
        if (!readOnly && syn && syn.supportsToggleLineComment)
            if (syn.canToggleLineComment(_selectionRange))
                syn.toggleLineComment(_selectionRange, this);
    }
    void toggleBlockComment()
    {
        SyntaxSupport syn = _content.syntaxSupport;
        if (!readOnly && syn && syn.supportsToggleBlockComment)
            if (syn.canToggleBlockComment(_selectionRange))
                syn.toggleBlockComment(_selectionRange, this);
    }

    protected void InsertNewLine()
    {
        if (!readOnly)
        {
            correctCaretPos();
            auto op = new EditOperation(EditAction.replace, _selectionRange, [""d, ""d]);
            _content.performOperation(op, this);
        }
    }
    protected void PrependNewLine()
    {
        if (!readOnly)
        {
            correctCaretPos();
            _caretPos.pos = 0;
            auto op = new EditOperation(EditAction.replace, _selectionRange, [""d, ""d]);
            _content.performOperation(op, this);
        }
    }
    protected void AppendNewLine()
    {
        if (!readOnly)
        {
            const TextPosition oldCaretPos = _caretPos;
            correctCaretPos();
            const TextPosition p = _content.lineEnd(_caretPos.line);
            const TextRange r = TextRange(p, p);
            auto op = new EditOperation(EditAction.replace, r, [""d, ""d]);
            _content.performOperation(op, this);
            _caretPos = oldCaretPos;
            handleEditorStateChange();
        }
    }
    protected void DeleteLine()
    {
        if (!readOnly)
        {
            correctCaretPos();
            auto op = new EditOperation(EditAction.replace, _content.lineRange(_caretPos.line), [""d]);
            _content.performOperation(op, this);
        }
    }

    //===============================================================

    protected void highlightTextPattern(DrawBuf buf, int lineIndex, Box lineBox, Box visibleBox)
    {
        dstring pattern = _textToHighlight;
        TextSearchOptions options = _textToHighlightOptions;
        if (!pattern.length)
        {
            // support highlighting selection text - if whole word is selected
            if (_selectionRange.empty || !_selectionRange.singleLine)
                return;
            if (_selectionRange.start.line >= _content.lineCount)
                return;
            const dstring selLine = _content.line(_selectionRange.start.line);
            const int start = _selectionRange.start.pos;
            const int end = _selectionRange.end.pos;
            if (start >= selLine.length)
                return;
            pattern = selLine[start .. end];
            if (!isWordChar(pattern[0]) || !isWordChar(pattern[$ - 1]))
                return;
            if (!isWholeWord(selLine, start, end))
                return;
            // whole word is selected - enable highlight for it
            options = TextSearchOptions.caseSensitive | TextSearchOptions.wholeWords;
        }
        if (!pattern.length)
            return;
        dstring lineText = _content.line(lineIndex);
        if (lineText.length < pattern.length)
            return;

        import std.string : indexOf, CaseSensitive;
        import std.typecons : Yes, No;

        const bool caseSensitive = (options & TextSearchOptions.caseSensitive) != 0;
        const bool wholeWords = (options & TextSearchOptions.wholeWords) != 0;
        const bool selectionOnly = (options & TextSearchOptions.selectionOnly) != 0;
        ptrdiff_t start;
        while (true)
        {
            const pos = lineText[start .. $].indexOf(pattern, caseSensitive ? Yes.caseSensitive : No.caseSensitive);
            if (pos < 0)
                break;
            // found text to highlight
            start += pos;
            if (!wholeWords || isWholeWord(lineText, start, start + pattern.length))
            {
                const a = cast(int)start;
                const b = a + cast(int)pattern.length;
                const caretInside = _caretPos.line == lineIndex && a <= _caretPos.pos && _caretPos.pos <= b;
                const color = caretInside ? _searchHighlightColorCurrent : _searchHighlightColorOther;
                highlightLineRange(buf, lineBox, color, lineIndex, a, b);
            }
            start += pattern.length;
        }
    }

    static bool isValidWordBound(dchar innerChar, dchar outerChar)
    {
        return !isWordChar(innerChar) || !isWordChar(outerChar);
    }
    /// Returns true if selected range of string is whole word
    static bool isWholeWord(dstring lineText, size_t start, size_t end)
    {
        if (start >= lineText.length || start >= end)
            return false;
        if (start > 0 && !isValidWordBound(lineText[start], lineText[start - 1]))
            return false;
        if (end > 0 && end < lineText.length && !isValidWordBound(lineText[end - 1], lineText[end]))
            return false;
        return true;
    }

    /// Find all occurences of text pattern in content; options is a bitset of `TextSearchOptions`
    TextRange[] findAll(dstring pattern, TextSearchOptions options) const
    {
        if (!pattern.length)
            return null;

        import std.string : indexOf, CaseSensitive;
        import std.typecons : Yes, No;

        const bool caseSensitive = (options & TextSearchOptions.caseSensitive) != 0;
        const bool wholeWords = (options & TextSearchOptions.wholeWords) != 0;
        const bool selectionOnly = (options & TextSearchOptions.selectionOnly) != 0;
        TextRange[] res;
        foreach (i; 0 .. _content.lineCount)
        {
            const dstring lineText = _content.line(i);
            if (lineText.length < pattern.length)
                continue;
            ptrdiff_t start;
            while (true)
            {
                const pos = lineText[start .. $].indexOf(pattern, caseSensitive ?
                        Yes.caseSensitive : No.caseSensitive);
                if (pos < 0)
                    break;
                // found text to highlight
                start += pos;
                if (!wholeWords || isWholeWord(lineText, start, start + pattern.length))
                {
                    const p = TextPosition(i, cast(int)start);
                    res ~= TextRange(p, p.offset(cast(int)pattern.length));
                }
                start += _textToHighlight.length;
            }
        }
        return res;
    }

    /// Find next occurence of text pattern in content, returns true if found
    bool findNextPattern(ref TextPosition pos, dstring pattern, TextSearchOptions searchOptions, int direction)
    {
        const TextRange[] all = findAll(pattern, searchOptions);
        if (!all.length)
            return false;
        int currentIndex = -1;
        int nearestIndex = cast(int)all.length;
        for (int i = 0; i < all.length; i++)
        {
            if (all[i].isInsideOrNext(pos))
            {
                currentIndex = i;
                break;
            }
        }
        for (int i = 0; i < all.length; i++)
        {
            if (pos < all[i].start)
            {
                nearestIndex = i;
                break;
            }
            if (pos > all[i].end)
            {
                nearestIndex = i + 1;
            }
        }
        if (currentIndex >= 0)
        {
            if (all.length < 2 && direction != 0)
                return false;
            currentIndex += direction;
            if (currentIndex < 0)
                currentIndex = cast(int)all.length - 1;
            else if (currentIndex >= all.length)
                currentIndex = 0;
            pos = all[currentIndex].start;
            return true;
        }
        if (direction < 0)
            nearestIndex--;
        if (nearestIndex < 0)
            nearestIndex = cast(int)all.length - 1;
        else if (nearestIndex >= all.length)
            nearestIndex = 0;
        pos = all[nearestIndex].start;
        return true;
    }

    override protected void adjustBoundaries(ref Boundaries bs)
    {
        measureVisibleText();
        _minSizeTester.style.tabSize = _content.tabSize;
        const sz = _minSizeTester.getSize() + Size(_leftPaneWidth, 0);
        bs.min += sz;
        bs.nat += sz;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        if (geom != box)
            _contentChanged = true;

        super.layout(geom);

        if (_findPanel && _findPanel.visibility != Visibility.gone)
        {
            _findPanel.measure();
            const sz = _findPanel.natSize;
            const cb = clientBox;
            _findPanel.layout(Box(cb.x, cb.y + cb.h - sz.h, cb.w, sz.h));
        }

        if (_contentChanged)
        {
            measureVisibleText();
            _contentChanged = false;
        }

        if (auto ph = _placeholder)
            ph.wrap(clientBox.w);

        setBox(geom);
    }

    override protected Size measureVisibleText()
    {
        int numVisibleLines = linesOnScreen;
        if (_firstVisibleLine >= _content.lineCount)
        {
            _firstVisibleLine = max(_content.lineCount - numVisibleLines + 1, 0);
            _caretPos.line = _content.lineCount - 1;
            _caretPos.pos = 0;
        }
        numVisibleLines = max(numVisibleLines, 1);
        if (_firstVisibleLine + numVisibleLines > _content.lineCount)
            numVisibleLines = max(_content.lineCount - _firstVisibleLine, 1);

        _visibleLines.length = numVisibleLines;
        _visibleLinePositions.length = numVisibleLines;
        _markupEngaged = 0;

        Size sz;
        foreach (i, ref line; _visibleLines)
        {
            line.str = _content[_firstVisibleLine + cast(int)i];
            line.markup = handleCustomLineMarkup(_firstVisibleLine + cast(int)i, line.str);
            line.measured = false;
            auto tlstyle = TextLayoutStyle(_txtStyle);
            line.measure(tlstyle);
            // width - max from visible lines
            sz.w = max(sz.w, line.size.w);
            // wrap now, because we may need this information without drawing
            if (_wordWrap)
                line.wrap(clientBox.w);
        }
        sz.h = _lineHeight * _content.lineCount; // height - for all lines
        // we use max width of the viewed lines as content width
        // in some situations, we reset it to shrink the horizontal scrolling range
        if (_content.lineCount < _lastMeasureLineCount / 3)
            _maxLineWidth = sz.w;
        else if (sz.w * 10 < _maxLineWidth && clientBox.w < sz.w)
            _maxLineWidth = sz.w;
        else
            _maxLineWidth = max(_maxLineWidth, sz.w);
        _lastMeasureLineCount = _content.lineCount;
        return sz;
    }

    protected void highlightLineRange(DrawBuf buf, Box lineBox, Color color,
        int line, int start, int end, bool extend = false)
    {
        const TextLine* ln = &_visibleLines[line - _firstVisibleLine];
        if (ln.wrapped)
        {
            int y = lineBox.y;
            foreach (ref span; ln.wrapSpans)
            {
                if (span.end <= start)
                {
                    y += span.height;
                    continue;
                }
                if (end <= span.start)
                    break;

                const i1 = max(span.start, start);
                const i2 = min(span.end, end);
                const ext = extend && i2 == ln.glyphCount;
                highlightLineRangeImpl(buf, y, span.height, color, line, i1, i2, ext);
                y += span.height;
            }
        }
        else
            highlightLineRangeImpl(buf, lineBox.y, lineBox.h, color, line, start, end, extend);
    }

    private void highlightLineRangeImpl(DrawBuf buf, int y, int h, Color color,
        int line, int start, int end, bool extend)
    {
        const Box a = textPosToClient(TextPosition(line, start));
        const Box b = textPosToClient(TextPosition(line, end));
        Rect rc = Rect(clientBox.x + a.x, y, clientBox.x + b.x, y + h);
        if (extend)
            rc.right += _spaceWidth;
        if (!rc.empty)
            buf.fillRect(rc, color);
    }

    /// Override to custom highlight of line background
    protected void drawLineBackground(DrawBuf buf, int lineIndex, Box lineBox, Box visibleBox)
    {
        // highlight odd lines
        //if ((lineIndex & 1))
        //    buf.fillRect(visibleRect, 0xF4808080);

        const sel = _selectionRange;
        if (!sel.empty && sel.start.line <= lineIndex && lineIndex <= sel.end.line)
        {
            // line is inside selection
            int start;
            int end = int.max;
            bool extend;
            if (lineIndex == sel.start.line)
            {
                start = sel.start.pos;
            }
            if (lineIndex == sel.end.line)
            {
                end = sel.end.pos;
            }
            else
                extend = true;
            // draw selection rect for the line
            const c = focused ? _selectionColorFocused : _selectionColorNormal;
            highlightLineRange(buf, lineBox, c, lineIndex, start, end, extend);
        }

        highlightTextPattern(buf, lineIndex, lineBox, visibleBox);

        const br = _matchingBraces;
        const brcolor = _matchingBracketHighlightColor;
        if (br.start.line == lineIndex)
        {
            highlightLineRange(buf, lineBox, brcolor, lineIndex, br.start.pos, br.start.pos + 1);
        }
        if (br.end.line == lineIndex)
        {
            highlightLineRange(buf, lineBox, brcolor, lineIndex, br.end.pos, br.end.pos + 1);
        }

        // frame around current line
        if (focused && lineIndex == _caretPos.line && sel.singleLine && sel.start.line == _caretPos.line)
        {
            buf.drawFrame(Rect(visibleBox), Color(0x808080, 0x60), Insets(1));
        }
    }

    override protected void drawExtendedArea(DrawBuf buf)
    {
        if (_leftPaneWidth <= 0)
            return;

        const int lineCount = _content.lineCount;
        const cb = clientBox;
        Box b = Box(cb.x - _leftPaneWidth, cb.y, _leftPaneWidth, 0);
        int i = _firstVisibleLine;
        while (b.y < cb.y + cb.h)
        {
            if (i < lineCount)
            {
                b.h = _visibleLines[i - _firstVisibleLine].height;
                drawLeftPane(buf, Rect(b), i);
            }
            else
            {
                b.h = _lineHeight;
                drawLeftPane(buf, Rect(b), -1);
            }
            b.y += b.h;
            i++;
        }
    }

    private TextAttr[][ubyte] _tokenHighlight;

    /// Set highlight options for particular token category
    void setTokenHighlight(TokenCategory category, TextAttr attribute)
    {
        if (auto p = category in _tokenHighlight)
            *p ~= attribute;
        else
            _tokenHighlight[category] = [attribute];
    }
    /// Clear highlight options for all tokens
    void clearTokenHighlight()
    {
        _tokenHighlight.clear();
    }

    /// Construct a custom text markup to highlight the line
    protected LineMarkup* handleCustomLineMarkup(int line, dstring txt)
    {
        import std.algorithm : group;

        if (_tokenHighlight.length == 0)
            return null; // no highlight attributes set

        TokenPropString tokenProps = _content.lineTokenProps(line);
        if (tokenProps.length == 0)
            return null;

        bool hasNonzeroTokens;
        foreach (t; tokenProps)
        {
            if (t)
            {
                hasNonzeroTokens = true;
                break;
            }
        }
        if (!hasNonzeroTokens)
            return null; // all characters are of unknown token type (uncategorized)

        const index = _markupEngaged;
        _markupEngaged++;
        if (_markup.length < _markupEngaged)
            _markup.length = _markupEngaged;

        LineMarkup* result = &_markup[index];
        result.clear();

        uint i;
        foreach (item; group(tokenProps))
        {
            const tok = item[0];
            TextAttr[] attrs;
            if (auto p = tok in _tokenHighlight)
                attrs = *p;
            else if (auto p = (tok & TOKEN_CATEGORY_MASK) in _tokenHighlight)
                attrs = *p;

            const len = cast(uint)item[1];
            if (attrs.length > 0)
            {
                MarkupSpan span = result.span(i, len);
                foreach (ref a; attrs)
                    span.set(a);
            }
            i += len;
        }
        assert(i == tokenProps.length);
        result.prepare(); // FIXME: should be automatic
        return result;
    }

    private TextRange _matchingBraces;

    /// Find max tab mark column position for line
    protected int findMaxTabMarkColumn(int lineIndex) const
    {
        if (lineIndex < 0 || lineIndex >= _content.lineCount)
            return -1;
        int maxSpace = -1;
        auto space = _content.getLineWhiteSpace(lineIndex);
        maxSpace = space.firstNonSpaceColumn;
        if (maxSpace >= 0)
            return maxSpace;
        foreach_reverse (i; 0 .. lineIndex)
        {
            space = _content.getLineWhiteSpace(i);
            if (!space.empty)
            {
                maxSpace = space.firstNonSpaceColumn;
                break;
            }
        }
        foreach (i; lineIndex + 1 .. _content.lineCount)
        {
            space = _content.getLineWhiteSpace(i);
            if (!space.empty)
            {
                if (maxSpace < 0 || maxSpace < space.firstNonSpaceColumn)
                    maxSpace = space.firstNonSpaceColumn;
                break;
            }
        }
        return maxSpace;
    }

    protected void drawTabPositionMarks(DrawBuf buf, int lineIndex, Box lineBox)
    {
        const int maxCol = findMaxTabMarkColumn(lineIndex);
        if (maxCol > 0)
        {
            const int spaceWidth = _spaceWidth;
            lineBox.h = _visibleLines[lineIndex - _firstVisibleLine].wrapSpans[0].height;
            Rect rc = lineBox;
            Color color = style.textColor;
            color.addAlpha(0xC0);
            for (int i = 0; i < maxCol; i += tabSize)
            {
                rc.left = lineBox.x + i * spaceWidth;
                rc.right = rc.left + 1;
                buf.fillRectPattern(rc, color, PatternType.dotted);
            }
        }
    }

    protected void drawWhiteSpaceMarks(DrawBuf buf, int lineIndex, Box lineBox, Box visibleBox)
    {
        const TextLine* line = &_visibleLines[lineIndex - _firstVisibleLine];
        const txt = line.str;
        int firstNonSpace = -1;
        int lastNonSpace = -1;
        bool hasTabs;
        for (int i = 0; i < txt.length; i++)
        {
            if (txt[i] == '\t')
            {
                hasTabs = true;
            }
            else if (txt[i] != ' ')
            {
                if (firstNonSpace == -1)
                    firstNonSpace = i;
                lastNonSpace = i + 1;
            }
        }
        if (txt.length > 0 && firstNonSpace == -1)
            firstNonSpace = cast(int)txt.length;
        if (firstNonSpace <= 0 && txt.length <= lastNonSpace && !hasTabs)
            return;

        Color color = style.textColor;
        color.addAlpha(0xC0);

        const FragmentGlyph[] glyphs = line.glyphs;
        const visibleRect = Rect(visibleBox);
        Box b = lineBox;
        foreach (ref span; line.wrapSpans)
        {
            const i1 = span.start;
            const i2 = span.end;
            b.x = lineBox.x + span.offset;
            foreach (i; i1 .. i2)
            {
                const fg = &glyphs[i];
                const ch = txt[i];
                const bool outsideText = i < firstNonSpace || lastNonSpace <= i;
                if ((ch == ' ' && outsideText) || ch == '\t')
                {
                    b.w = fg.width;
                    b.h = fg.height;
                    if (Rect(b).intersects(visibleRect))
                    {
                        if (ch == ' ')
                            drawSpaceMark(buf, b, color);
                        else if (ch == '\t')
                            drawTabMark(buf, b, color);
                    }
                }
                b.x += fg.width;
            }
            b.y += span.height;
        }
    }

    private void drawSpaceMark(DrawBuf buf, Box g, Color color)
    {
        const int sz = max(g.h / 6, 1);
        const b = Box(g.x + g.w / 2 - sz / 2, g.y + g.h / 2 - sz / 2, sz, sz);
        buf.fillRect(Rect(b), color);
    }

    private void drawTabMark(DrawBuf buf, Box g, Color color)
    {
        const p1 = Point(g.x + 1, g.y + g.h / 2);
        const p2 = Point(g.x + g.w - 1, p1.y);
        const int sz = clamp(g.h / 4, 2, p2.x - p1.x);
        buf.drawLine(p1, p2, color);
        buf.drawLine(p2, Point(p2.x - sz, p2.y - sz / 2), color);
        buf.drawLine(p2, Point(p2.x - sz, p2.y + sz / 2), color);
    }

    override protected void drawClient(DrawBuf buf)
    {
        // update matched braces
        if (!_content.findMatchedBraces(_caretPos, _matchingBraces))
        {
            _matchingBraces.start.line = -1;
            _matchingBraces.end.line = -1;
        }

        const b = clientBox;

        if (auto ph = _placeholder)
        {
            // draw the placeholder when no text
            const ls = _content.lines;
            if (ls.length == 0 || (ls.length == 1 && ls[0].length == 0))
                ph.draw(buf, b.x - scrollPos.x, b.y, b.w);
        }

        const px = b.x - scrollPos.x;
        int y;
        foreach (i, ref line; _visibleLines)
        {
            const py = b.y + y;
            const h = line.height;
            const lineIndex = _firstVisibleLine + cast(int)i;
            const lineBox = Box(px, py, line.size.w, h);
            const visibleBox = Box(b.x, lineBox.y, b.w, lineBox.h);
            drawLineBackground(buf, lineIndex, lineBox, visibleBox);
            if (_showTabPositionMarks)
                drawTabPositionMarks(buf, lineIndex, lineBox);
            if (_showWhiteSpaceMarks)
                drawWhiteSpaceMarks(buf, lineIndex, lineBox, visibleBox);

            const x = line.draw(buf, px, py, b.w, _txtStyle);
            _visibleLinePositions[i] = Point(x, y);
            y += h;
        }

        drawCaret(buf);

        _findPanel.maybe.draw(buf);
    }

    private FindPanel _findPanel;

    dstring selectionText(bool singleLineOnly = false) const
    {
        const TextRange range = _selectionRange;
        if (range.empty)
            return null;

        dstring res = getRangeText(range);
        if (singleLineOnly)
        {
            foreach (i, ch; res)
            {
                if (ch == '\n')
                {
                    res = res[0 .. i];
                    break;
                }
            }
        }
        return res;
    }

    protected void findNext(bool backward)
    {
        createFindPanel(false, false);
        _findPanel.findNext(backward);
        // don't change replace mode
    }

    protected void openFindPanel()
    {
        createFindPanel(false, false);
        _findPanel.replaceMode = false;
        _findPanel.activate();
    }

    protected void openReplacePanel()
    {
        createFindPanel(false, true);
        _findPanel.replaceMode = true;
        _findPanel.activate();
    }

    /// Create find panel; returns true if panel was not yet visible
    protected bool createFindPanel(bool selectionOnly, bool replaceMode)
    {
        bool res;
        const dstring txt = selectionText(true);
        if (!_findPanel)
        {
            _findPanel = new FindPanel(this, selectionOnly, replaceMode, txt);
            addChild(_findPanel);
            res = true;
        }
        else
        {
            if (_findPanel.visibility != Visibility.visible)
            {
                _findPanel.visibility = Visibility.visible;
                if (txt.length)
                    _findPanel.searchText = txt;
                res = true;
            }
        }
        return res;
    }

    /// Close find panel
    protected void closeFindPanel(bool hideOnly = true)
    {
        if (_findPanel)
        {
            setFocus();
            if (hideOnly)
            {
                _findPanel.visibility = Visibility.gone;
            }
            else
            {
                removeChild(_findPanel);
                destroy(_findPanel);
                _findPanel = null;
            }
        }
    }
}

/// Read only edit box for displaying logs with lines append operation
class LogWidget : EditBox
{
    @property
    {
        /// Max lines to show (when appended more than max lines, older lines will be truncated), 0 means no limit
        int maxLines() const { return _maxLines; }
        /// ditto
        void maxLines(int n)
        {
            _maxLines = n;
        }

        /// When true, automatically scrolls down when new lines are appended (usually being reset by scrollbar interaction)
        bool scrollLock() const { return _scrollLock; }
        /// ditto
        void scrollLock(bool flag)
        {
            _scrollLock = flag;
        }
    }

    private int _maxLines;
    private bool _scrollLock;

    this()
    {
        _scrollLock = true;
        _enableScrollAfterText = false;
        enabled = false;
        // allow font zoom with Ctrl + MouseWheel
        minFontSize = 8;
        maxFontSize = 36;
        handleThemeChange();
    }

    /// Append lines to the end of text
    void appendText(dstring text)
    {
        if (text.length == 0)
            return;
        {
            dstring[] lines = splitDString(text);
            TextRange range;
            range.start = range.end = _content.end;
            auto op = new EditOperation(EditAction.replace, range, lines);
            _content.performOperation(op, this);
        }
        if (_maxLines > 0 && _content.lineCount > _maxLines)
        {
            TextRange range;
            range.end.line = _content.lineCount - _maxLines;
            auto op = new EditOperation(EditAction.replace, range, [""d]);
            _content.performOperation(op, this);
        }
        updateScrollBars();
        if (_scrollLock)
        {
            _caretPos = lastLineBegin();
            ensureCaretVisible();
        }
    }

    TextPosition lastLineBegin() const
    {
        TextPosition res;
        if (_content.lineCount == 0)
            return res;
        if (_content.lineLength(_content.lineCount - 1) == 0 && _content.lineCount > 1)
            res.line = _content.lineCount - 2;
        else
            res.line = _content.lineCount - 1;
        return res;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        if (_scrollLock)
        {
            measureVisibleText();
            _caretPos = lastLineBegin();
            ensureCaretVisible();
        }
    }
}

class FindPanel : Panel
{
    @property
    {
        /// Returns true if panel is working in replace mode
        bool replaceMode() const { return _replaceMode; }
        /// ditto
        void replaceMode(bool newMode)
        {
            if (newMode != _replaceMode)
            {
                _replaceMode = newMode;
                childByID("rowReplace").visibility = newMode ? Visibility.visible : Visibility.gone;
            }
        }

        dstring searchText() const
        {
            return _edFind.text;
        }
        /// ditto
        void searchText(dstring newText)
        {
            _edFind.text = newText;
        }
    }

    private
    {
        EditBox _editor;
        EditLine _edFind;
        EditLine _edReplace;
        Button _cbCaseSensitive;
        Button _cbWholeWords;
        CheckBox _cbSelection;
        Button _btnFindNext;
        Button _btnFindPrev;
        bool _replaceMode;
    }

    this(EditBox editor, bool selectionOnly, bool replace, dstring initialText = ""d)
    {
        _editor = editor;
        _replaceMode = replace;

        auto main = new Panel(null, "main");
            auto rowFind = new Panel(null, "find");
                _edFind = new EditLine(initialText);
                _btnFindNext = new Button("Find next");
                _btnFindPrev = new Button("Find previous");
                auto findSettings = new Panel(null, "settings");
                    _cbCaseSensitive = new Button(null, "find_case_sensitive");
                    _cbWholeWords = new Button(null, "find_whole_words");
                    _cbSelection = new CheckBox("Sel");
            auto rowReplace = new Panel(null, "replace");
                _edReplace = new EditLine(initialText);
                auto btnReplace = new Button("Replace");
                auto btnReplaceAndFind = new Button("Replace and find");
                auto btnReplaceAll = new Button("Replace all");
        auto closeBtn = new Button(null, "close");

        with (main) {
            add(rowFind, rowReplace);
            with (rowFind) {
                add(_edFind, _btnFindNext, _btnFindPrev, findSettings);
                with (findSettings) {
                    add(_cbCaseSensitive, _cbWholeWords, _cbSelection);
                    with (_cbCaseSensitive) {
                        allowsToggle = true;
                        tooltipText = "Case sensitive";
                    }
                    with (_cbWholeWords) {
                        allowsToggle = true;
                        tooltipText = "Whole words";
                    }
                }
            }
            with (rowReplace) {
                add(_edReplace, btnReplace, btnReplaceAndFind, btnReplaceAll);
            }
        }
        with (closeBtn) {
            setAttribute("close");
        }
        add(main, closeBtn);

        _edFind.onEnterKeyPress ~= { findNext(_backDirection); return true; };
        _edFind.onContentChange ~= &handleFindTextChange;

        _btnFindNext.onClick ~= { findNext(false); };
        _btnFindPrev.onClick ~= { findNext(true); };

        _cbCaseSensitive.onToggle ~= &handleCaseSensitiveToggle;
        _cbWholeWords.onToggle ~= &handleCaseSensitiveToggle;
        _cbSelection.onToggle ~= &handleCaseSensitiveToggle;

        if (!replace)
            rowReplace.visibility = Visibility.gone;

        btnReplace.onClick ~= { replaceOne(); };
        btnReplaceAndFind.onClick ~= {
            replaceOne();
            findNext(_backDirection);
        };
        btnReplaceAll.onClick ~= { replaceAll(); };

        closeBtn.onClick ~= &close;

        focusGroup = true;

        setDirection(false);
        updateHighlight();
    }

    void activate()
    {
        _edFind.setFocus();
        const currentText = _edFind.text;
        debug (editors)
            Log.d("activate.currentText=", currentText);
        _edFind.jumpTo(0, cast(int)currentText.length);
    }

    void close()
    {
        _editor.setTextToHighlight(null, TextSearchOptions.none);
        _editor.closeFindPanel();
    }

    override bool handleKeyEvent(KeyEvent event)
    {
        if (event.key == Key.tab)
            return super.handleKeyEvent(event);
        if (event.action == KeyAction.keyDown && event.key == Key.escape)
        {
            close();
            return true;
        }
        return false;
    }

    private bool _backDirection;
    void setDirection(bool back)
    {
        _backDirection = back;
        if (back)
        {
            _btnFindNext.resetState(State.default_);
            _btnFindPrev.setState(State.default_);
        }
        else
        {
            _btnFindNext.setState(State.default_);
            _btnFindPrev.resetState(State.default_);
        }
    }

    TextSearchOptions makeSearchOptions() const
    {
        TextSearchOptions res;
        if (_cbCaseSensitive.checked)
            res |= TextSearchOptions.caseSensitive;
        if (_cbWholeWords.checked)
            res |= TextSearchOptions.wholeWords;
        if (_cbSelection.checked)
            res |= TextSearchOptions.selectionOnly;
        return res;
    }

    bool findNext(bool back)
    {
        setDirection(back);
        const currentText = _edFind.text;
        debug (editors)
            Log.d("findNext text=", currentText, " back=", back);
        if (!currentText.length)
            return false;
        _editor.setTextToHighlight(currentText, makeSearchOptions());
        TextPosition pos = _editor.caretPos;
        const bool res = _editor.findNextPattern(pos, currentText, makeSearchOptions(), back ? -1 : 1);
        if (res)
        {
            _editor.selectionRange = TextRange(pos, pos.offset(cast(int)currentText.length));
            _editor.ensureCaretVisible();
        }
        return res;
    }

    bool replaceOne()
    {
        const currentText = _edFind.text;
        const newText = _edReplace.text;
        debug (editors)
            Log.d("replaceOne text=", currentText, " back=", _backDirection, " newText=", newText);
        if (!currentText.length)
            return false;
        _editor.setTextToHighlight(currentText, makeSearchOptions());
        TextPosition pos = _editor.caretPos;
        const bool res = _editor.findNextPattern(pos, currentText, makeSearchOptions(), 0);
        if (res)
        {
            _editor.selectionRange = TextRange(pos, pos.offset(cast(int)currentText.length));
            _editor.replaceSelectionText(newText);
            _editor.selectionRange = TextRange(pos, pos.offset(cast(int)newText.length));
            _editor.ensureCaretVisible();
        }
        return res;
    }

    int replaceAll()
    {
        int count;
        for (int i;; i++)
        {
            debug (editors)
                Log.d("replaceAll - calling replaceOne, iteration ", i);
            if (!replaceOne())
                break;
            count++;
            TextPosition initialPosition = _editor.caretPos;
            debug (editors)
                Log.d("replaceAll - position is ", initialPosition);
            if (!findNext(_backDirection))
                break;
            TextPosition newPosition = _editor.caretPos;
            debug (editors)
                Log.d("replaceAll - next position is ", newPosition);
            if (_backDirection && newPosition >= initialPosition)
                break;
            if (!_backDirection && newPosition <= initialPosition)
                break;
        }
        debug (editors)
            Log.d("replaceAll - done, replace count = ", count);
        _editor.ensureCaretVisible();
        return count;
    }

    void updateHighlight()
    {
        const currentText = _edFind.text;
        debug (editors)
            Log.d("updateHighlight currentText: ", currentText);
        _editor.setTextToHighlight(currentText, makeSearchOptions());
    }

    void handleFindTextChange(EditableContent source)
    {
        debug (editors)
            Log.d("handleFindTextChange");
        updateHighlight();
    }

    void handleCaseSensitiveToggle(bool checkValue)
    {
        updateHighlight();
    }
}
