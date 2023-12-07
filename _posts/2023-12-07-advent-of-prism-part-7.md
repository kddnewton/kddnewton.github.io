---
layout: post
title: Advent of Prism
subtitle: Part 7 - Control-flow
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 7"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about control-flow.

Taking a break from writing to variables, today we're going to look at control-flow constructs. To recap, control-flow refers to the order in which statements are executed by a program. Ruby has many different syntactic patterns that allow the user to modify the control-flow of a program. Some are considered "local" control-flow, meaning they only affect the current scope. Others are considered "non-local" control-flow, meaning they can affect the entire program. Today we will be looking at local control-flow.

## Booleans

### `AndNode`

The `and` and `&&` operators are used to combine two expressions. The left-hand side expression is evaluated first. If it is truthy, the right-hand side expression is evaluated and returned. If it is falsy, the left-hand side expression is returned. Here are some examples in Ruby code:

```ruby
foo and bar
foo && bar
```

Note that once these expressions have been parsed, there is no difference between them in the semantics of the code. They are equivalent, and are therefore represented by the same node in the tree. Here's what the AST looks like for `1 and 2`:

<div align="center">
  <img src="/assets/aop/part7-and-node.svg" alt="and node">
</div>

You may wonder about the difference between the operators given that they are equivalent semantically. This is the first instance of this series where we're going to mention a new concept: operator precedence. Operator precedence refers to the manner in which expressions are grouped together. You can think of it loosely as "where would I insert parentheses to make this expression disambiguous?". For example:

```ruby
1 + 2 * 3
```

In the above example you would insert parentheses around the `2 * 3` because the `*` operator has a higher precedence than the `+` operator. This means that the `*` operator will be evaluated first, and the result will be passed to the `+` operator. All operators/expressions in Ruby have a precedence (and associativity, a topic for another time).

