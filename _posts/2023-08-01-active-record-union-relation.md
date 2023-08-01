---
layout: post
title: ActiveRecord::UnionRelation
---

I wrote a gem back in 2020 called [active_record-union_relation](https://github.com/kddnewton/active_record-union_relation), and I'm finally writing a blog post describing it. This is a very small gem that provides the ability to define Active Record relations from `UNION` queries. The resulting records that are returned when the queries are executed are polymorphic (i.e. they can be instances of different classes). I'll show how this works and why you might want to use it.

## Background for SQL

First, it's important to understand what a `UNION` query does. A `UNION` query combines the results of two or more `SELECT` statements into a single result set. Those `SELECT` statements can be from completely different tables. Note that for most databases, the columns in the `SELECT` statements must be the same.

For example, let's say you have `comments`, `posts`, and `tags` tables. They are layed out like this:

```
+-----------------+    +-----------------+    +-----------------+
| comments        |    | posts           |    | tags            |
+-----------------+    +-----------------+    +-----------------+
| id              |    | id              |    | id              |
| post_id         |    | title           |    | name            |
| body            |    | published       |    +-----------------+
+-----------------+    +-----------------+
```

Assume for our purposes that the column types follow your intuition. For example, `comments.post_id` is a foreign key to `posts.id`. Now, let's say you want to find all of the records that match a certain search query. You would write something like this:

```sql
SELECT 'comment' as 'type', id, body AS 'value' FROM comments WHERE body LIKE '%foo%'
UNION
SELECT 'post' as 'type', id, title AS 'value' FROM posts WHERE title LIKE '%foo%'
UNION
SELECT 'tag' as 'type', id, name AS 'value' FROM tags WHERE name LIKE '%foo%'
```

This query will return a result set that looks like this:

```
+---------+----+-------+
| type    | id | value |
+---------+----+-------+
| post    | 1  | foo   |
| tag     | 1  | foo   |
| tag     | 2  | foo   |
| comment | 1  | foo   |
+---------+----+-------+
```

In this way you can use a single query to search across multiple tables. This is a very simple example, but you can imagine how this could be useful in a more complex scenario. There are more options like `UNION ALL` and other complications that can be used, but I won't go into those here.

## Background for Active Record

An important thing to remember about the Active Record ORM is that records can represent table rows in very different states with regard to persistence. For example, a record that is brand new can have all of its fields be `nil` without error, whereas a record fetched from the database should in theory have its fields populated.

However, the values that Active Record uses for populating fields is entirely up to the query that fetches the fields. You can use `ActiveRecord::Relation#select` to modify the fields that are fetched and Active Record will happily store them in instances variables when the database returns them. For example you could `User.select("id * 2 AS 'id'")` and you will get back `User` objects with double their ID.

In essence, when Active Record records are fetched from the database, they are functioning more as views into the results of a query than as a direct representation of table rows. The query doesn't even necessarily need to correspond to the same table or have any of the same columns — the records will conveniently return fields using `#method_missing` when necessary.

For example, let's take our database schema from the SQL backend section and wrap it up in Active Record objects. Let's presume we have:

```ruby
class Comment < ActiveRecord::Base
  belongs_to :post
end

class Post < ActiveRecord::Base
  has_many :comments
end

class Tag < ActiveRecord::Base
end
```

Most queries that folks write would look something like `Post.all`. This breaks down simple select: `SELECT * FROM posts`. However, you could just as easily have written `Post.from("SELECT id, body AS 'title' FROM comments")`. This would return `Post` objects with the `id` and `title` fields populated from the `comments` table.

## Background for Single Table Inheritance (STI)

There is one place in Active Record that returns polymorphic arrays when a query is executed: single table inheritance. Single table inheritance is a feature of Active Record that allows you to have a single table represent multiple classes. For example, let's say you have a `posts` table that looks like this:

```
+-----------------+
| posts           |
+-----------------+
| id              |
| type            |
| title           |
| published       |
+-----------------+
```

You can have classes that look like:

```ruby
class Post < ActiveRecord::Base
end

class VideoPost < Post
end

class AudioPost < Post
end
```

If you were to iterate over `Post.all`, you would get back an array of `VideoPost` and `AudioPost` objects. It does this by looking at the `type` column and instantiating the appropriate class. Importantly, it does this by looking at the `#inheritance_column` method. It then will call the `#instantiate` method, and eventually the `#instantiate_instance_of` method, which is where the split on type happens.

## ActiveRecord::UnionRelation

In applications that I have written, I have found it helpful to use `UNION` queries to provide basic search functionality. (If the application grows or the search becomes more complicated then full-text options become more attractive.) There isn't a native way to do this in Active Record. This is where the `active_record-union_relation` gem comes in.

Effectively this gem provides a DSL to combine multiple subqueries into a single relation that can be used like any other relation. The resulting relation will return polymorphic records when the query is executed by taking advantage of the same mechanism used by single table inheritance. Let's take, for example, the models defined above. If we wanted to search the various text columns for a specific query, we could write:

```ruby
term = "foo"

relation =
  ActiveRecord.union(:id, :post_id, :matched) do |union|
    union.add(
      Post.where(published: true).where("title LIKE ?", "%#{term}%"),
      :id, nil, :title
    )

    union.add(
      Comment.where("body LIKE ?", "%#{term}%"),
      :id, :post_id, :body
    )

    union.add(
      Tag.where("name LIKE ?", "%#{term}%"),
      :id, nil, :name
    )
  end

relation.order(matched: :asc)
```

In the above code, we call `ActiveRecord::union` with the names of the common columns that will be returned by each subquery. Then within the given block, we add each subquery in turn. By adding a subquery we provide a relation and then each of the fields that should be mapped to the common columns of the overall union (using `nil` to mean we don't have something for that value). The resulting relation will return `Post`, `Comment`, and `Tag` objects that have `id`, `post_id`, and `matched` fields populated with the appropriate values.

Notice that in the code above we call `#order` on the relation. This works because the returned object is an `ActiveRecord::Relation` object. As such, all other query methods will work as expected.

## Wrapping up

As a quick disclaimer: I probably wouldn't pull in an entire separate gem just to provide this functionality. At the end of the day the code boils down to about [100 lines](https://github.com/kddnewton/active_record-union_relation/blob/main/lib/active_record/union_relation.rb) with lots of comments so this is more in the realm of copy-paste-able code. However, I think it's a neat trick and I hope you do too. Mostly I like this because it mirrors Ruby's idea of duck-typing. Effectively we're treating each record as an object fulfilling a role rather than a nominal type. This feels very at home in a Ruby application.

If you have any questions or comments, feel free to reach out to me on Twitter [@kddnewton](https://twitter.com/kddnewton) or GitHub [kddnewton](https://github.com/kddnewton).
