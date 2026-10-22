import pathlib, tempfile, subprocess, shutil
source=pathlib.Path('/workspace/Muyon-post-pr103-retirement-20261022')
pins=['214b4031deb38ca7dfd35ee86396089eb48157d5','01e56cc2d729dab70e1b1def05c3aa93b28f421a','8c5995515fa14ca3592a1c33c71afb4e4c1e5def','4d15b990f725d41a43b86fcd2b170b2219a6f766']
with tempfile.TemporaryDirectory(prefix='muyon-provenance-local-') as tmp:
 root=pathlib.Path(tmp)
 subprocess.run(['git','archive','HEAD'],cwd=source,stdout=(root/'tree.tar').open('wb'),check=True)
 subprocess.run(['tar','-xf','tree.tar'],cwd=root,check=True)
 subprocess.run(['git','init','-q'],cwd=root,check=True)
 subprocess.run(['git','fetch','--no-tags','--depth=1','/workspace/Muyon/.git',*pins],cwd=root,check=True)
 assert subprocess.check_output(['git','rev-parse','--is-shallow-repository'],cwd=root,text=True).strip()=='true'
 subprocess.run(['python3','-B','scripts/check_legacy_schema_reference.py'],cwd=root,check=True)
 subprocess.run(['python3','-B','scripts/test_retirement_prerequisites.py'],cwd=root,check=True)
 print('PASS: new isolated shallow repository; all four exact pin objects and 23 source witnesses checked. Transport local file, not GitHub network; no shared Git mutation.')
