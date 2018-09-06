/**
This module contains drawing buffer implementation.


Synopsis:
---
import beamui.graphics.drawbuf;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.graphics.drawbuf;

public import beamui.core.types;
import beamui.core.config;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.math3d;
import beamui.graphics.colors;

/// 9-patch image scaling information
struct NinePatch
{
    /// Frame (non-scalable) part size for left, top, right, bottom edges.
    RectOffset frame;
    /// Padding (distance to content area) for left, top, right, bottom edges.
    RectOffset padding;
}

enum PatternType : uint
{
    solid,
    dotted,
}

static if (USE_OPENGL)
{
    /// Non thread safe
    private __gshared uint drawBufIDGenerator = 0;
}

/// Custom draw delegate for OpenGL direct drawing
alias OpenGLDrawableDelegate = void delegate(Rect windowRect, Rect rc);

/// Drawing buffer - image container which allows to perform some drawing operations
class DrawBuf : RefCountedObject
{
    protected Rect _clipRect;
    protected NinePatch* _ninePatch;
    protected uint _alpha;

    static if (USE_OPENGL)
    {
        protected uint _id;
        /// Unique ID of drawbuf instance, for using with hardware accelerated rendering for caching
        @property uint id()
        {
            return _id;
        }
    }

    this()
    {
        static if (USE_OPENGL)
        {
            _id = drawBufIDGenerator++;
        }
        debug _instanceCount++;
    }

    debug private static __gshared int _instanceCount;
    debug @property static int instanceCount()
    {
        return _instanceCount;
    }

    ~this()
    {
        debug
        {
            if (APP_IS_SHUTTING_DOWN)
                onResourceDestroyWhileShutdown("DrawBuf", this.classinfo.name);
            _instanceCount--;
        }
        clear();
    }

    protected void function(uint) _onDestroyCallback;
    @property void onDestroyCallback(void function(uint) callback)
    {
        _onDestroyCallback = callback;
    }

    @property void function(uint) onDestroyCallback()
    {
        return _onDestroyCallback;
    }

    /// Call to remove this image from OpenGL cache when image is updated.
    void invalidate()
    {
        static if (USE_OPENGL)
        {
            if (_onDestroyCallback)
            {
                // remove from cache
                _onDestroyCallback(_id);
                // assign new ID
                _id = drawBufIDGenerator++;
            }
        }
    }

    /// Get current alpha setting (to be applied to all drawing operations)
    @property uint alpha()
    {
        return _alpha;
    }
    /// Set new alpha setting (to be applied to all drawing operations)
    @property void alpha(uint alpha)
    {
        _alpha = min(alpha, 0xFF);
    }

    /// Apply additional transparency to current drawbuf alpha value
    void addAlpha(uint alpha)
    {
        _alpha = blendAlpha(_alpha, alpha);
    }

    /// Applies current drawbuf alpha to argb color value
    uint applyAlpha(uint argb)
    {
        if (!_alpha)
            return argb; // no drawbuf alpha
        uint a1 = (argb >> 24) & 0xFF;
        if (a1 == 0xFF)
            return argb; // fully transparent
        uint a2 = _alpha & 0xFF;
        uint a = blendAlpha(a1, a2);
        return (argb & 0xFFFFFF) | (a << 24);
    }

    //===============================================================
    // 9-patch functions (image scaling using 9-patch markup - unscaled frame and scaled middle parts)

    /// Get nine patch information pointer, null if this is not a nine patch image buffer
    @property const(NinePatch)* ninePatch() const
    {
        return _ninePatch;
    }
    /// Set nine patch information pointer, null if this is not a nine patch image buffer
    @property void ninePatch(NinePatch* ninePatch)
    {
        _ninePatch = ninePatch;
    }
    /// Check whether there is nine-patch information available for drawing buffer
    @property bool hasNinePatch()
    {
        return _ninePatch !is null;
    }
    /// Override to detect nine patch using image 1-pixel border; returns true if 9-patch markup is found in image.
    bool detectNinePatch()
    {
        return false;
    }

    /// Returns current width
    @property int width()
    {
        return 0;
    }
    /// Returns current height
    @property int height()
    {
        return 0;
    }

    //===============================================================
    // Clipping rectangle functions

    /// Init clip rectangle to full buffer size
    void resetClipping()
    {
        _clipRect = Rect(0, 0, width, height);
    }

    @property bool hasClipping()
    {
        return _clipRect.left != 0 || _clipRect.top != 0 || _clipRect.right != width || _clipRect.bottom != height;
    }
    /// Returns clipping rectangle
    @property ref Rect clipRect()
    {
        return _clipRect;
    }
    /// Set new clipping rectangle
    @property void clipRect(const ref Rect rect)
    {
        _clipRect = rect;
        _clipRect.intersect(Rect(0, 0, width, height));
    }
    /// Set new clipping rectangle, intersect with previous one
    @property void intersectClipRect(const ref Rect rect)
    {
        _clipRect.intersect(rect);
    }
    /// Returns true if rectangle is completely clipped out and cannot be drawn.
    @property bool isClippedOut(const ref Rect rect)
    {
        return !_clipRect.intersects(rect);
    }
    /// Apply clipRect and buffer bounds clipping to rectangle
    bool applyClipping(ref Rect rc)
    {
        rc.intersect(_clipRect);
        if (rc.left < 0)
            rc.left = 0;
        if (rc.top < 0)
            rc.top = 0;
        if (rc.right > width)
            rc.right = width;
        if (rc.bottom > height)
            rc.bottom = height;
        return !rc.empty;
    }
    /// Apply clipRect and buffer bounds clipping to rectangle
    /// If clipping applied to first rectangle, reduce second rectangle bounds proportionally
    bool applyClipping(ref Rect rc, ref Rect rc2)
    {
        if (rc.empty || rc2.empty)
            return false;
        if (!rc.intersects(_clipRect))
            return false;
        if (rc.width == rc2.width && rc.height == rc2.height)
        {
            // unscaled
            if (rc.left < _clipRect.left)
            {
                rc2.left += _clipRect.left - rc.left;
                rc.left = _clipRect.left;
            }
            if (rc.top < _clipRect.top)
            {
                rc2.top += _clipRect.top - rc.top;
                rc.top = _clipRect.top;
            }
            if (rc.right > _clipRect.right)
            {
                rc2.right -= rc.right - _clipRect.right;
                rc.right = _clipRect.right;
            }
            if (rc.bottom > _clipRect.bottom)
            {
                rc2.bottom -= rc.bottom - _clipRect.bottom;
                rc.bottom = _clipRect.bottom;
            }
            if (rc.left < 0)
            {
                rc2.left += -rc.left;
                rc.left = 0;
            }
            if (rc.top < 0)
            {
                rc2.top += -rc.top;
                rc.top = 0;
            }
            if (rc.right > width)
            {
                rc2.right -= rc.right - width;
                rc.right = width;
            }
            if (rc.bottom > height)
            {
                rc2.bottom -= rc.bottom - height;
                rc.bottom = height;
            }
        }
        else
        {
            // scaled
            int dstdx = rc.width;
            int dstdy = rc.height;
            int srcdx = rc2.width;
            int srcdy = rc2.height;
            if (rc.left < _clipRect.left)
            {
                rc2.left += (_clipRect.left - rc.left) * srcdx / dstdx;
                rc.left = _clipRect.left;
            }
            if (rc.top < _clipRect.top)
            {
                rc2.top += (_clipRect.top - rc.top) * srcdy / dstdy;
                rc.top = _clipRect.top;
            }
            if (rc.right > _clipRect.right)
            {
                rc2.right -= (rc.right - _clipRect.right) * srcdx / dstdx;
                rc.right = _clipRect.right;
            }
            if (rc.bottom > _clipRect.bottom)
            {
                rc2.bottom -= (rc.bottom - _clipRect.bottom) * srcdy / dstdy;
                rc.bottom = _clipRect.bottom;
            }
            if (rc.left < 0)
            {
                rc2.left -= (rc.left) * srcdx / dstdx;
                rc.left = 0;
            }
            if (rc.top < 0)
            {
                rc2.top -= (rc.top) * srcdy / dstdy;
                rc.top = 0;
            }
            if (rc.right > width)
            {
                rc2.right -= (rc.right - width) * srcdx / dstdx;
                rc.right = width;
            }
            if (rc.bottom > height)
            {
                rc2.bottom -= (rc.bottom - height) * srcdx / dstdx;
                rc.bottom = height;
            }
        }
        return !rc.empty && !rc2.empty;
    }
    /// Reserved for hardware-accelerated drawing - begins drawing batch
    void beforeDrawing()
    {
        _alpha = 0;
    }
    /// Reserved for hardware-accelerated drawing - ends drawing batch
    void afterDrawing()
    {
    }
    /// Returns buffer bits per pixel
    @property int bpp()
    {
        return 0;
    }

    /// Resize buffer
    abstract void resize(int width, int height);

    //========================================================
    // Drawing methods

    /// Fill the whole buffer with solid color (no clipping applied)
    abstract void fill(uint color);
    /// Fill rectangle with solid color (clipping is applied)
    abstract void fillRect(Rect rc, uint color);
    /// Fill rectangle with a gradient (clipping is applied)
    abstract void fillGradientRect(Rect rc, uint color1, uint color2, uint color3, uint color4);

    /// Fill rectangle with solid color and pattern (clipping is applied)
    void fillRectPattern(Rect rc, uint color, PatternType pattern)
    {
        uint alpha = color >> 24;
        if (alpha == 255) // fully transparent
            return;
        if (applyClipping(rc))
        {
            final switch (pattern) with (PatternType)
            {
            case solid:
                fillRect(rc, color);
                break;
            case dotted:
                auto img = makeTemporaryImage(2, 2);
                img.fill(COLOR_TRANSPARENT);
                foreach (x; 0 .. 2)
                {
                    foreach (y; 0 .. 2)
                    {
                        if ((x ^ y) & 1)
                            img.drawPixel(x, y, color);
                    }
                }
                drawTiledImage(rc, img);
                destroy(img);
                break;
            }
        }
    }
    /// Draw pixel at (x, y) with specified color
    abstract void drawPixel(int x, int y, uint color);
    /// Draw 8bit alpha image - usually font glyph using specified color (clipping is applied)
    abstract void drawGlyph(int x, int y, Glyph* glyph, uint color);
    /// Draw source buffer rectangle contents to destination buffer
    abstract void drawFragment(int x, int y, DrawBuf src, Rect srcrect);
    /// Draw source buffer rectangle contents to destination buffer rectangle applying rescaling
    abstract void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect);
    /// Draw unscaled image at specified coordinates
    void drawImage(int x, int y, DrawBuf src)
    {
        drawFragment(x, y, src, Rect(0, 0, src.width, src.height));
    }
    /// Draw tiles of unscaled image to a buffer rectangle
    /// Experimental API
    void drawTiledImage(Rect dstrect, DrawBuf src, int tilex0 = 0, int tiley0 = 0)
    {
        Rect rc = dstrect;
        int imgdx = src.width;
        int imgdy = src.height;
        int offsetx = ((tilex0 % imgdx) + imgdx) % imgdx;
        int offsety = ((tiley0 % imgdy) + imgdy) % imgdy;
        int xx0 = rc.left;
        int yy0 = rc.top;
        if (offsetx)
            xx0 -= imgdx - offsetx;
        if (offsety)
            yy0 -= imgdy - offsety;
        for (int yy = yy0; yy < rc.bottom; yy += imgdy)
        {
            for (int xx = xx0; xx < rc.right; xx += imgdx)
            {
                Rect dst = Rect(xx, yy, xx + imgdx, yy + imgdy);
                if (dst.intersects(rc))
                {
                    Rect sr = Rect(0, 0, imgdx, imgdy);
                    if (dst.right > rc.right)
                        sr.right -= dst.right - rc.right;
                    if (dst.bottom > rc.bottom)
                        sr.bottom -= dst.bottom - rc.bottom;
                    if (!sr.empty)
                        drawFragment(dst.left, dst.top, src, sr);
                }
            }
        }
    }
    /// Draw an image rescaling with 9-patch
    void drawNinePatch(Rect dstrect, DrawBuf src, Rect srcrect)
    {
        assert(src.hasNinePatch);

        static void correctFrameBounds(ref int n1, ref int n2, ref int n3, ref int n4)
        {
            if (n1 > n2)
            {
                //assert(n2 - n1 == n4 - n3);
                int middledist = (n1 + n2) / 2 - n1;
                n1 = n2 = n1 + middledist;
                n3 = n4 = n3 + middledist;
            }
        }

        auto p = src.ninePatch;
        Rect rc = dstrect;
        uint w = srcrect.width;
        uint h = srcrect.height;
        int x0 = srcrect.left;
        int x1 = srcrect.left + p.frame.left;
        int x2 = srcrect.right - p.frame.right;
        int x3 = srcrect.right;
        int y0 = srcrect.top;
        int y1 = srcrect.top + p.frame.top;
        int y2 = srcrect.bottom - p.frame.bottom;
        int y3 = srcrect.bottom;
        int dstx0 = rc.left;
        int dstx1 = rc.left + p.frame.left;
        int dstx2 = rc.right - p.frame.right;
        int dstx3 = rc.right;
        int dsty0 = rc.top;
        int dsty1 = rc.top + p.frame.top;
        int dsty2 = rc.bottom - p.frame.bottom;
        int dsty3 = rc.bottom;

        correctFrameBounds(x1, x2, dstx1, dstx2);
        correctFrameBounds(y1, y2, dsty1, dsty2);

        //correctFrameBounds(x1, x2);
        //correctFrameBounds(y1, y2);
        //correctFrameBounds(dstx1, dstx2);
        //correctFrameBounds(dsty1, dsty2);
        if (y0 < y1 && dsty0 < dsty1)
        {
            // top row
            if (x0 < x1 && dstx0 < dstx1)
                drawFragment(dstx0, dsty0, src, Rect(x0, y0, x1, y1)); // top left
            if (x1 < x2 && dstx1 < dstx2)
                drawRescaled(Rect(dstx1, dsty0, dstx2, dsty1), src, Rect(x1, y0, x2, y1)); // top center
            if (x2 < x3 && dstx2 < dstx3)
                drawFragment(dstx2, dsty0, src, Rect(x2, y0, x3, y1)); // top right
        }
        if (y1 < y2 && dsty1 < dsty2)
        {
            // middle row
            if (x0 < x1 && dstx0 < dstx1)
                drawRescaled(Rect(dstx0, dsty1, dstx1, dsty2), src, Rect(x0, y1, x1, y2)); // middle center
            if (x1 < x2 && dstx1 < dstx2)
                drawRescaled(Rect(dstx1, dsty1, dstx2, dsty2), src, Rect(x1, y1, x2, y2)); // center
            if (x2 < x3 && dstx2 < dstx3)
                drawRescaled(Rect(dstx2, dsty1, dstx3, dsty2), src, Rect(x2, y1, x3, y2)); // middle center
        }
        if (y2 < y3 && dsty2 < dsty3)
        {
            // bottom row
            if (x0 < x1 && dstx0 < dstx1)
                drawFragment(dstx0, dsty2, src, Rect(x0, y2, x1, y3)); // bottom left
            if (x1 < x2 && dstx1 < dstx2)
                drawRescaled(Rect(dstx1, dsty2, dstx2, dsty3), src, Rect(x1, y2, x2, y3)); // bottom center
            if (x2 < x3 && dstx2 < dstx3)
                drawFragment(dstx2, dsty2, src, Rect(x2, y2, x3, y3)); // bottom right
        }
    }
    /// Draws rectangle frame of specified color, widths (per side), pattern and optinally fills inner area
    void drawFrame(Rect rc, uint frameColor, RectOffset frameSideWidths, uint innerAreaColor = 0xFFFFFFFF,
            PatternType pattern = PatternType.solid)
    {
        // draw frame
        if (!isFullyTransparentColor(frameColor))
        {
            Rect r;
            // left side
            r = rc;
            r.right = r.left + frameSideWidths.left;
            if (!r.empty)
                fillRectPattern(r, frameColor, pattern);
            // right side
            r = rc;
            r.left = r.right - frameSideWidths.right;
            if (!r.empty)
                fillRectPattern(r, frameColor, pattern);
            // top side
            r = rc;
            r.left += frameSideWidths.left;
            r.right -= frameSideWidths.right;
            Rect rc2 = r;
            rc2.bottom = r.top + frameSideWidths.top;
            if (!rc2.empty)
                fillRectPattern(rc2, frameColor, pattern);
            // bottom side
            rc2 = r;
            rc2.top = r.bottom - frameSideWidths.bottom;
            if (!rc2.empty)
                fillRectPattern(rc2, frameColor, pattern);
        }
        // draw internal area
        if (!isFullyTransparentColor(innerAreaColor))
        {
            rc.left += frameSideWidths.left;
            rc.top += frameSideWidths.top;
            rc.right -= frameSideWidths.right;
            rc.bottom -= frameSideWidths.bottom;
            if (!rc.empty)
                fillRect(rc, innerAreaColor);
        }
    }

    /// Draw focus rectangle; vertical gradient supported - colors[0] is top color, colors[1] is bottom color
    void drawFocusRect(Rect rc, const uint[] colors)
    {
        // override for faster performance when using OpenGL
        if (colors.length < 1)
            return;
        uint color1 = colors[0];
        uint color2 = colors.length > 1 ? colors[1] : color1;
        if (isFullyTransparentColor(color1) && isFullyTransparentColor(color2))
            return;
        // draw horizontal lines
        foreach (int x; rc.left .. rc.right)
        {
            if ((x ^ rc.top) & 1)
                fillRect(Rect(x, rc.top, x + 1, rc.top + 1), color1);
            if ((x ^ (rc.bottom - 1)) & 1)
                fillRect(Rect(x, rc.bottom - 1, x + 1, rc.bottom), color2);
        }
        // draw vertical lines
        foreach (int y; rc.top + 1 .. rc.bottom - 1)
        {
            uint color = color1 == color2 ? color1 : blendARGB(color2, color1, 255 / (rc.bottom - rc.top));
            if ((y ^ rc.left) & 1)
                fillRect(Rect(rc.left, y, rc.left + 1, y + 1), color);
            if ((y ^ (rc.right - 1)) & 1)
                fillRect(Rect(rc.right - 1, y, rc.right, y + 1), color);
        }
    }

    /// Draw filled triangle in float coordinates; clipping is already applied
    protected void fillTriangleFClipped(PointF p1, PointF p2, PointF p3, uint colour)
    {
        // override and implement it
    }

    /// Find intersection of line p1..p2 with clip rectangle
    protected bool intersectClipF(ref PointF p1, ref PointF p2, ref bool p1moved, ref bool p2moved)
    {
        if (p1.x < _clipRect.left && p2.x < _clipRect.left)
            return true;
        if (p1.x >= _clipRect.right && p2.x >= _clipRect.right)
            return true;
        if (p1.y < _clipRect.top && p2.y < _clipRect.top)
            return true;
        if (p1.y >= _clipRect.bottom && p2.y >= _clipRect.bottom)
            return true;
        // horizontal clip
        if (p1.x < _clipRect.left && p2.x >= _clipRect.left)
        {
            // move p1 to clip left
            p1 += (p2 - p1) * ((_clipRect.left - p1.x) / (p2.x - p1.x));
            p1moved = true;
        }
        if (p2.x < _clipRect.left && p1.x >= _clipRect.left)
        {
            // move p2 to clip left
            p2 += (p1 - p2) * ((_clipRect.left - p2.x) / (p1.x - p2.x));
            p2moved = true;
        }
        if (p1.x > _clipRect.right && p2.x < _clipRect.right)
        {
            // move p1 to clip right
            p1 += (p2 - p1) * ((_clipRect.right - p1.x) / (p2.x - p1.x));
            p1moved = true;
        }
        if (p2.x > _clipRect.right && p1.x < _clipRect.right)
        {
            // move p1 to clip right
            p2 += (p1 - p2) * ((_clipRect.right - p2.x) / (p1.x - p2.x));
            p2moved = true;
        }
        // vertical clip
        if (p1.y < _clipRect.top && p2.y >= _clipRect.top)
        {
            // move p1 to clip left
            p1 += (p2 - p1) * ((_clipRect.top - p1.y) / (p2.y - p1.y));
            p1moved = true;
        }
        if (p2.y < _clipRect.top && p1.y >= _clipRect.top)
        {
            // move p2 to clip left
            p2 += (p1 - p2) * ((_clipRect.top - p2.y) / (p1.y - p2.y));
            p2moved = true;
        }
        if (p1.y > _clipRect.bottom && p2.y < _clipRect.bottom)
        {
            // move p1 to clip right             <0              <0
            p1 += (p2 - p1) * ((_clipRect.bottom - p1.y) / (p2.y - p1.y));
            p1moved = true;
        }
        if (p2.y > _clipRect.bottom && p1.y < _clipRect.bottom)
        {
            // move p1 to clip right
            p2 += (p1 - p2) * ((_clipRect.bottom - p2.y) / (p1.y - p2.y));
            p2moved = true;
        }
        return false;
    }

    /// Draw filled triangle in float coordinates
    void fillTriangleF(PointF p1, PointF p2, PointF p3, uint colour)
    {
        if (_clipRect.empty) // clip rectangle is empty - all drawables are clipped out
            return;
        // apply clipping
        bool p1insideClip = (p1.x >= _clipRect.left && p1.x < _clipRect.right && p1.y >= _clipRect.top &&
                p1.y < _clipRect.bottom);
        bool p2insideClip = (p2.x >= _clipRect.left && p2.x < _clipRect.right && p2.y >= _clipRect.top &&
                p2.y < _clipRect.bottom);
        bool p3insideClip = (p3.x >= _clipRect.left && p3.x < _clipRect.right && p3.y >= _clipRect.top &&
                p3.y < _clipRect.bottom);
        if (p1insideClip && p2insideClip && p3insideClip)
        {
            // all points inside clipping area - no clipping required
            fillTriangleFClipped(p1, p2, p3, colour);
            return;
        }
        // do triangle clipping
        // check if all points outside the same bound
        if ((p1.x < _clipRect.left && p2.x < _clipRect.left && p3.x < _clipRect.left) ||
                (p1.x >= _clipRect.right && p2.x >= _clipRect.right && p3.x >= _clipRect.bottom) ||
                (p1.y < _clipRect.top && p2.y < _clipRect.top && p3.y < _clipRect.top) ||
                (p1.y >= _clipRect.bottom && p2.y >= _clipRect.bottom && p3.y >= _clipRect.bottom))
            return;
        /++
         +                   side 1
         +  p1-------p11------------p21--------------p2
         +   \                                       /
         +    \                                     /
         +     \                                   /
         +      \                                 /
         +    p13\                               /p22
         +        \                             /
         +         \                           /
         +          \                         /
         +           \                       /  side 2
         +    side 3  \                     /
         +             \                   /
         +              \                 /
         +               \               /p32
         +             p33\             /
         +                 \           /
         +                  \         /
         +                   \       /
         +                    \     /
         +                     \   /
         +                      \ /
         +                      p3
         +/
        PointF p11 = p1;
        PointF p13 = p1;
        PointF p21 = p2;
        PointF p22 = p2;
        PointF p32 = p3;
        PointF p33 = p3;
        bool p1moved = false;
        bool p2moved = false;
        bool p3moved = false;
        bool side1clipped = intersectClipF(p11, p21, p1moved, p2moved);
        bool side2clipped = intersectClipF(p22, p32, p2moved, p3moved);
        bool side3clipped = intersectClipF(p33, p13, p3moved, p1moved);
        if (!p1moved && !p2moved && !p3moved)
        {
            // no moved - no clipping
            fillTriangleFClipped(p1, p2, p3, colour);
        }
        else if (p1moved && !p2moved && !p3moved)
        {
            fillTriangleFClipped(p11, p2, p3, colour);
            fillTriangleFClipped(p3, p13, p11, colour);
        }
        else if (!p1moved && p2moved && !p3moved)
        {
            fillTriangleFClipped(p22, p3, p1, colour);
            fillTriangleFClipped(p1, p21, p22, colour);
        }
        else if (!p1moved && !p2moved && p3moved)
        {
            fillTriangleFClipped(p33, p1, p2, colour);
            fillTriangleFClipped(p2, p32, p33, colour);
        }
        else if (p1moved && p2moved && !p3moved)
        {
            if (!side1clipped)
            {
                fillTriangleFClipped(p13, p11, p21, colour);
                fillTriangleFClipped(p21, p22, p13, colour);
            }
            fillTriangleFClipped(p22, p3, p13, colour);
        }
        else if (!p1moved && p2moved && p3moved)
        {
            if (!side2clipped)
            {
                fillTriangleFClipped(p21, p22, p32, colour);
                fillTriangleFClipped(p32, p33, p21, colour);
            }
            fillTriangleFClipped(p21, p33, p1, colour);
        }
        else if (p1moved && !p2moved && p3moved)
        {
            if (!side3clipped)
            {
                fillTriangleFClipped(p13, p11, p32, colour);
                fillTriangleFClipped(p32, p33, p13, colour);
            }
            fillTriangleFClipped(p11, p2, p32, colour);
        }
        else if (p1moved && p2moved && p3moved)
        {
            if (side1clipped)
            {
                fillTriangleFClipped(p13, p22, p32, colour);
                fillTriangleFClipped(p32, p33, p13, colour);
            }
            else if (side2clipped)
            {
                fillTriangleFClipped(p11, p21, p33, colour);
                fillTriangleFClipped(p33, p13, p11, colour);
            }
            else if (side3clipped)
            {
                fillTriangleFClipped(p11, p21, p22, colour);
                fillTriangleFClipped(p22, p32, p11, colour);
            }
            else
            {
                fillTriangleFClipped(p13, p11, p21, colour);
                fillTriangleFClipped(p21, p22, p13, colour);
                fillTriangleFClipped(p22, p32, p33, colour);
                fillTriangleFClipped(p33, p13, p22, colour);
            }
        }
    }

    /// Draw filled quad in float coordinates
    void fillQuadF(PointF p1, PointF p2, PointF p3, PointF p4, uint colour)
    {
        fillTriangleF(p1, p2, p3, colour);
        fillTriangleF(p3, p4, p1, colour);
    }

    /// Draw line of arbitrary width in float coordinates
    void drawLineF(PointF p1, PointF p2, float width, uint colour)
    {
        // direction vector
        PointF v = (p2 - p1).normalized;
        // calculate normal vector
        // calculate normal vector : rotate CCW 90 degrees
        PointF n = v.rotated90ccw();
        // rotate CCW 90 degrees
        n.y = v.x;
        n.x = -v.y;
        // offset by normal * half_width
        n *= width / 2;
        // draw line using quad
        fillQuadF(p1 - n, p2 - n, p2 + n, p1 + n, colour);
    }

    // find intersection point for two vectors with start points p1, p2 and normalized directions dir1, dir2
    protected static PointF intersectVectors(PointF p1, PointF dir1, PointF p2, PointF dir2)
    {
        /*
        L1 = P1 + a * V1
        L2 = P2 + b * V2
        P1 + a * V1 = P2 + b * V2
        a * V1 = (P2 - P1) + b * V2
        a * (V1 X V2) = (P2 - P1) X V2
        a = (P2 - P1) * V2 / (V1*V2)
        return P1 + a * V1
        */
        // just return middle point
        PointF p2p1 = (p2 - p1); //.normalized;
        float d1 = p2p1.crossProduct(dir2);
        float d2 = dir1.crossProduct(dir2);
        // a * d1 = d2
        if (d2 >= -0.1f && d2 <= 0.1f)
        {
            return p1; //PointF((p1.x + p2.x)/2, (p1.y + p2.y)/2);
        }
        float a = d1 / d2;
        return p1 + dir1 * a;
    }

    protected void calcLineSegmentQuad(PointF p0, PointF p1, PointF p2, PointF p3, float width, ref PointF[4] quad)
    {
        // direction vector
        PointF v = (p2 - p1).normalized;
        // calculate normal vector : rotate CCW 90 degrees
        PointF n = v.rotated90ccw();
        // offset by normal * half_width
        n *= width / 2;
        // draw line using quad
        PointF pp10 = p1 - n;
        PointF pp20 = p2 - n;
        PointF pp11 = p1 + n;
        PointF pp21 = p2 + n;
        if ((p1 - p0).length > 0.1f)
        {
            // has prev segment
            PointF prevv = (p1 - p0).normalized;
            PointF prevn = prevv.rotated90ccw();
            PointF prev10 = p1 - prevn * width / 2;
            PointF prev11 = p1 + prevn * width / 2;
            PointF intersect0 = intersectVectors(pp10, -v, prev10, prevv);
            PointF intersect1 = intersectVectors(pp11, -v, prev11, prevv);
            pp10 = intersect0;
            pp11 = intersect1;
        }
        if ((p3 - p2).length > 0.1f)
        {
            // has next segment
            PointF nextv = (p3 - p2).normalized;
            PointF nextn = nextv.rotated90ccw();
            PointF next20 = p2 - nextn * width / 2;
            PointF next21 = p2 + nextn * width / 2;
            PointF intersect0 = intersectVectors(pp20, v, next20, -nextv);
            PointF intersect1 = intersectVectors(pp21, v, next21, -nextv);
            pp20 = intersect0;
            pp21 = intersect1;
        }
        quad[0] = pp10;
        quad[1] = pp20;
        quad[2] = pp21;
        quad[3] = pp11;
    }
    /// Draw line of arbitrary width in float coordinates p1..p2 with angle based on
    /// Previous (p0..p1) and next (p2..p3) segments
    void drawLineSegmentF(PointF p0, PointF p1, PointF p2, PointF p3, float width, uint colour)
    {
        PointF[4] quad;
        calcLineSegmentQuad(p0, p1, p2, p3, width, quad);
        fillQuadF(quad[0], quad[1], quad[2], quad[3], colour);
    }

    /// Draw poly line of arbitrary width in float coordinates;
    /// When cycled is true, connect first and last point (optionally fill inner area)
    void polyLineF(PointF[] points, float width, uint colour, bool cycled = false,
            uint innerAreaColour = COLOR_TRANSPARENT)
    {
        if (points.length < 2)
            return;
        bool hasInnerArea = !isFullyTransparentColor(innerAreaColour);
        if (isFullyTransparentColor(colour))
        {
            if (hasInnerArea)
                fillPolyF(points, innerAreaColour);
            return;
        }
        int len = cast(int)points.length;
        if (hasInnerArea)
        {
            PointF[] innerArea;
            innerArea.assumeSafeAppend;
            //Log.d("fill poly inner: ", points);
            for (int i = 0; i < len; i++)
            {
                PointF[4] quad;
                int index0 = i - 1;
                int index1 = i;
                int index2 = i + 1;
                int index3 = i + 2;
                if (index0 < 0)
                    index0 = cycled ? len - 1 : 0;
                index2 %= len; // only can be if cycled
                index3 %= len; // only can be if cycled
                if (!cycled)
                {
                    if (index1 == len - 1)
                    {
                        index0 = index1;
                        index2 = 0;
                        index3 = 0;
                    }
                    else if (index1 == len - 2)
                    {
                        index2 = len - 1;
                        index3 = len - 1;
                    }
                }
                //Log.d("lineSegment - inner ", index0, ", ", index1, ", ", index2, ", ", index3);
                calcLineSegmentQuad(points[index0], points[index1], points[index2], points[index3], width, quad);
                innerArea ~= quad[3];
            }
            fillPolyF(innerArea, innerAreaColour);
        }
        if (!isFullyTransparentColor(colour))
        {
            for (int i = 0; i < len; i++)
            {
                int index0 = i - 1;
                int index1 = i;
                int index2 = i + 1;
                int index3 = i + 2;
                if (index0 < 0)
                    index0 = cycled ? len - 1 : 0;
                index2 %= len; // only can be if cycled
                index3 %= len; // only can be if cycled
                if (!cycled)
                {
                    if (index1 == len - 1)
                    {
                        index0 = index1;
                        index2 = 0;
                        index3 = 0;
                    }
                    else if (index1 == len - 2)
                    {
                        index2 = len - 1;
                        index3 = len - 1;
                    }
                }
                //Log.d("lineSegment - outer ", index0, ", ", index1, ", ", index2, ", ", index3);
                if (cycled || i + 1 < len)
                    drawLineSegmentF(points[index0], points[index1], points[index2], points[index3], width, colour);
            }
        }
    }

    /// Draw filled polyline (vertexes must be in clockwise order)
    void fillPolyF(PointF[] points, uint colour)
    {
        if (points.length < 3)
        {
            return;
        }
        if (points.length == 3)
        {
            fillTriangleF(points[0], points[1], points[2], colour);
            return;
        }
        PointF[] list = points.dup;
        bool moved;
        while (list.length > 3)
        {
            moved = false;
            for (int i = 0; i < list.length; i++)
            {
                PointF p1 = list[i + 0];
                PointF p2 = list[(i + 1) % list.length];
                PointF p3 = list[(i + 2) % list.length];
                float cross = (p2 - p1).crossProduct(p3 - p2);
                if (cross > 0)
                {
                    // draw triangle
                    fillTriangleF(p1, p2, p3, colour);
                    int indexToRemove = (i + 1) % (cast(int)list.length);
                    // remove triangle from poly
                    for (int j = indexToRemove; j + 1 < list.length; j++)
                        list[j] = list[j + 1];
                    list.length = list.length - 1;
                    i += 2;
                    moved = true;
                }
            }
            if (list.length == 3)
            {
                fillTriangleF(list[0], list[1], list[2], colour);
                break;
            }
            if (!moved)
                break;
        }
    }

    /// Draw ellipse or filled ellipse
    void drawEllipseF(float centerX, float centerY, float xRadius, float yRadius, float lineWidth,
            uint lineColor, uint fillColor = COLOR_TRANSPARENT)
    {
        import std.math : sin, cos, PI;

        if (xRadius < 0)
            xRadius = -xRadius;
        if (yRadius < 0)
            yRadius = -yRadius;
        int numLines = cast(int)((xRadius + yRadius) / 5);
        if (numLines < 4)
            numLines = 4;
        float step = PI * 2 / numLines;
        float angle = 0;
        PointF[] points;
        points.assumeSafeAppend;
        for (int i = 0; i < numLines; i++)
        {
            float x = centerX + cos(angle) * xRadius;
            float y = centerY + sin(angle) * yRadius;
            angle += step;
            points ~= PointF(x, y);
        }
        polyLineF(points, lineWidth, lineColor, true, fillColor);
    }

    /// Draw ellipse arc or filled ellipse arc
    void drawEllipseArcF(float centerX, float centerY, float xRadius, float yRadius, float startAngle,
            float endAngle, float lineWidth, uint lineColor, uint fillColor = COLOR_TRANSPARENT)
    {
        import std.math : sin, cos, PI;

        if (xRadius < 0)
            xRadius = -xRadius;
        if (yRadius < 0)
            yRadius = -yRadius;
        startAngle = startAngle * 2 * PI / 360;
        endAngle = endAngle * 2 * PI / 360;
        if (endAngle < startAngle)
            endAngle += 2 * PI;
        float angleDiff = endAngle - startAngle;
        if (angleDiff > 2 * PI)
            angleDiff %= 2 * PI;
        int numLines = cast(int)((xRadius + yRadius) / angleDiff);
        if (numLines < 3)
            numLines = 4;
        float step = angleDiff / numLines;
        float angle = startAngle;
        PointF[] points;
        points.assumeSafeAppend;
        points ~= PointF(centerX, centerY);
        for (int i = 0; i < numLines; i++)
        {
            float x = centerX + cos(angle) * xRadius;
            float y = centerY + sin(angle) * yRadius;
            angle += step;
            points ~= PointF(x, y);
        }
        polyLineF(points, lineWidth, lineColor, true, fillColor);
    }

    /// Draw poly line of width == 1px; when cycled is true, connect first and last point
    void polyLine(Point[] points, uint colour, bool cycled)
    {
        if (points.length < 2)
            return;
        for (int i = 0; i + 1 < points.length; i++)
        {
            drawLine(points[i], points[i + 1], colour);
        }
        if (cycled && points.length > 2)
            drawLine(points[$ - 1], points[0], colour);
    }

    /// Draw line from point p1 to p2 with specified color
    void drawLine(Point p1, Point p2, uint colour)
    {
        if (!clipLine(_clipRect, p1, p2))
            return;
        // from rosettacode.org
        import std.math : abs;

        immutable int dx = p2.x - p1.x;
        immutable int ix = (dx > 0) - (dx < 0);
        immutable int dx2 = abs(dx) * 2;
        int dy = p2.y - p1.y;
        immutable int iy = (dy > 0) - (dy < 0);
        immutable int dy2 = abs(dy) * 2;
        drawPixel(p1.x, p1.y, colour);
        if (dx2 >= dy2)
        {
            int error = dy2 - (dx2 / 2);
            while (p1.x != p2.x)
            {
                if (error >= 0 && (error || (ix > 0)))
                {
                    error -= dx2;
                    p1.y += iy;
                }
                error += dy2;
                p1.x += ix;
                drawPixel(p1.x, p1.y, colour);
            }
        }
        else
        {
            int error = dx2 - (dy2 / 2);
            while (p1.y != p2.y)
            {
                if (error >= 0 && (error || (iy > 0)))
                {
                    error -= dy2;
                    p1.x += ix;
                }
                error += dx2;
                p1.y += iy;
                drawPixel(p1.x, p1.y, colour);
            }
        }
    }

    // basically a modified drawEllipseArcF that doesn't draw but gives you the lines instead!
    static PointF[] makeArcPath(PointF center, float radiusX, float radiusY, float startAngle, float endAngle)
    {
        import std.math : sin, cos, PI, abs, sqrt;

        radiusX = abs(radiusX);
        radiusY = abs(radiusY);
        startAngle = startAngle * 2 * PI / 360;
        endAngle = endAngle * 2 * PI / 360;
        if (endAngle < startAngle)
            endAngle += 2 * PI;
        float angleDiff = endAngle - startAngle;
        if (angleDiff > 2 * PI)
            angleDiff %= 2 * PI;
        int numLines = cast(int)(sqrt(radiusX * radiusX + radiusY * radiusY) / angleDiff);
        if (numLines < 3)
            numLines = 4;
        float step = angleDiff / numLines;
        float angle = startAngle;
        PointF[] points;
        points.assumeSafeAppend;
        if (radiusX == 0)
        {
            points ~= PointF(center.x, center.y);
        }
        else
            for (int i; i < numLines + 1; i++)
            {
                float x = center.x + cos(angle) * radiusX;
                float y = center.y + sin(angle) * radiusY;
                angle += step;
                points ~= PointF(x, y);
            }
        return points;
    }

    // calculates inwards XY offsets from rect corners
    static PointF[4] calcRectRoundedCornerRadius(vec4 corners, float w, float h, bool keepSquareXY)
    {
        import std.algorithm.comparison : min;

        // clamps radius to corner
        static float clampRadius(float r, float len) pure @nogc @safe
        {
            if (len - 2 * r < 0)
                return len / 2;
            return r;
        }

        if (keepSquareXY)
        {
            auto minSize = min(w, h);
            w = h = minSize;
        }
        PointF[4] cornerRad;
        cornerRad[0] = PointF(clampRadius(corners.x, w), clampRadius(corners.x, h));
        cornerRad[1] = PointF(-clampRadius(corners.y, w), clampRadius(corners.y, h));
        cornerRad[2] = PointF(clampRadius(corners.z, w), -clampRadius(corners.z, h));
        cornerRad[3] = PointF(-clampRadius(corners.w, w), -clampRadius(corners.w, h));
        return cornerRad;
    }

    /// Builds outer rounded rect path
    /// The last parameter optionally writes out indices of first segment of corners excluding top-left
    static PointF[] makeRoundedRectPath(Rect rect, vec4 corners, bool keepSquareXY,
            size_t[] outCornerSegmentsStart = null)
    {
        import std.range : chain;
        import std.array : array;

        PointF[4] cornerRad = calcRectRoundedCornerRadius(corners, rect.width, rect.height, keepSquareXY);
        PointF topLeftC = PointF(rect.left, rect.top) + cornerRad[0];
        PointF topRightC = PointF(rect.left, rect.top) + cornerRad[1] + PointF(rect.width, 0);
        PointF botLeftC = PointF(rect.left, rect.top) + cornerRad[2] + PointF(0, rect.height);
        PointF botRightC = PointF(rect.left, rect.top) + cornerRad[3] + PointF(rect.width, rect.height);
        auto lt = makeArcPath(topLeftC, cornerRad[0].x, cornerRad[0].y, 180, 270);
        auto rt = makeArcPath(topRightC, cornerRad[1].x, cornerRad[1].y, 270, 0);
        auto lb = makeArcPath(botLeftC, cornerRad[2].x, cornerRad[2].y, 90, 180);
        auto rb = makeArcPath(botRightC, cornerRad[3].x, cornerRad[3].y, 0, 90);
        if (outCornerSegmentsStart.length)
        {
            outCornerSegmentsStart[0] = lt.length;
            outCornerSegmentsStart[1] = lt.length + rt.length;
            outCornerSegmentsStart[2] = lt.length + rt.length + lb.length;
        }
        auto outerPath = chain(lt, rt, rb, lb, lt[0 .. 1]);
        return outerPath.array();
    }

    /// Draws rect with rounded corners
    void drawRoundedRectF(Rect rect, vec4 corners, bool keepSquareXY, float frameWidth, uint frameColor,
            uint fillColor = COLOR_TRANSPARENT)
    {
        auto fullPath = makeRoundedRectPath(rect, corners, keepSquareXY);
        // fill inner area, doing this manually by sectors to reduce flickering artifacts
        if (fillColor != COLOR_TRANSPARENT)
        {
            PointF center = PointF(rect.middlex, rect.middley);
            for (int i = 0; i < fullPath.length - 1; i++)
            {
                fillTriangleF(center, fullPath[i], fullPath[i + 1], fillColor);
            }
        }
        if (frameColor != COLOR_TRANSPARENT && frameWidth > 0)
        {
            for (int i = 0; i < fullPath.length - 1; i++)
            {
                drawLineF(fullPath[i], fullPath[i + 1], frameWidth, frameColor);
            }
        }
    }

    /// Create drawbuf with copy of current buffer with changed colors (returns this if not supported)
    /// NOT USED
    DrawBuf transformColors(ref ColorTransform transform)
    {
        return this;
    }

    /// Draw custom OpenGL scene
    void drawCustomOpenGLScene(Rect rc, OpenGLDrawableDelegate handler)
    {
        // override it for OpenGL draw buffer
        Log.w("drawCustomOpenGLScene is called for non-OpenGL DrawBuf");
    }

    void clear()
    {
        resetClipping();
    }
}

