---
layout: post
title: Advent of Prism
subtitle: Part 24 - Error tolerance
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 24"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about error tolerance.

We have finally reached the end of our series. To date, we have covered 147 nodes in the prism syntax tree. As it turns out, this is 1 less than the total. The final node is `MissingNode`, which is the subject of today's post. Before we get into that, however, we need to talk about error tolerance.

## Error tolerance

Every example we have seen in this blog series so far has been a valid Ruby program. Parsing _valid_ Ruby is actually not that difficult — it has been done correctly by many different tools over the years. Parsing _invalid_ Ruby, however, is another challenge altogether.

Most of the time that code is being written, it is invalid. We are not talking about production code or code that has already been saved to disk (hopefully). We're mostly talking about code that is in the middle of being edited. As you type, you introduce syntax errors until you get to the end of the current expression. Editors and linters want to be able to parse _as you type_, however. This means that they need to be able to parse invalid code.

Error tolerance is a field of study that involves parsing invalid code. It refers to the ability to the parser to "tolerate" syntax errors in the input and continue to parse the file to return a syntax tree. This is a difficult problem to solve, and ends up being a bit more art than science. However, there are some guardrails in place that we can talk about.

Let's take, for example, the following code:

```ruby
1 +
```

We know that this is invalid Ruby code, because the `+` operator is in the infix position and requires there to be an expression on the right-hand side. However, intuitively we know that this is a method call with a missing argument. We can translate that into our parser to allow it to "handle" this syntax error by determining if the token after the `+` operator could potentially begin an expression.

In this case it's the newline token, so the subsequent token cannot begin an expression. When we encounter a situation like this, we can insert a `MissingNode` into the syntax tree. This node is a placeholder that represents the missing expression. It is a child of the `+` method call, and has no children or fields of its own. After inserting the missing node we log an error and then continue parsing as if nothing happened.

Here is what the AST looks like for `1 +`:

<div align="center">
  <img src="/assets/aop/part24-missing-node.svg" alt="missing node">
</div>

We have weaved this kind of error tolerance into prism from the beginning. This has made it suitable for use in editors and linters, which is why it is the parse tree backing the [ruby-lsp](https://github.com/Shopify/ruby-lsp) project. By providing a syntax tree regardless of errors, it means tools like RuboCop and Sorbet can still lint and type check the input file even if it is invalid. This means sections of the file can be cached so that they do not have to be re-parsed and re-processed when the file is edited. This would not be possible if the parser simply failed on the first instance of invalid input.

## Ambiguous tokens

Another form of syntax error is ambiguous tokens. Consider, for example, the following code:

```ruby
class Foo
  def bar
    self.
  end
end
```

As a developer, most people would read this as a missing method name being sent to `self` inside the `bar` method. However, it is perfectly valid Ruby to have `self.end` be separated by newlines and whitespace. This means there is an ambiguity here between if the `end` is a method name or the keyword that closes the `def` block.

If the `end` is parsed as a method name, then the `class` statement will not be closed. In this case a syntax error will be raised. CRuby recently developed a solution for this: insert a missing `end` token and see if it "fixes" the problem. This turns out to be a common enough pattern that this solves a lot of the ambiguity problems in the parser.

Prism has not yet implemented this kind of recovery, but it is first on our list of tasks for next year. If and when CRuby adopts prism as its primary parser, we could not in good conscience do so without parity or improvements in error tolerance.

## Wrapping up

There you have it, folks! After 24 days of posts, we have covered every piece of known Ruby syntax up to Ruby 3.3.0. Tomorrow this version of Ruby will be released, and I'm assuming shortly thereafter we will have more fun syntax coming down the pipe.

I wrote this series for a couple of reasons. I wanted to introduce you all to prism, so that you can use it if you want to build something on top of the Ruby syntax tree. I also wanted to introduce you all to all of the varieties of Ruby syntax that I have gotten to know through building prism. Finally, I wanted a snapshot in time of what Ruby looks like, so that I have something to point people to if they have questions in the future.

I have learned a lot about Ruby, AST/IR design, and parsing in this journey. I hope you have learned something too. Here are the main things I hope you take away from this series:

* Ruby's grammar is incredibly complex because it tries to allow you to express code in whatever natural way you feel is best. It has grown and will continue to grow organically over the years to fit the needs of the community. Although it is difficult to parse, it is a joy to read and write, which is far more important.
* Usually the relative complexity of syntax and semantics are correlated, but not always! As an example, the binary one-character `+` operator consistently represents a single method call, but the binary two-character `+=` operator represents a method call and an assignment.
* Syntax that looks very similar can have very different meanings, depending on context. As a corrolary, syntax that looks very different can have the same meaning, depending on context. Consider the `if` modifier, which can either be an `if` statement or a guard clause in a pattern match. Also consider the ternary `?` and `:` markers, which can represent the same thing as an `if`.
* Through hard work, dedication, and cooperation, we can create incredible tools and developer experiences for Rubyists everywhere.

Thank you so much for reading. I hope you have a wonderful holiday season!
