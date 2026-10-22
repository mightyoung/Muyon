import pathlib,subprocess,concurrent.futures,hashlib,json,re,os,time
root=pathlib.Path('/workspace/ui-shell-tools/maven-offline-restore');repo=root/'repository';repo.mkdir(exist_ok=True)
origins=['https://dl.google.com/dl/android/maven2/','https://repo.maven.apache.org/maven2/','https://plugins.gradle.org/m2/']
manifest=root/'downloads.jsonl'; negative=set(json.loads((root/'negative-paths.json').read_text())) if (root/'negative-paths.json').exists() else set();counter=0
cache=pathlib.Path('/workspace/ui-shell-tools/gradle-cache/caches/modules-2/files-2.1')
def fetch(rel):
 target=repo/rel
 if target.exists():return True
 if rel in negative:return False
 target.parent.mkdir(parents=True,exist_ok=True)
 # Reuse Gradle-owned cache bytes if available; source provenance recorded as cache.
 parts=rel.split('/')
 if len(parts)>=4 and cache.exists():
  group='.'.join(parts[:-3]);artifact,version,name=parts[-3:]
  for existing in (cache/group/artifact/version).glob('*/'+name):
   data=existing.read_bytes();target.write_bytes(data)
   with manifest.open('a') as f:f.write(json.dumps(dict(path=rel,cache=str(existing),sha256=hashlib.sha256(data).hexdigest(),size=len(data)))+'\n')
   return True
 for origin in origins:
  tmp=target.with_name(target.name+'.part')
  r=subprocess.run(['curl','--fail','--silent','--show-error','--location','--proto','=https','--proto-redir','=https','--connect-timeout','10','--max-time','70','--output',str(tmp),'--write-out','%{url_effective}',origin+rel],capture_output=True,text=True)
  if r.returncode==0:
   data=tmp.read_bytes();tmp.replace(target)
   with manifest.open('a') as f:f.write(json.dumps(dict(path=rel,url=origin+rel,effective_url=r.stdout,sha256=hashlib.sha256(data).hexdigest(),size=len(data)))+'\n')
   return True
  tmp.unlink(missing_ok=True)
 negative.add(rel);return False
# Plugin marker POMs bootstrap; plugin JARs are resolved from their declared dependencies.
seeds=['com/android/application/com.android.application.gradle.plugin/8.11.1/com.android.application.gradle.plugin-8.11.1.pom','org/jetbrains/kotlin/android/org.jetbrains.kotlin.android.gradle.plugin/2.2.20/org.jetbrains.kotlin.android.gradle.plugin-2.2.20.pom','org/jetbrains/kotlin/plugin/compose/org.jetbrains.kotlin.plugin.compose.gradle.plugin/2.2.20/org.jetbrains.kotlin.plugin.compose.gradle.plugin-2.2.20.pom']
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:list(pool.map(fetch,seeds))
env=os.environ.copy();env.update(JAVA_HOME='/workspace/ui-shell-tools/jdk-17.0.21+9',ANDROID_USER_HOME='/workspace/ui-shell-tools/android-user',ANDROID_HOME='/workspace/ui-shell-tools/sdk',GRADLE_USER_HOME='/workspace/ui-shell-tools/gradle-cache',MUYON_UI_GRADLE='/workspace/ui-shell-tools/gradle-8.13/bin/gradle')
cmd=['/workspace/ui-shell-tools/gradle-8.13/bin/gradle','--offline','--no-daemon','--console=plain','--init-script',str(root/'local.init.gradle'),*os.environ.get('RESTORE_TASKS',':app:compileDebugKotlin :app:compileDebugAndroidTestKotlin').split()]
start=max([int(p.stem.split('-')[-1]) for p in root.glob('gradle-*.log')]+[0])+1
for counter in range(start,start+60):
 r=subprocess.run(cmd,cwd='/workspace/muyon-ui-shell/apps/muyon_android',env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=300)
 (root/('gradle-%03d.log'%counter)).write_text('ENV '+json.dumps({k:env.get(k) for k in ['JAVA_HOME','ANDROID_HOME','ANDROID_USER_HOME','GRADLE_USER_HOME']})+'\nCOMMAND '+ ' '.join(cmd)+'\n'+r.stdout+'\nEXIT '+str(r.returncode)+'\n')
 print('ITERATION',counter,'EXIT',r.returncode,flush=True)
 if r.returncode==0:break
 paths=set(re.findall(r'file:'+re.escape(str(repo))+r'/([^\s)\]<>]+)',r.stdout))
 # App configuration failures sometimes omit searched file locations; derive exact Maven coordinates.
 for group,artifact,version in re.findall(r'Could not find ([\w.\-]+):([\w.\-]+):([^\s]+)\.',r.stdout):
  if version and '/' not in version and ':' not in version:
   paths.add(group.replace('.','/')+'/'+artifact+'/'+version+'/'+artifact+'-'+version+'.pom')
 # Gradle commonly probes .module only after Maven POM exists; retrieve official module sibling too.
 for path in list(paths):
  if path.endswith('.pom'):paths.add(path[:-4]+'.module')
 missing=sorted(x for x in paths if not (repo/x).exists() and x not in negative)
 print('MISSING',len(missing),flush=True)
 if not missing:
  print(r.stdout[-6000:],flush=True);break
 with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:results=list(pool.map(fetch,missing))
 print('FETCHED',sum(results),'of',len(results),flush=True)
 if not any(results):print(r.stdout[-6000:],flush=True);break
(root/'negative-paths.json').write_text(json.dumps(sorted(negative),indent=2))
