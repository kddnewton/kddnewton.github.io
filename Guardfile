# frozen_string_literal: true

require 'erb'
require 'fileutils'
require 'kramdown'

def read(name)
  path = File.join('src', "#{name}.md")
  Kramdown::Document.new(File.read(path)).to_html
end

guard :shell do
  watch(/\Asrc/) do
    template = File.read(File.join('src', 'template.html'))

    File.write(
      'index.html',
      ERB.new(template).result_with_hash(
        projects: read('projects'),
        speaking: read('speaking'),
        posts: read('posts')
      )
    )
  end
end
