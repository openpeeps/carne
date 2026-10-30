import std/[os, unittest]
import pkg/openparser/json

import carne/pkg/publish
import carne/pkg/pkgmanifest

test "splitPublishTags handles commas, spaces and dupes":
  check splitPublishTags("web,library,wrapper") == @["web", "library", "wrapper"]
  check splitPublishTags("web library wrapper") == @["web", "library", "wrapper"]
  check splitPublishTags("web,, web  ,library,web") == @["web", "library"]
  check splitPublishTags("") == newSeq[string]()
  check splitPublishTags(" ,  , ") == newSeq[string]()

test "normalizeRepoUrl strips .git and maps scp/ssh to https":
  check normalizeRepoUrl("https://github.com/openpeeps/greet.git") ==
    "https://github.com/openpeeps/greet"
  check normalizeRepoUrl("git@github.com:openpeeps/greet.git") ==
    "https://github.com/openpeeps/greet"
  check normalizeRepoUrl("ssh://git@github.com/openpeeps/greet.git") ==
    "https://github.com/openpeeps/greet"

test "normalizeRepoUrl rejects credentials and garbage":
  expect ValueError:
    discard normalizeRepoUrl("https://user@github.com/openpeeps/greet")
  expect ValueError:
    discard normalizeRepoUrl("not a url at all !!!")
  expect ValueError:
    discard normalizeRepoUrl("")

test "forge aliases expand, unknown shapes raise":
  check expandPublishForgeAlias("gh:openpeeps/greet") ==
    "https://github.com/openpeeps/greet"
  check expandPublishForgeAlias("gl:group/sub/repo") ==
    "https://gitlab.com/group/sub/repo"
  expect ValueError:
    discard expandPublishForgeAlias("gitea:user/repo")
  check isPublishForgeAliasShape("gh:user/repo")
  check not isPublishForgeAliasShape("https://github.com/user/repo")
  check not isPublishForgeAliasShape("git@github.com:user/repo")
  check resolveRepoUrl("gh:openpeeps/greet") ==
    "https://github.com/openpeeps/greet"
  check resolveRepoUrl("https://github.com/openpeeps/greet.git") ==
    "https://github.com/openpeeps/greet"

test "publishEntry builds the registry schema":
  let entry = publishEntry("greet", "https://github.com/openpeeps/greet",
    "Say hi from Carne", "MIT", "https://github.com/openpeeps/greet",
    @["carne", "greet"])
  check entry["name"].getStr == "greet"
  check entry["url"].getStr == "https://github.com/openpeeps/greet"
  check entry["method"].getStr == "git"
  check entry["tags"].len == 2
  check entry["description"].getStr == "Say hi from Carne"
  check entry["license"].getStr == "MIT"
  check entry["web"].getStr == "https://github.com/openpeeps/greet"

test "entryExists finds names, misses others":
  let arr = %*[
    {"name": "greet", "url": "https://github.com/openpeeps/greet"},
    {"name": "concarne", "url": "https://github.com/georgelemon/concarne"}
  ]
  check entryExists(arr, "concarne")
  check not entryExists(arr, "kapsis")
  check not entryExists(newJArray(), "kapsis")
  check not entryExists(%*{"name": "greet"}, "other")

test "insertEntrySorted keeps name order and skips dupes":
  var arr = %*[
    {"name": "concarne"}, {"name": "greet"}
  ]
  insertEntrySorted(arr, %*{"name": "apple"})
  check arr[0]["name"].getStr == "apple"
  check arr[1]["name"].getStr == "concarne"
  check arr[2]["name"].getStr == "greet"
  insertEntrySorted(arr, %*{"name": "mango"})
  check arr[3]["name"].getStr == "mango"
  let before = arr.len
  insertEntrySorted(arr, %*{"name": "greet"})
  check arr.len == before

test "manifestKeywords reads, cleans and validates":
  check manifestKeywords(fromJson("""{"keywords": ["carne", " http "]}""")) ==
    @["carne", "http"]
  check manifestKeywords(fromJson("""{"keywords": ["a", "a", "", "b"]}""")) ==
    @["a", "b"]
  check manifestKeywords(fromJson("""{"name": "x"}""")) == newSeq[string]()
  expect ValueError:
    discard manifestKeywords(fromJson("""{"keywords": "carne"}"""))
  expect ValueError:
    discard manifestKeywords(fromJson("""{"keywords": [42]}"""))

test "manifestHomepage reads the homepage string":
  check manifestHomepage(fromJson(
    """{"homepage": "https://github.com/openpeeps/greet"}""")) ==
    "https://github.com/openpeeps/greet"
  check manifestHomepage(fromJson("""{"name": "x"}""")) == ""

test "readPublishToken parses KEY=VALUE with comments and quotes":
  let dir = getTempDir() / "carne_publish_tokens"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  defer: removeDir(dir)
  let f = dir / ".tokens"
  writeFile(f, "# secrets\nOTHER=1\nCARNE_GITHUB_TOKEN=ghp_test123\n")
  check readPublishToken(f) == "ghp_test123"
  writeFile(f, "CARNE_GITHUB_TOKEN=\"quoted-token\"  \n")
  check readPublishToken(f) == "quoted-token"
  writeFile(f, "CARNE_GITHUB_TOKEN=\n")
  check readPublishToken(f) == ""
  writeFile(f, "SOMETHING_ELSE=1\n")
  check readPublishToken(f) == ""
  check readPublishToken(dir / "missing") == ""

test "tokensFilePath honors an explicit home":
  check tokensFilePath("/tmp/fakehome") == "/tmp/fakehome" / ".tokens"

test "publishCommand dry-run prints the entry offline":
  let dir = getTempDir() / "carne_publish_dryrun"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  defer: removeDir(dir)
  writeFile(dir / "package.json", """{
    "name": "greet", "version": "0.1.0",
    "description": "Say hi", "license": "MIT",
    "keywords": ["carne", "greet"],
    "homepage": "https://github.com/openpeeps/greet"
  }""")
  # No git remote here: --url override keeps the dry run hermetic.
  check publishCommand(dir, (tags: "", web: "",
    urlOverride: "https://github.com/openpeeps/greet",
    dryRun: true, yesMode: false)) == 0

test "publishCommand refuses undescribed and keywordless packages":
  let dir = getTempDir() / "carne_publish_refuse"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  defer: removeDir(dir)
  writeFile(dir / "package.json", """{
    "name": "greet", "version": "0.1.0", "license": "MIT",
    "keywords": ["carne"]
  }""")
  check publishCommand(dir, (tags: "", web: "",
    urlOverride: "https://github.com/openpeeps/greet",
    dryRun: true, yesMode: false)) == 1
  writeFile(dir / "package.json", """{
    "name": "greet", "version": "0.1.0",
    "description": "Say hi", "license": "MIT"
  }""")
  check publishCommand(dir, (tags: "", web: "",
    urlOverride: "https://github.com/openpeeps/greet",
    dryRun: true, yesMode: false)) == 1

test "publishCommand needs a remote or --url":
  let dir = getTempDir() / "carne_publish_noremote"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  defer: removeDir(dir)
  writeFile(dir / "package.json", """{
    "name": "greet", "version": "0.1.0",
    "description": "Say hi", "license": "MIT",
    "keywords": ["carne"]
  }""")
  check publishCommand(dir, (tags: "", web: "", urlOverride: "",
    dryRun: true, yesMode: false)) == 1
