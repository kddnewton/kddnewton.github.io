---
layout: post
title: Advanced ActiveRecord
---

[ActiveRecord](https://github.com/rails/rails/tree/master/activerecord) is a Ruby implementation of the [active record pattern](https://www.martinfowler.com/eaaCatalog/activeRecord.html) of the same name described by Martin Fowler. It's the default [object-relational mapping](https://en.wikipedia.org/wiki/Object-relational_mapping) used by Ruby on Rails, and frequently the first time new engineers get introduced to the database layer of a web application.

The basic idea is to represents rows from relational database tables as objects in Ruby space, allowing easy access and manipulation of stored data. This as opposed to hand-writing every SQL query comes with a lot of benefits, well-detailed in other posts around the Ruby ecosystem. The post specifically is about ways that you can use the `ActiveRecord` APIs to get at exactly the kind of data that you're looking for without instantiating more objects, returning more rows, or putting more work on your DBMS than you need.


