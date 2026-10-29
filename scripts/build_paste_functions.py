"""Regenerate supabase/functions_paste/*.ts: each edge function as one file with its
_shared imports inlined, for deploying from the Supabase dashboard editor without the CLI.
Run from the repo root:  python3 scripts/build_paste_functions.py"""
import pathlib, re

root = pathlib.Path("supabase/functions")
out = pathlib.Path("supabase/functions_paste")
imp = re.compile(r'^import \{([^}]*)\} from "\.\./_shared/(\w+)\.ts";\n', re.M)

for fn in ["create-order", "stripe-webhook", "notify-ready"]:
    src = (root / fn / "index.ts").read_text()
    shared = [m.group(2) for m in imp.finditer(src)]
    src = imp.sub("", src)
    lines = src.split("\n")
    last_import = max(i for i, l in enumerate(lines) if l.startswith("import "))
    blocks = []
    for name in shared:
        body = (root / "_shared" / f"{name}.ts").read_text().rstrip() + "\n"
        blocks.append(f"// ---- inlined from _shared/{name}.ts ----\n{body}")
    inlined = "\n".join(blocks) + "// ---- end inlined ----\n"
    merged = "\n".join(lines[: last_import + 1]) + "\n\n" + inlined + "\n".join(lines[last_import + 1 :])
    (out / f"{fn}.ts").write_text(merged)
    print("wrote", out / f"{fn}.ts", "inlined:", ", ".join(shared) or "-")