In this case, the `&&` operator has a significantly higher precedence than the `and` operator, meaning it more tightly groups its surrounding expressions. If you want to learn even more about operator precedence, prism contributor [Hiroya Fujinami](https://github.com/MakeNowJust) has recently written a [great blog post](https://makenowjust-labs.github.io/blog/post/2023-12-04-operator-precedence) about it and a corresponding [RPrec](https://github.com/makenowjust/rprec) library.

### `OrNode`

The `or` and `||` operators can be used to combine two expressions. The left-hand side expression is evaluated first. If it is truthy, the left-hand side expression is returned. If it is falsy, the right-hand side expression is evaluated and returned. Here are some examples in Ruby code:

```ruby
foo or bar
foo || bar
```

As with the `AndNode` expressions, once they have been parsed the above two expressions are semantically equivalent. Here's what the AST looks like for `1 or 2`:

<div align="center">
  <img src="/assets/aop/part7-or-node.svg" alt="or node">
</div>

Again, operator precedence is the only difference between the two operators. As with the `&&` and `and` operators, the `||` operator has a much higher precedence than the `or` operator.

## Loops

Ruby has three different syntactic loops that can be used: `while`, `until`, and `for`. Each of these loops has a corresponding node in the AST.

### `WhileNode`

The `while` keyword creates a loop that will continue to execute as long as the given expression is truthy. Here are some examples in Ruby code:

```ruby
while foo
  bar
end

while foo do bar end

bar while foo
```

Note that all three of these examples are semantically equivalent, and therefore are represented with the same `WhileNode` node. The structure of the grammar for a `while` loop dictates that there must be a terminator after the predicate (the value to be compared) of the loop. That terminator can be a semicolon, a newline, or the `do` keyword. You'll see as we progress through the series that most syntactic constructs in Ruby have an optional keyword terminator in this position. This comes from some history that Ruby was originally designed in part to be a replacement for Perl and AWK on the command line. You wouldn't want to terminate expressions with newlines because it was less convenient when writing single-line scripts.

Here's what the AST looks like for `while 1 do 2 end`:

<div align="center">
  <img src="/assets/aop/part7-while-node.svg" alt="while node">
</div>

You may notice that the `WhileNode` node has a slot for flags. This is to allow for the possibility of marking it as a `begin_modifier?` loop. This is a special construct in Ruby that allows you to do what other languages typically represent as a `do ... while` loop. Here's an example:

```ruby
begin
  foo
end while bar
```

This will execute the body of the loop once before checking the predicate. If the predicate is truthy, the loop will continue to execute. If it is falsy, the loop will terminate. We need the flag on the node to differentiate it from:

```ruby
while bar
  begin
    foo
  end
end
```

Here's what the AST looks like for `begin 1 end while 2`:

<div align="center">
  <img src="/assets/aop/part7-while-node-2.svg" alt="while node begin modifier">
</div>

### `UntilNode`

The `until` keyword is the opposite of the `while` keyword, i.e., it executes a loop as long as the given expression is falsy. Here are some examples in Ruby code:

```ruby
until foo
  bar
end

until foo do bar end

bar until foo
```

As with the `while` keyword, all three of the above expressions are equivalent. Here's what the AST looks like for `until 1 do 2 end`:

<div align="center">
  <img src="/assets/aop/part7-until-node.svg" alt="until node">
</div>

The `until` keyword can also be used as the modifier on a `begin` block. Here's an example:

```ruby
begin
  foo
end until bar
```

As with `while`, this will execute the body of the loop once before checking the predicate. If the predicate is falsy, the loop will continue to execute. If it is truthy, the loop will terminate. Here's what the AST looks like for `begin 1 end until 2`:

<div align="center">
  <img src="/assets/aop/part7-until-node-2.svg" alt="until node begin modifier">
</div>

### `ForNode`

The `for` keyword in Ruby can be used to construct a for loop. These loops effectively break down to calling `.each` on the collection expression, with the index expression being used as the block parameter(s). There are a couple of small nuances however. First, here are some examples of it in Ruby code:

```ruby
for i in 1..10
  puts i
end

for j in k do l end
```

This code is _almost_ equivalent to `(1..10).each { |i| puts i }` except that for the `for` loop the iteration variable (`i` in the first case) is added to the current scope (as opposed to a block where it would be added to the block scope). This means that the `for` loop can be used to mutate variables in the current scope, and also introduce variables to the current scope. For example, if you were to access the `i` local variable after the loop, it would have the value of `10`.

As with `while` and `until`, there is the single-line version available via the `do` keyword. This is the required terminator, which can also be a newline or semicolon. Here's what the AST looks like for `for i in 1..10 do puts i end`:

<div align="center">
  <img src="/assets/aop/part7-for-node.svg" alt="for node">
</div>

There's a lot going on here, but most of it involves concepts we're already familiar with. The two we aren't are the `LocalVariableTargetNode` and the `CallNode`. I'll ask you to, for now, pretend you haven't seen them. Rest assured, we'll be coming back to these soon.

## Conditionals

Where loops iterate until a certain condition is met, conditionals execute a certain branch only once based on a condition. Ruby has a few different conditional constructs, and we'll be looking at each of them in turn.

### `IfNode`

The `if` keyword can be used to construct a conditional. Here are some examples in Ruby code:

```ruby
if foo
  bar
end

if foo then bar end

bar if foo
```

As with the loops, all three of these examples are semantically equivalent. First, the predicate will be checked. If it is truthy, the body of the conditional will be executed. If it is falsy, the body of the conditional will be skipped.

Also as with loops, the predicate must be followed by a terminator. For conditionals, that means the `then` keyword, a semicolon, or a newline. Here's what the AST looks like for `if 1 then 2 end`:

<div align="center">
  <img src="/assets/aop/part7-if-node.svg" alt="if node">
</div>

The `if` keyword can also be used as the modifier to a pattern matching expression on an `in` clause. We'll cover that functionality when we get to pattern matching, but for now here's an example:

```ruby
case foo
in 1 if bar
  baz
end
```

### `UnlessNode`

The `unless` keyword is the opposite of the `if` keyword, i.e., it executes a conditional if the given expression is falsy. Here are some examples in Ruby code:

```ruby
unless foo
  bar
end

unless foo then bar end

bar unless foo
```

All of these examples are semantically equivalent. Here's what the AST looks like for `unless 1 then 2 end`:

<div align="center">
  <img src="/assets/aop/part7-unless-node.svg" alt="unless node">
</div>

The `unless` keyword can also be used in pattern matching. Again, we'll just show the code here and revisit it when we get to pattern matching. Here's an example:

```ruby
case foo
in 1 unless bar
  baz
end
```

### `ElseNode`

The `else` keyword can be used as an alternative branch for the `if` and `unless` keywords. Here are some examples in Ruby code:

```ruby
if foo
  bar
else
  baz
end

if foo then bar else baz end

unless foo
  bar
else
  baz
end

unless foo then bar else baz end
```

In the examples we saw before, statements were entirely skipped if conditions weren't met. In these examples the statements within the `else` clause are executed instead. Here's what the AST looks like for `if 1 then 2 else 3 end`:

<div align="center">
  <img src="/assets/aop/part7-else-node.svg" alt="else node">
</div>

Note that the `else` keyword also shows up in `case` statements and `begin` statements. We'll cover those in their respective sections and posts. For now, here are some examples:

```ruby
# case-when statements
case foo
when bar
  1
else
  2
end

# case-in statements
case foo
in bar
  1
else
  2
end

# begin statements
begin
  foo
rescue
  bar
else
  baz
end
```

### Chaining

As we've seen with the `else` keyword, conditionals can be chained together. The `unless` keyword only supports a single `else` clause as the consequent clause, but the `if` keyword supports an arbitrary number of `elsif` clauses. Here's an example:

```ruby
if foo
  1
elsif bar
  2
elsif baz
  3
else
  4
end
```

Here's what the AST looks like for `if 1 then 2 elsif 3 then 4 else 5 end`:

<div align="center">
  <img src="/assets/aop/part7-elsif-node.svg" alt="elsif node">
</div>

You'll notice that the `elsif` keyword is represented using the `IfNode` node. This is because they are semantically equivalent: check the predicate and either execute the statements or skip them. In designing this part of the AST, we had to determine if we wanted a linked list (like you see above) or if wanted a flat list of conditions to check. Ultimately we decided to go with the linked list because it's rare that you would find a conditional with more than a few `elsif` clauses. Usually they end up being replaced with a `case` statement instead, which is what we'll look at next.

### Ternaries

There is one more conditional construct that we haven't looked at yet: the ternary expression. This is a special way of constructing `if`/`else` conditionals that can be used in a single expression. Here's an example:

```ruby
foo ? bar : baz
```

This is semantically equivalent to:

```ruby
if foo
  bar
else
  baz
end
```

This is another example of syntax sugar. You can already express this code using the keywords, but the ternary is a more terse form. Here's what the AST looks like for `1 ? 2 : 3`:

<div align="center">
  <img src="/assets/aop/part7-ternary-node.svg" alt="ternary node">
</div>

You'll notice that it only contains constructs we've already seen. The tree maintains enough information that consumers can determine if it's a ternary however: the `then_keyword_loc` points to the `?` token and the `else_keyword_loc` points to the `:` token. Furthermore the `if_keyword_loc` is `nil`.

### `CaseNode`

The `case` keyword can be used to construct three different things: a set of comparisons against a single value (the most common), an `elsif` chain like the one we saw above (less common), or a pattern matching expression. We'll look at the first two here, and the third when we get to pattern matching. Here's the first example in Ruby code:

```ruby
case foo
when bar
  1
when baz
  2
else
  3
end
```

This statement is semantically equivalent to a series of `if` statements that all compare against the single value. It would look something like:

```ruby
tmp = foo

if bar === tmp
  1
elsif baz === tmp
  2
else
  3
end
```

Note that the conditions all break down to `#===` method calls, meaning you can define your own custom logic for how the comparisons are made. Here's what the AST looks like for `case 1 when 2 then 3 when 4 then 5 else 6 end`:

<div align="center">
  <img src="/assets/aop/part7-case-node.svg" alt="case node">
</div>

You can see from the diagram above that we went with a flat list for the `when` clauses. We did this because it's significantly easier to process than a linked list, and it's fairly common to have a lot of them on a single `case` statement. The `else` clause is optional, and only gets executed if none of the other conditions match.

The second example of a `case` statement is when the predicate is dropped. This is the equivalent of an `elsif` chain. Here's an example:

```ruby
case
when foo
  1
when bar
  2
else
  3
end
```

This is semantically equivalent to:

```ruby
if foo
  1
elsif bar
  2
else
  3
end
```

Here's what the AST looks like for `case when 1 then 2 when 3 then 4 else 5 end`:

<div align="center">
  <img src="/assets/aop/part7-case-node-2.svg" alt="case node without value">
</div>

Notice that the `CaseNode` has no slot for the `predicate` in the diagram above. This represents the difference between the two forms. The design of this type of `case` statement is definitely a tradeoff. We could have gone with a different node; the semantics of the two forms are different enough to warrant it. CRuby represents them as different nodes, the [parser](https://github.com/whitequark/parser) gem doesn't. As with the other tradeoffs we've discussed, it makes it easier on some consumers (in this case linters/formatters) and more difficult on others (in this case interpreters/compilers). We may change this in the future, depending on how we see the community using the AST.

### `WhenNode`

The `when` keyword is part of the `case` statement AST, as we just saw. It can be slightly more complicated however. First, here are some more examples that show some of the additional complexity:

```ruby
case foo
when bar, baz
  1
when *qux
  2
when -> (value) { quux?(value) }
  3
when quuz... then
  4
end
```

In general the `when` clause accepts a comma-separated list of expressions that resolve to objects that should respond to the `#===` method. Each `,` delimits another expression. In the example above, here are the things we want to point out, in order:

1. The `bar` and `baz` expressions are separated by a comma. This means that the `when` clause will match if either of them match the predicate. Both will be checked, sequentially.
2. The `*qux` expression is a splat expression. This means that the `when` clause will match if any of the elements in the `qux` array match the predicate. Each element will be checked, sequentially.
3. The `-> (value) { quux?(value) }` expression is a lambda expression. This means that the `when` clause will match if the lambda returns a truthy value when called with the predicate. This works because `Proc` responds to `#===` by calling itself with the argument.
4. The `quuz...` expression is a range expression. This means the range object will have `#===` called on it, which will check for inclusion. The `then` keyword after is optional for most `when` clauses, but necessary in this case to delimit the statements of the `when` clause from the range itself.

## `FlipFlopNode`

The last control-flow construct we're going to look at today is the `flip-flop` operator. This is a special operator that allows you to create a conditional that is only true between two expressions within the predicate of a conditional. Here's an example in Ruby code:

```ruby
(1..10).each do |i|
  if i == 5 ... i == 8
    puts i
  end
end
```

The above code will output `5\n6\n7\n8\n`. It uses a hidden state variable to store the current state of the flip-flop. The state is set to true the first time the left-hand expression is evaluated to a truthy value and turned off the first time the right-hand expression is evaluated to a truthy value. Here's what the AST looks like for `1 if 2 ... 3`:

<div align="center">
  <img src="/assets/aop/part7-flip-flop-node.svg" alt="flip flop node">
</div>

Note that either the `..` or `...` operators can be used, which mirror the exclusive and inclusive range operators. This is indicated by the `exclude_end` flag.

Within an `if` or `unless` predicate are the more obvious places a flip-flop can show up, but there are a couple of eccentricities that allow it in other places as well. First, it can be nested within and `AndNode`/`OrNode` within the predicate, as in:

```ruby
if foo && bar ... baz
  qux
end
```

This can nest infinitely, and even allow for more than one flip-flop in the same predicate. The second eccentricity is that it can be used as the expression passed to the `not` keyword, as in:

```ruby
not foo .. bar
```

This breaks down to calling the `!` method on the result of the flip-flop expression, which is always either `true` or `false`. This can lead to horrible code if you combine it with monkey-patching `TrueClass`, but I'll leave that as a thought experiment for you.

### Design

Initially, we used a `RangeNode` to represent flip-flop expressions, with an additional flag to say "this is a flip-flop". Syntactically, they are identical, so it made a certain amount of sense. For a consumer like a linter or formatter, it might end up being easier to reason about since there would be fewer nodes. However, this was enough of a headache for interpreters and compilers that we ended up splitting the node in this way. This holds to our code design principle of not needing to check fields/child nodes to determine how to compile the current node.

## Wrapping up

Whew, we made it. That was a lot of nodes. Understanding control-flow is important to get a good mental model of how Ruby is going to execute your code. It's also important to understand how the AST represents it so that you can write tools that work with it. Here are a couple of things to think about:

* A lot of expressions have optional keywords that allow them to be expressed in a single line. This is nice for command-line scripting.
* It's worth mentioning again: if two expressions are syntactically different but represent the same semantics, they can and should be represented by the same node in the AST.
* Flip-flops are wild.

Next time, we'll close out our discussion of writing to variable by talking about a family of nodes that we call "target" nodes.
