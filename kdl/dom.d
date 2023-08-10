module kdl.dom;

import std.array : appender, Appender;
import kdl.parse : VisitType, KdlParser, Number, Keyword;

struct Value
{
    // todo: switch to Algebraic
    union InnerUnion
    {
        string s;
        ulong ul;
        real re;
        bool b;
    }

    enum Type
    {
        Null = "",
        String = "s",
        Ulong = "ul",
        Real = "re",
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

    this(Number num)
    {
        inner.ul = num.integral;
        type = Type.Ulong;
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

        if (type == Type.Null)
        {
            str.put("null");
            return;
        }
        if (type == Type.Ulong)
        {
            str.put(to!string(inner.ul));
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
            foreach (dchar c; inner.s.byCodePoint())
            {
                switch (c)
                {
                case '\u000A':
                    str.put(`\n`);
                    break;
                case '\u000D':
                    str.put(`\r`);
                    break;
                case '\u0009':
                    str.put(`\t`);
                    break;
                case '\u005C':
                    str.put(`\\`);
                    break;
                // case '\u002F':
                //     str.put(`\/`);
                //     break;
                case '\u0022':
                    str.put(`\"`);
                    break;
                case '\u0008':
                    str.put(`\b`);
                    break;
                case '\u000C':
                    str.put(`\f`);
                    break;
                default:
                    str.put(c);
                    break;
                }
            }
            str.put('"');
        }
    }
}

struct Node
{
    string typeHint;
    string name;
    Value[string] properties;
    Value[] values;

    Node*[] children;
    Node* parent;

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
        this.buildString(a, 0);
        return a[];
    }

    void buildString(ref Appender!string str, size_t ind = 0) const pure
    {
        import std.range : chain;

        void indent(size_t x = ind)
        {
            for (auto i = x; i > 0; i--)
                str.put("    ");
        }

        indent(ind);
        if (typeHint.length > 0)
            str.put(chain("(", typeHint, ")"));
        str.put(name);

        foreach (val; values)
            str.put(chain(" ", val.toString()));

        foreach (key, val; properties)
            str.put(chain(" ", key, "=", val.toString()));

        if (children.length > 0)
        {
            str.put(" {\n");
            foreach (c; children)
                c.buildString(str, ind + 1);
            indent();
            str.put("}\n");
        }
        else
            str.put("\n");
    }
}

struct DomVisitor
{
    Node root = Node("document");
    Node* head;

    bool pendingProp = false;
    string propName;

    import std.conv : to;
    import std.stdio : writeln;

    void visit(VisitType type, T...)(T args) if (type == VisitType.DocumentBegin)
    {
    }

    void visit(VisitType type, T...)(T args) if (type == VisitType.DocumentEnd)
    {
    }

    void visit(VisitType type, T...)(T args) if (type == VisitType.ChildrenBegin)
    {
    }

    void visit(VisitType type, T...)(T args) if (type == VisitType.ChildrenEnd)
    {
    }

    void visit(VisitType type, T...)(T args) if (type == VisitType.Node)
    {
        if (head == null)
            head = &root;

        if (args[0] != "/-")
        {
            head = head.addChild();
            head.typeHint = to!string(args[1]);
            head.name = to!string(args[2]);
        }
    }

    void visit(VisitType type, T...)(T args) if (type == VisitType.Property)
    {
        if (args[0] != "/-")
        {
            propName = to!string(args[1]);
            pendingProp = true;
        }
    }

    void visit(VisitType type, T...)(T args)
            if (type == VisitType.ValueString || type == VisitType.ValueNumber
            || type == VisitType.ValueKeyword)
    {
        if (args[0] == "/-")
            return;

        static if (type == VisitType.ValueString)
        {
            auto val = Value(to!string(args[2]));
        }
        else
        {
            auto val = Value(args[2]);
        }
        val.typeHint = to!string(args[1]);

        // We just saw a property event
        if (pendingProp)
        {
            pendingProp = false;
            head.properties[propName] = val;
        }
        else
        {
            head.values ~= val;
        }
    }

    void visit(VisitType type)() if (type == VisitType.NodeEnd)
    {
        head = head.parent;
    }
}
