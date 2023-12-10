---
layout: post
title: Advent of Prism
subtitle: Part 10 - Regular expressions
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 10"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about regular expressions.

Regular expressions in Ruby could have entire books written about them (and have). Today we're going to go through a small subset of regular expressions — just enough to introduce you to the nodes that we use to represent them in prism's syntax tree.

## `RegularExpressionNode`

The simplest form a regular expression is called a `RegularExpressionNode`. These nodes do not contain interpolation. They do, however, allow almost all escapes. They also support a number of flags that can be used as a suffix. This post is not going to go through much of the _inner_ syntax of regular expressions. Suffice to say, regular expressions are a grammar unto themselves. First, let's look at some examples:

```ruby
/foo/
%r{foo}
/foo|bar/imx
```

All of these expressions are represented with `RegularExpressionNode`. In the first line you see a simple regular expression that would match the literal "foo" string. The second line does the same thing, but delimited by the `%r` literal. The third example showcases how to use modifier flags on the end. There are 8 flags that are supported:

- ignore_case (`i`) - ignores the case of characters when matching
- extended (`x`) - ignores whitespace and allows comments in regular expressions
- multi_line (`m`) - allows `$` to match the end of lines within strings
- once (`o`) - only interpolates values into the regular expression once
- euc_jp (`e`) - forces the EUC-JP encoding
- ascii_8bit (`n`) - forces the ASCII-8BIT encoding
- windows_31j (`s`) - forces the Windows-31J encoding
- utf_8 (`u`) - forces the UTF-8 encoding

There is a lot more that could be said about regular expressions what the exact semantics of these flags. (As an example, the `i` flag ignoring case is a little simplistic - sometimes "case" maps one capital letter to two lowercase letters.) That being said, here's what the AST looks like for `/foo/`:

<div align="center">
  <img src="/assets/aop/part10-regular-expression-node.svg" alt="regular expression node">
</div>

You'll notice that the regular expression node looks very similar to the string nodes we saw yesterday. They are largely the same in representation. The `unescaped` field has some nuanced differences, however, which we'll discuss in a bit.

## `InterpolatedRegularExpressionNode`

Just as strings, xstrings, and symbols had interpolated counterparts, the regular expression has `InterpolatedRegularExpressionNode`. When regular expressions have interpolation it is represented as a list of string or embedded nodes. For example:

```ruby
/foo #{bar}/
```

This creates a regular expression with the `"foo "` prefix and the `bar` variable's `#to_s` representation at the end. The AST for this looks like:

<div align="center">
  <img src="/assets/aop/part10-interpolated-regular-expression-node.svg" alt="interpolated regular expression node">
</div>

### The `o` flag

The flags that regular expressions support can be grouped into three categories: flags that affect the match, flags the affect the encoding, and the `o` flag. The uniqueness of the `o` flag requires some further discussion.

The `o` flag means to interpolate into a regular expression only once. It is only effective on regular expressions that have interpolation in the first place. This means that for the life of the program, the regular expression will contain only the value that was interpolated the first time, regardless of whether or not that expression has changed. For example:

```ruby
(0...10).each do |number|
  pattern = /\d{#{number + 1}}/o
  pattern =~ "0123456789"
end
```

Adding the `o` flag here means that this pattern will only ever match the first `0` in the string. It's implemented in an interesting way in CRuby. If you'll permit me a brief aside as we look away from syntax into bytecode:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(4,3)> (catch: false)
0000 putobject                              0...10                    (   1)[Li]
0002 send                                   <calldata!mid:each, argc:0>, block in <main>
0005 leave

== disasm: #<ISeq:block in <main>@test.rb:1 (1,14)-(4,3)> (catch: false)
local table (size: 2, argc: 1 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 2] number@0<Arg>[ 1] pattern@1
0000 once                                   block (2 levels) in <main>, <is:0>(   2)[LiBc]
0003 setlocal_WC_0                          pattern@1
0005 getlocal_WC_0                          pattern@1                 (   3)[Li]
0007 putstring                              "0123456789"
0009 opt_regexpmatch2                       <calldata!mid:=~, argc:1, ARGS_SIMPLE>[CcCr]
0011 leave                                                            (   4)[Br]

== disasm: #<ISeq:block (2 levels) in <main>@test.rb:2 (2,12)-(2,32)> (catch: false)
0000 putobject                              "\\d{"                    (   2)
0002 getlocal_WC_1                          number@0
0004 putobject_INT2FIX_1_
0005 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0007 dup
0008 objtostring                            <calldata!mid:to_s, argc:0, FCALL|ARGS_SIMPLE>
0010 anytostring
0011 putobject                              "}"
0013 toregexp                               0, 3
0016 leave
```

There is a `once` instruction that accepts an instruction sequence and an inline storage. The instruction sequence contains the code to perform the interpolation. The inline storage is used to indicate if it has ever run. If it hasn't, it will do the interpolation once. From then on the cache prevents the interpolation from running again. Other Ruby implementations have other ways of doing this, but they all boil down to a hidden state variable.

## `DATA`

Before we continue with other nodes that have to do with regular expressions, we need to briefly talk about a constant in Ruby that can only exist in the main file it is executing. When Ruby executes the main file, if it finds the `__END__` syntax, it creates a `DATA` constant that contains a `File` object that can be used to read that content. For example:

```ruby
puts DATA.read

