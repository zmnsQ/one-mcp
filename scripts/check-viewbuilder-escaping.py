#!/usr/bin/env python3
"""Compile the production closure parameter against an escaping receiver.

This checks Swift closure typing, not SwiftUI/AppKit availability or a native app build.
The negative control reproduces the original compiler error without @escaping.
"""
import os, pathlib, re, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parent.parent
source=(root/'Sources/MCPHarbor/MenuBarPanel.swift').read_text()
section=source.split('private func statusSection<')[1].split('private func confirmStop')[0]
parameter=re.search(r'@ViewBuilder (content:\s*(?:@escaping\s+)?\(\)\s*->\s*Content)',section).group(1)
# Capture the real production parameter spelling, not a hard-coded @escaping assertion.
def program(parameter):
    return '''struct Stored<Content> {
  let render: () -> Content
  init(_ render: @escaping () -> Content) { self.render = render }
}
func statusSection<Content>('''+parameter+''') -> Stored<Content> {
  Stored { content() }
}
let view = statusSection { 42 }
precondition(view.render() == 42)
'''
swift=os.environ.get('SWIFTC','swiftc')
with tempfile.TemporaryDirectory(prefix='onemcp-escaping-') as d:
    path=pathlib.Path(d)/'Capture.swift'; binary=pathlib.Path(d)/'capture'
    path.write_text(program(parameter))
    good=subprocess.run([swift,'-module-cache-path',str(pathlib.Path(d)/'cache'),str(path),'-o',str(binary)],capture_output=True,text=True)
    if good.returncode: raise SystemExit(good.stderr)
    subprocess.run([str(binary)],check=True)
    path.write_text(program(parameter.replace('@escaping ','')))
    bad=subprocess.run([swift,'-module-cache-path',str(pathlib.Path(d)/'cache'),str(path),'-o',str(binary)],capture_output=True,text=True)
    assert bad.returncode != 0 and 'escaping closure captures non-escaping parameter' in bad.stderr, bad.stderr
print('PASS production statusSection closure compiled and executed; negative control reproduces escaping-capture failure')
