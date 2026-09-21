#!/usr/bin/env python3
import pathlib,sys,hashlib
p=pathlib.Path('MTJudge.xcodeproj/project.pbxproj');s=p.read_text()
for path in sys.argv[1:]:
 name=pathlib.Path(path).name
 ref=hashlib.sha1(('ref'+path).encode()).hexdigest()[:24].upper();build=hashlib.sha1(('build'+path).encode()).hexdigest()[:24].upper()
 if ref in s: continue
 ext=pathlib.Path(path).suffix;typ={'.m':'sourcecode.c.objc','.h':'sourcecode.c.h','.swift':'sourcecode.swift'}[ext]
 s=s.replace('/* End PBXFileReference section */',f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {typ}; path = "{path}"; sourceTree = SOURCE_ROOT; }};\n/* End PBXFileReference section */')
 marker='0E35982A226550C80093671C /* Sources */ = {'
 if ext!='.h':
  s=s.replace('/* End PBXBuildFile section */',f'\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref}; }};\n/* End PBXBuildFile section */')
  start=s.index(marker);index=s.index('files = (',start)+len('files = (');s=s[:index]+f'\n\t\t\t\t{build} /* {name} in Sources */,'+s[index:]
 # Place source references in the existing app group.
 start=s.index('/* Begin PBXGroup section */');index=s.index('children = (',s.index('0E35982',start))+len('children = (');s=s[:index]+f'\n\t\t\t\t{ref} /* {name} */,'+s[index:]
p.write_text(s)
