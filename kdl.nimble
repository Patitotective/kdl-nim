# Package

version       = "1.2.4"
author        = "Patitotective"
description   = "KDL document language Nim implementation"
license       = "MIT"
srcDir        = "src"
skipFiles     = @["src/kdl/query.nim", "src/kdl/schema.nim"]

# Dependencies

requires "nim >= 1.6.0"

task docs, "Generate documentation":
  exec "nim doc --outdir:docs/kdl --index:on src/kdl/prefs.nim"
  exec "echo \"<meta http-equiv=\\\"Refresh\\\" content=\\\"0; url='kdl/prefs.html'\\\" />\" >> docs/prefs.html"
  exec "nim doc --git.url:https://github.com/Patitotective/kdl-nim --git.commit:main --outdir:docs --project src/kdl.nim"
  exec "echo \"<meta http-equiv=\\\"Refresh\\\" content=\\\"0; url='kdl.html'\\\" />\" >> docs/index.html"