alias DrawBufRef = Ref!DrawBuf;

/// RAII setting/restoring of a DrawBuf clip rectangle
struct ClipRectSaver
{
    private DrawBuf _buf;
    private Rect _oldClipRect;
    private uint _oldAlpha;

    /// Apply (intersect) new clip rectangle and alpha to draw buf
    /// Set `intersect` parameter to `false`, if you want to draw something outside of the widget
    this(DrawBuf buf, Rect newClipRect, uint newAlpha = 0, bool intersect = true)
    {
        _buf = buf;
        _oldClipRect = buf.clipRect;
        _oldAlpha = buf.alpha;
        if (intersect)
            buf.intersectClipRect(newClipRect);
        else
            buf.clipRect = newClipRect;
        if (newAlpha)
            buf.addAlpha(newAlpha);
    }
    /// ditto
    this(DrawBuf buf, Box newClipBox, uint newAlpha = 0, bool intersect = true)
    {
        this(buf, Rect(newClipBox), newAlpha, intersect);
    }
    /// Restore previous clip rectangle
    ~this()
    {
        _buf.clipRect = _oldClipRect;
        _buf.alpha = _oldAlpha;
    }
}

class ColorDrawBufBase : DrawBuf
{
    protected int _w;
    protected int _h;

    /// Returns buffer bits per pixel
    override @property int bpp()
    {
        return 32;
    }

