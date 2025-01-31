/**
Linear algebra: vectors and matrices.

Copyright: Vadim Lopatin 2015-2016, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.linalg;

nothrow:

import std.math : cos, sin, sqrt, tan, isFinite, PI;
import std.string : format;
import beamui.core.math;

/// 2-4-dimensional vector
struct Vector(T, int N) if (2 <= N && N <= 4)
{
    nothrow:

    union
    {
        T[N] vec = 0;
        struct
        {
            T x;
            T y;
            static if (N >= 3)
                T z;
            static if (N == 4)
                T w;
        }
    }

    alias u = x;
    alias v = y;

    /// Vector dimension number
    enum int dimension = N;

    /// Returns a pointer to the first vector element
    const(T*) ptr() const { return vec.ptr; }

    /// Create with all components filled with specified value
    this(T v)
    {
        vec[] = v;
    }

    this(Args...)(Args values) if (2 <= Args.length && Args.length <= N)
    {
        static foreach (Arg; Args)
            static assert(is(Arg : T), "Arguments must be convertible to the base vector type");
        static foreach (i; 0 .. Args.length)
            vec[i] = values[i];
    }

    this(const ref T[N] v)
    {
        vec = v;
    }

    this(const T[] v)
    {
        vec = v[0 .. N];
    }

    static if (N == 4)
    {
        this(Vector!(T, 3) v)
        {
            vec[0 .. 3] = v.vec[];
            vec[3] = 1;
        }

        ref Vector opAssign(Vector!(T, 3) v)
        {
            vec[0 .. 3] = v.vec[];
            vec[3] = 1;
            return this;
        }
    }

    ref Vector opAssign(T[N] v)
    {
        vec = v;
        return this;
    }

    /// Fill all components of vector with specified value
    ref Vector clear(T v)
    {
        vec[] = v;
        return this;
    }

    static if (N == 2)
    {
        /// Returns vector rotated 90 degrees counter clockwise
        Vector rotated90ccw() const
        {
            return Vector(-y, x);
        }

        /// Returns vector rotated 90 degrees clockwise
        Vector rotated90cw() const
        {
            return Vector(y, -x);
        }
    }

    /// Returns vector with all components which are negative of components for this vector
    Vector opUnary(string op : "-")() const
    {
        Vector ret = this;
        ret.vec[] *= -1;
        return ret;
    }

    /// Perform operation with value to all components of vector
    ref Vector opOpAssign(string op)(T v)
        if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        mixin("vec[] "~op~"= v;");
        return this;
    }
    /// ditto
    Vector opBinary(string op)(T v) const
        if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        Vector ret = this;
        mixin("ret.vec[] "~op~"= v;");
        return ret;
    }

    /// Perform operation with another vector by component
    ref Vector opOpAssign(string op)(const Vector v)
        if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        mixin("vec[] "~op~"= v.vec[];");
        return this;
    }
    /// ditto
    Vector opBinary(string op)(const Vector v) const
        if (op == "+" || op == "-")
    {
        Vector ret = this;
        mixin("ret.vec[] "~op~"= v.vec[];");
        return ret;
    }

    /// Dot product (sum of by-component products of vector components)
    T opBinary(string op : "*")(const Vector v) const
    {
        return dotProduct(this, v);
    }

    /// Sum of squares of all vector components
    T magnitudeSquared() const
    {
        T ret = 0;
        static foreach (i; 0 .. N)
            ret += vec[i] * vec[i];
        return ret;
    }
    /// Length of vector
    T magnitude() const
    {
        static if (is(T == float) || is(T == double) || is(T == real))
            return sqrt(magnitudeSquared);
        else
            return cast(T)sqrt(cast(real)magnitudeSquared);
    }
    /// ditto
    alias length = magnitude;

    /// Normalize vector: make its length == 1
    void normalize()
    {
        this /= length;
    }
    /// Returns normalized copy of this vector
    Vector normalized() const
    {
        return this / length;
    }

    int opCmp(const ref Vector b) const
    {
        static foreach (i; 0 .. N)
        {
            if (vec[i] < b.vec[i])
                return -1;
            else if (vec[i] > b.vec[i])
                return 1;
        }
        return 0; // equal
    }

    string toString() const
    {
        try
        {
            static if (N == 2)
                return format("(%s, %s)", x, y);
            static if (N == 3)
                return format("(%s, %s, %s)", x, y, z);
            static if (N == 4)
                return format("(%s, %s, %s, %s)", x, y, z, w);
        }
        catch (Exception e)
        {
            return null;
        }
    }
}

/// Dot product (sum of by-component products of vector components)
T dotProduct(T, int N)(Vector!(T, N) a, Vector!(T, N) b)
{
    T ret = 0;
    static foreach (i; 0 .. N)
        ret += a.vec[i] * b.vec[i];
    return ret;
}
/// Cross product of two Vec2 is a scalar in Z axis
T crossProduct(T)(Vector!(T, 2) a, Vector!(T, 2) b)
{
    return a.x * b.y - a.y * b.x;
}
/// 3D cross product
Vector!(T, 3) crossProduct(T)(Vector!(T, 3) a, Vector!(T, 3) b)
{
    return Vector!(T, 3)(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

alias Vec2 = Vector!(float, 2);
alias Vec3 = Vector!(float, 3);
alias Vec4 = Vector!(float, 4);

alias Vec2d = Vector!(double, 2);
alias Vec3d = Vector!(double, 3);
alias Vec4d = Vector!(double, 4);

alias Vec2i = Vector!(int, 2);
alias Vec3i = Vector!(int, 3);
alias Vec4i = Vector!(int, 4);

/** Row-major 2x3 floating point matrix, used for 2D affine transformations. Zero by default.

    Multiplication and inversion are performed as 3x3 with implicit (0,0,1) last row.
*/
struct Mat2x3
{
    nothrow:

    float[3][2] store = [[0.0f, 0.0f, 0.0f], [0.0f, 0.0f, 0.0f]];

    /** Returns the pointer to the stored values array.

        Note: Values are stored in row-major order, so when passing it to OpenGL
        with `glUniform*` functions, you'll need to set `transpose` parameter to GL_TRUE.
    */
    const(float*) ptr() const { return store.ptr.ptr; }

    this(float diagonal)
    {
        store[0][0] = diagonal;
        store[1][1] = diagonal;
    }
    this(ref const float[6] array)
    {
        store = array;
    }
    this(const float[] array)
    {
        store = array[0 .. 6];
    }

    /// Identity matrix
    enum Mat2x3 identity = Mat2x3(1.0f);
    /// Reset this matrix to identity
    ref Mat2x3 setIdentity()
    {
        store[0][0] = 1.0f;
        store[0][1] = 0.0f;
        store[0][2] = 0.0f;
        store[1][0] = 0.0f;
        store[1][1] = 1.0f;
        store[1][2] = 0.0f;
        return this;
    }

