---
layout: post
title: Advent of Prism
subtitle: Part 22 - Pattern matching (part 1)
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 22"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about pattern matching.

Pattern matching was introduced in Ruby 2.7 as a way to match against a value and extract parts of it. It's a very powerful feature that effectively allows you to replace syntactically complicated `if`/`case` statements with a more terse syntax. (To be clear: the syntax is less complicated in pattern matching but the semantics — if anything — are more complicated.)

The pattern matching grammar is a whole grammar unto itself. You can think of it as a mini-parser within the overall Ruby parser. Operators like `|`, `^`, and `=>` have different meaning, brackets and braces create different kinds of structures, and reads/writes are flipped from what you might expect. It's a lot to take in, which is why pattern matching is split over two posts.

In this first part we'll look at the nodes that trigger pattern matching, as well as introduce the basics of matching against individual values. We'll also look at alternation and pinning. Tomorrow we'll cover the more advanced concepts: destructuring and capturing. For now, let's jump in.

## Matching

There are three ways to trigger pattern matching: using a `case ... in` statement, using the binary `in` operator, or using the binary `=>` operator. They each do different things, so we'll look at each one in turn.

### `CaseMatchNode`

When a `case` keyword is used, the parser first checks to see if there is a value associated with it. (Remember from [Part 7 - Control-flow](/2023/12/07/advent-of-prism-part-7) that `case` can optionally replace `if`/`elsif` chains by omitting the value.) If there _is_ a value, then the parser parses it and then checks the subsequent keyword. If the keyword is `when` then a `CaseNode` is created and parsed. If the keyword is `in` then a `CaseMatchNode` is created and parsed. Here's an example:

```ruby
case foo
in Integer
  puts "foo is an integer"
end
```

The above code will call the `foo` method and then check if the return value is an `Integer` using `Integer::===` (just like `case ... when` statements). If it is, then the `puts` statement will be executed. If it isn't the subsequent clause will be checked. In this case because there are no more, it will raise a `NoMatchingPatternError`. The AST for the above code looks like this:

<div align="center">
  <img src="/assets/aop/part22-case-match-node.svg" alt="case match node">
</div>

You can see that the structure is very similar to a `CaseNode`. Initially we had it as the same node, but decided to split considering it has such significantly different semantics.

The `CaseMatchNode` contains a pointer to the value to match against as well as a flat list of clauses to check. Each clause is or contains an `InNode` node. It also contains an optional `else` clause, which is an `ElseNode` node. That looks like:

```ruby
case foo
in Integer
  puts "foo is an integer"
else
  puts "foo is something else"
end
```

That AST looks like:

<div align="center">
  <img src="/assets/aop/part22-case-match-node.svg" alt="case match node">
</div>

The `else` clause allows you to specify a default behavior, meaning a `NoMatchingPatternError` will not be raised. Note that this can initially be surprising for developers who are familiar with `case ... when` statements because this error raising behavior is specific to pattern matching.

### `InNode`

Every clause in a `CaseMatchNode` is or contains an `InNode`. It contains a pointer to the singular pattern to match against and the statements to execute if the pattern matches. For example:

```ruby
case foo
in Integer
  puts "foo is an integer"
end
```

Importantly, `in` differs from `when` in that the pattern is singular and not a comma-separated list. Further evidence that the pattern matching grammar differs somewhat significantly from the Ruby grammar. The AST for this example is a part of the `CaseMatchNode` AST above.

#### Guards

It is possible to add guard clauses to `in` clauses. These are conditions that will also be checked in addition to the pattern, after the pattern has run. They can begin with either an `if` or `unless` keyword. For example:

```ruby
case foo
in Integer if foo > 10
  puts "foo is an integer greater than 10"
in Integer if foo > 5
  puts "foo is an integer greater than 5"
else
  puts "foo is something else"
end
```

These guards can be extremely powerful because you can reference values that you matched against. Fortunately for us, we already have a node that represents this kind of behavior: `IfNode`. In this case we reuse it. Here is the AST for this example (with the bodies of the `InNode` clauses stripped out):

<div align="center">
  <img src="/assets/aop/part22-if-guard.svg" alt="if guard">
</div>

### `MatchPredicateNode`

The `in` keyword can be also used as a binary operator. We call this a "match predicate" because it always returns `true` or `false`. Here is an example:

```ruby
foo in Integer
```

This will call the `Integer::===` method with the return value of the `foo` method call and return `true` or `false` depending on whether the value matches. Importantly, no error will be raised regardless of the outcome. The AST for this example looks like:

<div align="center">
  <img src="/assets/aop/part22-match-predicate-node.svg" alt="match predicate node">
</div>

