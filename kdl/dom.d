module kdl.dom;

/++
 + kdl.dom
 + 
 + Authors: Justin Stephens
 + Copyright: 2023 Justin Stephens
 + License: MIT
 +/

import std.array : appender, Appender;
import kdl.parse;
import kdl.util;

struct Value
{
    // todo: switch to Algebraic
    union InnerUnion
    {
        string s;
        BasedNumber bn;
        DecimalNumber dn;
        bool b;
    }

    enum Type
    {
        Null = "",
        String = "s",
        BasedNumber = "bn",
        DecimalNumber = "dn",
        Bool = "b"
    }

    InnerUnion inner;
    Type type;
    string typeHint;

    this(Keyword kw)
    {
        switch (kw)
        {
        case Keyword.True:
            inner.b = true;
            type = Type.Bool;
            break;
        case Keyword.False:
            inner.b = false;
            type = Type.Bool;
            break;
        case Keyword.Null:
            type = Type.Null;
            break;
        default:
            assert(0);
        }
    }

    this(BasedNumber num)
    {
        inner.bn = num;
        type = Type.BasedNumber;
    }

    this(DecimalNumber num)
    {
        inner.dn = num;
        type = Type.DecimalNumber;
    }

    this(string str)
    {
        inner.s = str;
        type = Type.String;
    }

    string toString() const pure
    {
        auto str = appender!string();
        buildString(str);
        return str[];
    }

    void buildString(Appender!string str) const pure
    {
        import std.conv : to;
        import std.string : format;
        import std.uni : byCodePoint, CodepointSet;

        if (typeHint.length > 0)
        {
            str.put("(");
            auto t = classifyIdentifier(typeHint);
            if (t == IdentifierType.Bare)
                str.put(typeHint);
            else if (t == IdentifierType.String)
            {
                str.put('"');
                str.writeEscaped(typeHint);
                str.put('"');
            }
            str.put(")");
        }

        if (type == Type.Null)
        {
            str.put("null");
            return;
        }
        if (type == Type.BasedNumber)
        {
            str.put(to!string(inner.bn.value));
            return;
        }
        if (type == Type.DecimalNumber)
        {
            import std.math : ceil;
            import std.math.exponential : log10;
            import std.range : repeat;

            str.put(to!string(inner.dn.integral));

            if (inner.dn.fractionalDigits > 0)
            {
                auto fracDigits = 0;
                for (ulong i = inner.dn.fractional; i > 0; i /= 10)
                    fracDigits++;
                str.put(repeat(' ', inner.dn.fractionalDigits - fracDigits));
            }

            if (inner.dn.exponent > 0)
            {
                str.put("e");
                if (inner.dn.exponentSign == false)
                    str.put("-");
                str.put(to!string(inner.dn.exponent));
            }

            return;
        }
        // todo: the below causes linker errors?
        // if (type == Type.Real)
        // {
        //     str.put(format("%f", inner.re));
        //     return;
        // }
        if (type == Type.Bool)
        {
            str.put(to!string(inner.b));
            return;
        }
        if (type == Type.String)
        {
            str.put('"');
            str.writeEscaped(inner.s);
            str.put('"');
        }
    }
}

struct Node
{
    Node* parent;
    string typeHint;
    string name;
    Value[string] properties;
    Value[] values;
    Node*[] children;

    this(string name)
    {
        this.name = name;
    }

    Node* addChild()
    {
        auto c = new Node();
        c.parent = &this;
        children ~= c;
        return c;
    }

    string toString() const pure
    {
        auto a = appender!string;
        this.buildString(a);
        return a[];
    }

    void buildString(ref Appender!string str, int ind = -1) const pure
    {
        import std.range : chain;

        void indent(int x = ind)
        {
            for (auto i = x; i > 0; i--)
                str.put("    ");
        }

        if (ind >= 0)
        {
            indent(ind);
            if (typeHint.length > 0)
                str.put(chain("(", typeHint, ")"));
            str.put(name);

            foreach (val; values)
                str.put(chain(" ", val.toString()));

            foreach (key, val; properties)
                str.put(chain(" ", key, "=", val.toString()));
        }

        if (children.length > 0)
        {
            if (ind >= 0)
                str.put(" {\n");
            foreach (c; children)
                c.buildString(str, ind + 1);
            if (ind >= 0)
            {
                indent();
                str.put("}\n");
            }
        }
        else if (ind >= 0)
            str.put("\n");
    }
}

struct DomVisitor
{
    Node root = Node("document");
    Node* head;

    // State from prior tokens
    private bool slashdash = false;
    private string typeHint = null;
    private string propName = null;

    // Tracks depth of tree relative relative to the oldest ancestor which was commented out via a
    // slashdash. When either is > 0, current processing is commented out.
    private int node_sds = 0;
    private int child_sds = 0;

    void visit(Token type, T...)(T args)
    {
        import std.conv : to;

        void ProcessValue()(Value val)
        {
            if (slashdash || node_sds > 0 || child_sds > 0)
            {
                slashdash = false;
                return;
            }

            if (typeHint != null)
            {
                val.typeHint = typeHint;
                typeHint = null;
            }

            if (propName != null)
            {
                head.properties[propName] = val;
                propName = null;
            }
            else
            {
                head.values ~= val;
            }
        }

        import std.stdio : writeln;

        // writeln("Token: ", type);
        // foreach (a; args)
        // {
        //     writeln("  ", a);
        // }

        static if (type == Token.DocumentBegin)
        {
            slashdash = false;
            typeHint = null;
            propName = null;
            node_sds = 0;
            child_sds = 0;
        }
        else static if (type == Token.DocumentEnd)
        {
        }
        else static if (type == Token.SlashDash)
        {
            slashdash = true;
        }
        else static if (type == Token.TypeHint)
        {
            typeHint = to!string(args[0]);
        }
        else static if (type == Token.ChildrenBegin)
        {
            if (slashdash || child_sds > 0)
            {
                slashdash = false;
                child_sds++;
            }
        }
        else static if (type == Token.ChildrenEnd)
        {
            if (child_sds > 0)
                child_sds--;
        }
        else static if (type == Token.Node)
        {
            if (head == null)
                head = &root;

            if (slashdash || node_sds > 0 || child_sds > 0)
            {
                slashdash = false;
                node_sds++;
                return;
            }

            head = head.addChild();
            head.name = to!string(args[0]);
            if (typeHint != null)
            {
                head.typeHint = typeHint;
                typeHint = null;
            }
        }
        else static if (type == Token.NodeEnd)
        {
            head = head.parent;
            if (node_sds > 0)
                node_sds--;
        }
        else static if (type == Token.Property)
        {
            // If a slashdash precedes this property, do nothing. Leave the slashdash flag high so that
            // the next Value we visit gets omitted as well
            //      or
            // If the node or child list is slashdashed out, do nothing
            if (slashdash || node_sds > 0 || child_sds > 0)
            {
                return;
            }

            // Set the property pending flag. The the next Value visited will be entered into the
            // property dictionary instead of the value array.
            propName = to!string(args[0]);
        }
        else static if (type == Token.EscapedString || type == Token.RawString)
        {
            ProcessValue(Value(to!string(args[0])));
        }
        else static if (type == Token.Keyword)
        {
            ProcessValue(Value(args[0]));
        }
        else static if (type == Token.BasedNumber)
        {
            ProcessValue(Value(args[0]));
        }
        else static if (type == Token.DecimalNumber)
        {
            ProcessValue(Value(args[0]));
        }
    }
}