    /// Add or subtract a matrix
    ref Mat2x3 opOpAssign(string op)(Mat2x3 mat) if (op == "+" || op == "-")
        in(isFinite(), msgNotFinite)
    {
        mixin("store[0] "~op~"= mat.store[0];");
        mixin("store[1] "~op~"= mat.store[1];");
        return this;
    }
    /// ditto
    Mat2x3 opBinary(string op)(Mat2x3 mat) const if (op == "+" || op == "-")
        in(isFinite(), msgNotFinite)
    {
        Mat2x3 ret = this;
        mixin("ret.store[0] "~op~"= mat.store[0];");
        mixin("ret.store[1] "~op~"= mat.store[1];");
        return ret;
    }
    /// Multiply this matrix by another one, as they were 3x3 with (0,0,1) last row
    ref Mat2x3 opOpAssign(string op: "*")(Mat2x3 mat)
        in(isFinite(), msgNotFinite)
    {
        const a00 = store[0][0];
        const a01 = store[0][1];
        const a10 = store[1][0];
        const a11 = store[1][1];
        store[0][0]  = a00 * mat.store[0][0] + a01 * mat.store[1][0];
        store[0][1]  = a00 * mat.store[0][1] + a01 * mat.store[1][1];
        store[0][2] += a00 * mat.store[0][2] + a01 * mat.store[1][2];
        store[1][0]  = a10 * mat.store[0][0] + a11 * mat.store[1][0];
        store[1][1]  = a10 * mat.store[0][1] + a11 * mat.store[1][1];
        store[1][2] += a10 * mat.store[0][2] + a11 * mat.store[1][2];
        return this;
    }
    /// ditto
    Mat2x3 opBinary(string op : "*")(Mat2x3 mat) const
        in(isFinite(), msgNotFinite)
    {
        Mat2x3 ret = void;
        ret.store[0][0] = store[0][0] * mat.store[0][0] + store[0][1] * mat.store[1][0];
        ret.store[0][1] = store[0][0] * mat.store[0][1] + store[0][1] * mat.store[1][1];
        ret.store[0][2] = store[0][0] * mat.store[0][2] + store[0][1] * mat.store[1][2] + store[0][2];
        ret.store[1][0] = store[1][0] * mat.store[0][0] + store[1][1] * mat.store[1][0];
        ret.store[1][1] = store[1][0] * mat.store[0][1] + store[1][1] * mat.store[1][1];
        ret.store[1][2] = store[1][0] * mat.store[0][2] + store[1][1] * mat.store[1][2] + store[1][2];
        return ret;
    }

    /// Transform a vector by this matrix
    Vec2 opBinary(string op : "*")(Vec2 vec) const
        out(v; .isFinite(v.x) && .isFinite(v.y), "Transformed vector is not finite")
    {
        return Vec2(
            store[0][0] * vec.x + store[0][1] * vec.y + store[0][2],
            store[1][0] * vec.x + store[1][1] * vec.y + store[1][2]);
    }

    bool opEquals()(auto ref const Mat2x3 m) const
    {
        return
            fequal6(store[0][0], m.store[0][0]) &&
            fequal6(store[0][1], m.store[0][1]) &&
            fequal6(store[0][2], m.store[0][2]) &&
            fequal6(store[1][0], m.store[1][0]) &&
            fequal6(store[1][1], m.store[1][1]) &&
            fequal6(store[1][2], m.store[1][2]);
    }

    /// Invert this transform. If matrix is not invertible, resets it to identity matrix
    ref Mat2x3 invert()
    {
        const float det = store[0][0] * store[1][1] - store[0][1] * store[1][0];
        if (fzero6(det))
        {
            return setIdentity();
        }
        else
        {
            const invdet = 1.0f / det;
            const a00 = store[0][0];
            const a01 = store[0][1];
            const a02 = store[0][2];
            const a10 = store[1][0];
            const a11 = store[1][1];
            const a12 = store[1][2];
            store[0][0] =  a11 * invdet;
            store[0][1] = -a01 * invdet;
            store[0][2] = (a01 * a12 - a02 * a11) * invdet;
            store[1][0] = -a10 * invdet;
            store[1][1] =  a00 * invdet;
            store[1][2] = (a10 * a02 - a00 * a12) * invdet;
            return this;
        }
    }
    /// Returns inverted matrix. If matrix is not invertible, returns identity matrix
    Mat2x3 inverted() const
    {
        Mat2x3 m = this;
        return m.invert();
    }

    /// Apply translation to this matrix
    ref Mat2x3 translate(Vec2 offset)
        in(isFinite(), msgNotFinite)
    {
        store[0][2] += store[0][0] * offset.x + store[0][1] * offset.y;
        store[1][2] += store[1][0] * offset.x + store[1][1] * offset.y;
        return this;
    }
    /// Make a translation matrix
    static Mat2x3 translation(Vec2 offset)
        out(m; m.isFinite(), msgNotFinite)
    {
        Mat2x3 m = identity;
        m.store[0][2] = offset.x;
        m.store[1][2] = offset.y;
        return m;
    }

    /// Apply rotation to this matrix
    ref Mat2x3 rotate(float radians)
        in(isFinite(), msgNotFinite)
    {
        const c = cos(radians);
        const s = sin(radians);
        const a00 = store[0][0];
        const a10 = store[1][0];
        store[0][0] =  a00 * c + store[0][1] * s;
        store[0][1] = -a00 * s + store[0][1] * c;
        store[1][0] =  a10 * c + store[1][1] * s;
        store[1][1] = -a10 * s + store[1][1] * c;
        return this;
    }
    /// Make a rotation matrix
    static Mat2x3 rotation(float radians)
        out(m; m.isFinite(), msgNotFinite)
    {
        Mat2x3 m;
        const c = cos(radians);
        const s = sin(radians);
        m.store[0][0] = c;
        m.store[0][1] = -s;
        m.store[1][0] = s;
        m.store[1][1] = c;
        return m;
    }

    /// Apply scaling to this matrix
    ref Mat2x3 scale(Vec2 factor)
        in(isFinite(), msgNotFinite)
    {
        store[0][0] *= factor.x;
        store[1][0] *= factor.x;
        store[0][1] *= factor.y;
        store[1][1] *= factor.y;
        return this;
    }
    /// Make a scaling matrix
    static Mat2x3 scaling(Vec2 factor)
        out(m; m.isFinite(), msgNotFinite)
    {
        Mat2x3 m;
        m.store[0][0] = factor.x;
        m.store[1][1] = factor.y;
        return m;
    }

    /// Apply skewing to this matrix
    ref Mat2x3 skew(Vec2 factor)
        in(isFinite(), msgNotFinite)
    {
        const a = tan(factor.x);
        const b = tan(factor.y);
        const a00 = store[0][0];
        const a10 = store[1][0];
        store[0][0] += b * store[0][1];
        store[0][1] += a * a00;
        store[1][0] += b * store[1][1];
        store[1][1] += a * a10;
        return this;
    }
    /// Make a skewing matrix
    static Mat2x3 skewing(Vec2 factor)
        out(m; m.isFinite(), msgNotFinite)
    {
        Mat2x3 m = identity;
        m.store[0][1] = tan(factor.x);
        m.store[1][0] = tan(factor.y);
        return m;
    }

