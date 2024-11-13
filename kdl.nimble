# Package

version       = "2.0.2"
author        = "Patitotective"
description   = "KDL document language Nim implementation"
license       = "MIT"
srcDir        = "src"
skipFiles     = @["src/kdl/query.nim", "src/kdl/schema.nim"]

# Dependencies

requires "nim >= 1.6.0"

task docs, "Generate documentation":
  # We create the prefs module documentation separately because it is not imported in the main kdl file as it's not backed:js friendly
  exec "nim doc --outdir:docs/kdl --index:on src/kdl/prefs.nim"
  exec "echo \"<meta http-equiv=\\\"Refresh\\\" content=\\\"0; url='kdl/prefs.html'\\\" />\" >> docs/prefs.html"

  # Here we make it so when you click 'Index' in the prefs.html file it redirects to theindex.html.
  exec "echo \"<meta http-equiv=\\\"Refresh\\\" content=\\\"0; url='../theindex.html'\\\" />\" >> docs/kdl/theindex.html"

  exec "nim doc --git.url:https://github.com/Patitotective/kdl-nim --git.commit:main --outdir:docs --project src/kdl.nim"
  exec "echo \"<meta http-equiv=\\\"Refresh\\\" content=\\\"0; url='kdl.html'\\\" />\" >> docs/index.html"
