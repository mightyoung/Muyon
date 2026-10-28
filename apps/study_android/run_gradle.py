#!/usr/bin/env python3
"""Run Gradle with the current process proxy (ephemeral Work environments rotate it)."""
import os, pathlib, subprocess, sys, urllib.parse
root=pathlib.Path(__file__).resolve().parent
gradle=os.environ.get('MUYON_GRADLE','gradle')
proxy=urllib.parse.urlparse(os.environ.get('HTTPS_PROXY',os.environ.get('https_proxy','')))
args=[gradle,'-p',str(root),'--no-daemon','--max-workers=2']
if proxy.hostname:
    args += [f'-Dhttps.proxyHost={proxy.hostname}',f'-Dhttps.proxyPort={proxy.port or 80}',f'-Dhttp.proxyHost={proxy.hostname}',f'-Dhttp.proxyPort={proxy.port or 80}']
sys.exit(subprocess.call(args+sys.argv[1:]))