    override @property int width()
    {
        return _w;
    }

    override @property int height()
    {
        return _h;
    }

    /// Returns pointer to ARGB scanline, null if y is out of range or buffer doesn't provide access to its memory
    uint* scanLine(int y)
    {
        return null;
    }

    /// Draw source buffer rectangle contents to destination buffer
    override void drawFragment(int x, int y, DrawBuf src, Rect srcrect)
    {
        Rect dstrect = Rect(x, y, x + srcrect.width, y + srcrect.height);
        if (applyClipping(dstrect, srcrect))
        {
            if (src.applyClipping(srcrect, dstrect))
            {
                int dx = srcrect.width;
                int dy = srcrect.height;
                ColorDrawBufBase colorDrawBuf = cast(ColorDrawBufBase)src;
                if (colorDrawBuf !is null)
                {
                    foreach (yy; 0 .. dy)
                    {
                        uint* srcrow = colorDrawBuf.scanLine(srcrect.top + yy) + srcrect.left;
                        uint* dstrow = scanLine(dstrect.top + yy) + dstrect.left;
                        if (!_alpha)
                        {
                            // simplified version - no alpha blending
                            foreach (i; 0 .. dx)
                            {
                                uint pixel = srcrow[i];
                                uint alpha = pixel >> 24;
                                if (!alpha)
                                    dstrow[i] = pixel;
                                else if (alpha < 254)
                                {
                                    // apply blending
                                    dstrow[i] = blendARGB(dstrow[i], pixel, alpha);
                                }
                            }
                        }
                        else
                        {
                            // combine two alphas
                            foreach (i; 0 .. dx)
                            {
                                uint pixel = srcrow[i];
                                uint alpha = blendAlpha(_alpha, pixel >> 24);
                                if (!alpha)
                                    dstrow[i] = pixel;
                                else if (alpha < 254)
                                {
                                    // apply blending
                                    dstrow[i] = blendARGB(dstrow[i], pixel, alpha);
                                }
                            }
                        }

                    }
                }
            }
        }
    }