    string toString() const
    {
        try
        {
            return format("[%s %s %s] [%s %s %s]",
                store[0][0], store[0][1], store[0][2],
                store[1][0], store[1][1], store[1][2]);
        }
        catch (Exception e)
        {
            return null;
        }
    }

    private bool isFinite() const
    {
        return .isFinite((this * Vec2(1, 1)).magnitudeSquared);
    }
    private static immutable msgNotFinite = "Transformation is not finite anymore";
}

struct mat4
{
    nothrow:

    float[16] m = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

    this(float v)
    {
        setDiagonal(v);
    }

    this(const float[16] v)
    {
        m[] = v[];
    }

    ref mat4 opAssign(const ref mat4 v)
    {
        m[] = v.m[];
        return this;
    }

    ref mat4 opAssign(const mat4 v)
    {
        m[] = v.m[];
        return this;
    }

    ref mat4 opAssign(const float[16] v)
    {
        m[] = v[];
        return this;
    }

    void setOrtho(float left, float right, float bottom, float top, float nearPlane, float farPlane)
    {
        // Bail out if the projection volume is zero-sized.
        if (left == right || bottom == top || nearPlane == farPlane)
            return;

        // Construct the projection.
        float width = right - left;
        float invheight = top - bottom;
        float clip = farPlane - nearPlane;
        m[0 * 4 + 0] = 2.0f / width;
        m[1 * 4 + 0] = 0.0f;
        m[2 * 4 + 0] = 0.0f;
        m[3 * 4 + 0] = -(left + right) / width;
        m[0 * 4 + 1] = 0.0f;
        m[1 * 4 + 1] = 2.0f / invheight;
        m[2 * 4 + 1] = 0.0f;
        m[3 * 4 + 1] = -(top + bottom) / invheight;
        m[0 * 4 + 2] = 0.0f;
        m[1 * 4 + 2] = 0.0f;
        m[2 * 4 + 2] = -2.0f / clip;
        m[3 * 4 + 2] = -(nearPlane + farPlane) / clip;
        m[0 * 4 + 3] = 0.0f;
        m[1 * 4 + 3] = 0.0f;
        m[2 * 4 + 3] = 0.0f;
        m[3 * 4 + 3] = 1.0f;
    }

    void setPerspective(float angle, float aspect, float nearPlane, float farPlane)
    {
        // Bail out if the projection volume is zero-sized.
        float radians = (angle / 2.0f) * PI / 180.0f;
        if (nearPlane == farPlane || aspect == 0.0f || radians < 0.0001f)
            return;
        float f = 1 / tan(radians);
        float d = 1 / (nearPlane - farPlane);

        // Construct the projection.
        m[0 * 4 + 0] = f / aspect;
        m[1 * 4 + 0] = 0.0f;
        m[2 * 4 + 0] = 0.0f;
        m[3 * 4 + 0] = 0.0f;

        m[0 * 4 + 1] = 0.0f;
        m[1 * 4 + 1] = f;
        m[2 * 4 + 1] = 0.0f;
        m[3 * 4 + 1] = 0.0f;

        m[0 * 4 + 2] = 0.0f;
        m[1 * 4 + 2] = 0.0f;
        m[2 * 4 + 2] = (nearPlane + farPlane) * d;
        m[3 * 4 + 2] = 2.0f * nearPlane * farPlane * d;

        m[0 * 4 + 3] = 0.0f;
        m[1 * 4 + 3] = 0.0f;
        m[2 * 4 + 3] = -1.0f;
        m[3 * 4 + 3] = 0.0f;
    }

    ref mat4 lookAt(const Vec3 eye, const Vec3 center, const Vec3 up)
    {
        Vec3 forward = (center - eye).normalized();
        Vec3 side = crossProduct(forward, up).normalized();
        Vec3 upVector = crossProduct(side, forward);

        mat4 m;
        m.setIdentity();
        m[0 * 4 + 0] = side.x;
        m[1 * 4 + 0] = side.y;
        m[2 * 4 + 0] = side.z;
        m[3 * 4 + 0] = 0.0f;
        m[0 * 4 + 1] = upVector.x;
        m[1 * 4 + 1] = upVector.y;
        m[2 * 4 + 1] = upVector.z;
        m[3 * 4 + 1] = 0.0f;
        m[0 * 4 + 2] = -forward.x;
        m[1 * 4 + 2] = -forward.y;
        m[2 * 4 + 2] = -forward.z;
        m[3 * 4 + 2] = 0.0f;
        m[0 * 4 + 3] = 0.0f;
        m[1 * 4 + 3] = 0.0f;
        m[2 * 4 + 3] = 0.0f;
        m[3 * 4 + 3] = 1.0f;

        this *= m;
        translate(-eye);
        return this;
    }

    /// Transpose matrix
    void transpose()
    {
        float[16] tmp = [m[0], m[4], m[8], m[12], m[1], m[5], m[9], m[13], m[2], m[6], m[10],
            m[14], m[3], m[7], m[11], m[15]];
        m = tmp;
    }

    mat4 invert() const
    {
        float a0 = m[0] * m[5] - m[1] * m[4];
        float a1 = m[0] * m[6] - m[2] * m[4];
        float a2 = m[0] * m[7] - m[3] * m[4];
        float a3 = m[1] * m[6] - m[2] * m[5];
        float a4 = m[1] * m[7] - m[3] * m[5];
        float a5 = m[2] * m[7] - m[3] * m[6];
        float b0 = m[8] * m[13] - m[9] * m[12];
        float b1 = m[8] * m[14] - m[10] * m[12];
        float b2 = m[8] * m[15] - m[11] * m[12];
        float b3 = m[9] * m[14] - m[10] * m[13];
        float b4 = m[9] * m[15] - m[11] * m[13];
        float b5 = m[10] * m[15] - m[11] * m[14];

        // Calculate the determinant.
        float det = a0 * b5 - a1 * b4 + a2 * b3 + a3 * b2 - a4 * b1 + a5 * b0;

        mat4 inverse;

        // Close to zero, can't invert.
        if (fzero6(det))
            return inverse;

        // Support the case where m == dst.
        inverse.m[0] = m[5] * b5 - m[6] * b4 + m[7] * b3;
        inverse.m[1] = -m[1] * b5 + m[2] * b4 - m[3] * b3;
        inverse.m[2] = m[13] * a5 - m[14] * a4 + m[15] * a3;
        inverse.m[3] = -m[9] * a5 + m[10] * a4 - m[11] * a3;

        inverse.m[4] = -m[4] * b5 + m[6] * b2 - m[7] * b1;
        inverse.m[5] = m[0] * b5 - m[2] * b2 + m[3] * b1;
        inverse.m[6] = -m[12] * a5 + m[14] * a2 - m[15] * a1;
        inverse.m[7] = m[8] * a5 - m[10] * a2 + m[11] * a1;

        inverse.m[8] = m[4] * b4 - m[5] * b2 + m[7] * b0;
        inverse.m[9] = -m[0] * b4 + m[1] * b2 - m[3] * b0;
        inverse.m[10] = m[12] * a4 - m[13] * a2 + m[15] * a0;
        inverse.m[11] = -m[8] * a4 + m[9] * a2 - m[11] * a0;

        inverse.m[12] = -m[4] * b3 + m[5] * b1 - m[6] * b0;
        inverse.m[13] = m[0] * b3 - m[1] * b1 + m[2] * b0;
        inverse.m[14] = -m[12] * a3 + m[13] * a1 - m[14] * a0;
        inverse.m[15] = m[8] * a3 - m[9] * a1 + m[10] * a0;

        float mul = 1.0f / det;
        inverse *= mul;
        return inverse;
    }

