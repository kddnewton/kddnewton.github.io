---
layout: post
title: Advent of YARV
subtitle: Part 0 - Introduction
---

Since I started working on the YJIT team at Shopify, I've been learning more and more about the CRuby virtual machine known as YARV. A lot of the details of how YARV works are not well documented or the documentation is difficult to find. As such, I decided to write a series of blog posts about how YARV works internally as a Christmas present to both the Ruby community and myself. I hope that this series will help others understand how YARV works and provide a better understanding of CRuby internals. This is the blog series I wish I had had access to when I first started working on CRuby.

In theory, I'll post a new post every morning describing different aspects of the virtual machine. I've divided them up into sections such that each post builds on the foundation of the others, so if you're catching up, I encourage you to start from the beginning. We'll wrap up on Christmas just in time for Ruby 3.2.0 to be released, which is what this series is targeting.

* [Advent of YARV: Part 1 - Pushing onto the stack](/2022/11/28/advent-of-yarv-part-1.html)
* [Advent of YARV: Part 2 - Manipulating the stack](/2022/11/28/advent-of-yarv-part-2.html)
* Advent of YARV: Part 3 - Frames and events
* Advent of YARV: Part 4 - Creating objects from the stack
* Advent of YARV: Part 5 - Changing objects on the stack
* Advent of YARV: Part 6 - Calling methods (1)
* Advent of YARV: Part 7 - Calling methods (2)
* Advent of YARV: Part 8 - Local variables (1)
* Advent of YARV: Part 9 - Local variables (2)
* Advent of YARV: Part 10 - Local variables (3)
* Advent of YARV: Part 11 - Instance variables
* Advent of YARV: Part 12 - Class variables
* Advent of YARV: Part 13 - Global variables
* Advent of YARV: Part 14 - Constants
* Advent of YARV: Part 15 - Branching
* Advent of YARV: Part 16 - Defining classes
* Advent of YARV: Part 17 - Defining methods
* Advent of YARV: Part 18 - Arguments
* Advent of YARV: Part 19 - Super
* Advent of YARV: Part 20 - Defined
* Advent of YARV: Part 21 - Catch tables
* Advent of YARV: Part 22 - Once
* Advent of YARV: Part 23 - Pattern matching
* Advent of YARV: Part 24 - Primitive
* Advent of YARV: Part 25 - Wrapping up
