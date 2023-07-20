---
layout: post
title: Ruby operators
---

Ruby's grammar has a ton of operators. Overtimes, they can mean more than one thing, depending on their context. This blog post enumerates each operator and its meaning.

## Call operator operators

First, we have the operators that are used to call methods. These are not the names of the methods themselves, but rather specify the manner in which the method should be called. They are:

* `.` - This is the main call operator. It calls a method on the receiver, as in: `foo.bar`.
* `::` - Although this is normally used as the constant resolution operator, it can also be used to call methods in almost any place `.` can be used. For example, `foo::bar` is equivalent to `foo.bar`.
* `&.` - The "lonely" operator (so named because it looks like someone looking at their feet). Otherwise known as the safe navigation operator. This operator calls a method on the receiver if the receiver is not `nil`. Otherwise, it returns `nil`.

## Call name operators

Next, we have the operators that are the names of methods on objects. All of these operators can be used in their normal form (either as a unary or binary expression) or in their call form (like a normal method call). For example, `foo + bar` is equivalent to `foo.+(bar)`.

### Unary call name operators

* `!` - The negation operator. This operator calls the `!` method on the receiver. Note that `!@` can also be called when a call operator is used (e.g. `foo.!@`). Note that the name of this method can be either `!` or `!@` since there is no binary equivalent. The parser normalizes this difference
* `not` - An alias for the `!` method, a `not` expression breaks down to a method call to the `!` method. Other than different precedence, these are equivalent.
* `~` - The bitwise negation operator. This operator calls the `~@` method on the receiver. Note that `~@` can also be called when a call operator is used (e.g. `foo.~@`).
* `+` - This operator calls the `+` method on the receiver. This calls the `+@` method on the receiver (not to be confused with the `+` method, which accepts a single operand).
* `-` - The same thing as `+`, but for subtraction.

### Arithmetic call name operators

These operators represent what is classically considered arithmetic operations. Most of them have fast paths in the various Ruby implementations when the receiver is a numeric type. YJIT also has fast paths for all of these operators.

* `+` - The addition operator. This is usually found on numeric types, but also commonly on arrays and strings.
* `-` - The subtraction operator. This is also usually found on numeric types, but also commonly on arrays.
* `*` - The multiplication operator. Numeric types have this, as well as strings and arrays. Note that this is also the splat operator, and is found in creating arrays, delimiting how arrays should be destructured, or defining rest parameters on methods or blocks. When used to pass an object as an array, it breaks down to a call to the `to_ary` method.
* `/` - The division operator. Numeric types have this as well as pathname.
* `%` - The modulo operator. This is usually only found on numeric types.
* `**` - The exponentiation operator. This is usually only found on numeric types. This is the only one of the arithmetic operators that is right-associative. Note that this is also the keyword splat operator, and is found in creating hashes, delimiting how hashes should be destructured, or defining keyword rest parameters in methods or blocks. When used to pass an object as a hash, it breaks down to a call to the `to_hash` method.

### Bitwise call name operators

* `&` - The bitwise AND operator. This is usually only found on numeric types, but is also used on arrays for the intersection operator. Note that this is also the block operator, and is found when passing blocks to methods or defining block parameters. When used to pass an object to as a block argument, it breaks down to a call to the `to_proc` method. This operator can also be used to forward block arguments to another method when used anonymously within a method that anonymously captured a block.
* `|` - The bitwise OR operator. This is usually found on numeric types, but is also used on arrays for the union operator. Note that this is also used to delimit parameters on blocks.
* `^` - The bitwise XOR operator. This is usually only found on numeric types. It is commonly found when defining the `hash` method on objects. Note that this operator is also used to pin values for comparison in pattern matching.
* `<<` - The bitwise left shift operator. This is found on numeric types, but is more commonly used on strings and arrays.
* `>>` - The bitwise right shift operator. This is usually only found on numeric types.

### Comparison call name operators

