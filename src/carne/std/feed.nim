# Carne std/feed: RSS and Atom feed parsing via openparser.
#
#   const feed = require("std/feed");
#   feed.parseRss(text)  -> feed object with items[]
#   feed.parseAtom(text) -> feed object with entries[]
#
# Parse-only in v1. Absent options stay absent.

import std/[json, options]

import javascriptcore

import pkg/openparser/[feed, rss]

import ../bridge

proc optStr(obj: JsonNode; key: string; v: Option[string]) =
  if v.isSome:
    obj[key] = %v.get()

proc optInt(obj: JsonNode; key: string; v: Option[int]) =
  if v.isSome:
    obj[key] = %v.get()

# -- RSS ---------------------------------------------------------------

proc rssMediaToJson(m: RssMediaContent): JsonNode =
  result = newJObject()
  optStr(result, "url", m.url)
  optStr(result, "mediaType", m.mediaType)
  optStr(result, "medium", m.medium)
  optInt(result, "height", m.height)
  optInt(result, "width", m.width)

proc rssItemToJson(item: RssItem): JsonNode =
  result = newJObject()
  optStr(result, "title", item.title)
  optStr(result, "link", item.link)
  optStr(result, "description", item.description)
  optStr(result, "pubDate", item.pubDate)
  optStr(result, "category", item.category)
  optStr(result, "guid", item.guid)
  optStr(result, "source", item.source)
  if item.mediaContent.isSome:
    result["mediaContent"] = rssMediaToJson(item.mediaContent.get())

proc rssToJson(f: RssFeed): JsonNode =
  result = %*{
    "title": f.title, "link": f.link, "description": f.description,
    "copyright": f.copyright, "pubDate": f.pubDate,
    "lastBuildDate": f.lastBuildDate, "ttl": f.ttl}
  optStr(result, "atomSelfLink", f.atomSelfLink)
  result["image"] = %*{
    "url": f.image.url, "title": f.image.title, "link": f.image.link}
  var items = newJArray()
  for item in f.items:
    items.add(rssItemToJson(item))
  result["items"] = items

# -- Atom --------------------------------------------------------------

proc atomTextToJson(t: AtomText): JsonNode =
  %*{"kind": t.kind, "value": t.value}

proc atomPersonToJson(p: AtomPerson): JsonNode =
  result = %*{"name": p.name}
  optStr(result, "uri", p.uri)
  optStr(result, "email", p.email)

proc atomLinkToJson(l: AtomLink): JsonNode =
  result = %*{"href": l.href}
  optStr(result, "rel", l.rel)
  optStr(result, "type", l.mimeType)
  optStr(result, "hreflang", l.hreflang)
  optStr(result, "title", l.title)
  optInt(result, "length", l.length)

proc atomCategoryToJson(c: AtomCategory): JsonNode =
  result = %*{"term": c.term}
  optStr(result, "scheme", c.scheme)
  optStr(result, "label", c.label)

proc personsToJson[T](persons: seq[T];
    conv: proc(p: T): JsonNode): JsonNode =
  result = newJArray()
  for p in persons:
    result.add(conv(p))

proc atomEntryToJson(e: AtomEntry): JsonNode =
  result = %*{"id": e.id, "title": atomTextToJson(e.title),
    "updated": e.updated}
  result["authors"] = personsToJson(e.authors, atomPersonToJson)
  result["contributors"] = personsToJson(e.contributors, atomPersonToJson)
  result["links"] = personsToJson(e.links, atomLinkToJson)
  result["categories"] = personsToJson(e.categories, atomCategoryToJson)
  if e.summary.isSome:
    result["summary"] = atomTextToJson(e.summary.get())
  if e.content.isSome:
    let c = e.content.get()
    var obj = newJObject()
    optStr(obj, "kind", c.kind)
    optStr(obj, "src", c.src)
    optStr(obj, "value", c.value)
    result["content"] = obj
  if e.rights.isSome:
    result["rights"] = atomTextToJson(e.rights.get())
  optStr(result, "published", e.published)

proc atomToJson(f: AtomFeed): JsonNode =
  result = %*{"id": f.id, "title": atomTextToJson(f.title),
    "updated": f.updated}
  result["authors"] = personsToJson(f.authors, atomPersonToJson)
  result["contributors"] = personsToJson(f.contributors, atomPersonToJson)
  result["links"] = personsToJson(f.links, atomLinkToJson)
  result["categories"] = personsToJson(f.categories, atomCategoryToJson)
  if f.subtitle.isSome:
    result["subtitle"] = atomTextToJson(f.subtitle.get())
  if f.rights.isSome:
    result["rights"] = atomTextToJson(f.rights.get())
  if f.generator.isSome:
    let g = f.generator.get()
    var obj = %*{"value": g.value}
    optStr(obj, "uri", g.uri)
    optStr(obj, "version", g.version)
    result["generator"] = obj
  optStr(result, "icon", f.icon)
  optStr(result, "logo", f.logo)
  var entries = newJArray()
  for e in f.entries:
    entries.add(atomEntryToJson(e))
  result["entries"] = entries
  optStr(result, "lang", f.lang)
  optStr(result, "base", f.base)

# -- JS entry points ---------------------------------------------------

## Builds the std/feed namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parseRss:
      ## feed.parseRss(text) -> feed object with items[]
      if not checkArity(argumentCount, 1, 1, "parseRss", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parseRss", exception, text):
        return nil
      try:
        returnJson(ctx, rssToJson(parseRss(text)), "parseRss", exception)
      except CatchableError as e:
        throwError(ctx, "parseRss: " & e.msg, exception)
        nil

    module.registerFn parseAtom:
      ## feed.parseAtom(text) -> feed object with entries[]
      if not checkArity(argumentCount, 1, 1, "parseAtom", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parseAtom", exception, text):
        return nil
      try:
        returnJson(ctx, atomToJson(parseAtom(text)), "parseAtom", exception)
      except CatchableError as e:
        throwError(ctx, "parseAtom: " & e.msg, exception)
        nil
