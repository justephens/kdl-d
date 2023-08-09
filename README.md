# KDL-d

A D library for parsing and operating on [KDL](kdl.dev) documents.

KDL is a markup language inspired by the DLang Community's own [SDLang](sdlang.org), but with some
design tweaks to make it more broadly appealing. KDL appears to have gained wider traction than
SDLang (and in my view rightly taken the crown for "friendliest markup language"), so I figured
it's time to bring it to D.

## Example

```D
import std.file : readText;
import std.stdio : writeln;
import std.uni : byCodePoint;

// Read file into memory, create a range to lazily decode into unicode code points
auto inputFile = readText("myFile.kdl");
auto inputStream = inputFile.byCodePoint();

// Parse into a DOM
DomVisitor vis;
KdlParser!vis.parseNodes(inputStream);
```

## Features

- Range-based parser will parse any [Forward Range](https://dlang.org/phobos/std_range_primitives.html#isForwardRange) of `dchar`.
- Visitor pattern means parser backend can by easily customized.
  - See [doc/VisitorInterface.md] for more information.

### Planned features

- Parser Improvements
  - [ ] Emit comments
  - [ ] Emit indent level for each line (to allow multi-line strings to remove indents)
- Document Improvements
  - [ ] Basic DOM model
  - [ ] Automatically convert common type hints to `std` types
  - [ ] Support for [KDL Query Language](https://github.com/kdl-org/kdl/blob/main/QUERY-SPEC.md)
- Stretch Goals:
  - [ ] Support for [KDL Schema](https://github.com/kdl-org/kdl/blob/main/SCHEMA-SPEC.md)
    - [ ] Validate DOM after parsing
    - [ ] Bake validation into parser at compile time

## Build
1. To build library, run `dub`
2. To build example code, run `dub --config=example -- path/to/test/document.kdl`
3. To run test cases, run `dub test`
