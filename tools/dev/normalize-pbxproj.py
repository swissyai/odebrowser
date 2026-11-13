import re, sys
# XcodeGen assigns the bodies of copy-file phases that share a name to their ids in no fixed
# order. Give each id the body upstream gives it, when the bodies are only permuted.
BLOCK = re.compile(r"(\t\t([0-9A-F]{24}) /\* ([^*]+) \*/ = \{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n(?:.*\n)*?\t\t\};\n)")
def blocks(text):
    return {m.group(2): (m.group(3), m.group(1)) for m in BLOCK.finditer(text)}
def normalize(generated, reference):
    gen, ref = blocks(generated), blocks(reference)
    def body(b, i): return b.replace(i, "ID", 1)
    by_name = {}
    for i, (name, b) in gen.items(): by_name.setdefault(name, []).append(i)
    out = generated
    for name, ids in by_name.items():
        if len(ids) < 2 or not all(i in ref for i in ids): continue
        gen_bodies = sorted(body(gen[i][1], i) for i in ids); ref_bodies = sorted(body(ref[i][1], i) for i in ids)
        if gen_bodies != ref_bodies: continue
        for i in ids:
            out = out.replace(gen[i][1], "\x00" + i + "\x00", 1)
        for i in ids:
            out = out.replace("\x00" + i + "\x00", ref[i][1], 1)
    return out
# Usage: python3 tools/dev/normalize-pbxproj.py Ode.xcodeproj/project.pbxproj <reference project.pbxproj>
# for example the committed file: git show HEAD:Ode.xcodeproj/project.pbxproj > /tmp/ref.pbxproj
if __name__ == "__main__":
    path, ref = sys.argv[1], sys.argv[2]
    text = open(path).read(); fixed = normalize(text, open(ref).read())
    if fixed != text: open(path, "w").write(fixed); print("normalized copy phases")
