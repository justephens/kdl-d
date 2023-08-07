
import kdl.dom;
import kdl.parse;

void main(string[] args)
{
    import std.stdio;
    import std.uni;
    import std.utf;

    string ident = "+7node  fsd";
    string strLiteral = `r#"Just a "raw" string \with\no\escapes"# and more nodes`;
    string node = `/-mynode "foo" key=1 {
  a
  b
  c
}`;

    auto byCP = ident.byUTF!(dchar).byCodePoint();

    DomVisitor vis;

    KdlParser!(DomVisitor).parse(vis, byCP);
}