    import std.container.array;

    /// Create mapping of source coordinates to destination coordinates, for resize.
    private Array!int createMap(int dst0, int dst1, int src0, int src1, double k)
    {
        int dd = dst1 - dst0;
        //int sd = src1 - src0;
        Array!int res;
        res.length = dd;
        foreach (int i; 0 .. dd)
            res[i] = src0 + cast(int)(i * k); //sd / dd;
        return res;
    }

    /// Draw source buffer rectangle contents to destination buffer rectangle applying rescaling
    override void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect)
    {
        //Log.d("drawRescaled ", dstrect, " <- ", srcrect);
        if (_alpha >= 254)
            return; // fully transparent - don't draw
        double kx = cast(double)srcrect.width / dstrect.width;
        double ky = cast(double)srcrect.height / dstrect.height;
        if (applyClipping(dstrect, srcrect))
        {
            auto xmapArray = createMap(dstrect.left, dstrect.right, srcrect.left, srcrect.right, kx);
            auto ymapArray = createMap(dstrect.top, dstrect.bottom, srcrect.top, srcrect.bottom, ky);

            int* xmap = &xmapArray[0];
            int* ymap = &ymapArray[0];
            int dx = dstrect.width;
            int dy = dstrect.height;
            ColorDrawBufBase colorDrawBuf = cast(ColorDrawBufBase)src;
            if (colorDrawBuf !is null)
            {
                foreach (y; 0 .. dy)
                {
                    uint* srcrow = colorDrawBuf.scanLine(ymap[y]);
                    uint* dstrow = scanLine(dstrect.top + y) + dstrect.left;
                    if (!_alpha)
                    {
                        // simplified alpha calculation
                        foreach (x; 0 .. dx)
                        {
                            uint srcpixel = srcrow[xmap[x]];
                            uint dstpixel = dstrow[x];
                            uint alpha = srcpixel >> 24;
                            if (!alpha)
                                dstrow[x] = srcpixel;
                            else if (alpha < 255)
                            {
                                // apply blending
                                dstrow[x] = blendARGB(dstpixel, srcpixel, alpha);
                            }
                        }
                    }
                    else
                    {
                        // blending two alphas
                        foreach (x; 0 .. dx)
                        {
                            uint srcpixel = srcrow[xmap[x]];
                            uint dstpixel = dstrow[x];
                            uint srca = srcpixel >> 24;
                            uint alpha = !srca ? _alpha : blendAlpha(_alpha, srca);
                            if (!alpha)
                                dstrow[x] = srcpixel;
                            else if (alpha < 255)
                            {
                                // apply blending
                                dstrow[x] = blendARGB(dstpixel, srcpixel, alpha);
                            }
                        }
                    }
                }
            }
        }
    }

    /// Detect position of black pixels in row for 9-patch markup
    private bool detectHLine(int y, ref int x0, ref int x1)
    {
        uint* line = scanLine(y);
        bool foundUsed = false;
        x0 = 0;
        x1 = 0;
        foreach (int x; 1 .. _w - 1)
        {
            if (isBlackPixel(line[x]))
            { // opaque black pixel
                if (!foundUsed)
                {
                    x0 = x;
                    foundUsed = true;
                }
                x1 = x + 1;
            }
        }
        return x1 > x0;
    }

    static bool isBlackPixel(uint c)
    {
        if (((c >> 24) & 255) > 10)
            return false;
        if (((c >> 16) & 255) > 10)
            return false;
        if (((c >> 8) & 255) > 10)
            return false;
        if (((c >> 0) & 255) > 10)
            return false;
        return true;
    }

    /// Detect position of black pixels in column for 9-patch markup
    private bool detectVLine(int x, ref int y0, ref int y1)
    {
        bool foundUsed = false;
        y0 = 0;
        y1 = 0;
        foreach (int y; 1 .. _h - 1)
        {
            uint* line = scanLine(y);
            if (isBlackPixel(line[x]))
            { // opaque black pixel
                if (!foundUsed)
                {
                    y0 = y;
                    foundUsed = true;
                }
                y1 = y + 1;
            }
        }
        return y1 > y0;
    }
    /// Detect nine patch using image 1-pixel border (see Android documentation)
    override bool detectNinePatch()
    {
        if (_w < 3 || _h < 3)
            return false; // image is too small
        int x00, x01, x10, x11, y00, y01, y10, y11;
        bool found = true;
        found = found && detectHLine(0, x00, x01);
        found = found && detectHLine(_h - 1, x10, x11);
        found = found && detectVLine(0, y00, y01);
        found = found && detectVLine(_w - 1, y10, y11);
        if (!found)
            return false; // no black pixels on 1-pixel frame
        NinePatch* p = new NinePatch;
        p.frame.left = x00 - 1;
        p.frame.right = _w - x01 - 1;
        p.frame.top = y00 - 1;
        p.frame.bottom = _h - y01 - 1;
        p.padding.left = x10 - 1;
        p.padding.right = _w - x11 - 1;
        p.padding.top = y10 - 1;
        p.padding.bottom = _h - y11 - 1;
        _ninePatch = p;
        //Log.d("NinePatch detected: frame=", p.frame, " padding=", p.padding, " left+right=", p.frame.left + p.frame.right, " dx=", _w);
        return true;
    }

    override void drawGlyph(int x, int y, Glyph* glyph, uint color)
    {
        ubyte[] src = glyph.glyph;
        int srcdx = glyph.blackBoxX;
        int srcdy = glyph.blackBoxY;
        bool clipping = true; //!_clipRect.empty();
        color = applyAlpha(color);
        bool subpixel = glyph.subpixelMode != SubpixelRenderingMode.none;
        foreach (int yy; 0 .. srcdy)
        {
            int liney = y + yy;
            if (clipping && (liney < _clipRect.top || liney >= _clipRect.bottom))
                continue;
            if (liney < 0 || liney >= _h)
                continue;
            uint* row = scanLine(liney);
            ubyte* srcrow = src.ptr + yy * srcdx;
            foreach (int xx; 0 .. srcdx)
            {
                int colx = x + (subpixel ? xx / 3 : xx);
                if (clipping && (colx < _clipRect.left || colx >= _clipRect.right))
                    continue;
                if (colx < 0 || colx >= _w)
                    continue;
                uint alpha2 = (color >> 24);
                uint alpha1 = srcrow[xx] ^ 255;
                uint alpha = ((((alpha1 ^ 255) * (alpha2 ^ 255)) >> 8) ^ 255) & 255;
                if (subpixel)
                {
                    int x0 = xx % 3;
                    ubyte* dst = cast(ubyte*)(row + colx);
                    ubyte* pcolor = cast(ubyte*)(&color);
                    blendSubpixel(dst, pcolor, alpha, x0, glyph.subpixelMode);
                }
                else
                {
                    uint pixel = row[colx];
                    if (alpha < 255)
                    {
                        if (!alpha)
                            row[colx] = pixel;
                        else
                        {
                            // apply blending
                            row[colx] = blendARGB(pixel, color, alpha);
                        }
                    }
                }
            }
        }
    }

    void drawGlyphToTexture(int x, int y, Glyph* glyph)
    {
        ubyte[] src = glyph.glyph;
        int srcdx = glyph.blackBoxX;
        int srcdy = glyph.blackBoxY;
        bool subpixel = glyph.subpixelMode != SubpixelRenderingMode.none;
        foreach (int yy; 0 .. srcdy)
        {
            int liney = y + yy;
            uint* row = scanLine(liney);
            ubyte* srcrow = src.ptr + yy * srcdx;
            int increment = subpixel ? 3 : 1;
            for (int xx = 0; xx <= srcdx - increment; xx += increment)
            {
                int colx = x + (subpixel ? xx / 3 : xx);
                if (subpixel)
                {
                    uint t1 = srcrow[xx];
                    uint t2 = srcrow[xx + 1];
                    uint t3 = srcrow[xx + 2];
                    //uint pixel = ((t2 ^ 0x00) << 24) | ((t1  ^ 0xFF)<< 16) | ((t2 ^ 0xFF) << 8) | (t3 ^ 0xFF);
                    uint pixel = ((t2 ^ 0x00) << 24) | 0xFFFFFF;
                    row[colx] = pixel;
                }
                else
                {
                    uint alpha1 = srcrow[xx] ^ 0xFF;
                    //uint pixel = (alpha1 << 24) | 0xFFFFFF; //(alpha1 << 16) || (alpha1 << 8) || alpha1;
                    //uint pixel = ((alpha1 ^ 0xFF) << 24) | (alpha1 << 16) | (alpha1 << 8) | alpha1;
                    uint pixel = ((alpha1 ^ 0xFF) << 24) | 0xFFFFFF;
                    row[colx] = pixel;
                }
            }
        }
    }

    override void fillRect(Rect rc, uint color)
    {
        uint alpha = color >> 24;
        if (applyClipping(rc))
        {
            foreach (y; rc.top .. rc.bottom)
            {
                uint* row = scanLine(y);
                if (!alpha)
                {
                    row[rc.left .. rc.right] = color;
                }
                else if (alpha < 254)
                {
                    foreach (x; rc.left .. rc.right)
                    {
                        // apply blending
                        row[x] = blendARGB(row[x], color, alpha);
                    }
                }
            }
        }
    }

    /// Fill rectangle with a gradient (clipping is applied)
    override void fillGradientRect(Rect rc, uint color1, uint color2, uint color3, uint color4)
    {
        if (applyClipping(rc))
        {
            foreach (y; rc.top .. rc.bottom)
            {
                // interpolate vertically at the side edges
                uint ay = (255 * (y - rc.top)) / (rc.bottom - rc.top);
                uint cl = blendARGB(color2, color1, ay);
                uint cr = blendARGB(color4, color3, ay);

                uint* row = scanLine(y);
                foreach (x; rc.left .. rc.right)
                {
                    // interpolate horizontally
                    uint ax = (255 * (x - rc.left)) / (rc.right - rc.left);
                    row[x] = blendARGB(cr, cl, ax);
                }
            }
        }
    }

    /// Draw pixel at (x, y) with specified color
    override void drawPixel(int x, int y, uint color)
    {
        if (!_clipRect.isPointInside(x, y))
            return;
        color = applyAlpha(color);
        uint* row = scanLine(y);
        uint alpha = color >> 24;
        if (!alpha)
        {
            row[x] = color;
        }
        else if (alpha < 254)
        {
            // apply blending
            row[x] = blendARGB(row[x], color, alpha);
        }
    }
}

