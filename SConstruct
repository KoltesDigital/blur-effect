import os

vars = Variables('config.py')

base = Environment(ENV = os.environ, variables = vars)
base.Append(DFLAGS = ['-property'])

Export('base')

Help("""
Type 'scons [target]' where target may be
  debug (default)
  release
  doc
  all
""")

debug = SConscript('SConscript.debug', variant_dir='build/debug', duplicate=0)
release = SConscript('SConscript.release', variant_dir='build/release', duplicate=0)
doc = SConscript('SConscript.doc')

Alias('all', '.')
Alias('debug', debug)
Alias('release', release)
Alias('doc', doc)
Default(debug)
