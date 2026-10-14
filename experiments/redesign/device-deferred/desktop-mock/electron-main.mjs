// Optional adapter skeleton; runtime NOT_RUN. No native core/IPC capability installed.
import {app,BrowserWindow} from 'electron';
import {fileURLToPath} from 'node:url';
await app.whenReady();
const window=new BrowserWindow({width:1280,height:900,webPreferences:{nodeIntegration:false,contextIsolation:true,sandbox:true,preload:fileURLToPath(new URL('./preload.cjs',import.meta.url))}});
window.webContents.setWindowOpenHandler(()=>({action:'deny'}));
window.webContents.on('will-navigate',event=>event.preventDefault());
await window.loadFile(fileURLToPath(new URL('./index.html',import.meta.url)));
app.on('window-all-closed',()=>app.quit());