class GrayDrawBuf : DrawBuf
{
    protected int _w;
    protected int _h;
    /// Returns buffer bits per pixel
    override @property int bpp()
    {
        return 8;
    }

    override @property int width()
    {
        return _w;
    }

    override @property int height()
    {
        return _h;
    }

    protected MallocBuf!ubyte _buf;

    this(int width, int height)
    {
        resize(width, height);
    }

    ubyte* scanLine(int y)
    {
        if (y >= 0 && y < _h)
            return _buf.ptr + _w * y;
        return null;
    }

    override void resize(int width, int height)
    {
        if (_w == width && _h == height)
            return;
        _w = width;
        _h = height;
        _buf.length = _w * _h;
        resetClipping();
    }

    override void fill(uint color)
    {
        if (hasClipping)
        {
            fillRect(_clipRect, color);
            return;
        }
        int len = _w * _h;
        ubyte* p = _buf.ptr;
        ubyte cl = rgbToGray(color);
        foreach (i; 0 .. len)
            p[i] = cl;
    }

    /// Draw source buffer rectangle contents to destination buffer
    override void drawFragment(int x, int y, DrawBuf src, Rect srcrect)
    {
        Rect dstrect = Rect(x, y, x + srcrect.width, y + srcrect.height);
        if (applyClipping(dstrect, srcrect))
        {
            if (src.applyClipping(srcrect, dstrect))
            {
                int dx = srcrect.width;
                int dy = srcrect.height;
                GrayDrawBuf grayDrawBuf = cast(GrayDrawBuf)src;
                if (grayDrawBuf !is null)
                {
                    foreach (yy; 0 .. dy)
                    {
                        ubyte* srcrow = grayDrawBuf.scanLine(srcrect.top + yy) + srcrect.left;
                        ubyte* dstrow = scanLine(dstrect.top + yy) + dstrect.left;
                        foreach (i; 0 .. dx)
                        {
                            ubyte pixel = srcrow[i];
                            dstrow[i] = pixel;
                        }
                    }
                }
            }
        }
    }