    ref mat4 setLookAt(const Vec3 eye, const Vec3 center, const Vec3 up)
    {
        setIdentity();
        lookAt(eye, center, up);
        return this;
    }

    ref mat4 translate(const Vec3 v)
    {
        m[3 * 4 + 0] += m[0 * 4 + 0] * v.x + m[1 * 4 + 0] * v.y + m[2 * 4 + 0] * v.z;
        m[3 * 4 + 1] += m[0 * 4 + 1] * v.x + m[1 * 4 + 1] * v.y + m[2 * 4 + 1] * v.z;
        m[3 * 4 + 2] += m[0 * 4 + 2] * v.x + m[1 * 4 + 2] * v.y + m[2 * 4 + 2] * v.z;
        m[3 * 4 + 3] += m[0 * 4 + 3] * v.x + m[1 * 4 + 3] * v.y + m[2 * 4 + 3] * v.z;
        return this;
    }

    ref mat4 translate(float x, float y, float z)
    {
        m[3 * 4 + 0] += m[0 * 4 + 0] * x + m[1 * 4 + 0] * y + m[2 * 4 + 0] * z;
        m[3 * 4 + 1] += m[0 * 4 + 1] * x + m[1 * 4 + 1] * y + m[2 * 4 + 1] * z;
        m[3 * 4 + 2] += m[0 * 4 + 2] * x + m[1 * 4 + 2] * y + m[2 * 4 + 2] * z;
        m[3 * 4 + 3] += m[0 * 4 + 3] * x + m[1 * 4 + 3] * y + m[2 * 4 + 3] * z;
        return this;
    }

