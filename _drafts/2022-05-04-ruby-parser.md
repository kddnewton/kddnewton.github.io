---
layout: post
title: The Case for a New Ruby Parser
---

I strongly believe the time has come to rewrite the CRuby parser. In this post I'm going to talk a bit of the history around parser Ruby code, I'm going to talk a bit about the current state of parsing Ruby code, and I'm going the lay out the reasons why I think the parser should be rewritten.

## History

First, a bit of history. I already [gave a talk](https://youtu.be/lUIt2UWXW-I) about the history of parsing Ruby, which you're more than welcome to watch. You can also check out the [accompanying website](https://kddnewton.com/parsing-ruby/) I built to show how the parser has changed over time. I'll repeat a couple of things here and lay them out in a slightly different way to give a little more context to what writing a new parser would look like.

### The CRuby parser

In late 1993, Matz released version `0.01` of Ruby. At the time, he used the [Yacc](https://en.wikipedia.org/wiki/Yacc) parser generator to build the parser. This would be the parser generator that would be extended and used up through the release of `1.9` a whole 14 years later when it switched to [GNU Bison](https://en.wikipedia.org/wiki/GNU_Bison) (an alternative parser generator designed to replace Yacc). This parser generator is still in use today in CRuby.

The grammar has added a lot of syntax over the years. [Here](https://kddnewton.com/parsing-ruby/ebnf/0.76.txt) is the grammar for `0.76` from 1995; [here](https://kddnewton.com/parsing-ruby/ebnf/3.0.0.txt) is the grammar for `3.0.0` from 2020. In general the biggest jumps were [1.2.0](https://kddnewton.com/parsing-ruby/ebnf/1.2.1.txt), [1.9.0](https://kddnewton.com/parsing-ruby/ebnf/1.9.0.txt), [2.0.0](https://kddnewton.com/parsing-ruby/ebnf/2.0.0.txt), and [2.7.0](https://kddnewton.com/parsing-ruby/ebnf/2.7.0.txt). The last one in particular added pattern matching, which was a relative large addition to the grammar.

### Non CRuby parsers

* [Artichoke Ruby](https://github.com/artichoke/artichoke)
* [Blue Ruby](https://archive.sap.com/kmuuid2/408a9a3b-03f9-2b10-b29c-f0a3374b19d8/Blue%20Ruby%3A%20A%20Ruby%20VM%20in%20ABAP.pdf)
* [Cardinal](https://github.com/parrot/cardinal)
* [IronRuby](http://www.wilcob.com/Wilco/IronRuby/microsoft_ironruby.aspx)
* [JRuby](https://github.com/jruby/jruby)
* [lib-ruby-parser](https://github.com/lib-ruby-parser/lib-ruby-parser)
* [MacRuby](https://github.com/MacRuby/MacRuby)
* [MagLev](https://github.com/MagLev/maglev)
* [Natalie](https://github.com/natalie-lang/natalie)
* [parser](https://github.com/whitequark/parser)
* [ParseTree](https://github.com/seattlerb/parsetree)
* [Rubinius](https://github.com/carlosbrando/melbourne)
* [Ruby Intermediate Language](http://www.cs.umd.edu/projects/PL/druby/papers/druby-dls09.pdf)
* [ruby_parser](https://github.com/seattlerb/ruby_parser)
* [ruruby](https://github.com/sisshiki1969/ruruby)
* [topaz](https://github.com/topazproject/topaz)
* [tree-sitter-ruby](https://github.com/tree-sitter/tree-sitter-ruby)
* [TruffleRuby](https://github.com/oracle/truffleruby)
* [typedruby](https://github.com/typedruby/typedruby)
* [xruby](https://code.google.com/archive/p/xruby/)

## Parsing Ruby today

* CRuby/ripper/RubyVM::AST
* ruby_parser
* parser
* JRuby
* TruffleRuby
* typedruby/Sorbet

## Rewriting the parser

### Maintainability

One thing worth noting is that all of the way back to version `0.76` in 1995 there was a `ToDo` file in the root of the repository that contained the line `hand written parser (recursive descent)`.

A quick note about parser generators before we go on. Parser generators have much to recommend them: they're great for getting new parsers up and running quickly, they warn you about ambiguities in your grammar, they can be built to be reentrant with a single option toggle, and there are many tools built on top of them. However, there _are_ tradeoffs. Generally speaking, you can squeeze more performance out of a hand-written parser than a generated one. Error recovery becomes much easier when you have complete control over lexing and parsing. Ambiguities in your grammar are resolved explicitly in hand-written parsers, while they are implicitly handled in generated parsers. These and others reasons may be why of the [2021 Redmonk top 10 languages](https://redmonk.com/sogrady/2021/03/01/language-rankings-1-21/), [8 of them](https://notes.eatonphil.com/parser-generators-vs-handwritten-parsers-survey-2021.html) use a handwritten parser.

### Error recovery

Error recovery refers to the ability for a parser to continue parsing after it has received a syntax error. Many techniques have been developed over the years, including [panic mode](http://www.cs.ecu.edu/karl/4627/spr18/Notes/Bison/error.html), [error productions](https://www.gnu.org/software/bison/manual/html_node/Error-Recovery.html), and [statement recovery](https://github.com/microsoft/tolerant-php-parser/blob/main/docs/HowItWorks.md). This is an entire field of study in the realm of Computer Science.

### Portability

As mentioned in the section on non CRuby parsers, there are a lot of different efforts to parse Ruby that don't link directly against CRuby.

### Extensibility