    /// Create mapping of source coordinates to destination coordinates, for resize.
    private int[] createMap(int dst0, int dst1, int src0, int src1)
    {
        int dd = dst1 - dst0;
        int sd = src1 - src0;
        int[] res = new int[dd];
        foreach (int i; 0 .. dd)
            res[i] = src0 + i * sd / dd;
        return res;
    }
    /// Draw source buffer rectangle contents to destination buffer rectangle applying rescaling
    override void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect)
    {
        //Log.d("drawRescaled ", dstrect, " <- ", srcrect);
        if (applyClipping(dstrect, srcrect))
        {
            int[] xmap = createMap(dstrect.left, dstrect.right, srcrect.left, srcrect.right);
            int[] ymap = createMap(dstrect.top, dstrect.bottom, srcrect.top, srcrect.bottom);
            int dx = dstrect.width;
            int dy = dstrect.height;
            GrayDrawBuf grayDrawBuf = cast(GrayDrawBuf)src;
            if (grayDrawBuf !is null)
            {
                foreach (y; 0 .. dy)
                {
                    ubyte* srcrow = grayDrawBuf.scanLine(ymap[y]);
                    ubyte* dstrow = scanLine(dstrect.top + y) + dstrect.left;
                    foreach (x; 0 .. dx)
                    {
                        ubyte srcpixel = srcrow[xmap[x]];
                        ubyte dstpixel = dstrow[x];
                        dstrow[x] = srcpixel;
                    }
                }
            }
        }
    }

    /// Detect position of black pixels in row for 9-patch markup
    private bool detectHLine(int y, ref int x0, ref int x1)
    {
        ubyte* line = scanLine(y);
        bool foundUsed = false;
        x0 = 0;
        x1 = 0;
        foreach (int x; 1 .. _w - 1)
        {
            if (line[x] == 0x00000000)
            { // opaque black pixel
                if (!foundUsed)
                {
                    x0 = x;
                    foundUsed = true;
                }
                x1 = x + 1;
            }
        }
        return x1 > x0;
    }

    /// Detect position of black pixels in column for 9-patch markup
    private bool detectVLine(int x, ref int y0, ref int y1)
    {
        bool foundUsed = false;
        y0 = 0;
        y1 = 0;
        foreach (int y; 1 .. _h - 1)
        {
            ubyte* line = scanLine(y);
            if (line[x] == 0x00000000)
            { // opaque black pixel
                if (!foundUsed)
                {
                    y0 = y;
                    foundUsed = true;
                }
                y1 = y + 1;
            }
        }
        return y1 > y0;
    }
    /// Detect nine patch using image 1-pixel border (see Android documentation)
    override bool detectNinePatch()
    {
        if (_w < 3 || _h < 3)
            return false; // image is too small
        int x00, x01, x10, x11, y00, y01, y10, y11;
        bool found = true;
        found = found && detectHLine(0, x00, x01);
        found = found && detectHLine(_h - 1, x10, x11);
        found = found && detectVLine(0, y00, y01);
        found = found && detectVLine(_w - 1, y10, y11);
        if (!found)
            return false; // no black pixels on 1-pixel frame
        NinePatch* p = new NinePatch;
        p.frame.left = x00 - 1;
        p.frame.right = _h - y01 - 1;
        p.frame.top = y00 - 1;
        p.frame.bottom = _h - y01 - 1;
        p.padding.left = x10 - 1;
        p.padding.right = _h - y11 - 1;
        p.padding.top = y10 - 1;
        p.padding.bottom = _h - y11 - 1;
        _ninePatch = p;
        return true;
    }

    override void drawGlyph(int x, int y, Glyph* glyph, uint color)
    {
        ubyte[] src = glyph.glyph;
        int srcdx = glyph.blackBoxX;
        int srcdy = glyph.blackBoxY;
        bool clipping = true; //!_clipRect.empty();
        foreach (int yy; 0 .. srcdy)
        {
            int liney = y + yy;
            if (clipping && (liney < _clipRect.top || liney >= _clipRect.bottom))
                continue;
            if (liney < 0 || liney >= _h)
                continue;
            ubyte* row = scanLine(liney);
            ubyte* srcrow = src.ptr + yy * srcdx;
            foreach (int xx; 0 .. srcdx)
            {
                int colx = xx + x;
                if (clipping && (colx < _clipRect.left || colx >= _clipRect.right))
                    continue;
                if (colx < 0 || colx >= _w)
                    continue;
                uint alpha1 = srcrow[xx] ^ 255;
                uint alpha2 = (color >> 24);
                uint alpha = ((((alpha1 ^ 255) * (alpha2 ^ 255)) >> 8) ^ 255) & 255;
                uint pixel = row[colx];
                if (!alpha)
                    row[colx] = cast(ubyte)pixel;
                else if (alpha < 255)
                {
                    // apply blending
                    row[colx] = cast(ubyte)blendARGB(pixel, color, alpha);
                }
            }
        }
    }

    override void fillRect(Rect rc, uint color)
    {
        if (applyClipping(rc))
        {
            uint alpha = color >> 24;
            ubyte cl = rgbToGray(color);
            foreach (y; rc.top .. rc.bottom)
            {
                ubyte* row = scanLine(y);
                foreach (x; rc.left .. rc.right)
                {
                    if (!alpha)
                        row[x] = cl;
                    else if (alpha < 255)
                    {
                        // apply blending
                        row[x] = blendGray(row[x], cl, alpha);
                    }
                }
            }
        }
    }

    /// Fill rectangle with a gradient (clipping is applied)
    override void fillGradientRect(Rect rc, uint color1, uint color2, uint color3, uint color4)
    {
        if (applyClipping(rc))
        {
            ubyte c1 = rgbToGray(color1);
            ubyte c2 = rgbToGray(color2);
            ubyte c3 = rgbToGray(color3);
            ubyte c4 = rgbToGray(color4);
            foreach (y; rc.top .. rc.bottom)
            {
                // interpolate vertically at the side edges
                uint ay = (255 * (y - rc.top)) / (rc.bottom - rc.top);
                ubyte cl = blendGray(c2, c1, ay);
                ubyte cr = blendGray(c4, c3, ay);

                ubyte* row = scanLine(y);
                foreach (x; rc.left .. rc.right)
                {
                    // interpolate horizontally
                    uint ax = (255 * (x - rc.left)) / (rc.right - rc.left);
                    row[x] = blendGray(cr, cl, ax);
                }
            }
        }
    }

    /// Draw pixel at (x, y) with specified color
    override void drawPixel(int x, int y, uint color)
    {
        if (!_clipRect.isPointInside(x, y))
            return;
        color = applyAlpha(color);
        ubyte cl = rgbToGray(color);
        ubyte* row = scanLine(y);
        uint alpha = color >> 24;
        if (!alpha)
        {
            row[x] = cl;
        }
        else if (alpha < 254)
        {
            // apply blending
            row[x] = blendGray(row[x], cl, alpha);
        }
    }
}

