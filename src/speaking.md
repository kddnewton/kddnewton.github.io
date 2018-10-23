## Speaking

### Grow a bonsai, not a shrub

Oftentimes we trade away code style for the sake of pushing new features. This often results in a tangled web of code that few understand and fewer can maintain. This talk explores Ruby’s tools and how to wield them to trim your application’s code into the shape it should eventually take.
[[Code](https://github.com/kddeisz/bonsai)]
[[Slides](https://speakerdeck.com/kddeisz/grow-a-bonsai-not-a-shrub)]

<iframe src="https://www.youtube.com/embed/wyDe_segUs0" title="Gorw a bonsai, not a shrub" frameborder="0" allowfullscreen></iframe>

* [Boston Ruby Group Oct 2018](https://bostonrb.org/)

### Compiling Ruby

Since Ruby 2.3 and the introduction of `RubyVM::InstructionSequence::load_iseq`, we've been able to programmatically load ruby bytecode. By divorcing the process of running YARV byte code from the process of compiling ruby code, we can take advantage of the strengths of the ruby virtual machine while simultaneously reaping the benefits of a compiler such as macros, type checking, and instruction sequence optimizations. This can make our ruby faster and more readable! This talk demonstrates how to integrate this into your own workflows and the exciting possibilities this enables. [[Code](https://github.com/kddeisz/compiling-ruby)]
[[Slides](https://speakerdeck.com/kddeisz/compiling-ruby)]

<iframe src="https://www.youtube.com/embed/B3Uf-aHZwmw" title="Compiling Ruby" frameborder="0" allowfullscreen></iframe>

* [Ruby Kaigi 2017](http://rubykaigi.org/2017/presentations/kddeisz.html)
* [RubyConf 2017](http://confreaks.tv/videos/rubyconf2017-compiling-ruby)
* [Ruby On Ice 2018](https://rubyonice.com/2018/speakers/kevin_deisz)

### Practical debugging

People give ruby a bad reputation for speed, efficiency, weak typing, etc. But one of the biggest benefits of an interpreted language is the ability to debug and introspect quickly without compilation. Oftentimes developers reach for heavy-handed libraries to debug their application when they could just as easily get the information they need by using tools they already have.

In this talk you will learn practical techniques to make debugging easier. You will see how simple techniques from the ruby standard library can greatly increase your ability to keep your codebase clean and bug-free. [[Code](https://github.com/kddeisz/practical-debugging)] [[Slides](https://speakerdeck.com/kddeisz/practical-debugging)]

<iframe src="https://www.youtube.com/embed/oi4h30chCz8" title="Practical debugging" frameborder="0" allowfullscreen></iframe>

* [RailsConf 2017](http://railsconf.com/2017/program.html#session-140)
