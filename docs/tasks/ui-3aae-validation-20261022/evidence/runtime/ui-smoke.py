from ui import hierarchy,capture,tap
from device import shell
n=capture('cold-uninitialized');assert any(x.get('text')=='请创建新工作台' for x in n)
tap(n,text='创建新工作台')
# Mutation occurs once; a subsequent read failure stops. Recovery must inspect state, not replay.
n=capture('main-empty');assert any(x.get('text')=='今天想做些什么？' for x in n)
tap(n,**{'content-desc':'打开工作空间导航'})
n=capture('menu-open');tap(n,**{'content-desc':'关闭菜单'})
n=hierarchy('menu-explicit-close');assert any(x.get('text')=='今天想做些什么？' for x in n)
tap(n,**{'content-desc':'打开工作空间导航'});hierarchy('menu-second-open');print(shell('input keyevent 4'))
n=hierarchy('menu-back-close');assert any(x.get('text')=='今天想做些什么？' for x in n)
print(shell('input keyevent 4'));print(shell("dumpsys activity activities | grep -E 'mResumedActivity|mFocusedActivity'",'back-launcher.txt'))
print(shell('am start -W -n com.mightyoung.muyon.product/.MainActivity','relaunch.txt'))
capture('main-reentry');print('REAL PRODUCT UI SMOKE PASS',flush=True)