class ColorDrawBuf : ColorDrawBufBase
{
    protected MallocBuf!uint _buf;

    /// Create ARGB8888 draw buf of specified width and height
    this(int width, int height)
    {
        resize(width, height);
    }
    /// Create copy of ColorDrawBuf
    this(ColorDrawBuf v)
    {
        this(v.width, v.height);
        if (auto len = _buf.length)
            _buf.ptr[0 .. len] = v._buf.ptr[0 .. len];
    }
    /// Create resized copy of ColorDrawBuf
    this(ColorDrawBuf v, int dx, int dy)
    {
        this(dx, dy);
        fill(0xFFFFFFFF);
        drawRescaled(Rect(0, 0, dx, dy), v, Rect(0, 0, v.width, v.height));
    }

    void invertAndPreMultiplyAlpha()
    {
        foreach (ref pixel; _buf[])
        {
            uint a = (pixel >> 24) & 0xFF;
            uint r = (pixel >> 16) & 0xFF;
            uint g = (pixel >> 8) & 0xFF;
            uint b = (pixel >> 0) & 0xFF;
            a ^= 0xFF;
            if (a > 0xFC)
            {
                r = ((r * a) >> 8) & 0xFF;
                g = ((g * a) >> 8) & 0xFF;
                b = ((b * a) >> 8) & 0xFF;
            }
            pixel = (a << 24) | (r << 16) | (g << 8) | (b << 0);
        }
    }

