---
layout: default
title: Speaking
---

## Yet Another Ruby Parser

Building good Ruby tooling is dependent on having a good parser. Today, it is difficult to use the CRuby parser to build tooling because of its lack of public interface and documentation. This has led to people using external gems and generally fragmenting the community.

The Yet Another Ruby Parser project is building a universal Ruby parser that can be used by all Ruby implementations and tools. It is documented, error tolerant, and performant. It can be used without linking against CRuby, which means it can be easily used by other projects.

This talk is about the YARP project's motivation, design, implementation, and results. Come to learn about the future of parsing Ruby.

<iframe src="https://www.youtube.com/embed/3vzpv9GZdLo" title="Yet Another Ruby Parser" frameborder="0" allowfullscreen></iframe>

* [RubyKaigi (2023)](https://rubykaigi.org/2023/presentations/kddnewton.html#day2)

## Syntax Tree

Syntax Tree is a new toolkit for interacting with the Ruby parse tree. It can be used to analyze, inspect, debug, and format your Ruby code. In this talk we'll walk through how it works, how to use it in your own applications, and the exciting future possibilities enabled by Syntax Tree. [[Slides](https://speakerdeck.com/kddnewton/syntax-tree-rubyconf-mini)]

<iframe src="https://www.youtube.com/embed/VN72YBy8KsY" title="Syntax Tree" frameborder="0" allowfullscreen></iframe>

* [RubyConf Mini (2022)](https://www.rubyconfmini.com/program)
* [RubyKaigi (2022)](https://rubykaigi.org/2022/presentations/kddnewton.html)

## Parsing Ruby

Since Ruby's inception, there have been many different projects that parse Ruby code. This includes everything from development tools to Ruby implementations themselves. This talk dives into the technical details and tradeoffs of how each of these tools parses and subsequently understands your applications. After, we'll discuss how you can do the same with your own projects using the Ripper standard library. You'll see just how far we can take this library toward building useful development tools. [[Code](https://github.com/kddnewton/parsing-ruby)] [[Slides](https://speakerdeck.com/kddnewton/parsing-ruby-rubyconf)]

<iframe src="https://www.youtube.com/embed/lUIt2UWXW-I" title="Parsing Ruby" frameborder="0" allowfullscreen></iframe>

* [Ruby Kaigi (2021)](https://rubykaigi.org/2021-takeout/presentations/kddnewton.html)
* [Boston Ruby Group (Nov 2021)](https://bostonrb.org)
* [RubyConf (2021)](https://rubyconf.org/program/sessions#session-1183)

## Prettier for Ruby

Prettier was created in 2017 and has since seen a meteoric rise within the JavaScript community. It differentiated itself from other code formatters and linters by supporting minimal configuration, eliminating the need for long discussions and arguments by enforcing an opinionated style on its users. That enforcement ended up resonating well, as it allowed developers to get back to work on the more important aspects of their job.

Since then, it has expanded to support other languages and markup, including Ruby. The Ruby plugin is now in use in dozens of applications around the world, and better formatting is being worked on daily. This talk will give you a high-level overview of prettier and how to wield it in your project. It will also dive into the nitty gritty, showing how the plugin was made and how you can help contribute to its growth. You’ll come away with a better understanding of Ruby syntax, knowledge of a new tool and how it can be used to help your team. [[Code](https://github.com/prettier/plugin-ruby)] [[Slides](https://speakerdeck.com/kddnewton/prettier-for-ruby-2020)]

<iframe src="https://www.youtube.com/embed/3945FmGGHhw" title="Prettier for Ruby" frameborder="0" allowfullscreen></iframe>

* [Boston Ruby Group (Mar 2019)](https://bostonrb.org/)
* [Ruby Kaigi (2020)](https://rubykaigi.org/2020-takeout/presentations/kddeisz.html)

## Pre-evaluation in Ruby

Ruby is historically difficult to optimize due to features that improve flexibility and productivity at the cost of performance. Techniques like Ruby's new JIT compiler and deoptimization code help, but still are limited by techniques like monkey-patching and binding inspection. Pre-evaluation is another optimization technique that works based on user-defined contracts and assumptions. Users can opt in to optimizations by limiting their use of Ruby's features and thereby allowing further compiler work. [[Code](https://github.com/kddnewton/preval)]
[[Slides](https://speakerdeck.com/kddnewton/pre-evaluation-in-ruby)]

<iframe src="https://www.youtube.com/embed/7GqhHmfjemY" title="Pre-evaluation in Ruby" frameborder="0" allowfullscreen></iframe>

* [Ruby Kaigi (2019)](https://rubykaigi.org/2019/presentations/kddeisz.html)
* [RailsConf (2019)](https://www.railsconf.com/2019/program/sessions#session-748)

## Grow a bonsai, not a shrub

Oftentimes we trade away code style for the sake of pushing new features. This often results in a tangled web of code that few understand and fewer can maintain. This talk explores Ruby’s tools and how to wield them to trim your application’s code into the shape it should eventually take.
[[Code](https://github.com/kddnewton/bonsai)]
[[Slides](https://speakerdeck.com/kddnewton/grow-a-bonsai-not-a-shrub)]

<iframe src="https://www.youtube.com/embed/wyDe_segUs0" title="Grow a bonsai, not a shrub" frameborder="0" allowfullscreen></iframe>

* [Boston Ruby Group (Oct 2018)](https://bostonrb.org/)

## Compiling Ruby

Since Ruby 2.3 and the introduction of `RubyVM::InstructionSequence::load_iseq`, we've been able to programmatically load ruby bytecode. By divorcing the process of running YARV byte code from the process of compiling ruby code, we can take advantage of the strengths of the ruby virtual machine while simultaneously reaping the benefits of a compiler such as macros, type checking, and instruction sequence optimizations. This can make our ruby faster and more readable! This talk demonstrates how to integrate this into your own workflows and the exciting possibilities this enables. [[Code](https://github.com/kddnewton/compiling-ruby)]
[[Slides](https://speakerdeck.com/kddnewton/compiling-ruby)]

<iframe src="https://www.youtube.com/embed/B3Uf-aHZwmw" title="Compiling Ruby" frameborder="0" allowfullscreen></iframe>

* [Ruby Kaigi (2017)](http://rubykaigi.org/2017/presentations/kddeisz.html)
* [RubyConf (2017)](http://confreaks.tv/videos/rubyconf2017-compiling-ruby)
* [Ruby On Ice (2018)](https://rubyonice.com/2018/speakers/kevin_deisz)

## Practical debugging

People give ruby a bad reputation for speed, efficiency, weak typing, etc. But one of the biggest benefits of an interpreted language is the ability to debug and introspect quickly without compilation. Oftentimes developers reach for heavy-handed libraries to debug their application when they could just as easily get the information they need by using tools they already have.

In this talk you will learn practical techniques to make debugging easier. You will see how simple techniques from the ruby standard library can greatly increase your ability to keep your codebase clean and bug-free. [[Code](https://github.com/kddnewton/practical-debugging)] [[Slides](https://speakerdeck.com/kddnewton/practical-debugging)]

<iframe src="https://www.youtube.com/embed/oi4h30chCz8" title="Practical debugging" frameborder="0" allowfullscreen></iframe>

* [RailsConf (2017)](http://railsconf.com/2017/program.html#session-140)
