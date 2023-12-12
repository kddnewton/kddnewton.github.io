---
layout: post
title: Advent of Prism
subtitle: Part 21 - Throws and jumps
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 21"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about throws and jumps.

The terms "throw" and "jump" have more to do with the actual execution of Ruby than the parse tree, but they neatly categorize the nodes that we're going to look at today.

## Throws

"Throw" refers to throwing an exception. CRuby implements many of these using `setjmp`/`longjmp`, which are context-saving functions that allow you to break the execution flow of your C program much like you would with exceptions in Ruby. Ruby provides a couple of syntactic structures for handling these kinds of non-local control flow.

### `BeginNode`

The parent node of any kind of exception handling is the `BeginNode` node. This node houses an optional set of statements as well as any number of `rescue` clauses, an optional `ensure` clause, and an optional `else` clause. Here is an example:

```ruby
begin
  1
rescue
  2
end
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part21-begin-node.svg" alt="begin node">
</div>

You can see the node has a `statements` field that is the optional `StatementsNode` holding the statements that should be executed. It also has a pointer to a `rescue` node that is the first `rescue` clause. If there are more `rescue` clauses, they are linked together in a linked list. The `ensure` and `else` clauses are not present in this example so you don't see their fields.

Remember from our previous posts that this node is also used to represent `rescue`/`else`/`ensure` clauses being used in other contexts: class and module definitions, singleton class definitions, method definitions, and blocks and lambdas that use `do`/`end`.

### `RescueNode`

When the `rescue` keyword is used as another clause in a `begin` statement, we represent it with the `RescueNode` node. This node has a list of exceptions to rescue, an optional variable to assign the exception to, an optional set of statements, and an optional consequent `rescue` clause. Here is an example that showcases all of that:

```ruby
begin
  foo
rescue Exception1 => error
  warn error.message
rescue Exception2, Exception3 => @error
rescue *exception_list
rescue
  warn "unknown error"
end
```

The actual flow of this program works like this:

1. `foo` is called.
2. If `foo` raises an error, Ruby walks through the `rescue` clauses in order.
3. In the first `rescue` clause, the `Exception1` constant is looked up. If it does not contain a class or module, a `TypeError` is raised. If it does, then it checks if it is in the ancestor chain of the exception that was raised. If it is, then the exception is assigned to the `error` local variable and the statements in the clause are executed. If it is not, then the error is reraised to trigger checking the subsequent clause.
4. In the second `rescue` clause, both the `Exception2` and `Exception3` variables are checked in the same manner. If either of them are in the ancestor chain of the exception that was raised, then the exception is assigned to the `@error` instance variable. Because there are no statements in this clause, nothing else happens. If neither of them are in the ancestor chain, then the error is reraised to trigger checking the subsequent clause.
5. In the third `rescue` clause, `exception_list` has `#to_a` called on it and then Ruby iterates over each element in the resulting array to check for classes or modules in the same as the other exceptions. If any of them are in the ancestor chain, the code jumps out of the `begin` node. Otherwise the error is reraised to trigger checking the subsequent clause.
6. In the last `rescue` clause the error is implicitly checked against `StandardError`. If it is in the ancestor chain, then the body of the clause is executed. Otherwise the error is reraised.

A couple of important things to note here in terms of syntax:

* The optional error handle is any target that we have seen so far, including call targets. This means you can have the error handle actually be a method call if you want.
* The list of errors is a comma-separated list of (optionally splatted) expressions, not just constants. This is very powerful, but also a source of confusion. Remember that constant lookup itself can trigger method calls (through `const_missing`) so this can get quite dynamic.
* If you omit any classes or modules to check against, Ruby implicitly checks against `StandardError`.

Let's look at a slightly simpler example to see how this is represented in the AST:

```ruby
begin
rescue Error1 => error
rescue Error2
  warn("error")
end
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part21-rescue-node.svg" alt="rescue node">
</div>

Notice that the `RescueNode` nodes form a linked list, much like the if statements that we covered back in [Part 7 - Control-flow](/2023/12/07/advent-of-prism-part-7). As we discussed back then, the two options we have for representing these kinds of nodes is a linked list or a flat list. We went with a linked list in this case because it's not that common that you have more than a couple of `rescue` clauses, and it's simpler to implement this way.

### `RescueModifierNode`

When the `rescue` keyword is used as a modifier to an expression, we represent it with the `RescueModifierNode` node. Here's an example:

```ruby
foo rescue "error!"
```

This is semantically equivalent to:

```ruby
begin
  foo
rescue StandardError
  "error!"
