---
layout: post
title: Advent of Prism
subtitle: Part 9 - Strings
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 9"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about strings.

## Individuals

### `StringNode`

Strings that represent a contiguous sequence of characters in source and that do not contain interpolation are represented by `StringNode`. This includes a fairly large variety of syntax, including:

* `'foo'` - single-quoted string, disallows interpolation and most escapes
* `"foo"` - double-quoted string, allows interpolation and all escapes
* `"foo #{bar}"` - double-quoted string with interpolation, represented as a list of nodes, plain content will be string nodes
* `?f` - character literal, disallows interpolation but allows some escapes
* `%[foo]` - %-string, disallows interpolation and most escapes
* `%q[foo]` - %-q string, disallows interpolation and most escapes
* `%Q[foo]` - %-Q string, allows interpolation and all escapes
* `%w[foo]` - %-w array, contains string literals separated by whitespace, disallows interpolation and most escapes
* `%W[foo]` - %-W array, contains string literals separated by whitespace, allows interpolation and all escapes
* `%I[foo#{bar}]` - %-i array, contains interpolated symbols separated by whitespace, plain content within the individual interpolated symbols will be string nodes
* `:"foo #{bar}"` - symbols with interpolation are represented as lists of nodes, plain content will be string nodes
* `/foo #{bar}/` - regular expressions with interpolation are represented as lists of nodes, plain content will be string nodes
* `` `foo #{bar}` `` - backtick strings with interpolation are represented as lists of nodes, plain content will be string nodes
* `<<FOO\nfoo\nFOO` - heredocs that do not contain interpolation are represented as plain string nodes
* `<<FOO\nfoo #{bar}\nFOO` - heredocs that contain interpolation are represented as lists of nodes, plain content will be string nodes

As you can see, there are many, _many_ ways to express strings in Ruby code. The `StringNode` class is responsible for representing the plain string content within them all. This maps relatively closely to the way CRuby compiles them as well (with either `putstring` or `putobject` instructions). Let's take a look at the AST for `"foo"`:

<div align="center">
  <img src="/assets/aop/part9-string-node.svg" alt="string node">
</div>

There are some interesting nuances to the things we have chosen to store on these nodes. We'll go through each:

* `flags` - here we store a couple of things
  * if the string is frozen (impacted by the optional `# frozen_string_literal: true` magic comment at the top of the file)
  * if the string is forced into UTF-8 encoding (impacted by `\u` escape seuqences)
  * if the string is forced into ASCII-8BIT encoding (impacted by internal bytes in the `US-ASCII` encoding only)
