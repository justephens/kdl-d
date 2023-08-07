module kdl.dom;

import std.stdio;

struct DomVisitor
{
    void visitIdentifier(T...)(T args)
    {
        writeln("Identifier:");
        foreach (a; args)
        {
            writeln(a);
        }
    }

    auto opDispatch(string member, T...)(T args)
    {
        writeln("Call:");
        writeln("  ", member);
        foreach (a; args)
            writeln("  - ", a);
    }
}