__END__
This is content that can be read by the File stored in the DATA constant.
The DATA constant only exists in the main file being run by Ruby.
It is a convenient way to store data in files to be read during execution.
```

The output of this file will be all of the content below the `__END__` marker put out to stdout. This is especially useful if you have some data you don't want to embed directly into the source code like an HTML template file, a JSON or CSV data file, or really anything else.

## `MatchLastLineNode`

There is a very esoteric syntax that has to do with regular expressions that most Rubyists do not know exists. That is that when a regular expression is used as the predicate of a conditional expression, it implicitly matches against the last line that was read from an IO object. Taking advantage of our previous example, this can be combined to produce:

```ruby
while DATA.gets
  if /^T/
    puts $_
  end
end

__END__
This is content that can be read by the File stored in the DATA constant.
The DATA constant only exists in the main file being run by Ruby.
It is a convenient way to store data in files to be read during execution.
```

The output of this program will be the first two lines of the output but _not_ the third. You would expect that the regular expression in the predicate of the conditional would be interpreted as truthy, since Ruby treats all objects that aren't `nil` or `false` as truthy. However, because it is a regular expression and because it is in the predicate position, it instead gets interpreted as implicitly matching against `$_`, otherwise known as the last line read by an IO object. Since `DATA` is an IO object, this qualifies.

The AST for the whole `if` statement above is:

<div align="center">
  <img src="/assets/aop/part10-match-last-line-node.svg" alt="match last line node">
</div>

You'll notice that it has the exact same structure as a `RegularExpressionNode`. This is because when prism determines that we have a `MatchLastLineNode` the only thing it does is to change the type. All other flags and escapes continue to apply.

## `InterpolatedMatchLastLineNode`

Because regular expressions support interpolation, `MatchLastLineNode` also must have an interpolated version. That would look like:

```ruby
while DATA.gets
  if /^T#{"his|he"}/
    puts $_
  end
end
```

This is a more restrictive version of the regular expression above, but results in the same output. Here is the AST for that `if` statement:

<div align="center">
  <img src="/assets/aop/part10-interpolated-match-last-line-node.svg" alt="interpolated match last line node">
</div>

## `MatchWriteNode`

We mentioned this briefly when we talked about local variable targets, but here we finally are discussing regular expressions. There is an inner syntax in regular expressions that allows capture groups to be named. For example:

```ruby
/(?<value>\d+)/ =~ "123"
```

This syntax says to match one or more digits in a row and assign it the name of `value`. On the resulting `MatchData` object you would be able access the capture group via `match[:value]`. However, there is a side-effect if the regular expression is used on the left-hand side of a `=~` operator. That is, Ruby will write all named captures to local variables. For example, here is the AST for the above expression:

<div align="center">
  <img src="/assets/aop/part10-match-write-node.svg" alt="match write node">
</div>

You can see that the `MatchWriteNode` contains the call to the `=~` operator as well as a list of targets. These will always be local variable targets. They can either introduce new local variables (as done in this example) or write to existing local variables.

## Escapes

Escapes still happen in regular expressions, but happen slightly differently. CRuby uses a regular expression engine named Onigmo, which does its own escaping. CRuby supports a superset of Onigmo's escape sequences, so when it reads escapes it normalizes them to the escapes that Onigmo supports.

For example, Onigmo _does_ support `\x` escape sequences, so you can write `/\xD0/` and it will copy it over directly to the regular expression. However, Onigmo _does not_ support meta and control escape sequences. As such, CRuby will resolve them and them copy them over to `\x` escape sequences instead. For example if you wanted to target a specific Unicode value but did it in a super convoluted way:

```ruby
/\xD0\C-\M-?/
# => /\xD0\x9F/
```

It would resolve to that much simpler way of expressing the same bytes. Honestly, this is more an interesting bit of trivia than something you actually need to know. But I personally struggled to understand this for long enough that I wanted someone else in the world to know this as well. So now you and I can share this burden of knowledge together.

## Wrapping up

Thanks for reading! Today we learned about regular expressions and the many varied contexts in which they can be found. Here are a couple of things to take away:

* Regular expressions have a complex inner grammar but a relatively simple outer grammar.
* Regular expressions, when used in the predicate of a conditional, implicitly match against `$_`.
* Escape sequences in CRuby regular expressions can be rewritten before they are passed to Onigmo.

That's all for today. Tomorrow we'll slow things down and look at a single keyword in Ruby that is deceptively complex: `defined?`.
