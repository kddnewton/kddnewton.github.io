require "base64"

Jekyll::Hooks.register(:posts, :pre_render) do |post|
  post.content.gsub!(/```dot\n(.+?)```/m) do |content|
    output =
      IO.popen("dot -Tsvg", "w+") do |file|
        file.write($1)
        file.close_write
        file.readlines
      end

    3.times { output.shift }

    <<~TAG
      <div align="center">
        <img src="data:image/svg+xml;base64,#{Base64.encode64(output.join)}" />
      </div>
    TAG
  end
end
