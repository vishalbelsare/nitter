import httpclient, asyncdispatch, htmlparser
import strutils, json, xmltree, uri

import ".."/[types, parser, parserutils, query]
import utils, consts, timeline

proc getResult*[T](json: JsonNode; query: Query; after: string): Result[T] =
  if json == nil: return Result[T](beginning: true, query: query)
  Result[T](
    hasMore: json{"has_more_items"}.getBool(false),
    maxId: json{"max_position"}.getStr(""),
    minId: json{"min_position"}.getStr(""),
    query: query,
    beginning: after.len == 0
  )

proc getSearch*[T](query: Query; after, agent: string;
                   media=true): Future[Result[T]] {.async.} =
  let
    kind = if query.kind == users: "users" else: "tweets"

    param = genQueryParam(query)
    encoded = encodeUrl(param, usePlus=false)

    referer = base / ("search?f=$1&q=$2&src=typd" % [kind, encoded])
    headers = genHeaders(agent, referer, auth=true, xml=true)

    params = {
      "f": kind,
      "vertical": "default",
      "q": param,
      "src": "typd",
      "include_available_features": "1",
      "include_entities": "1",
      "max_position": if after.len > 0: after else: "0",
      "reset_error_state": "false"
    }

  if param in ["include:nativeretweets", "-filter:nativeretweets", ""]:
    return Result[T](query: query, beginning: true)

  let json = await fetchJson(base / searchUrl ? params, headers)

  result = getResult[T](json, query, after)
  if json == nil or not json.hasKey("items_html"): return

  when T is Tweet:
    result = await finishTimeline(json, query, after, agent, media)
  elif T is Profile:
    let html = json["items_html"].to(string)
    result.hasMore = html != "\n"
    for p in parseHtml(html).selectAll(".js-stream-item"):
      result.content.add parsePopupProfile(p, ".ProfileCard")
