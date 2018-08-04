# frozen_string_literal: true

require 'erb'
require 'fileutils'
require 'kramdown'
require 'yui/compressor'

ASSET_DIR = File.expand_path('assets', __dir__)
BUILD_DIR = File.expand_path('build', __dir__)
SRC_DIR = File.expand_path('src', __dir__)

def read_md(name)
  Kramdown::Document.new(File.read(File.join(SRC_DIR, "#{name}.md"))).to_html
end

guard :shell do
  watch(/\Asrc/) do
    projects = read_md('projects')
    speaking = read_md('speaking')
    posts = read_md('posts')
    result = ERB.new(File.read(File.join(SRC_DIR, 'template.html'))).result(binding)

    File.write(File.join(BUILD_DIR, 'index.html'), result)
  end

  watch(%r{\Aassets/(.+)}) do |match|
    filename = match[1]

    source = File.join(ASSET_DIR, filename)
    dest = File.join(BUILD_DIR, 'assets', filename)

    if filename.end_with?('.css')
      compressor = YUI::CssCompressor.new
      File.write(dest, compressor.compress(File.read(source)))
    else
      FileUtils.cp(source, dest)
    end
  end
end
