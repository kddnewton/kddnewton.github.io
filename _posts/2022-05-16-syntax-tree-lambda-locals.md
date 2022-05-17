---
layout: post
title: Syntax Tree and lambda-local variables
---

I just released version `2.6.0` of Syntax Tree. Along with a couple of other changes, this includes support for lambda-local variable declarations. This was a bit of a journey, so I thought I'd write up how I discovered this syntax, how I added support for it to Syntax Tree, and go ahead and plug Syntax Tree one more time as something that should be merged into Ruby core.

If you want to skip straight to the code, here's the [pull request](https://github.com/ruby-syntax-tree/syntax_tree/pull/84/files).

## lambda-local variables

What are lambda-local variables? (Side note: I have no idea if that's the correct terminology. I might be making it up.) You _may_ be familiar with block-local variables. If you're not don't worry about it — you're certainly not the only one. I'll introduce both quickly. First, let's look at the syntax for block-local variables:

```ruby
double = 10

[1, 2, 3].each do |single; double, triple|
  double = single * 2
  triple = single * 3

  p [single, double, triple]
end

p double # => 10
```

What is going on here? It turns out that _after_ all of the regular parameter declarations on blocks, you can use a semicolon to indicate that you want to declare block-local variables. Those variables are exclusively scoped to the block, and will not effect variables declared outside the block (notice that printing the `double` variable after the block shows us it has its initial value).

You can do the same thing with lambda literals. For example, if we were to do the same kind of thing as the above example:

```ruby
double = 10

perform = ->(single; double, triple) do
  double = single * 2
  triple = single * 3

  p [single, double, triple]
end

[1, 2, 3].each(&perform)

p double # => 10
```

I've never actually seen someone use this feature. You probably haven't either. That's okay, that's not actually what this post is about.

## Discovery

Lately, I've been working on translating Syntax Tree's AST into other Ruby ASTs in my [ruby-syntax-tree/syntax_tree-translator](https://github.com/ruby-syntax-tree/syntax_tree-translator) project. This project has a lot of different uses, not all of which I'm ready to share just yet.

In the translator project's test suite, I pull in the tests for [whitequark/parser](https://github.com/whitequark/parser) and [seattlerb/ruby_parser](https://github.com/seattlerb/ruby_parser). I do this so that I can assert that my translated tree when translated matches their expected tree when parsed. When doing this, I noticed a lot of interesting differences with the parsers. One of the things that stood out from this list was an entire class of failures involving lambda-local variables.

Since Syntax Tree is based on ripper, I was surprised to find that there was syntax that it didn't handle. Only issue was, this was irrefutable evidence that it didn't. Both the `parser` and `ruby_parser` gems were showing me their ASTs, and they both had references to these locals (I also learned because of this that they're sometimes called shadow variables).

## Support

Because [Syntax Tree](https://github.com/ruby-syntax-tree/syntax_tree) is a syntax tree and formatter for the Ruby language, it necessarily has to support every kind of syntax in the language. This includes so many things that most folks will never use. But to be correct, it's all or nothing. So, in that spirit, I went about adding support for lambda-local variables.

I know from exhaustively looking at ripper classes that ripper didn't support this out of the box, otherwise I would have seen it. This meant going into `parse.y` and finding the specific production rule to edit. Fortunately, the [pull request](https://github.com/ruby/ruby/pull/5801/files) wasn't so bad. I'm not going to go into this pull request too much, but if you're interested in learning more check out my post on [how ripper works](/2022/02/14/formatting-ruby-part-1.html).

Now that I know Ruby will eventually support it, I needed to support it in Syntax Tree for all of the existing versions. The first step was going to be to add support for the new event once it gets into ripper. That itself is not so bad, and looks like most of the other ripper event handlers in Syntax Tree:

```ruby
# :call-seq:
#   on_lambda_var: (Params params, Array[ Ident ] locals) -> LambdaVar
def on_lambda_var(params, locals)
  location = params.location
  location = location.to(locals.last.location) if locals.any?

  LambdaVar.new(params: params, locals: locals || [], location: location)
end
```

This first determines its location by looking at its children, the instantiates a new node. Not so bad. This will work in versions going forward. However, to support previous versions, we're going to need to parse the code ourselves without the help of the parser generator.

## Parsing

In order to write our own parser, we're going to need the tokens first. Fortunately, ripper ships with `Ripper.lex`, which will provide those tokens. If you lex the source for an example in the console, you'll get the following output:

```ruby
Ripper.lex("->(; local) {}")
=> 
[[[1, 0], :on_tlambda, "->", ENDFN],                    
 [[1, 2], :on_lparen, "(", BEG|LABEL],                  
 [[1, 3], :on_semicolon, ";", BEG],                     
 [[1, 4], :on_sp, " ", BEG],                            
 [[1, 5], :on_ident, "local", CMDARG],                  
 [[1, 10], :on_rparen, ")", ENDFN],                     
 [[1, 11], :on_sp, " ", ENDFN],                         
 [[1, 12], :on_tlambeg, "{", BEG],                      
 [[1, 13], :on_rbrace, "}", END]]   
```

The first column is a tuple of line and column information. The second is the type of token. The third is the actual value. The fourth is the lexer state when it hit that token. Since we now have the tokens, we'll need to write a little parser. Fortunately, this parser can be relatively simple and modeled as a state machine.

First, we're going to set an initial state. If we've found a semicolon, then we have to find an item first. (You can't do `->(;) {}`.) So we'll say our initial state is `:item`. From there, if we hit an `:on_ident` token, then we've received our item and we can transition to a new state. This new state should either look for an `:on_comma` (to indicate another local is present) or an `:on_rparen` to indicate we've hit the end of the list. Favor in a couple of whitespace events like `:on_sp` and we've got ourselves a state machine. The machine itself is described in ASCII art below:

```
    ┌────────┐               ┌────────┐                ┌─────────┐
    │        │               │        │                │┌───────┐│
──> │  item  │ ─── ident ──> │  next  │ ─── rparen ──> ││ final ││
    │        │ <── comma ─── │        │                │└───────┘│
    └────────┘               └────────┘                └─────────┘
       │  ^                     │  ^
       └──┘                     └──┘
   ignored_nl, sp              nl, sp
```

The reason we have to do this validation is that you can actually have a semicolon in a couple of places within those parentheses, and we need to make sure we're parsing the correct pattern. For example:

```ruby
-> (param = (1; 2)) {}
```

While this is a bit contrived, if we didn't have our state machine we would choke on this input because it would see the `;` and attempt to parse lambda-locals immediately afterward.

With that, we're done! We can map all of the `:on_ident` tokens into `SyntaxTree::Ident` nodes and pretend like it came in through the future `on_lambda_var` method. When we eventually drop support for `3.1` in 2025, we can remove all of this extraneous code.

## Syntax Tree

I want to take just a second to talk about why an object layer above the AST is so valuable. Ruby core understandably doesn't want to commit to an AST structure. The logic is that it's too easy to get pinned into supporting a structure that you want to change. I understand this argument, and sympathize with its intention. I certainly wouldn't want to lay more work on an already overburdened team of dedicated individuals.

However, Syntax Tree can ease that burden by providing this abstraction. I can release this new version of Syntax Tree outside the release cycle of Ruby to fix this for consumers of the AST. If there are breaking changes, folks can continue to use old versions of the gem. The actual change that's occurring within Syntax Tree that could potentially impact folks boils down to:

* `SyntaxTree::Lambda`'s `params` field is now a `LambdaVar | Paren` as opposed to a `Params | Paren`.
* `on_lambda_var` should be added to any visitors attempting to visit every node.

That's a pretty small surface area for such a big change. Even though a lot of stuff had to change in the parser, not much has to change in the object layer. Just food for thought.

## Wrapping up

I really enjoyed this deep-dive into Ruby syntax. It was nice to be able to put my skills to the test and work on fixing up ripper's behavior. I hope you can see from this post how this is possible!
