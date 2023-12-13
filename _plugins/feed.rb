# frozen_string_literal: true

module Jekyll
  module Feed
    class Generator < Jekyll::Generator
      safe true
      priority :lowest

      class BlankPage < Jekyll::Page
        def read_yaml(*)
          @data ||= {}
        end
      end

      # Matches all whitespace that follows
      #   1. A '>', which closes an XML tag or
      #   2. A '}', which closes a Liquid tag
      # We will strip all of this whitespace to minify the template
      MINIFY_REGEX = %r!(?<=>|})\s+!.freeze

      def generate(site)
        return if File.exist?(site.in_source_dir("feed.xml"))

        Jekyll.logger.info("[Jekyll::Feed]:", "Generating feed for posts")
        page = BlankPage.new(site, __dir__, "", "feed.xml")

        page.content = File.read(File.expand_path("feed.xml", __dir__)).gsub(MINIFY_REGEX, "")
        page.data.merge!("layout" => nil, "sitemap" => false, "xsl" => false, "collection" => "posts", "category" => nil, "tags" => nil)
        page.output

        site.pages << page
      end
    end
  end
end