    /// Perform operation with a scalar to all items of matrix
    void opOpAssign(string op)(float v)
        if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        mixin("m[] "~op~"= v;");
    }
    /// ditto
    mat4 opBinary(string op)(float v) const
        if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        mat4 ret = this;
        mixin("ret.m[] "~op~"= v;");
        return ret;
    }

    /// Multiply this matrix by another matrix
    mat4 opBinary(string op : "*")(const ref mat4 m2) const
    {
        return mul(this, m2);
    }
    /// ditto
    void opOpAssign(string op : "*")(const ref mat4 m2)
    {
        this = mul(this, m2);
    }

    /// Multiply two matrices
    static mat4 mul(const ref mat4 m1, const ref mat4 m2)
    {
        mat4 m;
        m.m[0 * 4 + 0] = m1.m[0 * 4 + 0] * m2.m[0 * 4 + 0] + m1.m[1 * 4 + 0] * m2.m[0 * 4 + 1] +
            m1.m[2 * 4 + 0] * m2.m[0 * 4 + 2] + m1.m[3 * 4 + 0] * m2.m[0 * 4 + 3];
        m.m[0 * 4 + 1] = m1.m[0 * 4 + 1] * m2.m[0 * 4 + 0] + m1.m[1 * 4 + 1] * m2.m[0 * 4 + 1] +
            m1.m[2 * 4 + 1] * m2.m[0 * 4 + 2] + m1.m[3 * 4 + 1] * m2.m[0 * 4 + 3];
        m.m[0 * 4 + 2] = m1.m[0 * 4 + 2] * m2.m[0 * 4 + 0] + m1.m[1 * 4 + 2] * m2.m[0 * 4 + 1] +
            m1.m[2 * 4 + 2] * m2.m[0 * 4 + 2] + m1.m[3 * 4 + 2] * m2.m[0 * 4 + 3];
        m.m[0 * 4 + 3] = m1.m[0 * 4 + 3] * m2.m[0 * 4 + 0] + m1.m[1 * 4 + 3] * m2.m[0 * 4 + 1] +
            m1.m[2 * 4 + 3] * m2.m[0 * 4 + 2] + m1.m[3 * 4 + 3] * m2.m[0 * 4 + 3];
        m.m[1 * 4 + 0] = m1.m[0 * 4 + 0] * m2.m[1 * 4 + 0] + m1.m[1 * 4 + 0] * m2.m[1 * 4 + 1] +
            m1.m[2 * 4 + 0] * m2.m[1 * 4 + 2] + m1.m[3 * 4 + 0] * m2.m[1 * 4 + 3];
        m.m[1 * 4 + 1] = m1.m[0 * 4 + 1] * m2.m[1 * 4 + 0] + m1.m[1 * 4 + 1] * m2.m[1 * 4 + 1] +
            m1.m[2 * 4 + 1] * m2.m[1 * 4 + 2] + m1.m[3 * 4 + 1] * m2.m[1 * 4 + 3];
        m.m[1 * 4 + 2] = m1.m[0 * 4 + 2] * m2.m[1 * 4 + 0] + m1.m[1 * 4 + 2] * m2.m[1 * 4 + 1] +
            m1.m[2 * 4 + 2] * m2.m[1 * 4 + 2] + m1.m[3 * 4 + 2] * m2.m[1 * 4 + 3];
        m.m[1 * 4 + 3] = m1.m[0 * 4 + 3] * m2.m[1 * 4 + 0] + m1.m[1 * 4 + 3] * m2.m[1 * 4 + 1] +
            m1.m[2 * 4 + 3] * m2.m[1 * 4 + 2] + m1.m[3 * 4 + 3] * m2.m[1 * 4 + 3];
        m.m[2 * 4 + 0] = m1.m[0 * 4 + 0] * m2.m[2 * 4 + 0] + m1.m[1 * 4 + 0] * m2.m[2 * 4 + 1] +
            m1.m[2 * 4 + 0] * m2.m[2 * 4 + 2] + m1.m[3 * 4 + 0] * m2.m[2 * 4 + 3];
        m.m[2 * 4 + 1] = m1.m[0 * 4 + 1] * m2.m[2 * 4 + 0] + m1.m[1 * 4 + 1] * m2.m[2 * 4 + 1] +
            m1.m[2 * 4 + 1] * m2.m[2 * 4 + 2] + m1.m[3 * 4 + 1] * m2.m[2 * 4 + 3];
        m.m[2 * 4 + 2] = m1.m[0 * 4 + 2] * m2.m[2 * 4 + 0] + m1.m[1 * 4 + 2] * m2.m[2 * 4 + 1] +
            m1.m[2 * 4 + 2] * m2.m[2 * 4 + 2] + m1.m[3 * 4 + 2] * m2.m[2 * 4 + 3];
        m.m[2 * 4 + 3] = m1.m[0 * 4 + 3] * m2.m[2 * 4 + 0] + m1.m[1 * 4 + 3] * m2.m[2 * 4 + 1] +
            m1.m[2 * 4 + 3] * m2.m[2 * 4 + 2] + m1.m[3 * 4 + 3] * m2.m[2 * 4 + 3];
        m.m[3 * 4 + 0] = m1.m[0 * 4 + 0] * m2.m[3 * 4 + 0] + m1.m[1 * 4 + 0] * m2.m[3 * 4 + 1] +
            m1.m[2 * 4 + 0] * m2.m[3 * 4 + 2] + m1.m[3 * 4 + 0] * m2.m[3 * 4 + 3];
        m.m[3 * 4 + 1] = m1.m[0 * 4 + 1] * m2.m[3 * 4 + 0] + m1.m[1 * 4 + 1] * m2.m[3 * 4 + 1] +
            m1.m[2 * 4 + 1] * m2.m[3 * 4 + 2] + m1.m[3 * 4 + 1] * m2.m[3 * 4 + 3];
        m.m[3 * 4 + 2] = m1.m[0 * 4 + 2] * m2.m[3 * 4 + 0] + m1.m[1 * 4 + 2] * m2.m[3 * 4 + 1] +
            m1.m[2 * 4 + 2] * m2.m[3 * 4 + 2] + m1.m[3 * 4 + 2] * m2.m[3 * 4 + 3];
        m.m[3 * 4 + 3] = m1.m[0 * 4 + 3] * m2.m[3 * 4 + 0] + m1.m[1 * 4 + 3] * m2.m[3 * 4 + 1] +
            m1.m[2 * 4 + 3] * m2.m[3 * 4 + 2] + m1.m[3 * 4 + 3] * m2.m[3 * 4 + 3];
        return m;
    }

    /// Multiply matrix by Vec3
    Vec3 opBinary(string op : "*")(const Vec3 v) const
    {
        float x = v.x * m[0 * 4 + 0] + v.y * m[1 * 4 + 0] + v.z * m[2 * 4 + 0] + m[3 * 4 + 0];
        float y = v.x * m[0 * 4 + 1] + v.y * m[1 * 4 + 1] + v.z * m[2 * 4 + 1] + m[3 * 4 + 1];
        float z = v.x * m[0 * 4 + 2] + v.y * m[1 * 4 + 2] + v.z * m[2 * 4 + 2] + m[3 * 4 + 2];
        float w = v.x * m[0 * 4 + 3] + v.y * m[1 * 4 + 3] + v.z * m[2 * 4 + 3] + m[3 * 4 + 3];
        if (w == 1.0f)
            return Vec3(x, y, z);
        else
            return Vec3(x / w, y / w, z / w);
    }
    /// ditto
    Vec3 opBinaryRight(string op : "*")(const Vec3 v) const
    {
        float x = v.x * m[0 * 4 + 0] + v.y * m[0 * 4 + 1] + v.z * m[0 * 4 + 2] + m[0 * 4 + 3];
        float y = v.x * m[1 * 4 + 0] + v.y * m[1 * 4 + 1] + v.z * m[1 * 4 + 2] + m[1 * 4 + 3];
        float z = v.x * m[2 * 4 + 0] + v.y * m[2 * 4 + 1] + v.z * m[2 * 4 + 2] + m[2 * 4 + 3];
        float w = v.x * m[3 * 4 + 0] + v.y * m[3 * 4 + 1] + v.z * m[3 * 4 + 2] + m[3 * 4 + 3];
        if (w == 1.0f)
            return Vec3(x, y, z);
        else
            return Vec3(x / w, y / w, z / w);
    }

    /// Multiply matrix by Vec4
    Vec4 opBinary(string op : "*")(const Vec4 v) const
    {
        float x = v.x * m[0 * 4 + 0] + v.y * m[1 * 4 + 0] + v.z * m[2 * 4 + 0] + v.w * m[3 * 4 + 0];
        float y = v.x * m[0 * 4 + 1] + v.y * m[1 * 4 + 1] + v.z * m[2 * 4 + 1] + v.w * m[3 * 4 + 1];
        float z = v.x * m[0 * 4 + 2] + v.y * m[1 * 4 + 2] + v.z * m[2 * 4 + 2] + v.w * m[3 * 4 + 2];
        float w = v.x * m[0 * 4 + 3] + v.y * m[1 * 4 + 3] + v.z * m[2 * 4 + 3] + v.w * m[3 * 4 + 3];
        return Vec4(x, y, z, w);
    }
    /// ditto
    Vec4 opBinaryRight(string op : "*")(const Vec4 v) const
    {
        float x = v.x * m[0 * 4 + 0] + v.y * m[0 * 4 + 1] + v.z * m[0 * 4 + 2] + v.w * m[0 * 4 + 3];
        float y = v.x * m[1 * 4 + 0] + v.y * m[1 * 4 + 1] + v.z * m[1 * 4 + 2] + v.w * m[1 * 4 + 3];
        float z = v.x * m[2 * 4 + 0] + v.y * m[2 * 4 + 1] + v.z * m[2 * 4 + 2] + v.w * m[2 * 4 + 3];
        float w = v.x * m[3 * 4 + 0] + v.y * m[3 * 4 + 1] + v.z * m[3 * 4 + 2] + v.w * m[3 * 4 + 3];
        return Vec4(x, y, z, w);
    }

    /// 2d index by row, col
    ref float opIndex(int y, int x)
    {
        return m[y * 4 + x];
    }

    /// 2d index by row, col
    float opIndex(int y, int x) const
    {
        return m[y * 4 + x];
    }

    /// Scalar index by rows then (y*4 + x)
    ref float opIndex(int index)
    {
        return m[index];
    }

    /// Scalar index by rows then (y*4 + x)
    float opIndex(int index) const
    {
        return m[index];
    }

    /// Set to identity: fill all items of matrix with zero except main diagonal items which will be assigned to 1.0f
    ref mat4 setIdentity()
    {
        this = mat4.init;
        return this;
    }
    /// Set to diagonal: fill all items of matrix with zero except main diagonal items which will be assigned to v
    ref mat4 setDiagonal(float v)
    {
        foreach (x; 0 .. 4)
            foreach (y; 0 .. 4)
                m[y * 4 + x] = (x == y) ? v : 0;
        return this;
    }
    /// Fill all items of matrix with specified value
    ref mat4 fill(float v)
    {
        m[] = v;
        return this;
    }
    /// Fill all items of matrix with zero
    ref mat4 setZero()
    {
        m[] = 0;
        return this;
    }
    /// Creates identity matrix
    static mat4 identity()
    {
        return mat4.init;
    }
    /// Creates zero matrix
    static mat4 zero()
    {
        mat4 ret = void;
        ret.m[] = 0;
        return ret;
    }

    /// Inplace rotate around Z axis
    ref mat4 rotatez(float angle)
    {
        return rotate(angle, 0, 0, 1);
    }

    /// Inplace rotate around X axis
    ref mat4 rotatex(float angle)
    {
        return rotate(angle, 1, 0, 0);
    }

    /// Inplace rotate around Y axis
    ref mat4 rotatey(float angle)
    {
        return rotate(angle, 0, 1, 0);
    }

    ref mat4 rotate(float angle, const Vec3 axis)
    {
        return rotate(angle, axis.x, axis.y, axis.z);
    }

    ref mat4 rotate(float angle, float x, float y, float z)
    {
        if (angle == 0.0f)
            return this;
        mat4 m;
        float c, s, ic;
        if (angle == 90.0f || angle == -270.0f)
        {
            s = 1.0f;
            c = 0.0f;
        }
        else if (angle == -90.0f || angle == 270.0f)
        {
            s = -1.0f;
            c = 0.0f;
        }
        else if (angle == 180.0f || angle == -180.0f)
        {
            s = 0.0f;
            c = -1.0f;
        }
        else
        {
            float a = angle * PI / 180.0f;
            c = cos(a);
            s = sin(a);
        }
        bool quick = false;
        if (x == 0.0f)
        {
            if (y == 0.0f)
            {
                if (z != 0.0f)
                {
                    // Rotate around the Z axis.
                    m.setIdentity();
                    m.m[0 * 4 + 0] = c;
                    m.m[1 * 4 + 1] = c;
                    if (z < 0.0f)
                    {
                        m.m[1 * 4 + 0] = s;
                        m.m[0 * 4 + 1] = -s;
                    }
                    else
                    {
                        m.m[1 * 4 + 0] = -s;
                        m.m[0 * 4 + 1] = s;
                    }
                    quick = true;
                }
            }
            else if (z == 0.0f)
            {
                // Rotate around the Y axis.
                m.setIdentity();
                m.m[0 * 4 + 0] = c;
                m.m[2 * 4 + 2] = c;
                if (y < 0.0f)
                {
                    m.m[2 * 4 + 0] = -s;
                    m.m[0 * 4 + 2] = s;
                }
                else
                {
                    m.m[2 * 4 + 0] = s;
                    m.m[0 * 4 + 2] = -s;
                }
                quick = true;
            }
        }
        else if (y == 0.0f && z == 0.0f)
        {
            // Rotate around the X axis.
            m.setIdentity();
            m.m[1 * 4 + 1] = c;
            m.m[2 * 4 + 2] = c;
            if (x < 0.0f)
            {
                m.m[2 * 4 + 1] = s;
                m.m[1 * 4 + 2] = -s;
            }
            else
            {
                m.m[2 * 4 + 1] = -s;
                m.m[1 * 4 + 2] = s;
            }
            quick = true;
        }
        if (!quick)
        {
            float len = x * x + y * y + z * z;
            if (!fzero6(len - 1.0f) && !fzero6(len))
            {
                len = sqrt(len);
                x /= len;
                y /= len;
                z /= len;
            }
            ic = 1.0f - c;
            m.m[0 * 4 + 0] = x * x * ic + c;
            m.m[1 * 4 + 0] = x * y * ic - z * s;
            m.m[2 * 4 + 0] = x * z * ic + y * s;
            m.m[3 * 4 + 0] = 0.0f;
            m.m[0 * 4 + 1] = y * x * ic + z * s;
            m.m[1 * 4 + 1] = y * y * ic + c;
            m.m[2 * 4 + 1] = y * z * ic - x * s;
            m.m[3 * 4 + 1] = 0.0f;
            m.m[0 * 4 + 2] = x * z * ic - y * s;
            m.m[1 * 4 + 2] = y * z * ic + x * s;
            m.m[2 * 4 + 2] = z * z * ic + c;
            m.m[3 * 4 + 2] = 0.0f;
            m.m[0 * 4 + 3] = 0.0f;
            m.m[1 * 4 + 3] = 0.0f;
            m.m[2 * 4 + 3] = 0.0f;
            m.m[3 * 4 + 3] = 1.0f;
        }
        this *= m;
        return this;
    }

    ref mat4 rotateX(float angle)
    {
        return rotate(angle, 1, 0, 0);
    }

    ref mat4 rotateY(float angle)
    {
        return rotate(angle, 0, 1, 0);
    }

    ref mat4 rotateZ(float angle)
    {
        return rotate(angle, 0, 0, 1);
    }

    ref mat4 scale(float x, float y, float z)
    {
        m[0 * 4 + 0] *= x;
        m[0 * 4 + 1] *= x;
        m[0 * 4 + 2] *= x;
        m[0 * 4 + 3] *= x;
        m[1 * 4 + 0] *= y;
        m[1 * 4 + 1] *= y;
        m[1 * 4 + 2] *= y;
        m[1 * 4 + 3] *= y;
        m[2 * 4 + 0] *= z;
        m[2 * 4 + 1] *= z;
        m[2 * 4 + 2] *= z;
        m[2 * 4 + 3] *= z;
        return this;
    }

    ref mat4 scale(float v)
    {
        m[0 * 4 + 0] *= v;
        m[0 * 4 + 1] *= v;
        m[0 * 4 + 2] *= v;
        m[0 * 4 + 3] *= v;
        m[1 * 4 + 0] *= v;
        m[1 * 4 + 1] *= v;
        m[1 * 4 + 2] *= v;
        m[1 * 4 + 3] *= v;
        m[2 * 4 + 0] *= v;
        m[2 * 4 + 1] *= v;
        m[2 * 4 + 2] *= v;
        m[2 * 4 + 3] *= v;
        return this;
    }

    ref mat4 scale(const Vec3 v)
    {
        m[0 * 4 + 0] *= v.x;
        m[0 * 4 + 1] *= v.x;
        m[0 * 4 + 2] *= v.x;
        m[0 * 4 + 3] *= v.x;
        m[1 * 4 + 0] *= v.y;
        m[1 * 4 + 1] *= v.y;
        m[1 * 4 + 2] *= v.y;
        m[1 * 4 + 3] *= v.y;
        m[2 * 4 + 0] *= v.z;
        m[2 * 4 + 1] *= v.z;
        m[2 * 4 + 2] *= v.z;
        m[2 * 4 + 3] *= v.z;
        return this;
    }

    static mat4 translation(float x, float y, float z)
    {
        // TODO
        mat4 res = 1;
        return res;
    }

    /// Decomposes the scale, rotation and translation components of this matrix
    bool decompose(Vec3* scale, Vec4* rotation, Vec3* translation) const
    {
        if (translation)
        {
            // Extract the translation.
            translation.x = m[12];
            translation.y = m[13];
            translation.z = m[14];
        }

        // Nothing left to do.
        if (!scale && !rotation)
            return true;

        // Extract the scale.
        // This is simply the length of each axis (row/column) in the matrix.
        Vec3 xaxis = Vec3(m[0], m[1], m[2]);
        float scaleX = xaxis.length;

        Vec3 yaxis = Vec3(m[4], m[5], m[6]);
        float scaleY = yaxis.length;

        Vec3 zaxis = Vec3(m[8], m[9], m[10]);
        float scaleZ = zaxis.length;

        // Determine if we have a negative scale (true if determinant is less than zero).
        // In this case, we simply negate a single axis of the scale.
        float det = determinant();
        if (det < 0)
            scaleZ = -scaleZ;

        if (scale)
        {
            scale.x = scaleX;
            scale.y = scaleY;
            scale.z = scaleZ;
        }

        // Nothing left to do.
        if (!rotation)
            return true;

        //// Scale too close to zero, can't decompose rotation.
        //if (scaleX < MATH_TOLERANCE || scaleY < MATH_TOLERANCE || fabs(scaleZ) < MATH_TOLERANCE)
        //    return false;
        // TODO: support rotation
        return false;
    }

    float determinant() const
    {
        float a0 = m[0] * m[5] - m[1] * m[4];
        float a1 = m[0] * m[6] - m[2] * m[4];
        float a2 = m[0] * m[7] - m[3] * m[4];
        float a3 = m[1] * m[6] - m[2] * m[5];
        float a4 = m[1] * m[7] - m[3] * m[5];
        float a5 = m[2] * m[7] - m[3] * m[6];
        float b0 = m[8] * m[13] - m[9] * m[12];
        float b1 = m[8] * m[14] - m[10] * m[12];
        float b2 = m[8] * m[15] - m[11] * m[12];
        float b3 = m[9] * m[14] - m[10] * m[13];
        float b4 = m[9] * m[15] - m[11] * m[13];
        float b5 = m[10] * m[15] - m[11] * m[14];
        // calculate the determinant
        return a0 * b5 - a1 * b4 + a2 * b3 + a3 * b2 - a4 * b1 + a5 * b0;
    }

    Vec3 forwardVector() const
    {
        return Vec3(-m[8], -m[9], -m[10]);
    }

    Vec3 backVector() const
    {
        return Vec3(m[8], m[9], m[10]);
    }

    void transformVector(ref Vec3 v) const
    {
        transformVector(v.x, v.y, v.z, 0, v);
    }

    void transformPoint(ref Vec3 v) const
    {
        transformVector(v.x, v.y, v.z, 1, v);
    }

    void transformVector(float x, float y, float z, float w, ref Vec3 dst) const
    {
        dst.x = x * m[0] + y * m[4] + z * m[8] + w * m[12];
        dst.y = x * m[1] + y * m[5] + z * m[9] + w * m[13];
        dst.z = x * m[2] + y * m[6] + z * m[10] + w * m[14];
    }
}