end
```

The example is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part21-rescue-modifier-node.svg" alt="rescue modifier node">
</div>

This relatively simple node is deceptively complex to parse, but easy to understand and compile. The `rescue` keyword actually breaks operator precedence rules and is allowed to be used as the modifier to any assignment expression. This means that you can do things like:

```ruby
foo = bar rescue baz
```

and instead of being parsed as `(foo = bar) rescue baz`, it is parsed as `foo = (bar rescue baz)`. This special path through the parser makes things complex, but tends to better match programmers intuition.

### `EnsureNode`

The `ensure` keyword is an optional clause on the `begin` statement that is always executed, even if an exception is raised. We represent it with the `EnsureNode`. Here is an example:

```ruby
begin
  foo
ensure
  bar
end
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part21-ensure-node.svg" alt="ensure node">
</div>

Effectively this node is just a wrapper around a set of statements. It is far more complicated to implement than to parse.

### `ReturnNode`

The last throw is the `return` keyword. In normal execution, the `return` keyword can be implemented using a `leave` instruction, however you can also return from within blocks. In this case the virtual machine must jump all of the way out to the method, which is why this is a throw. First, here is an example:

```ruby
def foo
  [1, 2, 3].each do |i|
    return i if i == 2
  end
end
```

This is a little contrived, but it demonstrates the point. This code will call the `#each` method on the array literal, and when the iteration variable `i` is equal to `2`, it will return `i` from the method. This whole example is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part21-return-node.svg" alt="return node">
</div>

You can see the `ReturnNode` in the bottom right of the diagram there. It has an optional set of arguments, which are the values to return from the method. If there are multiple values, they are grouped together into an array.

## Jumps

"Jump" refers to jumping around the instructions in a program. You can think of them effectively as `goto` statements. Ruby provides many keywords for jumping around, and they all have their own nodes in the parse tree. Let's look at them one by one.

### `BreakNode`

The `break` keyword jumps out of the current block. It can optionally accept a value to return from the block as here. Here is an example:

```ruby
while true
  break 1
end
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part21-break-node.svg" alt="break node">
</div>

The code above says to immediately break out of the loop and return `1`. Any number of arguments can be passed to `break` — they end up being grouped together into an array if there are multiple. A common misconception is that `break` accepts parentheses; in reality if you use parentheses you're actually just grouping together the first argument.

### `NextNode`

The `next` keyword jumps to the end of the current block, but not out of it. Like `break`, it can optionally accept any number of values to return from the block. Here is an example:

```ruby
while true
  next 1
end
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part21-next-node.svg" alt="next node">
</div>

The code above says to immediately jump to the end of the loop and return `1`. This will actually loop indefinitely because the `next` keyword just keeps getting executed. Like `break`, `next` accepts any number of arguments, which are grouped together into an array if there are multiple.

### `RedoNode`

The `redo` keyword is effectively the opposite of the `next` keyword: it jumps back to the start of the current block. It does not accept any arguments. Here is an example:

```ruby
while true
  redo
end
```

This will, of course, loop indefinitely. Parsing this is very simple; you only parse the keyword. The node itself is therefore relatively simple as well. Here is the AST for the above snippet:

<div align="center">
  <img src="/assets/aop/part21-redo-node.svg" alt="redo node">
</div>

### `RetryNode`

The `retry` keyword is used to jump out of a `rescue` clause and back to the `begin` block. It does not accept any arguments. Here is an example:

```ruby
begin
  foo
rescue
  retry
end
```

This `retry` will get triggered if `foo` raises an exception. It will then jump back to the `begin` block and try again. This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part21-retry-node.svg" alt="retry node">
</div>

### `YieldNode`

Using the `yield` keyword, you can trigger the execution of a block that was passed to the current method. It can optionally accept any number of arguments to pass to the block. Here is an example:

```ruby
def foo
  yield 1
end
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part21-yield-node.svg" alt="yield node">
</div>

Parsing the `yield` construct is much the same as the other keywords we've looked at so far. It also accepts a list of arguments that are comma-delimited.

## Wrapping up

Throws and jumps allow you to issue non-local control flow within your program. They are very powerful constructs, and understanding their semantics will help you get a better picture of what Ruby is doing under the hood. Here are a couple of things to remember from today:

* There are many ways to represent non-local control flow in Ruby
* There is a lot of syntax that allows you to jump around statements in your program
* `break`, `next`, `yield`, and `return` all accept arguments but none of them use parentheses

We're almost at the end here! Tomorrow we'll be looking at the first of two posts on pattern matching. See you then!
