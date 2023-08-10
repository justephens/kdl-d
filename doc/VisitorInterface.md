# Visitor Interface

## Conventions

When the parser passes data to the visitor, the following conventions apply:

- Strings do not contain the parentheses or delimiters. Any escape codes are decoded into UTF-8

- `type` hints contain only the contents between `()`s.
    ```kdl
    (i32)800
    ```
    gives the type hint of `i32`

```D
struct MyVisitor
{
    void visit(VisitType type, T...)(T args)
    {
        writeln("Visit ", type, ":");
        foreach (a; args)
            writeln("  ", a);
    }
}
```

## Visit Prototypes

| VisitType     | Use                                                | Arguments                                                                                 |
| ------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| DocumentBegin | Emitted when parsing begins                        | None                                                                                      |
| DocumentEnd   | Emitted when input range becomes empty             | None                                                                                      |
| Node          | Emitted for each node declaration                  | `(SlashDash sd, R type, R identifier)`                                                    |
|               |                                                    | -- `sd`: whether this node is commented out with a `/-` comment.                          |
|               |                                                    | -- `typeHint`: the KDL type hint on this node, or empty range if not present.             |
|               |                                                    | -- `identifier`: name of this node. Always non-empty.                                     |
| Property      | Emitted for the key of each property               | `(SlashDash sd, R identifier)`                                                            |
|               |                                                    | -- `sd`: whether this node is commented out with a `/-` comment.                          |
|               |                                                    | -- `identifier`: the KDL type hint on this node, or empty range if not present            |
| ValueString   | Emitted for the string value                       | `(SlashDash sd, R typeHint, U value)`                                                     |
|               |                                                    | -- `sd`: whether this node is commented out with a `/-` comment.                          |
|               |                                                    | -- `typeHint`: the KDL type hint on this node, or empty range if not present.             |
|               |                                                    | -- `value`: range for the text of the value. Always non-empty.                            |
| ValueNumber   | Emitted for the numeric value                      | `(SlashDash sd, R typeHint, Number num, R numRaw)`                                        |
|               |                                                    | -- `sd`: whether this node is commented out with a `/-` comment.                          |
|               |                                                    | -- `typeHint`: the KDL type hint on this node, or empty range if not present.             |
|               |                                                    | -- `num`: an instance of `Number` struct describing the elements of the value.            |
|               |                                                    | -- `numRaw`: range of the raw, unprocessed literal the number was read from.              |
| ValueKeyword  | Emitted for the keyword value                      | `(SlashDash sd, R typeHint, Keyword kw)`                                                  |
|               |                                                    | -- `sd`: whether this node is commented out with a `/-` comment.                          |
|               |                                                    | -- `typeHint`: the KDL type hint on this node, or empty range if not present.             |
|               |                                                    | -- `kw`: enum of which keyword this is (`Keyword.True`, `Keyword.False`, `Keyword.Null`). |
| ChildrenBegin | Emitted when a child list opens (`{`)              | None                                                                                      |
| ChildrenEnd   | Emitted when a child list closes (`}`)             | None                                                                                      |
| NodeEnd       | Emitted after all properties, values, and children | None                                                                                      |
