"""Remove em dashes from legal markdown with explicit, reviewable rules.
R1  "- Label — rest" (list label)            -> "- Label: rest"  (fr: "Label : rest")
R2  "A — B — C" paired inside one sentence    -> "A (B) C"         ("— B —," -> "(B),")
R3  any single remaining " — "               -> overrides table, else "; " / " ; " is NOT used: default ": "
Prints every R3 decision so a human can review it."""
import re, sys
SENT = re.compile(r'(?<=[.!?])\s+(?=[A-ZÀ-ÖØ-Þ«“])')
def colon(fr): return ' : ' if fr else ': '
def fix_line(line, fr, log, overrides):
    m6 = re.match(r'^(\s*- )(.*?) — (.*?)\. (Base|Basis) ?:(.*)$', line)
    if m6 and '—' not in m6.group(3):
        return f"{m6.group(1)}{m6.group(2)}. {'Données concernées' if fr else 'Data'}{colon(fr).rstrip()} {m6.group(3)}. {m6.group(4)}{colon(fr).rstrip()}{m6.group(5)}"
    m = re.match(r'^(\s*- )([^—\n]{1,80}?) — (.*)$', line)
    first = SENT.split(line)[0]
    if m and not re.search(r'[.;]\s', m.group(2)) and first.count(' — ') == 1:
        line = m.group(1) + m.group(2) + colon(fr) + m.group(3)
    parts = SENT.split(line)
    out = []
    for s in parts:
        while s.count(' — ') >= 2 or re.search(r' — [^—]+? —[,;.:]', s):
            s2 = re.sub(r' — ([^—]+?) —(?=[,;.:])', r' (\1)', s, count=1)
            if s2 == s:
                s2 = re.sub(r' — ([^—]+?) — ', r' (\1) ', s, count=1)
            if s2 == s: break
            log.append('R2: ' + re.findall(r'\(([^()]*)\)', s2)[-1][:120] if re.findall(r'\(([^()]*)\)', s2) else 'R2: ?')
            s = s2
        if ' — ' in s or '—' in s:
            for k, v in overrides:
                if k in s: s = s.replace(k, v)
            s = re.sub(r' — ((?:voir|see) [^.;]+?)(?=[.;]|$)', r' (\1)', s)
            s = re.sub(r' — (?=(?:et |and )ce\b)', ' ', s) if s.lstrip().startswith('#') else s
            s = re.sub(r' — (?=(?:par exemple|notamment|et |and |dans |in |on |ce que |chacun |each |which |en particulier|là encore|une seule fois|jamais|y compris|sauf|ni |for example|for instance|including|in particular|again|once|never|except|such as|nor )\b)', ', ', s)
            if '—' in s:
                log.append('R3: ' + s.strip())
                s = s.replace(' — ', colon(fr))
        out.append(s)
    # re-join with the original separators
    res = line
    if len(parts) > 1:
        seps = SENT.findall(line) if False else None
    joined = ''
    idx = 0
    pieces = SENT.split(line)
    seps = [m.group(0) for m in SENT.finditer(line)]
    joined = out[0] + ''.join(seps[i] + out[i+1] for i in range(len(seps)))
    return joined
def run(text, fr, overrides=()):
    log = []
    lines = [fix_line(l, fr, log, overrides) if '—' in l else l for l in text.split('\n')]
    return '\n'.join(lines), log
if __name__ == '__main__':
    for f in sys.argv[1:]:
        t = open(f).read(); fr = '.fr.' in f
        new, log = run(t, fr)
        print(f'### {f}: {t.count("—")} -> {new.count("—")}; R3 decisions: {len(log)}')
        for s in log: print('  ·', s[:400])
