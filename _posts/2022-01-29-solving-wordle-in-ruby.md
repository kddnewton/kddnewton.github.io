---
layout: post
title: Solving Wordle in Ruby
---

You may have seen the word game [wordle](https://www.powerlanguage.co.uk/wordle/) going around the various social media. It's a simple game that works like this:

* The game selects a 5-letter word that the player is trying to guess.
* The player gets 6 guesses to find the word.
* Every time the player guesses a word, they are told if the letter they selected was either not in the word (gray tile), in the word but in the wrong place (yellow tile), or in the word and in the right place (green tile).

Being a programmer, it's hard to resist the urge to script a solution to this game. So that's what I did. If you want to skip straight to the code, it's here: [kddnewton/wordle](https://github.com/kddnewton/wordle). Otherwise, read on for how this is done.

## Getting the list of words

Fortunately, wordle is a relatively simple game, and makes no attempt to hide the dictionary it's using (by, for instance, putting it behind an API request). Instead, everything ships in one compact JavaScript bundle. So if you view the source of the file through your browser, you can pull out the exact words it's going to be using. (You can also just pull out the solutions, but that's not nearly as fun.)

After you find the right variables, you can dump them into a file for reading later. In my repository, I called it (somewhat unimaginatively) `words.txt`. We then need to read the file in and create the shell of our program, which is done like so:

```ruby
# The `chomp` here means to strip off the newline characters from each line, so
# we're just left with the words.
words = File.readlines("words.txt", chomp: true)

while words.length > 1
  # Do something in here to whittle down the list of words that are left until
  # we're left with just one.
end

# At this point, there should only be one word left in the dictionary, which
# means we've found our final word.
puts "The word is: #{words.first}"
```

## Getting user input

Now that we have the shell of our program, we need a way to get the user's input so we can guess words and they can tell us how we did. We'll come up with a simple little protocol that works like the following:

* We'll output a guess to the command line.
* The player will input that guess into wordle.
* The player will then input the color of the tiles back to our program. `_` will represent a gray tile, `y` will represent a yellow tile, and `g` will represent a green tile.
* Repeat.

For now, we'll just output a random word as a guess. We'll come back and make it better shortly. Here's how we're going to accomplish what we've just described:

```ruby
# Get a random word from the remaining list of words.
guess = words.sample
print "#{guess} ? "

# Read the user's input from the command line.
input = gets.chomp.downcase
guess.each_char.zip(input.each_char).each_with_index do |(letter, action), index|
  case action
  when "_"
    # In this case, the letter is not in the final word, so delete any words
    # from the dictionary that contain that letter.
    words.reject! { |word| word.include?(letter) }
  when "g"
    # In this case, the letter is in the final word at this index, so delete
    # any words from the dictionary that do not also have this letter at
    # that index.
    words.reject! { |word| word[index] != letter }
  when "y"
    # In this case, the letter is in the final word but at a different
    # index, so delete any words from the dictionary that either do not have
    # this letter or that have this letter at this same index.
    words.reject! { |word| !word.include?(letter) || word[index] == letter }
  end
end
```

That code will go in the middle of our `while` loop that we created earlier. This code actually works pretty well, though the guesses are very much not optimal. Let's see if we can fix that.

## Guessing better words

The strategy that we're going to take for this is going to be to guess the word that gives us the most information. If almost every word remaining in our dictionary contains an `a`, then for sure we want our guess to include an `a`. The same can be said about any other letter. We also want to make sure we weight it according to the remaining possible words, not just the entire dictionary every time. So if we've already guessed `a`, we don't want it to factor into our guessing at all. We can accomplish this with the following code:

```ruby
# First, set of a list of letters remaining to be guessed. This is important for
# building up the list of weights for choosing optimal guesses.
letters = ("a".."z").to_a

# Now, within the while loop...
# Build up a list of "weights". This is a hash of letters that point to the
# number of unique words that contain those letters. So for example, if you had
# the words:
#
#     apple
#     knoll
#
# You would end up with a hash of weights that looked like:
#
#     { "a" => 1, "e" => 1, "k" => 1, "l" => 2, "n" => 1, "o" => 1, "p" => 1 }
#
weights = Hash.new { 0 }
words.each { |word| word.each_char.uniq.tally(weights, &:itself) }
weights.select! { |letter, _| letters.include?(letter) }

# Determine which word we're guessing based on which word in the remaining
# list has the highest weight. We determine the weight by adding the weight of
# each letter in the word together.
guess = words.max_by { |word| word.each_char.uniq.sum(&weights) }
```

Now our guess is properly weighted by the remaining words. The only other thing to add is something that deletes from the `letters` list when an action is taken, so we can add to our `each_with_index` loop above:

```ruby
letters.delete(letter)
```

We're done! We're now guessing much better words.

## Testing our guessing

To test that our program won't break on any input, we can run through every word in the dictionary and see how it performs. That will involve running our guessing program for each word and playing through it by writing the tile colors back as if we were playing on the actual game.

We can do this by spawning a subprocess. Let's assume we're working with a fixed word like "apple":

```ruby
require "open3"

word = "apple"

# Open a new ruby process executing the wordle.rb file. Within the
# block, you can write to the STDIN and read from the STDOUT IO objects
# to communicate with the child process.
Open3.popen2("ruby wordle.rb") do |stdin, stdout, waiter|
  # The protocol is a little loose, but basically if you get to the
  # final word it outputs "The word is", so we can use that as our loop
  # condition.
  until (read = stdout.read(3)) == "The"
    # Read the rest of the guess, and then skip past the prompt on the
    # STDOUT pipe.
    guess = "#{read}#{stdout.read(2)}"
    stdout.read(10)

    # Create the input necessary to tell the child process which tiles
    # turned which colors. This is analogous to inputting the guessed
    # word into the text box.
    chars =
      guess.each_char.map.with_index do |char, index|
        if word[index] == char
          "g"
        elsif word.include?(char)
          "y"
        else
          "_"
        end
      end

    # Write the input to STDIN and flush it down the pipe so the child
    # process will unblock its read.
    stdin.write("#{chars.join}\n")
    stdin.flush
  end

  # Once we get here, it has started to print "The word is" so read the
  # rest and then verify that it selected the correct word.
  stdout.read(10)
  raise if stdout.read(5) != word
end
```

The code above allows us to communicate with the subprocess by writing to its STDIN (as if the user were typing in) and reading from its STDOUT (as if the user were reading the output).

We can now change the code above to loop through every word in the dictionary:

```ruby
# Build up a thread-safe queue for every word in the dictionary.
queue = Queue.new
File.foreach("words.txt", chomp: true) { |word| queue << word }

until queue.empty?
  word = queue.shift

  # The code above goes here.
end
```

We can even parallelize it to get better performance using threads (since a lot of this work is IO-bound):

```ruby
workers =
  8.times.map do
    Thread.new do
      # our until loop goes here
    end
  end

# Join each worker thread back into the main thread to make sure we wait for
# everything to complete.
workers.map(&:join)
```

## Rating our guessing

If we want to rate our guessing (so we can improve the algorithm over time), we can add a little logging to our tests. First, we'll create a hash where we'll log the information about how many guesses each word took:

```ruby
# Create a hash whose default value is 0 for any new keys. We'll use this to
# track how many guesses it took to successfully get to the final word.
results = Hash.new { 0 }
```

Then, inside the `until` loop, we'll create a variable to track how many guesses each word took:

```ruby
guesses = 0
```

Inside the inner `until` loop we'll increment this value so it tracks each guess.

```ruby
guesses += 1
```

Finally, at the end of the `until` loop, we'll log our score for that word:

```ruby
results[guesses] += 1
```

At the end of the test program, we now have a hash of number of guesses pointing to the number of words that required that many guesses. Somewhat arbitrarily, we can score this like the following:

```ruby
score =
  (results[1] + results[2] + results[3]) * 10 +
  (results[4] + results[5] + results[6]) * 5
```

where you get 10 points for every word that you guessed within 3 guesses, and 5 points for every word that you got correctly at all.

## Wrapping up

In this post, I showed some code to solve the twitter-famed wordle game. We wrote some tests, and scored it as well. I hope you enjoyed! Here are a couple of APIs that I used if you're interesting in learning more:

* [Enumerable#max_by](https://ruby-doc.org/core-3.1.0/Enumerable.html#method-i-max_by)
* [Enumerable#tally](https://ruby-doc.org/core-3.1.0/Enumerable.html#method-i-tally)
* [Enumerable#zip](https://ruby-doc.org/core-3.1.0/Enumerable.html#method-i-zip)
* [IO#readlines](https://ruby-doc.org/core-3.1.0/IO.html#method-c-readlines)
* [Open3::popen2](https://ruby-doc.org/stdlib-3.1.0/libdoc/open3/rdoc/Open3.html#method-c-popen2)

For the algorithm I've detailed in the post, I get a score of `81370`. Feel like a challenge? I'd love to hear of a higher score and how you got it!
