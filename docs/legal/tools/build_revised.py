import sys, glob, os
sys.path.insert(0, os.path.dirname(__file__))
from dedash import run
# Hand-written replacements where a mechanical rule reads badly. Applied first, each must match once.
OVERRIDES = {
 'fr': [
  ('concernant votre utilisation de FunctionAlps — c’est-à-dire l’ensemble : l’application,', 'concernant votre utilisation de FunctionAlps, c’est-à-dire de l’ensemble du service : l’application,'),
  ('au sujet du service lui-même — sécurité, modification des présentes conditions, problème sur votre compte.', 'au sujet du service lui-même (sécurité, modification des présentes conditions, problème sur votre compte).'),
  ('à thomas@functionalps.ch — nous préférons', 'à thomas@functionalps.ch. Nous préférons'),
  ('Vous — dans l’application comme sur le tableau de bord membres, qui vous présentent le même dossier.', 'Vous, dans l’application comme sur le tableau de bord membres, qui vous présentent le même dossier.'),
  ('vous fournir le service — vous restituer vos saisies', 'vous fournir le service, c’est-à-dire vous restituer vos saisies'),
  ('construits à partir de vos propres données — dans l’application comme sur le tableau de bord membres', 'construits à partir de vos propres données, dans l’application comme sur le tableau de bord membres'),
 ],
 'en': [
  ('for one purpose: providing you the service — showing you what you logged', 'for one purpose: providing you the service, which means showing you what you logged'),
  ('at thomas@functionalps.ch — we would rather', 'at thomas@functionalps.ch. We would rather'),
 ],
}
SUMMARY_FIX = {
 'Les règles d’utilisation de FunctionAlps — et ce qu’elle n’est pas.': 'Les règles d’utilisation de FunctionAlps, et ce qu’elle n’est pas.',
}
def build(src, dst):
    t = open(src).read(); lang = 'fr' if '.fr.' in src else 'en'
    for a, b in OVERRIDES[lang]:
        n = t.count(a)
        if n > 1: raise SystemExit(f'{src}: override occurs {n}x: {a[:50]}')
        t = t.replace(a, b)
    new, log = run(t, lang == 'fr')
    assert '—' not in new and '–' not in new, src
    open(dst, 'w').write(new)
    return log
if __name__ == '__main__':
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    for src in sys.argv[2:]:
        build(src, os.path.join(out, os.path.basename(src)))
        print('built', src)