/// Calculate normal for triangle
Vec3 triangleNormal(Vec3 p1, Vec3 p2, Vec3 p3)
{
    return crossProduct(p2 - p1, p3 - p2).normalized();
}
/// ditto
Vec3 triangleNormal(ref float[3] p1, ref float[3] p2, ref float[3] p3)
{
    return crossProduct(Vec3(p2) - Vec3(p1), Vec3(p3) - Vec3(p2)).normalized();
}

/** Find intersection point for two vectors with start points `p1`, `p2` and normalized directions `dir1`, `dir2`.

    Returns `p1` if vectors are parallel.
*/
Vec2 intersectVectors(Vec2 p1, Vec2 dir1, Vec2 p2, Vec2 dir2)
{
    /*
    L1 = P1 + a * V1
    L2 = P2 + b * V2
    P1 + a * V1 = P2 + b * V2
    a * V1 = (P2 - P1) + b * V2
    a * (V1 x V2) = (P2 - P1) x V2
    a = ((P2 - P1) x V2) / (V1 x V2)
    return P1 + a * V1
    */
    const float d1 = crossProduct(p2 - p1, dir2);
    const float d2 = crossProduct(dir1, dir2);
    // a * d2 = d1
    if (!fzero2(d2))
        return p1 + dir1 * d1 / d2;
    else
        return p1; // parallel
}

