---
layout: post
title: Advent of Prism
subtitle: Part 18 - Parameters
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 18"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about parameters.

Parameters appear in three locations in the prism AST: method definitions, blocks, and lambdas. There is very little difference between the three, so they are all represented with `ParametersNode`. We'll start there today.

## `ParametersNode`

When parameters to a method, block, or lambda are declared, they are represented by a `ParameterNode`. Here's an example:

```ruby
def foo(bar)
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part18-parameters-node.svg" alt="parameters node">
</div>

You can see the `ParametersNode` in the middle of the diagram above. In this case it holds a bunch of empty lists except for the list of `required` parameters, which has a single node. We'll go through each type of parameter that can be attached to this parent node in turn.

## Positional

Certain parameters are "positional" in that they are bound to a specific position in the parameter list. These are the most common types of parameters, and were the only ones (besides blocks) until keyword parameters were introduced.

### `RequiredParameterNode`

When positional parameters are declared before optionals/a rest, they are represented by a `RequiredParameterNode`. The first snippet in this post has an example of this, but to reiterate:

<div align="center">
  <img src="/assets/aop/part18-required-parameter-node.svg" alt="required parameter node">
</div>

This node also represents parameters declared after optionals/a rest. Here's an example:

```ruby
def foo(*, bar)
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part18-required-parameter-node-2.svg" alt="required parameter node">
</div>

In either of these two places, it's also possible for the required parameter to be automatically destructured. (We saw this in [Part 8 - Target writes](/2023/12/08/advent-of-prism-part-8)). Here's an example:

```ruby
def foo((bar,))
end
```

This makes use of the `MultiTargetNode` that we've already seen. The AST for this example looks like:

<div align="center">
  <img src="/assets/aop/part18-required-parameter-node-3.svg" alt="required parameter node">
</div>

When Ruby executes this code, it first accepts the argument in its normal position on the stack. It then will destructure it at the beginning of the execution of the method.

### `ImplicitRestNode`

If you look at the AST in the above diagram, you'll see a reference to an `ImplicitRestNode`. This is triggered when there is a trailing comma in a destructure list, as in the example above. It implies that the values should be spread and that the rest of the parameters should be ignored. That means the above is _almost_ equivalent to:

```ruby
def foo((bar, *))
end
```

The difference comes in blocks and lambdas, where it changes the arity. For example:

```ruby
def arity(&block) = block.arity

arity { |bar,| } # => 1
arity { |bar, *| } # => -2
```

Explaining why that is is beyond the scope of this blog post, but it's worth noting that it is a difference.

### `OptionalParameterNode`

Optional positional parameters are declared using the `=` operator after an identifier indicating the name. Here's an example:

```ruby
def foo(bar = 1)
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part18-optional-parameter-node.svg" alt="optional parameter node">
</div>

Much like destructuring, the values of these parameters are evaluated at the beginning of the method if they are not already present on the stack. They can even reference other variables in their default values (just not themselves), as in:

```ruby
def foo(bar, baz = bar)
end
```

This can get particularly confusing when combined with destructuring because the order in which things are executed can get quite weird. As an exercise, think about what `def foo((bar, baz), qux = bar); end` should do, and then try it. The answer may surprise you.

### `RestParameterNode`

Parameters can declare a "rest" parameter, which will gather up all remaining positional arguments into an array. Here's an example:

```ruby
def foo(bar, *baz)
end
```

This says to assign the first argument to `bar`, and then group the rest into an array and assign that to `baz`. This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part18-rest-parameter-node.svg" alt="rest parameter node">
</div>

You may also omit the identifier and use just the `*` operator. This does the same thing without providing you a handle to access the values. It also enables you to forward the arguments to another method, as we saw in [Part 15 - Call arguments](/2023/12/15/advent-of-prism-part-15).

## Keywords

When keyword parameters were first introduced, there was some difficulty in adoption. This was because their implementation implicitly allocated a hash underneath the hood and occasionally exposed it. Since Ruby 3, this has been solved and we have "true" keyword parameters. Let's take a look.

### `RequiredKeywordParameterNode`

Keywords can be required by not declaring a default value. That is represented using the `RequiredKeywordParameterNode` node. Here's an example:

```ruby
def foo(bar:)
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part18-required-keyword-parameter-node.svg" alt="required keyword parameter node">
</div>

This indicates the parameter `bar` is required and must be passed as a keyword argument.

### `OptionalKeywordParameterNode`

Keywords can be optional by declaring a default value. That is represented using the `OptionalKeywordParameterNode` node. Here's an example:

```ruby
def foo(bar: 1)
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part18-optional-keyword-parameter-node.svg" alt="optional keyword parameter node">
</div>

Much like optional positional parameters, the default value is evaluated at the beginning of the method if it is not already present on the stack. Default values can also reference other parameters, but not themselves.

### `KeywordRestParameterNode`

The remaining keywords that were not explicitly named can be grouped together into a hash using the `**` operator. That is represented using the `KeywordRestParameterNode` node. Here's an example:

```ruby
def foo(bar:, **baz)
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part18-keyword-rest-parameter-node.svg" alt="keyword rest parameter node">
</div>

The name can be omitted, which will still gather up the remaining keywords into a hash, but will not provide you a handle to access the values. It also enables you to forward the keywords to another method.

### `NoKeywordsParameterNode`

In terms of keyword parameters, the last one to cover is the least commonly used: `**nil`. This syntax allows you to indicate that a method accepts no keywords. We represent this with the `NoKeywordsParameterNode` node. Here's an example:

```ruby
def foo(**nil)
end
```

This yields:

<div align="center">
  <img src="/assets/aop/part18-no-keywords-parameter-node.svg" alt="no keywords parameter node">
</div>

We store this in the `keyword_rest` position to indicate that it should apply to all keywords.

## Others

### `BlockParameterNode`

When declaring that a set of parameters accepts a block, you can use the `&` operator. This is represented using the `BlockParameterNode` node. Here's an example:

```ruby
def foo(&bar)
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part18-block-parameter-node.svg" alt="block parameter node">
</div>

As with the other parameters with unary prefix operators, the name itself is optional. Omitting it will still accept a block, but will not provide you a handle to access it. It will, however, enable you to forward the block to another method call.

### `ForwardingParameterNode`

The last parameter type is the `ForwardingParameterNode`. This is created when the `...` parameter is declared within a parameter list. It indicates that all other parameters should be grouped so that they can later be forwarded. Here's an example:

```ruby
def foo(...)
end
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part18-forwarding-parameter-node.svg" alt="forwarding parameter node">
</div>

You cannot use a name for this parameter as it cannot be grouped into an object. You can only then reuse the `...` operator to forward all of the arguments to another method call. It's important to note that this is the only parameter that can only be found on method definitions, not blocks or lambdas.

## Wrapping up

Perhaps because method calls are so foundational to Ruby, parameters in Ruby are quite varied. Here are some things to remember from our overview of them:

* Destructuring parameters and assigning default values to parameters are evaluated at the beginning of a method.
* Default values for parameters can reference other parameters, but not themselves.
* `*`, `**`, and `&` can be used without names to forward arguments to another method call.

Because we talked so much about parameters today, it is only fitting that tomorrow we talk about blocks and lambdas.
