---
layout: post
title: Advent of Prism
subtitle: Part 23 - Pattern matching (part 2)
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 23"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about pattern matching.

Yesterday, we looked at the basics of pattern matching. Today we're going to close out that discussion by talking about the more advanced features: destructuring and capturing. Let's get into it.

## `HashPatternNode`

It's common to want to match against certain attributes of an object, even if they are method calls. For example, let's say we have some kind of person class:

```ruby
class Person
  attr_reader :name, :age

  def initialize(name, age)
    @name = name
    @age = age
  end
end
```

If we wanted to match against a specific name and age, we could do something like:

```ruby
person = Person.new("Kevin", 33)

if (person.name in "Kevin") && (person.age in 33)
  puts "It's Kevin!"
end
```

This gets a bit verbose if you want to match against more than just 2 values. Fortunately, Ruby has a shorthand for this: the hash pattern. It looks like this:

```ruby
case person
in { name: "Kevin", age: 33 }
  puts "It's Kevin!"
end
```

This indicates that we want to match against a hash with the keys `name` and `age`, and the values `"Kevin"` and `33` respectively. In order to get this working, we will need to implement a `deconstruct_keys` method on `Person`. That looks like:

```ruby
class Person
  def deconstruct_keys(matching_keys)
    ((matching_keys || %i[name age]) & %i[name age]).to_h do |matching_key|
      [matching_key, public_send(matching_key)]
    end
  end
end
```

With this method in place, Ruby knows how to normalize a `Person` object into a hash. In doing so, it can then perform its matching as expected. This post is meant to discuss the parser aspects of pattern matching, but first let's take a brief look into what `deconstruct_keys` is doing:

1. `#deconstruct_keys` is called whenever Ruby tries to match an object against a hash pattern
2. It is given the keys that are present in the hash pattern or `nil` if all keys should be matched
3. In our implementation, we ensure a default value of all keys and then intersect them with the known keys
4. Given we know the keys, we can then call `public_send` to get the values
5. This returns a hash of `{ name: name, age: age }` in the case that all keys are matched against

In terms of the actual syntax, every time you see a hash pattern you can know that `#deconstruct_keys` is going to be called on the match object before any matching occurs. This is significantly different from other patterns we have seen which do not usually trigger method calls on the object iself.

For the hash pattern itself, there are a couple of variations. Here are some examples:

```ruby
case person
in Person[name: "Kevin"]               # (1)
in Person(age: 33)                     # (2)
in { name: /Kevin/ }                   # (3)
in age: Integer                        # (4)
in Person[**attributes]                # (5)
in Person[**nil]                       # (6)
in Person[name: Person[name: "Kevin"]] # (7)
end
```

We'll talk about each of these in turn:

1. You can optionally attach a constant path to a hash pattern which will first check the constant to see if it matches the class of the object using the `#===` method.
2. You can use `[]` or `()` to surround the attributes of the hash pattern after a constant.
3. Keys in hash patterns must always be symbol labels but values can be any object that could be used in a pattern match.
4. The braces can be omitted on hash patterns in most cases.
5. You can use the double splat operator to capture all remaining keys in a hash pattern. This will assign them to a local variable if a name is present.
6. You can use the double splat operator with `nil` to match against empty hashes.
7. You can nest hash patterns inside of other patterns as the values of keys.

Let's simplify the example first:

```ruby
person in Person[name: "Kevin"]
```

So that we can look at the AST:

<div align="center">
  <img src="/assets/aop/part23-hash-pattern-node.svg" alt="hash pattern node">
</div>

You can see we have pointers to the optional constant as well as the list of elements within the hash pattern to match against.

## `ArrayPatternNode`

Normalizing to a hash is common, but sometimes objects more closely resemble arrays. For example, let's say we have a `Point` class:

```ruby
class Point
  attr_reader :x, :y

  def initialize(x, y)
    @x = x
    @y = y
  end
end
```

We can match against this class using an array pattern:

```ruby
case point
in Point[5, 6]
  puts "found!"
end
```

This will call `#deconstruct` on the `Point` object, which must return an array. This is then matched against the array pattern. This method looks like:

```ruby
class Point
  def deconstruct
    [x, y]
  end
end
```

Note that unlike `#deconstruct_keys` there is no argument to `#deconstruct`, so there is no way to limit the size of the resulting array in the case that only a couple of values are matched.