//===============================================================
// Tests

unittest
{
    Vec3 a, b, c;
    a.clear(5);
    b.clear(2);
    float d = a * b;
    auto r1 = a + b;
    auto r2 = a - b;
    c = a;
    c += b;
    c = a;
    c -= b;
    c = a;
    c *= b;
    c = a;
    c /= b;
    c += 0.3f;
    c -= 0.3f;
    c *= 0.3f;
    c /= 0.3f;
    a.x += 0.5f;
    a.y += 0.5f;
    a.z += 0.5f;
    auto v = b.vec;
    a = [0.1f, 0.2f, 0.3f];
    a.normalize();
    c = b.normalized;
}

unittest
{
    Vec4 a, b, c;
    a.clear(5);
    b.clear(2);
    float d = a * b;
    auto r1 = a + b;
    auto r2 = a - b;
    c = a;
    c += b;
    c = a;
    c -= b;
    c = a;
    c *= b;
    c = a;
    c /= b;
    c += 0.3f;
    c -= 0.3f;
    c *= 0.3f;
    c /= 0.3f;
    a.x += 0.5f;
    a.y += 0.5f;
    a.z += 0.5f;
    auto v = b.vec;
    a = [0.1f, 0.2f, 0.3f, 0.4f];
    a.normalize();
    c = b.normalized;
}

unittest
{
    const a = Vec2(10, 8);
    const b = Vec2(-5, -4);
    const c = Vec2(5, 5);
    const z = Mat2x3.init;
    const i = Mat2x3.identity;
    const t = Mat2x3.translation(Vec2(1, -1));
    const r = Mat2x3.rotation(PI / 3);
    const s = Mat2x3.scaling(Vec2(2, 3));
    const za = z * a;
    const ib = i * b;
    const ta = t * a;
    const tb = t * b;
    const rc = r * c;
    const sa = s * a;
    const sb = s * b;
    assert(fequal6(za.x,  0) && fequal6(za.y,  0));
    assert(fequal6(ib.x, -5) && fequal6(ib.y, -4));
    assert(fequal6(ta.x, 11) && fequal6(ta.y,  7));
    assert(fequal6(tb.x, -4) && fequal6(tb.y, -5));
    assert(fequal2(rc.x, -1.83) && fequal2(rc.y, 6.83));
    assert(fequal6(sa.x,  20) && fequal6(sa.y,  24));
    assert(fequal6(sb.x, -10) && fequal6(sb.y, -12));

    const m1 = t * r * s;
    const m2 = Mat2x3.identity.translate(Vec2(1, -1)).rotate(PI / 3).scale(Vec2(2, 3));
    const d1 = m1 * Vec2(15, 10);
    const d2 = m2 * Vec2(15, 10);
    assert(fequal2(d1.x, -9.98) && fequal2(d1.y, 39.98));
    assert(fequal6(d1.x, d2.x) && fequal6(d1.y, d2.y));

    assert(i * i.inverted == Mat2x3.identity);
    assert(t * t.inverted == Mat2x3.identity);
    assert(r * r.inverted == Mat2x3.identity);
    assert(s * s.inverted == Mat2x3.identity);
    assert(m1 * m1.inverted == Mat2x3.identity);
    assert(m2 * m2.inverted == Mat2x3.identity);
}

