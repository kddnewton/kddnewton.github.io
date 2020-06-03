---
layout: default
---

{% for post in site.posts %}
# [{{ post.title }}]({{ post.url }})
<time>{{ post.date | date: "%b %d, %Y" }}</time>

{{ post.excerpt }}
{% endfor %}
