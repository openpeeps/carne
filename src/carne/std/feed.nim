# Carne std/feed: RSS and Atom feed parsing via openparser.
#
#   const feed = require("std/feed");
#   feed.parseRss(text)  -> feed object with items[]
#   feed.parseAtom(text) -> feed object with entries[]
#
# Parse-only in v1. Absent options stay absent.

import std/options

import javascriptcore

import pkg/openparser/[feed, rss]

import ../bridge



proc personsToJS[T](ctx: JSContextRef; persons: seq[T]; fname: string;
    exception: ptr JSValueRef;
    conv: proc(ctx: JSContextRef; p: T; fname: string;
      exception: ptr JSValueRef): JSValueRef): JSValueRef =
  var vals: seq[JSValueRef] = @[]
  for p in persons:
    let j = conv(ctx, p, fname, exception)
    if j == nil:
      return nil
    vals.add(j)
  let arr = makeJSArray(ctx, vals)
  if arr == nil:
    throwError(ctx, fname & ": could not convert result to JS",
      exception)
    return nil
  arr

# -- RSS ---------------------------------------------------------------

proc rssMediaToJS(ctx: JSContextRef; m: RssMediaContent; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not optSetStr(ctx, obj, "url", m.url, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "mediaType", m.mediaType, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "medium", m.medium, fname, exception):
    return nil
  if not optSetInt(ctx, obj, "height", m.height, fname, exception):
    return nil
  if not optSetInt(ctx, obj, "width", m.width, fname, exception):
    return nil
  obj

proc rssItemToJS(ctx: JSContextRef; item: RssItem; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not optSetStr(ctx, obj, "title", item.title, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "link", item.link, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "description", item.description, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "pubDate", item.pubDate, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "category", item.category, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "guid", item.guid, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "source", item.source, fname, exception):
    return nil
  if item.mediaContent.isSome:
    let m = rssMediaToJS(ctx, item.mediaContent.get(), fname, exception)
    if m == nil:
      return nil
    if not setPropChecked(ctx, obj, "mediaContent", m, fname, exception):
      return nil
  obj

proc rssToJS(ctx: JSContextRef; f: RssFeed; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  for (key, val) in [("title", f.title), ("link", f.link),
      ("description", f.description), ("copyright", f.copyright),
      ("pubDate", f.pubDate), ("lastBuildDate", f.lastBuildDate)]:
    if not setPropChecked(ctx, obj, key, toJS(ctx, val), fname,
        exception):
      return nil
  if not setPropChecked(ctx, obj, "ttl", toJS(ctx, f.ttl), fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "atomSelfLink", f.atomSelfLink, fname,
      exception):
    return nil
  let img = newObject(ctx)
  if not setPropChecked(ctx, img, "url", toJS(ctx, f.image.url), fname,
      exception):
    return nil
  if not setPropChecked(ctx, img, "title", toJS(ctx, f.image.title),
      fname, exception):
    return nil
  if not setPropChecked(ctx, img, "link", toJS(ctx, f.image.link),
      fname, exception):
    return nil
  if not setPropChecked(ctx, obj, "image", img, fname, exception):
    return nil
  let items = personsToJS(ctx, f.items, fname, exception, rssItemToJS)
  if items == nil:
    return nil
  if not setPropChecked(ctx, obj, "items", items, fname, exception):
    return nil
  obj

# -- Atom --------------------------------------------------------------

proc atomTextToJS(ctx: JSContextRef; t: AtomText): JSValueRef =
  let obj = newObject(ctx)
  var ex: JSValueRef = nil
  setProp(ctx, obj, "kind", toJS(ctx, t.kind), addr ex)
  setProp(ctx, obj, "value", toJS(ctx, t.value), addr ex)
  if ex != nil:
    return nil
  obj

proc atomPersonToJS(ctx: JSContextRef; p: AtomPerson; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "name", toJS(ctx, p.name), fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "uri", p.uri, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "email", p.email, fname, exception):
    return nil
  obj

proc atomLinkToJS(ctx: JSContextRef; l: AtomLink; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "href", toJS(ctx, l.href), fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "rel", l.rel, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "type", l.mimeType, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "hreflang", l.hreflang, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "title", l.title, fname, exception):
    return nil
  if not optSetInt(ctx, obj, "length", l.length, fname, exception):
    return nil
  obj

proc atomCategoryToJS(ctx: JSContextRef; c: AtomCategory; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "term", toJS(ctx, c.term), fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "scheme", c.scheme, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "label", c.label, fname, exception):
    return nil
  obj

proc atomEntryToJS(ctx: JSContextRef; e: AtomEntry; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "id", toJS(ctx, e.id), fname,
      exception):
    return nil
  let title = atomTextToJS(ctx, e.title)
  if title == nil:
    throwError(ctx, fname & ": could not convert result to JS",
      exception)
    return nil
  if not setPropChecked(ctx, obj, "title", title, fname, exception):
    return nil
  if not setPropChecked(ctx, obj, "updated", toJS(ctx, e.updated),
      fname, exception):
    return nil
  template setPeople(key: string; items, conv: untyped): untyped =
    let arrVal = personsToJS(ctx, items, fname, exception, conv)
    if arrVal == nil:
      return nil
    if not setPropChecked(ctx, obj, key, arrVal, fname, exception):
      return nil
  setPeople("authors", e.authors, atomPersonToJS)
  setPeople("contributors", e.contributors, atomPersonToJS)
  setPeople("links", e.links, atomLinkToJS)
  setPeople("categories", e.categories, atomCategoryToJS)
  if e.summary.isSome:
    let s = atomTextToJS(ctx, e.summary.get())
    if s == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "summary", s, fname, exception):
      return nil
  if e.content.isSome:
    let c = e.content.get()
    let cobj = newObject(ctx)
    if not optSetStr(ctx, cobj, "kind", c.kind, fname, exception):
      return nil
    if not optSetStr(ctx, cobj, "src", c.src, fname, exception):
      return nil
    if not optSetStr(ctx, cobj, "value", c.value, fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "content", cobj, fname, exception):
      return nil
  if e.rights.isSome:
    let r = atomTextToJS(ctx, e.rights.get())
    if r == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "rights", r, fname, exception):
      return nil
  if not optSetStr(ctx, obj, "published", e.published, fname, exception):
    return nil
  obj

proc atomToJS(ctx: JSContextRef; f: AtomFeed; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "id", toJS(ctx, f.id), fname,
      exception):
    return nil
  let title = atomTextToJS(ctx, f.title)
  if title == nil:
    throwError(ctx, fname & ": could not convert result to JS",
      exception)
    return nil
  if not setPropChecked(ctx, obj, "title", title, fname, exception):
    return nil
  if not setPropChecked(ctx, obj, "updated", toJS(ctx, f.updated),
      fname, exception):
    return nil
  template setPeople(key: string; items, conv: untyped): untyped =
    let arrVal = personsToJS(ctx, items, fname, exception, conv)
    if arrVal == nil:
      return nil
    if not setPropChecked(ctx, obj, key, arrVal, fname, exception):
      return nil
  setPeople("authors", f.authors, atomPersonToJS)
  setPeople("contributors", f.contributors, atomPersonToJS)
  setPeople("links", f.links, atomLinkToJS)
  setPeople("categories", f.categories, atomCategoryToJS)
  if f.subtitle.isSome:
    let s = atomTextToJS(ctx, f.subtitle.get())
    if s == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "subtitle", s, fname, exception):
      return nil
  if f.rights.isSome:
    let r = atomTextToJS(ctx, f.rights.get())
    if r == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "rights", r, fname, exception):
      return nil
  if f.generator.isSome:
    let g = f.generator.get()
    let gobj = newObject(ctx)
    if not setPropChecked(ctx, gobj, "value", toJS(ctx, g.value), fname,
        exception):
      return nil
    if not optSetStr(ctx, gobj, "uri", g.uri, fname, exception):
      return nil
    if not optSetStr(ctx, gobj, "version", g.version, fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "generator", gobj, fname,
        exception):
      return nil
  if not optSetStr(ctx, obj, "icon", f.icon, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "logo", f.logo, fname, exception):
    return nil
  let entries = personsToJS(ctx, f.entries, fname, exception,
    atomEntryToJS)
  if entries == nil:
    return nil
  if not setPropChecked(ctx, obj, "entries", entries, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "lang", f.lang, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "base", f.base, fname, exception):
    return nil
  obj

# -- JS entry points ---------------------------------------------------

## Builds the std/feed namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parseRss(text: string):
      ## feed.parseRss(text) -> feed object with items[]
      try:
        let j = rssToJS(ctx, parseRss(text), "parseRss", exception)
        if j == nil:
          throwError(ctx, "parseRss: could not convert result to JS",
            exception)
          return nil
        j
      except CatchableError as e:
        throwError(ctx, "parseRss: " & e.msg, exception)
        nil

    module.registerFn parseAtom(text: string):
      ## feed.parseAtom(text) -> feed object with entries[]
      try:
        let j = atomToJS(ctx, parseAtom(text), "parseAtom", exception)
        if j == nil:
          throwError(ctx, "parseAtom: could not convert result to JS",
            exception)
          return nil
        j
      except CatchableError as e:
        throwError(ctx, "parseAtom: " & e.msg, exception)
        nil