This is another case of a relatively simple AST that represents a relatively complicated semantic. Under the hood the entire pattern on the right-hand side is compiled into a set of requirements that are then checked against the value on the left-hand side.

### `MatchRequiredNode`

The `=>` operator is reused from hashes and rescues as a binary operator to match "match required". Here is an example:

```ruby
foo => Integer
```

This is similar to the `in` operator, but it will raise a `NoMatchingPatternError` if the value does not match. The AST for this example looks like:

<div align="center">
  <img src="/assets/aop/part22-match-required-node.svg" alt="match required node">
</div>

Again, this is a relatively simple AST that hides some real complexity. Lots of developers are initially confused by the difference between `in` and `=>` because of the inconsistency with the rest of the language. As we've seen, usually operator/keyword pairs do the same thing and just have different precedence like `and`/`&&`, `or`/`||`, `not`/`!`. In this case, however, it's important to remember that this keyword and operator have very different semantics.

## Patterns

Now that we've looked at the nodes that hold patterns, let's look at some of the patterns themselves. In general you can match against most literal objects (numbers, strings, ranges, regular expressions, etc.). In every case the `#===` method will be called on the pattern with the value to match against (under the hood in CRuby the `checkmatch` instruction does exactly this). For example:

```ruby
foo in 1
foo in 1.0
foo in 1..10
foo in "foo"
foo in :foo
foo in :"foo"
foo in /foo/
foo in Foo
```

Matching against a single value is useful, but sometimes you want to match against multiple values. We'll look at that next.

### `AlternationPatternNode`

When you want to match against multiple values, you can use the `|` operator. This operator is different from the normal Ruby `|` method call. Instead, it indicates that the pattern on the left-hand side _or_ the pattern on the right-hand side should check for a match. You can think of it as semantically similar to the commas in a `case ... when` statement. For example:

```ruby
foo in 1 | 2
```

This will match if `foo` is either `1` or `2`. The AST for this example looks like:

<div align="center">
  <img src="/assets/aop/part22-alternation-pattern-node.svg" alt="alternation pattern node">
</div>

Note that `|` can be chained, in which case the parser will form a linked list of `AlternationPatternNode` nodes. For example:

```ruby
foo in 1 | 1.0 | 1r | 1i
```

The AST for this example looks like:

<div align="center">
  <img src="/assets/aop/part22-alternation-pattern-node-2.svg" alt="alternation pattern node">
</div>

## Pinning

Matching against static values is nice, but it's not nearly as powerful as matching against dynamic values. For example, let's say you have some local variable that you want to match against the return value of a method. Let's see how we can do that.

### `PinnedVariableNode`

When you want to match against a variable value, you can use the `^` operator. This is called the "pin" operator, which "pins" the value within the pattern. For example:

```ruby
bar = 5
foo in ^bar
```

This will call `#===` on the value of the `bar` local variable to check if the return value of the `foo` method call matches. The AST for this example looks like:

<div align="center">
  <img src="/assets/aop/part22-pinned-variable-node.svg" alt="pinned variable node">
</div>

Note that you can pin any kind of variable, so this could also be instance, class, or global variables. For example:

```ruby
foo in ^@bar
foo in ^@@bar
foo in ^$bar
```

In all cases, the `PinnedVariableNode` will be used, which has a single pointer to the variable being pinned. Note that this syntax is how you read variables in pattern matching: by prefixing them with the `^` operator. We'll see in our post tomorrow how writing variables looks an awful lot like reading variables everywhere else in Ruby.

### `PinnedExpressionNode`

Beyond pinning variables, you can also pin expressions. This looks like:

```ruby
foo in ^(bar)
```

This will call the `bar` method and use its value within the pattern (i.e., it will call `#===` on the return value). The AST for this example looks like:

<div align="center">
  <img src="/assets/aop/part22-pinned-expression-node.svg" alt="pinned expression node">
</div>

Note that the parentheses are the only difference betwen `PinnedVariableNode` and `PinnedExpressionNode` in terms of syntax, though they have very different semantics. Note also that unlike everywhere else in Ruby, multiple statements are not allowed within the parentheses. So even though space is allowed between `^` and `(`, I encourage you to think of them as a single delimiter.

## Wrapping up

Today we looked at the basics of pattern matching syntax. This includes all of the nodes that trigger pattern matching, as well as some of the more basic patterns. Here are some things to remember from today:

* Pattern matching is triggered by `case ... in` statements, the binary `in` operator, and the binary `=>` operator.
* The binary `in` and `=>` operators have very different semantics.
* The `|` operator is used to match against multiple values.
* Reading variables in patterns is done by prefixing them with the `^` operator.
* Reading singular expressions in patterns is done by wrapping them in `^(` and `)`.

Tomorrow we'll close out our discussion of pattern matching by looking at destructuring and capturing. See you then!
