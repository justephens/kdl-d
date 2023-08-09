module kdl.dom;

import std.stdio;
import kdl.parse : VisitType, KdlParser;

struct DomVisitor
{
    void visit(VisitType type, T...)(T args)
    {
        writeln("Visit ", type, ":");
        foreach (a; args)
            writeln("  ", a);
    }
}

struct Value
{
    import std.typecons : Nullable;

    union U {
        string s;
        ulong i;
        real f;
        bool b;
    }
    private Nullable!U _inner;

    string typeHint;
}

struct Node
{
    string typeHint;
    string name;
    Value[string] properties;
    Value[] values;

    Node[] children;
}
