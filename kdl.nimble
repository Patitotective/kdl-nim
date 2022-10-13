# Package

version       = "0.2.1"
author        = "Patitotective"
description   = "KDL document language Nim implementation"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.6"

task docs, "Generate documentation":
  exec "nim doc --git.url:https://github.com/Patitotective/kdl-nim --git.commit:main --outdir:docs --project src/kdl.nim"
  exec "echo \"<meta http-equiv=\\\"Refresh\\\" content=\\\"0; url='kdl.html'\\\" />\" >> docs/index.html"
