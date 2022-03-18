require "base64"

module FlowCharts
  def self.call(source)
    source.gsub!(/```dot\n(.+?)```/m) do |content|
      output =
        IO.popen("dot -Tsvg", "w+") do |file|
          file.write($1)
          file.close_write
          file.readlines
        end
  
      3.times { output.shift }
  
      <<~TAG.strip
        <div align="center">
        <!--
        #{$1.strip}
        -->
          <img src="data:image/svg+xml;base64,#{Base64.strict_encode64(output.join)}" />
        </div>
      TAG
    end
  end
end

if defined?(Jekyll)
  Jekyll::Hooks.register(:posts, :pre_render) do |post|
    FlowCharts.call(post.content)
  end
end
