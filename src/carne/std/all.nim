# Carne full stdlib registry: registers every std implementation.
#
# Imported by the `carne` binary only (see ../../carne.nim). Tests
# import just the std modules they use and call registerStd for those,
# so each test compiles a fraction of this graph.

import ../modules

import ./env
import ./fs
import ./yaml
import ./toml
import ./ical
import ./dotenv
import ./plist
import ./bson
import ./vcard
import ./feed
import ./csv
import ./xml
import ./sql
import ./crypto
import ./path
import ./colors
import ./css
import ./diff
import ./gettext
import ./regex
import ./qr
import ./svg
import ./http
import ./ws

registerStd("std/env", env.install)
registerStd("std/fs", fs.install)
registerStd("std/yaml", yaml.install)
registerStd("std/toml", toml.install)
registerStd("std/ical", ical.install)
registerStd("std/dotenv", dotenv.install)
registerStd("std/plist", plist.install)
registerStd("std/bson", bson.install)
registerStd("std/vcard", vcard.install)
registerStd("std/feed", feed.install)
registerStd("std/csv", csv.install)
registerStd("std/xml", xml.install)
registerStd("std/sql", sql.install)
registerStd("std/crypto", crypto.install)
registerStd("std/path", path.install)
registerStd("std/colors", colors.install)
registerStd("std/css", css.install)
registerStd("std/diff", diff.install)
registerStd("std/gettext", gettext.install)
registerStd("std/regex", regex.install)
registerStd("std/qr", qr.install)
registerStd("std/svg", svg.install)
registerStd("std/http", http.install)
registerStd("std/ws", ws.install)