* `==` - The equality operator. This is found on almost all types, and is used to check basic equality. Note that this is typically a less-strict version of the `eql?` method, which is used to check for strict equality.
* `!=` - The inequality operator. This is found on almost all types, and is used to check basic inequality.
* `<` - The less-than operator. This is found on numeric types, but is also found on classes and modules to check for inheritance.
* `<=` - The less-than-or-equal-to operator. This is found on numeric types, and can also be used to check for inheritance on classes and modules.
* `>` - The greater-than operator. Similar functions to the less-than operator.
* `>=` - The greater-than-or-equal-to operator. Similar functions to the less-than-or-equal-to operator.
* `<=>` - The comparison operator. This operator is used to define comparisons between two objects, often used for sorting. It is found on numeric types and strings, as well as various other types. 
* `===` - The case equality operator. This method is used as the backend for `case` statements. It is found on various types, most commonly strings, regular expressions, and classes and modules.
* `=~` - The pattern match operator. Typically this is found on regular expressions and strings.
* `!~` - The negated pattern match operator. This breaks down to a call to `=~`, which is then negated.

### Miscellaneous call name operators

* `[]` - The element reference operator. This is found on arrays, hashes, strings, numerics, and various other types. It is used to access elements of the receiver. Any number of arguments may be accepted by the grammar within the brackets, as in `foo[1, 2, 3]`.
* `` ` `` - The backtick operator. Most typically this is used to create shell commands by calling the `` Kernel#` `` method. However, you can define any backtick method that you want, and when you create a string like `` `foo` `` it will call that method.

## Assignment operators

Next, we get to the assignment operators. These operators typically break down to reading a value, performing some operation on it, and then assigning it back to the receiver. For example, `foo += 1` is equivalent to `foo = foo + 1`. However, there are a couple of exceptions.

Note that for each of these operators, the target of the expression (the expression on the left-hand side of the operator) can drastically change the semantics of the operator. The target can be any of the variable types (local, instance, class, global, constant, etc.), as well as almost any method call without arguments (e.g. `foo.bar`), or even some method calls with arguments (e.g. `foo[1]`). When the receiver is a method call, the name of the method is automatically changed by appending an `=`. For example, `foo.bar = 1` is equivalent to `foo.bar=(1)`.

* `=` - The assignment operator. This is the most common assignment operator, and is used to assign a value to a variable or constant. Note that this is also used to define default values for method or block parameters. This is the only assignment operator that does not break down to a method call. It is also the only assignment operator that can be used to assign multiple values at once, as in `foo, bar = 1, 2`.

### Arithmetic assignment operators

Similarly to the arithmetic call name operators, these operators are used to perform arithmetic operations. The result is then assigned back to the receiver.

* `+=` - The addition assignment operator.
* `-=` - The subtraction assignment operator.
* `*=` - The multiplication assignment operator.
* `/=` - The division assignment operator.
* `%=` - The modulo assignment operator.
* `**=` - The exponentiation assignment operator.

### Bitwise assignment operators

* `&=` - The bitwise AND assignment operator.
* `|=` - The bitwise OR assignment operator.
* `^=` - The bitwise XOR assignment operator.
* `<<=` - The bitwise left shift assignment operator.
* `>>=` - The bitwise right shift assignment operator.

### Miscellaneous assignment operators

* `[]=` - The element assignment operator. This is used to assign a value to an element of an array, hash, or various other types. It deserves its own mention because it is the only assignment operator that can take multiple arguments. For example, `foo[1, 2] = 3` is equivalent to `foo.[]=(1, 2, 3)`.
* `&&=` - The AND conditional assignment operator. This effectively breaks down to looking at the value of the receiver, and if it is truthy, assigning the value to the receiver. For example, `foo &&= 1` is equivalent to `foo && foo = 1`. Note that this is not a method call, and instead is more similar to a conditional expression.
* `||=` - The OR conditional assignment operator. This effectively breaks down to looking at the value of the receiver, and if it is falsy, assigning the value to the receiver. For example, `foo ||= 1` is equivalent to `foo || foo = 1`. Similar to `&&=`, this is not a method call and is more similar to a conditional expression.

## Control-flow operators

