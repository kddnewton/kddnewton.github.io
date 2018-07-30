# frozen_string_literal: true

require 'erb'
require 'fileutils'
require 'kramdown'
require 'yui/compressor'

guard :shell do
  asset_dir = File.expand_path('assets', __dir__)
  build_dir = File.expand_path('build', __dir__)
  src_dir = File.expand_path('src', __dir__)

  watch(/\Asrc/) do
    body = Kramdown::Document.new(File.read(File.join(src_dir, 'index.md'))).to_html
    result = ERB.new(File.read(File.join(src_dir, 'template.html'))).result(binding)

    File.write('index.html', result)
  end

  watch(%r{\Aassets/(.+)}) do |match|
    filename = match[1]

    source = File.join(asset_dir, filename)
    dest = File.join(build_dir, 'assets', filename)

    if filename.end_with?('.css')
      compressor = YUI::CssCompressor.new
      File.write(dest, compressor.compress(File.read(source)))
    else
      FileUtils.cp(source, dest)
    end
  end
end
