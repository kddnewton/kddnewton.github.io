---
layout: post
title: Advent of Prism
subtitle: Part 0 - Introduction
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 0"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

Two and a half years ago, I began working on what is today known as the [prism](https://github.com/ruby/prism) Ruby parser. This is a new Ruby parser that is now being integrated into runtimes and tooling alike. This includes [CRuby](https://github.com/ruby/ruby), [JRuby](https://github.com/jruby/jruby), [TruffleRuby](https://github.com/oracle/truffleruby), [Natalie](https://github.com/natalie-lang/natalie), [Syntax Tree](https://github.com/ruby-syntax-tree/syntax_tree-prism), [RuboCop](https://github.com/kddnewton/parser-prism), and many others.

Over that time period, I've learned just about everything there is to know about Ruby syntax and how it translates to executed code. I would like to share that knowledge with you in a series of blog posts that I'm calling "Advent of Prism". This will be 24 posts, one for each day of December leading up to Christmas. Each post will cover a different set of nodes in the prism syntax tree, as well as relevant details about Ruby execution as they come up. At the end of the series, you will come away having at least seen every possible variation of Ruby syntax, and hopefully you will come away with an appreciation for the power of this incredibly expressive grammar.

Before we get started, I want to say a couple of thank-yous. First and foremost, everyone on my team at Shopify but especially [Jemma Issroff](https://jemma.dev/about-me/), [Aaron Patternson](https://tenderlovemaking.com/), and [Matt Valentine-House](https://www.eightbitraptor.com/). Working with these lovely folks every day has made slogging through the Ruby grammar significantly more fun. Second, to the many people I've gotten to work with through their own projects that are integrating prism, namely [Tom Enebo](http://blog.enebo.com/), [Benoit Daloze](https://eregon.me/blog/), and [Tim Morgan](https://timmorgan.dev/), thank you for your patience, feedback, and expertise. Third, to the many contributors to the prism project, but especially those at GitHub who have decidedly saved us from many headaches by successfully taking on many challenging issues including [Adam Hess](https://hparker.xyz/) and [Haldun Bayhantopcu](https://github.com/haldun). Finally, to you, the reader, thank you for taking the time to read this series. I hope you find it as fun to read as I have found it to write.

Links to the individual blog posts will appear here as they are published, so feel free to bookmark this particular page and come back to it as the series progresses, or really whenever you please.

* [Part 1 - Literals](/2023/12/01/advent-of-prism-part-1)
* [Part 2 - Data structures](/2023/12/02/advent-of-prism-part-2)
* [Part 3 - Reads](/2023/12/03/advent-of-prism-part-3)
* [Part 4 - Writes](/2023/12/04/advent-of-prism-part-4)
* [Part 5 - Operator writes](/2023/12/05/advent-of-prism-part-5)
* [Part 6 - Control-flow writes](/2023/12/06/advent-of-prism-part-6)
* [Part 7 - Control-flow](/2023/12/07/advent-of-prism-part-7)
* [Part 8 - Target writes](/2023/12/08/advent-of-prism-part-8)
* [Part 9 - Strings](/2023/12/09/advent-of-prism-part-9)
* [Part 10 - Regular expressions](/2023/12/10/advent-of-prism-part-10)
* [Part 11 - Defined](/2023/12/11/advent-of-prism-part-11)
* [Part 12 - Program structure](/2023/12/12/advent-of-prism-part-12)
* [Part 13 - Calls (part 1)](/2023/12/13/advent-of-prism-part-13)
* [Part 14 - Calls (part 2)](/2023/12/14/advent-of-prism-part-14)
* [Part 15 - Call arguments](/2023/12/15/advent-of-prism-part-15)
* [Part 16 - Control-flow calls](/2023/12/16/advent-of-prism-part-16)
* [Part 17 - Scopes](/2023/12/17/advent-of-prism-part-17)
* [Part 18 - Parameters](/2023/12/18/advent-of-prism-part-18)
* [Part 19 - Blocks](/2023/12/19/advent-of-prism-part-19)
* [Part 20 - Alias and undef](/2023/12/20/advent-of-prism-part-20)
* [Part 21 - Throws and jumps](/2023/12/21/advent-of-prism-part-21)
* [Part 22 - Pattern matching (part 1)](/2023/12/22/advent-of-prism-part-22)
* [Part 23 - Pattern matching (part 2)](/2023/12/23/advent-of-prism-part-23)
* [Part 24 - Error tolerance](/2023/12/24/advent-of-prism-part-24)

## Exploring

As the blog series progresses you'll see me exploring prism, but also other parsers and tools along the way. I encourage you to explore on your own as well, the best way to learn something like this is through your own experimentation. Below are a couple of ways to get started:

### ruby/prism

First, `gem install prism` or add `prism` to your Gemfile and `bundle install`. Next, in IRB:

```ruby
require "prism"
Prism.parse("1 + 2").value
```

### ruby/ruby (parse tree)

In a terminal:

```bash
ruby --dump=parsetree -e "1 + 2"
```

### ruby/ruby (ripper)

In IRB:

```ruby
require "ripper"
Ripper.sexp("1 + 2")
```

### whitequark/parser

First, `gem install parser` or add `parser` to your Gemfile and `bundle install`. Next, in a terminal:

```bash
ruby-parse -e "1 + 2"
```

### seattlerb/ruby_parser

First, `gem install ruby_parser` or add `ruby_parser` to your Gemfile and `bundle install`. Next, in IRB:

```ruby
require "ruby_parser"
RubyParser.new.parse("1 + 2")
```

### ruby-syntax-tree/syntax_tree

First, `gem install syntax_tree` or add `syntax_tree` to your Gemfile and `bundle install`. Next, in a terminal:

```ruby
stree ast -e "1 + 2"
```

## Glossary

This series explores a parser and its associated syntax tree. These can be somewhat difficult to understand. As such, there are many terms that are used to describe different aspects of the parser's execution and structure. I'll try to define them here as I reference them in various posts here so that you can come back here to look them up if you're not familiar with them or if you forget.

Prism
: A new portable, maintainable, and error-tolerant parser written for Ruby.
