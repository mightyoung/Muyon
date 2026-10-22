from pathlib import Path
import subprocess
root=Path('/workspace/bot-setup-draft')
source=root/'apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agents/setup/BotSetupDraft.kt'
tests=root/'apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/BotSetupDraftChecks.kt'
original=source.read_text()
mutations={
 'late-result': ('if (cancelled || token != request || token.revision != revision) return false','if (cancelled) return false'),
 'user-lock': ('|| role.userLocked',''),
 'unknown-unfreeze': ('require(!cancelled && creation.status in setOf(CreationStatus.NOT_REQUESTED, CreationStatus.REJECTED))','require(!cancelled)'),
 'unconfirmed-review': ('require(invalidations.isEmpty())', 'require(true)'),
 'cross-scope': ('require(allowedMaterials.all { it.id.isNotBlank() && it.scope == scope })','require(allowedMaterials.all { it.id.isNotBlank() })'),
}
for label,(before,after) in mutations.items():
 assert before in original
 folder=Path('/tmp/bot-setup-mutation-'+label);folder.mkdir(exist_ok=True)
 mutated=folder/'BotSetupDraft.kt';mutated.write_text(original.replace(before,after))
 compiled=subprocess.run(['/tmp/bot-setup-tools/kotlinc/bin/kotlinc',str(mutated),str(tests),'-include-runtime','-d',str(folder/'checks.jar')],capture_output=True,text=True)
 if compiled.returncode: raise RuntimeError('mutation compile failed '+compiled.stderr)
 run=subprocess.run(['java','-jar',str(folder/'checks.jar')],capture_output=True,text=True)
 assert run.returncode != 0,label+' survived'
 print(label+': KILLED by behavioral check',flush=True)