unittest
{
    mat4 m;
    m.setIdentity();
    m = [1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f, 7.0f, 8.0f, 9.0f, 10.0f, 11.0f, 12.0f, 13.0f, 14.0f, 15.0f, 16.0f];
    float r;
    r = m[1, 3];
    m[2, 1] = 0.0f;
    m += 1;
    m -= 2;
    m *= 3;
    m /= 3;
    m.translate(Vec3(2, 3, 4));
    m.translate(5, 6, 7);
    m.lookAt(Vec3(5, 5, 5), Vec3(0, 0, 0), Vec3(-1, 1, 1));
    m.setLookAt(Vec3(5, 5, 5), Vec3(0, 0, 0), Vec3(-1, 1, 1));
    m.scale(2, 3, 4);
    m.scale(Vec3(2, 3, 4));

    Vec3 vv1 = Vec3(1, 2, 3);
    auto p1 = m * vv1;
    Vec3 vv2 = Vec3(3, 4, 5);
    auto p2 = vv2 * m;
    auto p3 = Vec4(1, 2, 3, 4) * m;
    auto p4 = m * Vec4(1, 2, 3, 4);

    m.rotate(30, 1, 1, 1);
    m.rotateX(10);
    m.rotateY(10);
    m.rotateZ(10);
}

//===============================================================

// this form can be used within shaders
/// Cubic bezier curve
Vec2 bezierCubic(const Vec2[] cp, float t)
in
{
    assert(cp.length > 3);
}
do
{
    // control points
    auto p0 = cp[0];
    auto p1 = cp[1];
    auto p2 = cp[2];
    auto p3 = cp[3];

    float u1 = (1.0 - t);
    float u2 = t * t;
    // the polynomials
    float b3 = u2 * t;
    float b2 = 3.0 * u2 * u1;
    float b1 = 3.0 * t * u1 * u1;
    float b0 = u1 * u1 * u1;
    // cubic bezier interpolation
    Vec2 p = p0 * b0 + p1 * b1 + p2 * b2 + p3 * b3;
    return p;
}

/// Quadratic bezier curve (not tested)
Vec2 bezierQuadratic(const Vec2[] cp, float t)
in
{
    assert(cp.length > 2);
}
do
{
    auto p0 = cp[0];
    auto p1 = cp[1];
    auto p2 = cp[2];

    float u1 = (1.0 - t);
    float u2 = u1 * u1;

    float b2 = t * t;
    float b1 = 2.0 * u1 * t;
    float b0 = u2;

    Vec2 p = p0 * b0 + p1 * b1 + p2 * b2;
    return p;
}

/// Cubic bezier (first) derivative
Vec2 bezierCubicDerivative(const Vec2[] cp, float t)
in
{
    assert(cp.length > 3);
}
do
{
    auto p0 = cp[0];
    auto p1 = cp[1];
    auto p2 = cp[2];
    auto p3 = cp[3];

    float u1 = (1.0 - t);
    float u2 = t * t;
    float u3 = 6 * (u1) * t;
    float d0 = 3 * u1 * u1;
    // -3*P0*(1-t)^2 + P1*(3*(1-t)^2 - 6*(1-t)*t) + P2*(6*(1-t)*t - 3*t^2) + 3*P3*t^2
    Vec2 d = p0 * (-d0) + p1 * (d0 - u3) + p2 * (u3 - 3 * u2) + (p3 * 3) * u2;
    return d;
}

/// Quadratic bezier (first) derivative
Vec2 bezierQuadraticDerivative(const Vec2[] cp, float t)
in
{
    assert(cp.length > 2);
}
do
{
    auto p0 = cp[0];
    auto p1 = cp[1];
    auto p2 = cp[2];

    float u1 = (1.0 - t);
    // -2*(1-t)*(p1-p0) + 2*t*(p2-p1);
    Vec2 d = (p0 - p1) * -2 * u1 + (p2 - p1) * 2 * t;
    return d;
}

/// Evaluates cubic bezier direction(tangent) at point t
Vec2 bezierCubicDirection(const Vec2[] cp, float t)
{
    auto d = bezierCubicDerivative(cp, t);
    d.normalize();
    return Vec2(tan(d.x), tan(d.y));
}

/// Evaluates quadratic bezier direction(tangent) at point t
Vec2 bezierQuadraticDirection(const Vec2[] cp, float t)
{
    auto d = bezierQuadraticDerivative(cp, t);
    d.normalize();
    return Vec2(tan(d.x), tan(d.y));
}

/// Templated version of bezier flatten curve function, allocates temporary buffer
Vec2[] flattenBezier(alias BezierFunc)(const Vec2[] cp, int segmentCountInclusive)
        if (is(typeof(BezierFunc) == function))
{
    if (segmentCountInclusive < 2)
        return Vec2[].init;
    Vec2[] coords = new Vec2[segmentCountInclusive + 1];
    flattenBezier!BezierFunc(cp, segmentCountInclusive, coords);
    return coords;
}

/// Flatten bezier curve function, writes to provided buffer instead of allocation
void flattenBezier(alias BezierFunc)(const Vec2[] cp, int segmentCountInclusive, Vec2[] outSegments)
        if (is(typeof(BezierFunc) == function))
{
    if (segmentCountInclusive < 2)
        return;
    float step = 1f / segmentCountInclusive;
    outSegments[0] = BezierFunc(cp, 0);
    foreach (i; 1 .. segmentCountInclusive)
    {
        outSegments[i] = BezierFunc(cp, i * step);
    }
    outSegments[segmentCountInclusive] = BezierFunc(cp, 1f);
}

/// Flattens cubic bezier curve, returns Vec2[segmentCount+1] array or empty array if <1 segments
Vec2[] flattenBezierCubic(const Vec2[] cp, int segmentCount)
{
    return flattenBezier!bezierCubic(cp, segmentCount);
}

/// Flattens quadratic bezier curve, returns Vec2[segmentCount+1] array or empty array if <1 segments
Vec2[] flattenBezierQuadratic(const Vec2[] cp, int segmentCount)
{
    return flattenBezier!bezierQuadratic(cp, segmentCount);
}

/// Calculates normal vector at point t using direction
Vec2 bezierCubicNormal(const Vec2[] cp, float t)
{
    auto d = bezierCubicDirection(cp, t);
    return d.rotated90ccw;
}

/// Calculates normal vector at point t using direction
Vec2 bezierQuadraticNormal(const Vec2[] cp, float t)
{
    auto d = bezierQuadraticDerivative(cp, t);
    return d.rotated90ccw;
}