Next, we have the control-flow operators. For completeness, I've included some keywords in here that you might normally think of as statements, but in reality they function more similarly to infix operators.

### Truthiness operators

These operators are used to check the truthiness of a value.

* `&&` - The AND operator. This operator checks the truthiness of the receiver, and if it is truthy, evaluates the right-hand side of the operator. Otherwise, it returns the receiver.
* `and` - The AND operator. This is an alias for `&&` and has no difference except for within the parser.
* `||` - The OR operator. This operator checks the truthiness of the receiver, and if it is falsy, evaluates the right-hand side of the operator. Otherwise, it returns the receiver.
* `or` - The OR operator. This is an alias for `||` and has no difference except for within the parser.
* `?:` - The ternary operator. This operator checks the truthiness of the receiver, and if it is truthy, evaluates the truthy branch. Otherwise, it evaluates the falsy branch. Note that this is the only operator in this list that is right-associative.

### Conditional operators

These operators are used to perform conditional expressions.

* `if` - The if operator. This operator checks the truthiness of the predicate, and if it is truthy, evaluates the expression on the left-hand side of the operator. Note that this operator is also used as a statement and as a guard clause in pattern matching. When in a statement form, it can be followed by an `elsif` or `else` clause.
* `unless` - The unless operator. This operator checks the truthiness of the predicate, and if it is falsy, evaluates the expression on the left-hand side of the operator. Note that this operator is also used as a statement and as a guard clause in pattern matching. When in a statement form, it can be followed by an `else` clause.
* `while` - The while operator. This operator continuously checks the truthiness of the predicate, and if it is truthy, evaluates the expression on the left-hand side of the operator. Note that this operator is also used as a statement.
* `until` - The until operator. This operator continuously checks the truthiness of the predicate, and if it is falsy, evaluates the expression on the left-hand side of the operator. Note that this operator is also used as a statement.
* `rescue` - The rescue operator. This operator evaluates the expression on the left-hand side of the operator and rescues any errors that are raised that are a subclass of `StandardError`. If an error is raised, the expression on the right-hand side of the operator is evaluated and returned, otherwise the expression on the left-hand side of the operator is returned. Note that this operator is also used as a statement. When in a statement form, it can be followed by more `rescue` clauses, an `else` clause, or an `ensure` clause.

### Pattern matching operators

These operators are used to perform pattern matching.

* `in` - The match predicate operator. This operator will evaluate the left-hand side of the operator and check if it matches the pattern specified on the right-hand side of the operator. If it does, it will return `true`, otherwise it will return `false`. Note that this operator is also used as a keyword in a `for` statement or as a clause in a `case` statement that is using pattern matching.
* `=>` - The right-hand assignment operator. This operator will evaluate the left-hand side of the operator and check if it matches the pattern specified on the right-hand side of the operator. If it does not, it will raise an error. Otherwise it will return `nil`. Note that this operator is also used to specify associations in hashes as well as specifying the object that should capture errors in a `rescue` clause.

## Range operators

Finally, we get to the range operators. These operators can be used to create ranges (either inclusive or exclusive). They can also be used to create flip-flops, if the left- and right-hand side of the operator are particular kinds of expressions.

* `..` - The inclusive range operator. This operator creates an inclusive range between the left- and right-hand side of the operator. This operator can also be used to create a flip-flop.
* `...` - The exclusive range operator. This operator creates an exclusive range between the left- and right-hand side of the operator. This operator can also be used to create a flip-flop. This operator is also used to forward arguments in method calls or to denote capturing all of the parameters in a method or block declaration.

As a random bit of trivia, if an endless range is used as the final predicate to a `when` or `in` clause, then you will have to use a semicolon, the `then` keyword, or parentheses to delimit the end of the list.

## Wrapping up

That's a lot of operators! I hope you learned something and that this list comes in handy for educational purposes. If you have any questions or comments, feel free to reach out to me on Twitter [@kddnewton](https://twitter.com/kddnewton) or GitHub [kddnewton](https://github.com/kddnewton).