    void invertAlpha()
    {
        foreach (ref pixel; _buf[])
            pixel ^= 0xFF000000;
    }

    void invertByteOrder()
    {
        foreach (ref pixel; _buf[])
        {
            pixel = (pixel & 0xFF00FF00) | ((pixel & 0xFF0000) >> 16) | ((pixel & 0xFF) << 16);
        }
    }

    // for passing of image to OpenGL texture
    void invertAlphaAndByteOrder()
    {
        foreach (ref pixel; _buf[])
        {
            pixel = ((pixel & 0xFF00FF00) | ((pixel & 0xFF0000) >> 16) | ((pixel & 0xFF) << 16));
            pixel ^= 0xFF000000;
        }
    }

    override uint* scanLine(int y)
    {
        if (y >= 0 && y < _h)
            return _buf.ptr + _w * y;
        return null;
    }

    override void resize(int width, int height)
    {
        if (_w == width && _h == height)
            return;
        _w = width;
        _h = height;
        _buf.length = _w * _h;
        resetClipping();
    }

    override void fill(uint color)
    {
        if (hasClipping)
        {
            fillRect(_clipRect, color);
            return;
        }
        int len = _w * _h;
        uint* p = _buf.ptr;
        foreach (i; 0 .. len)
            p[i] = color;
    }

    /// NOT USED
    override DrawBuf transformColors(ref ColorTransform transform)
    {
        if (transform.empty)
            return this;
        bool skipFrame = hasNinePatch;
        ColorDrawBuf res = new ColorDrawBuf(_w, _h);
        if (hasNinePatch)
        {
            NinePatch* p = new NinePatch;
            *p = *_ninePatch;
            res.ninePatch = p;
        }
        foreach (int y; 0 .. _h)
        {
            uint* srcline = scanLine(y);
            uint* dstline = res.scanLine(y);
            bool allowTransformY = !skipFrame || (y != 0 && y != _h - 1);
            foreach (int x; 0 .. _w)
            {
                bool allowTransformX = !skipFrame || (x != 0 && x != _w - 1);
                if (!allowTransformX || !allowTransformY)
                    dstline[x] = srcline[x];
                else
                    dstline[x] = transform.transform(srcline[x]);
            }
        }
        return res;
    }

    /// Apply Gaussian blur to the image
    void blur(uint blurSize)
    {
        if (blurSize == 0)
            return; // trivial case

        // utility functions to get and set color
        float[4] get(uint[] buf, uint x, uint y)
        {
            uint c = buf[x + y * _w];
            float a = 255 - (c >> 24);
            float r = (c >> 16) & 0xFF;
            float g = (c >> 8) & 0xFF;
            float b = (c >> 0) & 0xFF;
            return [r, g, b, a];
        }

        void set(uint[] buf, uint x, uint y, float[4] c)
        {
            buf[x + y * _w] = makeRGBA(c[0], c[1], c[2], 255 - c[3]);
        }

        import std.algorithm : max, min;
        import std.math;

        // Gaussian function
        static float weight(in float x, in float sigma) pure nothrow
        {
            enum inv_sqrt_2pi = 1 / sqrt(2 * PI);
            return exp(-x ^^ 2 / (2 * sigma ^^ 2)) * inv_sqrt_2pi / sigma;
        }

        void blurOneDimension(uint[] bufIn, uint[] bufOut, uint blurSize, bool horizontally)
        {
            float sigma = blurSize > 2 ? blurSize / 3.0 : blurSize / 2.0;

            foreach (x; 0 .. _w)
            {
                foreach (y; 0 .. _h)
                {
                    float[4] c;
                    c[] = 0;

                    float sum = 0;
                    foreach (int i; 1 .. blurSize + 1)
                    {
                        float[4] c1 = get(bufIn, horizontally ? min(x + i, _w - 1) : x,
                                horizontally ? y : min(y + i, _h - 1));
                        float[4] c2 = get(bufIn, horizontally ? max(x - i, 0) : x, horizontally ? y : max(y - i, 0));
                        float w = weight(i, sigma);
                        c[] += (c1[] + c2[]) * w;
                        sum += 2 * w;
                    }
                    c[] += get(bufIn, x, y)[] * (1 - sum);
                    set(bufOut, x, y, c);
                }
            }
        }
        // intermediate buffer for image
        uint[] tmpbuf;
        tmpbuf.length = _buf.length;
        // do horizontal blur
        blurOneDimension(_buf[], tmpbuf, blurSize, true);
        // then do vertical blur
        blurOneDimension(tmpbuf, _buf[], blurSize, false);
    }
}

/// Experimental
DrawBuf makeTemporaryImage(uint width, uint height)
{
    return new ColorDrawBuf(width, height);
}

// line clipping algorithm from https://en.wikipedia.org/wiki/Cohen%E2%80%93Sutherland_algorithm
private alias OutCode = int;

private enum
{
    INSIDE = 0, // 0000
    LEFT = 1, // 0001
    RIGHT = 2, // 0010
    BOTTOM = 4, // 0100
    TOP = 8, // 1000
}

// Compute the bit code for a point (x, y) using the clip rectangle
// bounded diagonally by (xmin, ymin), and (xmax, ymax)

// ASSUME THAT xmax, xmin, ymax and ymin are global constants.

private OutCode ComputeOutCode(Rect clipRect, double x, double y)
{
    OutCode code;

    code = INSIDE; // initialised as being inside of clip window

    if (x < clipRect.left) // to the left of clip window
        code |= LEFT;
    else if (x > clipRect.right) // to the right of clip window
        code |= RIGHT;
    if (y < clipRect.top) // below the clip window
        code |= BOTTOM;
    else if (y > clipRect.bottom) // above the clip window
        code |= TOP;

    return code;
}

package bool clipLine(ref Rect clipRect, ref Point p1, ref Point p2)
{
    double x0 = p1.x;
    double y0 = p1.y;
    double x1 = p2.x;
    double y1 = p2.y;
    bool res = CohenSutherlandLineClipAndDraw(clipRect, x0, y0, x1, y1);
    if (res)
    {
        p1.x = cast(int)x0;
        p1.y = cast(int)y0;
        p2.x = cast(int)x1;
        p2.y = cast(int)y1;
    }
    return res;
}

// Cohen–Sutherland clipping algorithm clips a line from
// P0 = (x0, y0) to P1 = (x1, y1) against a rectangle with
// diagonal from (xmin, ymin) to (xmax, ymax).
private bool CohenSutherlandLineClipAndDraw(ref Rect clipRect, ref double x0, ref double y0, ref double x1, ref double y1)
{
    // compute outcodes for P0, P1, and whatever point lies outside the clip rectangle
    OutCode outcode0 = ComputeOutCode(clipRect, x0, y0);
    OutCode outcode1 = ComputeOutCode(clipRect, x1, y1);
    bool accept = false;

    while (true)
    {
        if (!(outcode0 | outcode1))
        { // Bitwise OR is 0. Trivially accept and get out of loop
            accept = true;
            break;
        }
        else if (outcode0 & outcode1)
        { // Bitwise AND is not 0. Trivially reject and get out of loop
            break;
        }
        else
        {
            // failed both tests, so calculate the line segment to clip
            // from an outside point to an intersection with clip edge
            double x, y;

            // At least one endpoint is outside the clip rectangle; pick it.
            OutCode outcodeOut = outcode0 ? outcode0 : outcode1;

            // Now find the intersection point;
            // use formulas y = y0 + slope * (x - x0), x = x0 + (1 / slope) * (y - y0)
            if (outcodeOut & TOP)
            { // point is above the clip rectangle
                x = x0 + (x1 - x0) * (clipRect.bottom - y0) / (y1 - y0);
                y = clipRect.bottom;
            }
            else if (outcodeOut & BOTTOM)
            { // point is below the clip rectangle
                x = x0 + (x1 - x0) * (clipRect.top - y0) / (y1 - y0);
                y = clipRect.top;
            }
            else if (outcodeOut & RIGHT)
            { // point is to the right of clip rectangle
                y = y0 + (y1 - y0) * (clipRect.right - x0) / (x1 - x0);
                x = clipRect.right;
            }
            else if (outcodeOut & LEFT)
            { // point is to the left of clip rectangle
                y = y0 + (y1 - y0) * (clipRect.left - x0) / (x1 - x0);
                x = clipRect.left;
            }

            // Now we move outside point to intersection point to clip
            // and get ready for next pass.
            if (outcodeOut == outcode0)
            {
                x0 = x;
                y0 = y;
                outcode0 = ComputeOutCode(clipRect, x0, y0);
            }
            else
            {
                x1 = x;
                y1 = y;
                outcode1 = ComputeOutCode(clipRect, x1, y1);
            }
        }
    }
    return accept;
}