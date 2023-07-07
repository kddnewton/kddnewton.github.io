---
layout: post
title: Best Practices and Common Mistakes with Travis CI
source: https://eng.localytics.com/best-practices-and-common-mistakes-with-travis-ci/
---

At Localytics, we've worked hard to ensure that all of our services are built and deployed using our own internal best practices. One of those core best practices is that the service in question is using continuous integration (CI). CI greatly reduces the amount of time an engineer needs to spend finding the origin of a bug by running tests early and often. By integrating each change into a central repository where the tests can be run, we can precipitate faster cycle times and a more productive work environment.

Our CI tool of choice is [Travis CI](https://travis-ci.org). Travis's tight integration with GitHub (our version control provider) allows us to quickly create an integrated testing environment for each of our services. Travis is widely used by the most popular GitHub repositories, with about [one third](https://blog.travis-ci.com/2016-07-28-what-we-learned-from-analyzing-2-million-travis-builds) of repositories with 50 or more stars using it.

Travis builds code based on a `.travis.yml` file checked in to the root of the repository. By default, the build environment is Ubuntu 12.04 LTS with four gigabytes of memory running on two cores. Most of the build process is configurable through the .travis.yml file, including the machine it's running on, the entire [build lifecycle](https://docs.travis-ci.com/user/customizing-the-build), [notifications](https://docs.travis-ci.com/user/notifications/), and [deployment of artifacts](https://docs.travis-ci.com/user/deployment/).

## Best practices

Over time, we've developed the five best practices listed below. There are plenty of others out there, but we found these particularly helpful for efficiently using Travis within our team.

### 1. Minimize build time

One of the most important metrics in increasing development speed is decreasing test time. Every extra second tests are running is time that could be spent doing further development. If tests run for more than 10 minutes, developers will often start a new task rather than wait for the tests to finish. If the tests then fail, the developer now has to switch back to the original task. Constantly switching between tasks dramatically reduces productivity. Minimizing build time is both difficult and time-consuming, but in the end the investment is worth it because it allows developers to focus on one task at a time.

Travis has a section on ["Speeding up the build"](https://docs.travis-ci.com/user/speeding-up-the-build/) in their documentation, and lists multiple ways to achieve this. The simplest is to take advantage of their build matrix and achieve "parallelism" by segregating your test suite.

For some projects, we've also implemented our own test segregation by only running the tests that need to be run. This works particularly well if you have a repository with distinct top-level folders that have no cross-dependencies. First, query the git history to find the files that changed. Then, only test those directories. For example, the below code from one of our repositories only tests the rails code if there are changes to files within the "rails" subdirectory:

```sh
CHANGES=$(git --no-pager diff --name-only FETCH_HEAD $(git merge-base FETCH_HEAD master))  
[ -n "$(grep '^rails' <<< "$CHANGES")" ] && testRails
```

### 2. Pull out large sections of logic into their own shell scripts

The `.travis.yml` script is great for small scripts like:

```yaml
script:  
- bundle exec rake
- bundle exec rubocop
```

but much beyond two or three lines it can become pretty unwieldy. We've found that moving those kinds of scripts into their own `bin/test` or `bin/deploy` can make testing simpler and allows you to run them outside of the Travis environment.

### 3. Test multiple language versions for libraries

When developing an application, you only need to test against the version(s) of the language that you're running in production. At the most you might also test against the next version to see what's going to break when you upgrade. For a library, however, you'll want to test against every possible version with which your library could be run. For example, our `Humidifier` library is tested against [four ruby versions](https://github.com/localytics/humidifier/blob/master/.travis.yml) to ensure engineers using it in various applications will not run into unaccounted-for bugs because they are using a different ruby version.

### 4. Skip unnecessary builds

Especially when you're working with a large team with multiple Travis-enabled repositories, you'll want to avoid running any unnecessary builds. The most common reason a build might be unnecessary is that it's just a documentation or comment change. For simple changes like these, add ["[ci skip]"](https://docs.travis-ci.com/user/customizing-the-build/) to your commit message, and Travis will automatically skip that build. The other common reason is if you're on a pull request and push code that was incorrect and then immediately push a fix. That first build is still going to run, but should be cancelled as quickly as possible so as to not overpopulate your team's queue.

### 5. Debug builds using Travis' docker containers

When things break in Travis, usually the tests are failing. In that case, usually they are also failing on your local machine. In this case, the build can be fixed easily by pushing the same changes that fix the problem in your development environment. The more difficult case is when tests pass in your development environment but not in Travis. When this happens, [Travis' Docker containers](https://docs.travis-ci.com/user/common-build-problems/) are your friend. Simply mount your code as a volume and run the tests (e.g., `docker run -it -v $(pwd):/code quay.io/travisci/travis-ruby /bin/bash`).

## Common mistakes

In addition to best practices, we've also run into trouble often with the five common mistakes listed below. Either a new engineer is using Travis for the first time, or an experienced engineer forgets; all of the mistakes listed below are easy to make.

### 1. Over-caching

Travis offers the ability to [cache files](https://docs.travis-ci.com/user/caching/) between builds to decrease the setup time needed before the tests can be run. This is a particularly attractive option, and works well for things like `cache: bundler` (which will cache all ruby gem dependencies) and `cache: yarn` (which will cache node package dependencies). You can even cache arbitrary directories where you might write your own dependencies.

Avoid over-caching though, as this can end up doing more harm than good. At one point we ended up with a cache for one of our projects that was almost a full gigabyte; removing the cache sped up the build.

### 2. Using `$?`

Don't use the `$?` bash special parameter to determine the exit status of a previous command. The lines in `.travis.yml` are processed internally by Travis, and will not have the exit status you expect. Instead, follow the best practice listed above and extract anything that complicated into its own script.

### 3. Misusing `$TRAVIS_BRANCH`

Travis provides a variety of [environment variables](https://docs.travis-ci.com/user/environment-variables/) that you can use in your build scripts. The most easily abused is `$TRAVIS_BRANCH`, particularly if you're determining whether or not to deploy. Be cautious though - when Travis is building a pull request, `$TRAVIS_BRANCH` will be set to the target as opposed to the origin. To determine if the running environment is merged into master, you'll need to `[[ $TRAVIS_PULL_REQUEST == "false" ]] && [[ $TRAVIS_BRANCH == "master" ]]` and to determine the exact branch you're on you'll need to shell out to `git` itself.

### 4. `after_*` callbacks do not mark the build as a failure

Don't rely on `after_*`-style callbacks to [break the build](https://docs.travis-ci.com/user/customizing-the-build/). If the script that you're calling in an after callback is somehow broken, the build will succeed and you will not be notified. Therefore, don't put anything in that section of the pipeline that's mission-critical. Instead, put that as another line inside the script section. We've generally reserved the `after_*` callbacks for things like reporting code coverage, as it won't break anything if that fails.

### 5. Two builds per PR

By default, Travis will build [twice for each pull request](https://docs.travis-ci.com/user/pull-requests/). One of the builds will be the build for the branch itself, and one of the builds will be for the potential future merge commit against the target of the pull request. For us, because we merge to master quickly, it's rare that the merge commit build will find something that the branch build doesn't. Because of that, we've disabled the second build for a lot of our less fundamental services.

## Travis clients

The Travis interface doesn't provide a lot of insight into the metrics around your builds, but they provide the tools to find these yourself relatively easily. Using the [travis ruby client](https://github.com/travis-ci/travis.rb) we were able to inspect our entire Travis configuration: finding the percentage of breaking builds per project, or finding the average amount of time the builds took.

We decided to write some of these scripts in [elixir](https://eng.localytics.com/flirting-with-elixir/). There wasn't an equivalent Travis client written in elixir, so we wrote our own, which we are open-sourcing today: [https://github.com/localytics/travis.ex](https://github.com/localytics/travis.ex). It's up on [hex](https://hex.pm/packages/travis) and freely available for use. When you do, please share your experience, approach, and any feedback in a gist, on a blog, or in the comments.