* `opening_loc` - the optional location of the opening delimiter (which won't be present when a string is internal to another node, like an interpolated string)
* `content_loc` - the location of the string content
* `closing_loc` - the optional location of the closing delimiter (which won't be present when a string is internal to another node, like an interpolated string, and also won't be present for character literals)
* `unescaped` - the actual bytes present in the string

The most important of these for compilers and interpreters is the `unescaped` field. This field contains the actual bytes that were represented by the source code. For simple strings like all of the examples listed above, this will be a slice of the source file. However, in the event of escape sequences in strings that allow them, this can have a different value. Consider for example:

```ruby
'foo\n'.bytes # => [102, 111, 111, 92, 110]
"foo\n".bytes # => [102, 111, 111, 10]
```

In the first example the `\n` escape sequence is not allowed, so it is represented as two characters: `\` and `n`. In the second example the `\n` escape sequence _is_ allowed, so it is represented as a single `\n` character. By providing the `unescaped` field it means individual implementations like CRuby, JRuby, and TruffleRuby can rely on the parser to give them the right bytes instead of having to re-implement the escape sequence logic themselves.

Overall, `StringNode` shows up in a lot of places, but because the semantics are the same in every case, we reuse the same type. By keeping around the `*_loc` fields, we allow other non-compiler tools to recreate the source as they see fit (e.g., for a character literal the `opening_loc` will point to a `?`).

### `XStringNode`

Compared to the relative complexity of the `StringNode`, `XStringNode` can only show up in a single place:

```ruby
`foo`
```

This is an `XStringNode`, and it causes the Ruby implementation to call the `` #` `` method on the current `self` object. Most of the time, this isn't overridden, so it ends up calling `` Kernel#` ``. This method is responsible for executing the command in the string and returning any output to `stdout` that the command may have produced as a string. Here is the AST for `` `foo` ``:

<div align="center">
  <img src="/assets/aop/part9-xstring-node.svg" alt="xstring node">
</div>

You'll notice this effectively has all of the same fields as a regular string node. For all intents and purposes, that's what it is. It represents the string node that will be passed to the `` #` `` method. The only difference in the flags is that these strings are always frozen, so that flag doesn't need to exist.

### `SymbolNode`

Symbol nodes are listed in this post because of their relationship with strings. Symbols are represented by `SymbolNode` and can be present in many places:

* `:foo` - plain symbol
* `:'foo'` - symbol that disallows interpolation
* `:"foo"` - symbol that allows interpolation but doesn't have it
* `%s[foo]` - %-s symbol that disallows interpolation and most escapes
* `%i[foo]` - %-i array, contains symbols separated by whitespace, disallows interpolation and most escapes
* `%I[foo]` - %-I array, contains symbols separated by whitespace, allows interpolation and all escapes. In this case because the first element has no interpolation it will be a plain symbol node.
* `{ :foo => 1 }` - symbol keys in hashes
* `{ foo: 1 }` - symbol label keys in hashes
* `foo(:bar => 1)` - symbol keys in keyword arguments
* `foo(bar: 1)` - symbol label keys in keyword arguments
* `foo in bar: 1` - symbol label keys in hash patterns
* `alias :foo :bar` - symbol names in aliases
* `undef :foo` - symbol names in undefs

Symbols have lots of special rules around what is an is not allowed inside of them. In general, they closely follow the lexer rules for what is allowed as a method name. Here is the AST for `%s[foo]`:

<div align="center">
  <img src="/assets/aop/part9-symbol-node.svg" alt="symbol node">
</div>

You'll notice it has all of the same fields as a string node. As with the `XStringNode`, the only difference is that there is no frozen flag.

## Interpolated content

When creating strings, symbols, xstrings, and regular expressions, you are allowed to interpolate statements and variables into them. This creates a dynamic string that is determined at runtime. First, we'll look at the kinds of content that can be interpolated.

## `EmbeddedStatementsNode`

First, there are embedded statements. This is the much more common form of interpolation. Here is what it looks like:

```ruby
"foo #{bar} baz"
```

The code says to create a string that is flanked by `"foo "` and `" baz"`. The result of the `bar` expression is evaluated and then implicitly `#to_s` is called before it becomes part of the string. This is represented by an `EmbeddedStatementsNode`. When inside of a string-like node that allows interpolation, it is represented by the `#{` operator followed by any number of statements followed by the `}` operator. Here is the AST for `"foo #{bar} baz"`:

<div align="center">
  <img src="/assets/aop/part9-embedded-statements-node.svg" alt="embedded statements node">
</div>

The node itself is relatively simple. It contains inner locations for the `#{` and `}` operators, as well as a pointer to a statements node that contains the statements that will be interpolated.

## `EmbeddedVariableNode`

The far less common form of interpolation is embedded variables. Effectively it is a way to interpolate instance, class, or global variables into a string by omitting the braces. Here is what it looks like:

```ruby
"#@foo #@@bar #$baz"
```

Semantically this is equivalent to:

```ruby
"#{@foo} #{@@bar} #{$baz}"
```

We represent this as an `EmbeddedVariableNode`. These nodes hold an inner location for the `#` marker as well as a pointer to the node they are interpolating. Here is the AST for `"#@foo"`:

<div align="center">
  <img src="/assets/aop/part9-embedded-variable-node.svg" alt="embedded variable node">
</div>

The nodes that can be in that position are `InstanceVariableReadNode`, `ClassVariableReadNode`, and `GlobalVariableReadNode`.

## Containers

As you've already seen, when interpolation is present in a string, symbol, xstring, or regular expression, the result is a list of nodes contained in a node that is prefixed by `Interpolated`.

### `InterpolatedStringNode`

When interpolation is present in a string, the result is an `InterpolatedStringNode`. This node contains a list of nodes that represent the content of the string. Again, here is the AST for `"foo #{bar} baz"`:

<div align="center">
  <img src="/assets/aop/part9-interpolated-string-node.svg" alt="interpolated string node">
</div>

The node itself contains locations for the opening quote, the closing quote, and the list of parts of the string. Interpolated strings can also appear in `%W` lists, as in `%W[foo\ #{bar}\ baz]`:

<div align="center">
  <img src="/assets/aop/part9-interpolated-string-node-2.svg" alt="interpolated string node in %W">
</div>

You'll notice the first element in the list is equivalent to the interpolated string we saw first. The only difference is that it does not contain the locations for the opening and closing quotes as they are not present.

### `InterpolatedXStringNode`

In the same way that `XStringNode` nodes are the same as `StringNode` with the added semantic that they send the string to the `` #` `` method, `InterpolatedXStringNode` nodes are the same as `InterpolatedStringNode` with the same semantic. Here is the AST for `` `foo #{bar} baz` ``:

<div align="center">
  <img src="/assets/aop/part9-interpolated-xstring-node.svg" alt="interpolated xstring node">
</div>

### `InterpolatedSymbolNode`

Symbols can have interpolation when they are wrapping in `:"` and `"`. They can also have interpolation when used inside hashes and keyword arguments wrapped in `"` and `":`. Here is the AST for `:"foo #{bar} baz"`:

<div align="center">
  <img src="/assets/aop/part9-interpolated-symbol-node.svg" alt="interpolated symbol node">
</div>

## Heredocs

Heredocs are another way of representing strings. They are semantically equivalent to `StringNode` and `InterpolatedStringNode`, although their syntax is significantly different. Here is an example:

```ruby
<<-FOO
  bar
FOO
```

After a heredoc has been declared, the content of the heredoc begins on the next newline. Syntactically, this can get quite complicated, because the next newline might be further than you think. For example:

```ruby
foo(<<-BAR)
  baz
BAR
```

In this example, it's semantically equivalent to passing a string into the `foo` method. In order to parse this correctly, prism sees the declaration of the heredoc and creates a save point. It then skips to the next newline and parses the content of the heredoc. When it finds the closing delimiter, it creates another save point. It then jumps back to the first save point, parses the rest of the line, and then jumps back to the second save point. If it sounds complicated, it's because it is. Here is the AST for the first example:

<div align="center">
  <img src="/assets/aop/part9-heredoc-node.svg" alt="heredoc node">
</div>

You can see it just resolves to a string node. This allows compilers to not have to care about heredocs at all, since they are effectively resolved by the time they get the tree. Heredocs as a whole are one of the most difficult parts of both parsing and understanding Ruby. Because of various combinations of nodes, they can be even more complicated than originally intended, as in:

```ruby
<<A+%
a
A
b
```

While this code is valid Ruby, it's also the last snippet we know of that is still failing to parse in prism. Obviously we can't have that, so by putting this into a blog post I'm promising myself I'll fix it.

Heredocs have other semantics depending on the quotes they use and the indentation form they use. For example, a heredoc that begins with `<<` requires the closing delimiter to be at the start of its own line. `<<-` indicates it can have any amount of whitespace before it. `<<~` means to eliminate all common whitespace (ignoring blank lines) from every line in the heredoc.

Quoting can change the semantics as well. `<<'` means to disable interpolation (interpolation is allowed by default in heredocs). `<<"` means to keep interpolation (it is somewhat redundant). `` <<` `` means to transform the heredoc into an xstring.

There is so much hidden complexity in this feature that it could be its own blog series. Suffice to say, it's not a blog series I'd like to write.

## Escapes

Within strings, escape sequences make it easier to write certain bytes. They can also change the encoding of the string from the default encoding of the file. Here is a list of the escape sequences that are supported:

* `\\`, `\'`, `\"`, `\r`, `\n` - single-character escapes depending on context
* `\a`, `\b`, `\e`, `\f`, `\s`, `\t`, `\v` - single-character escapes
* `\r\n` - a two-character escape
* `\nnn` - octal escape where `nnn` is a 1, 2, or 3-digit octal number
* `\xnn` - hexadecimal escape where `nn` is a 1 or 2-digit hex number
* `\unnnn` - unicode escape where `nnnn` is a 4-digit hex number
* `\u{nnnnnn+}` - unicode escapes, multiple codepoints are allowed separated by whitespace
* `\c`, `\C` - control character escapes
* `\M` - meta character escapes

Listing out how each of these function is beyond the scope of this blog, but if you're interested in learning you should check out the official [CRuby documentation](https://docs.ruby-lang.org/en/master/syntax/literals_rdoc.html#label-String+Literals).

## Encoding

Every string (and xstring and symbol) has an associated encoding. These encodings represent the way the bytes of the string should be interpreted when considered as characters/codepoints. The default encoding of a string is the encoding of the file it is in. The file encoding, in turn, defaults to `UTF-8` but can be changed by a magic `# encoding:` comment at the top of the file.

String-like nodes can have a different encoding depending on their internal bytes and escape sequences. In general, if a string contains a unicode escape sequence (`\u`) that resolves to a codepoint that is not in the `US-ASCII` encoding, the string will be forced into the `UTF-8` encoding. The only caveat is that if a file is encoded in `US-ASCII` and a byte is present that is not in the `US-ASCII` encoding, the string will be forced into the `ASCII-8BIT` encoding.

Encodings have much more nuance than that as a whole, but that's enough for today.

## Wrapping up

We made it! Strings have lots of complexity, but hopefully this post gives you a window into everything you might want to know or lookup later. Here are a couple of things to remember:

* `StringNode` represents a string that does not contain interpolation, and can be found in many places in the prism AST
* Backtick strings are effectively strings that represent a call to the `` #` `` method
* Prism performs unescaping to provide the exact bytes that are necessary to its consumers
* Heredocs are a syntax feature, but do not represent any kind of different semantics in the language itself
* Escapes can change the internal bytes of a string
* Every string-like object has an encoding, and it can change from the source file

Tomorrow we'll be looking at the other kind of string-like node: regular expressions. See you then!
