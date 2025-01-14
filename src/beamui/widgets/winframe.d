/**
Window frame widget.

Copyright: Vadim Lopatin 2015
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.winframe;

import beamui.widgets.controls;
import beamui.widgets.text;
import beamui.widgets.widget;

/// Window frame with caption widget
class WindowFrame : Panel
{
    @property Widget bodyWidget() { return _bodyWidget; }
    /// ditto
    @property void bodyWidget(Widget widget)
    {
        _bodyLayout.replaceChild(_bodyWidget, widget);
        destroy(_bodyWidget);
        _bodyWidget = widget;
    }

    @property Label title() { return _title; }

    Signal!(void delegate()) onCloseButtonClick;

    private
    {
        Widget _bodyWidget;
        Panel _titleLayout;
        Label _title;
        Button _closeButton;
        bool _showCloseButton;
        Panel _bodyLayout;
    }

    this(bool showCloseButton = true)
    {
        _showCloseButton = showCloseButton;
        initialize();
    }

    protected void initialize()
    {
        _titleLayout = new Panel;
            _title = new Label;
            _closeButton = new Button(null, "close");
        _bodyLayout = new Panel;
            _bodyWidget = createBodyWidget();

        with (_titleLayout) {
            bindSubItem(this, "caption");
            add(_title, _closeButton);
            _title.bindSubItem(this, "label");
            _closeButton.setAttribute("flat");
        }
        with (_bodyLayout) {
            bindSubItem(this, "body");
            add(_bodyWidget);
        }
        add(_titleLayout, _bodyLayout);

        _closeButton.onClick ~= &onCloseButtonClick.emit;
        if (!_showCloseButton)
            _closeButton.visibility = Visibility.gone;
    }

    protected Widget createBodyWidget()
    {
        return new Widget("DOCK_WINDOW_BODY");
    }
}