Most of the varieties of hash patterns also apply to array patterns as well. Here are some examples:

```ruby
case point
in Point[5, *]        # (1)
in Point(5, *)        # (2)
in [5, 6]             # (3)
in 5, 6               # (4)
in [Integer, Integer] # (5)
in [5, [6, 7]]        # (6)
end
```

We'll talk about each of these in turn:

1. You can use the splat operator to capture all remaining elements in an array pattern. This will assign them to a local variable if a name is present.
2. You can use `[]` or `()` to surround the elements of the array pattern.
3. You do not have to match against a constant, you can match instead directly against an array.
4. You can omit the surrounding `[]` on array patterns in most cases.
5. You can use any pattern as an element of an array pattern. The value will always be matched with the `#===` method.
6. You can nest array patterns inside of other patterns as the elements of the array.

Simplifying our match a bit:

```ruby
point in Point[5, 6]
```

Let's take a look at the AST:

<div align="center">
  <img src="/assets/aop/part23-array-pattern-node.svg" alt="array pattern node">
</div>

You can see that this is split up in much the same way as a multi target node where we have a list of `requireds`, `posts`, and an optional slot for `rest`. Note that it is only possible to use a single splat operator in an array pattern.

## `FindPatternNode`

There is another way of matching against arrays that allows you to search for specific elements. This is called the find pattern. It looks like this:

```ruby
integers in [*, 5, *]
```

This will return `true` if the array contains the value `5` at any position. We represent this kind of pattern with a `FindPatternNode`. Let's take a look at the AST:

<div align="center">
  <img src="/assets/aop/part23-find-pattern-node.svg" alt="find pattern node">
</div>

Note that all of the syntactic variations of the array pattern also apply here to the find pattern. The splats on the left and right of the pattern are required, and may optionally have names. The list of values in the middle can have as many sub patterns as you want.

## Local variable targeting

As we mentioned yesterday, reading local variables in patterns involves the use of the `^` operator. Writing local variables, on the other hand, involves only the name of the local variable. For example:

```ruby
foo in bar
```

In this pattern match we are assigning the value of `foo` to the local variable `bar`. Here's the AST for this example:

<div align="center">
  <img src="/assets/aop/part23-local-variable-target-node.svg" alt="local variable target node">
</div>

This gets much more powerful when combined with all of the other patterns we have learned about so far. For example, if you combine pinning, local variable targeting, and a find pattern, you can do:

```ruby
integers in [*, value, ^(value + 1), *]
```

This will check within the array for a value that is followed by a value that is 1 greater than it. If it finds one, it will assign the value to the local variable `value` and return `true`. Here's the AST for this example:

<div align="center">
  <img src="/assets/aop/part23-local-variable-target-node-2.svg" alt="local variable target node">
</div>

As you can see, pattern matching can get quite complex quite quickly.

## `CapturePatternNode`

Writing to a local variable is very nice, especially when you want to use that value later. However, using this syntax does not allow you to pattern matching the value you are about to write. That is where the `=>` operator comes into play. Note that this is a different operator from the hash key/value pair delimiter _and_ a different operator from the operator that triggers pattern matching in the first place.

Let's take a look at an example:

```ruby
person in Person[age: Integer => age]
```

In this example, we are matching against a `Person` object with an `age` key that is an `Integer`. If we find a match, we will assign the value of the `age` key to the local variable `age`. Here's the AST for this example:

<div align="center">
  <img src="/assets/aop/part23-capture-pattern-node.svg" alt="capture pattern node">
</div>

Note that only local variables can be written this way. Local variables at different depths _can_ be written, though, so something like this is possible:

```ruby
age = 30
self.then { person in Person[age: Integer => age] }
```

This is somewhat contrived, but it demonstrates that you can assign to an already existing local variable.

## Wrapping up

Today we looked at the more powerful features of pattern matching: destructuring and capturing. Here are the main takeaways:

* Ruby allows you to define your own normalization functions named `#deconstruct` and `#deconstruct_keys` to form arrays and hashes, respectively from your objects to match against.
* The argument to `#deconstruct_keys` can be `nil`. In this case, all keys will be matched against.
* You can write to local variables by simply listing the name of the local variable.
* You can match against _and_ capture the value of a field in a match by using the `=>` operator.
* The `=>` operator is very overloaded.

Believe it or not, we only have a single node left in our tree. We'll talk about it tomorrrow. See you then!
